"""
scripts/reset_dev_data.py against a fake S3. It wipes every installation's
data in the test database, so these tests only run against a local database
(localhost or a Unix socket), never a hosted one such as Neon.
"""
import uuid
from urllib.parse import urlparse

import psycopg
import pytest
from botocore.exceptions import ClientError
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from scripts import reset_dev_data
from tests.conftest import upload_test_photo

client = TestClient(app)

pytestmark = pytest.mark.skipif(
    urlparse(settings.database_url).hostname not in (None, "", "localhost", "127.0.0.1", "::1"),
    reason="wipes all user data: runs only against a local test database",
)


class FakeS3:
    """Just enough of boto3's S3 client: listing (paginated), versions, batch delete."""

    def __init__(self, keys, versioned=True, versions_listable=True, fail_on=()):
        self.objects = set(keys)
        self.old_versions = {k: ["v0"] for k in keys} if versioned else {}
        self.versions_listable, self.fail_on, self.deleted = versions_listable, set(fail_on), []

    def get_paginator(self, name):
        fake = self

        class Paginator:
            def paginate(self, Bucket, Prefix):
                matching = sorted(k for k in fake.objects if k.startswith(Prefix))
                if name == "list_objects_v2":
                    for start in range(0, max(len(matching), 1), 2):  # pages of 2
                        yield {"Contents": [{"Key": k} for k in matching[start:start + 2]]}
                else:
                    if not fake.versions_listable:
                        raise ClientError({"Error": {"Code": "AccessDenied"}}, "ListObjectVersions")
                    yield {"Versions": [{"Key": k, "VersionId": v}
                                        for k, vs in sorted(fake.old_versions.items()) if k.startswith(Prefix) for v in vs],
                           "DeleteMarkers": []}
        return Paginator()

    def delete_objects(self, Bucket, Delete):
        errors = []
        for item in Delete["Objects"]:
            if item["Key"] in self.fail_on:
                errors.append({"Key": item["Key"], "Code": "AccessDenied"})
                continue
            self.deleted.append(item)
            if "VersionId" in item:
                self.old_versions.get(item["Key"], []).remove(item["VersionId"]) if item["VersionId"] in self.old_versions.get(item["Key"], []) else None
                if not self.old_versions.get(item["Key"]):
                    self.old_versions.pop(item["Key"], None)
            else:
                self.objects.discard(item["Key"])
        return {"Errors": errors}


def headers(installation_id):
    return {"X-Installation-ID": installation_id}


def db():
    return psycopg.connect(settings.database_url)


def make_user_history(uploaded) -> tuple[str, list[str]]:
    """A user with a check-in, a completed activity with a photo memory, an in-progress one and a bookmark."""
    iid = str(uuid.uuid4())
    body = {"feeling": "hopeful", "contact_urge": 3, "energy_level": "medium", "hardest_areas": [], "local_date": "2026-10-17"}
    assert client.post("/check-ins", json=body, headers=headers(iid)).status_code == 201
    cards = client.get("/recommendations/latest", headers=headers(iid)).json()["recommendations"]
    sel = client.post(f"/recommendations/{cards[0]['id']}/selection", headers=headers(iid)).json()
    photo = upload_test_photo(client, iid, uploaded)
    assert client.post("/reflections", headers=headers(iid), json={
        "activity_selection_id": sel["id"], "thought_about_ex": "a_little", "mood_change": "much_better",
        "note": "A quiet moment", "local_date": "2026-10-17", "photo_id": photo}).status_code == 201
    client.post(f"/recommendations/{cards[1]['id']}/selection", headers=headers(iid))
    client.put(f"/bookmarks/{cards[2]['activity']['id']}", headers=headers(iid))
    with db() as conn:
        keys = [r[0] for r in conn.execute("SELECT object_key FROM scrapbook_photos WHERE installation_id = %s", (iid,))]
    return iid, keys


def counts(conn):
    tables = [t for t in reset_dev_data.USER_TABLES
              if conn.execute("SELECT to_regclass(%s) IS NOT NULL", (t,)).fetchone()[0]]
    return {t: conn.execute(f"SELECT count(*) FROM {t}").fetchone()[0] for t in tables}


def catalog(conn):
    return conn.execute("""SELECT (SELECT count(*) FROM activities WHERE is_active), (SELECT count(*) FROM research_bases),
                                  (SELECT count(*) FROM activity_research_bases), (SELECT count(*) FROM activity_categories)""").fetchone()


def test_reset_clears_user_data_and_only_the_apps_uploads(fake_s3):
    uploaded, _ = fake_s3
    users = [make_user_history(uploaded) for _ in range(2)]
    db_keys = [k for _, keys in users for k in keys]
    orphan = f"scrapbook/{uuid.uuid4().hex}.jpg"
    older_format = f"installations/{uuid.uuid4()}/{uuid.uuid4().hex}.jpg"
    unrelated = ["Yankee_Stadium_overhead_2010.jpg", "scrapbook/readme.txt", "assets/logo.png"]
    s3 = FakeS3(db_keys + [orphan, older_format] + unrelated)

    with db() as conn:
        before_catalog = catalog(conn)
        report = reset_dev_data.reset(conn, s3, "bucket")
        after = counts(conn)
        after_catalog = catalog(conn)

    assert set(after.values()) == {0}                                  # every user table is empty
    assert after_catalog == before_catalog and after_catalog[:3] == (100, 6, 109)
    assert s3.objects == set(unrelated)                                # the app's uploads only
    assert not any(k in s3.old_versions for k in db_keys + [orphan, older_format])  # old versions too
    assert report["s3"]["orphans_before"] == 2 and report["s3"]["objects_after"] == 0
    assert report["s3"]["left_alone_in_prefixes"] == ["scrapbook/readme.txt"]

    # A user whose installation is gone starts fresh: empty reads, then a working check-in.
    iid = users[0][0]
    assert client.get("/reflections", headers=headers(iid)).json() == []
    assert client.get("/activity-selections/current", headers=headers(iid)).json()["selection"] is None
    assert client.get("/recommendations/latest", headers=headers(iid)).json()["check_in_id"] is None
    week = client.get("/insights?period=week&today=2026-10-17", headers=headers(iid)).json()
    assert week["has_data"] is False and week["completed"] == 0
    body = {"feeling": "heavy", "contact_urge": 3, "energy_level": "low", "hardest_areas": [], "local_date": "2026-10-17"}
    assert client.post("/check-ins", json=body, headers=headers(iid)).status_code == 201
    assert len(client.get("/recommendations/latest", headers=headers(iid)).json()["recommendations"]) == 3
    with db() as conn:
        conn.execute("DELETE FROM installations WHERE id = %s", (iid,))


def test_failed_s3_deletion_leaves_the_database_untouched(fake_s3):
    uploaded, _ = fake_s3
    iid, keys = make_user_history(uploaded)
    s3 = FakeS3(keys, fail_on={keys[0]})
    try:
        with db() as conn:
            with pytest.raises(RuntimeError, match="S3 cleanup incomplete"):
                reset_dev_data.reset(conn, s3, "bucket")
            conn.rollback()
        with db() as conn:
            assert conn.execute("SELECT count(*) FROM scrapbook_photos WHERE installation_id = %s", (iid,)).fetchone()[0] == 1
    finally:
        with db() as conn:
            conn.execute("DELETE FROM installations WHERE id = %s", (iid,))


def test_unlisted_versions_are_reported_not_assumed(fake_s3):
    uploaded, _ = fake_s3
    iid, keys = make_user_history(uploaded)
    s3 = FakeS3(keys, versions_listable=False)
    with db() as conn:
        report = reset_dev_data.reset(conn, s3, "bucket")
    assert report["s3"]["versions_listable"] is False and report["s3"]["versions_deleted"] is None
    assert s3.objects == set()


def test_database_only_lists_the_files_it_keeps(fake_s3):
    uploaded, _ = fake_s3
    iid, keys = make_user_history(uploaded)
    orphan = f"scrapbook/{uuid.uuid4().hex}.jpg"
    s3 = FakeS3(keys + [orphan, "Yankee_Stadium_overhead_2010.jpg"])
    with db() as conn:
        report = reset_dev_data.reset(conn, s3, "bucket", delete_s3=False)
        assert set(counts(conn).values()) == {0}
    assert s3.deleted == [] and report["s3"]["left_in_s3"] == sorted(keys + [orphan])

    # Later, with delete permission, a full run still finds and removes them.
    with db() as conn:
        report = reset_dev_data.reset(conn, s3, "bucket")
    assert s3.objects == {"Yankee_Stadium_overhead_2010.jpg"} and report["s3"]["orphans_before"] == 2


def test_reset_refuses_when_a_user_table_is_unknown():
    with db() as conn:
        conn.execute("CREATE TABLE chat_messages (installation_id UUID REFERENCES installations(id))")
        with pytest.raises(RuntimeError, match="chat_messages"):
            reset_dev_data.reset(conn, None)
        conn.rollback()
