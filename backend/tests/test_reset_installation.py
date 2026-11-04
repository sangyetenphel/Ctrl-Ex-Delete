"""
scripts/reset_installation.py: resets ONE installation. Synthetic users are
built through the real API (S3 faked), then installation A is reset and
installation B, the catalogs and every other row are checked to be unchanged.
Runs only against a local database (it creates and deletes test rows).
"""
import uuid
from urllib.parse import urlparse

import psycopg
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app
from scripts import reset_installation as ri
from tests.conftest import upload_test_photo

client = TestClient(app)

pytestmark = pytest.mark.skipif(
    urlparse(settings.database_url).hostname not in (None, "", "localhost", "127.0.0.1", "::1"),
    reason="creates and resets test installations: runs only against a local test database",
)

NOTE = "PRIVATE-NOTE-must-never-be-printed"
CATALOGS = sorted(ri.PROTECTED_TABLES - {"schema_migrations"}) + ["schema_migrations"]


class S3Error(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.response = {"Error": {"Code": code}}


class FakeS3:
    """Just enough of boto3's S3 client for the script: head, batch delete, listing."""

    def __init__(self, keys, fail_keys=(), raise_on_delete=False):
        self.objects, self.fail_keys, self.raise_on_delete = set(keys), set(fail_keys), raise_on_delete
        self.deleted: list[str] = []

    def head_object(self, Bucket, Key):
        if Key not in self.objects:
            raise S3Error("404")
        return {"ContentLength": 1000}

    def delete_objects(self, Bucket, Delete):
        if self.raise_on_delete:
            raise S3Error("ServiceUnavailable")
        errors = []
        for item in Delete["Objects"]:
            if item["Key"] in self.fail_keys:
                errors.append({"Key": item["Key"], "Code": "AccessDenied"})
            else:
                self.objects.discard(item["Key"])     # a missing key "succeeds", like S3
                self.deleted.append(item["Key"])
        return {"Errors": errors} if errors else {}

    def get_paginator(self, name):
        fake = self

        class Paginator:
            def paginate(self, Bucket, Prefix):
                yield {"Contents": [{"Key": k} for k in sorted(fake.objects) if k.startswith(Prefix)]}
        return Paginator()


def make_user(installation_id: str, uploaded: dict, day: str) -> list[str]:
    """A full journey: check-in (+ recommendations, room message), activity,
    bookmark, reflection with a photo, a spare photo, Moving Forward, Ced usage.
    Returns the installation's photo keys."""
    h = {"X-Installation-ID": installation_id}
    assert client.post("/check-ins", headers=h, json={
        "feeling": "hopeful", "contact_urge": 3, "energy_level": "medium",
        "hardest_areas": ["feeling_lonely"], "local_date": day}).status_code == 201
    recs = client.get("/recommendations/latest", headers=h).json()["recommendations"]
    selection = client.post(f"/recommendations/{recs[0]['id']}/selection", headers=h).json()
    assert client.put(f"/bookmarks/{recs[1]['activity']['id']}", headers=h).status_code in (200, 201)
    photo_id = upload_test_photo(client, installation_id, uploaded)
    assert client.post("/reflections", headers=h, json={
        "activity_selection_id": selection["id"], "photo_id": photo_id, "note": NOTE,
        "thought_about_ex": "a_little", "mood_change": "a_little_better", "local_date": day}).status_code == 201
    upload_test_photo(client, installation_id, uploaded)   # a photo not (yet) in a memory
    with psycopg.connect(settings.database_url) as conn:
        conn.execute("INSERT INTO moving_forward_check_ins (installation_id, moved_forward_on) VALUES (%s, %s)",
                     (installation_id, day))
        conn.execute("INSERT INTO ced_usage (installation_id, usage_date, messages) VALUES (%s, %s, 4)",
                     (installation_id, day))
        return [r[0] for r in conn.execute(
            "SELECT object_key FROM scrapbook_photos WHERE installation_id = %s", (installation_id,))]


def snapshot(conn, installation_id: str) -> dict:
    """Every row (all columns) belonging to one installation, per table."""
    filters = ri.row_filters(conn)
    return {t: sorted(map(repr, conn.execute(f"SELECT * FROM {t} WHERE {w}", {"id": installation_id})))
            for t, w in filters.items()}


def catalog_snapshot(conn) -> dict:
    return {t: sorted(map(repr, conn.execute(f"SELECT * FROM {t}"))) for t in CATALOGS}


@pytest.fixture
def two_users(fake_s3, installation_id, other_installation_id):
    uploaded, _ = fake_s3
    keys_a = make_user(installation_id, uploaded, "2026-10-01")
    keys_b = make_user(other_installation_id, uploaded, "2026-10-01")
    return installation_id, other_installation_id, keys_a, keys_b


def connect():
    return psycopg.connect(settings.database_url, autocommit=True)


# ─────────────────────────────────────────────
# Targets and arguments
# ─────────────────────────────────────────────

def test_only_local_or_the_production_fingerprint_is_allowed(monkeypatch):
    assert ri.classify_target("postgresql://u@localhost:5432/x", None) == "local"
    assert ri.classify_target("postgresql:///x", None) == "local"
    with pytest.raises(ri.Refused, match="local database with real S3"):
        ri.classify_target("postgresql://u@localhost/x", "some-bucket")
    with pytest.raises(ri.Refused, match="known CED database"):
        ri.classify_target("postgresql://u@ep-someone-else.us-east-2.aws.neon.tech/neondb", "their-bucket")

    host, bucket = "ep-test-prod.us-east-1.aws.neon.tech", "test-prod-bucket"
    monkeypatch.setitem(ri.PRODUCTION_TARGET, "db_host_sha256", ri._sha256(host))
    monkeypatch.setitem(ri.PRODUCTION_TARGET, "bucket_sha256", ri._sha256(bucket))
    assert ri.classify_target(f"postgresql://u:p@{host.upper()}/neondb?sslmode=require", bucket) == "production"
    with pytest.raises(ri.Refused, match="production bucket"):
        ri.classify_target(f"postgresql://u@{host}/neondb", "another-bucket")
    with pytest.raises(ri.Refused, match="production bucket"):
        ri.classify_target(f"postgresql://u@{host}/neondb", None)
    with pytest.raises(ri.Refused, match="known CED database"):
        ri.classify_target(f"postgresql://u@{host}/rehearsal", bucket)


def test_installation_id_must_be_one_explicit_uuid():
    assert ri.parse_installation_id("0F8C1D2E-1111-4222-8333-944455556666") == "0f8c1d2e-1111-4222-8333-944455556666"
    for bad in ("", "all", "*", "%", "0f8c1d2e", "0f8c1d2e11114222833394445555666"):
        with pytest.raises(ri.Refused):
            ri.parse_installation_id(bad)
    with pytest.raises(SystemExit):
        ri.main([])   # the ID is required: there is no "all users"


# ─────────────────────────────────────────────
# Dry run
# ─────────────────────────────────────────────

def test_dry_run_counts_one_installation_and_changes_nothing(two_users):
    a, b, keys_a, keys_b = two_users
    s3 = FakeS3(keys_a + keys_b)
    with connect() as conn:
        before = (snapshot(conn, a), snapshot(conn, b), catalog_snapshot(conn))
        plan = ri.make_plan(conn, a, s3, "bucket")
        assert (snapshot(conn, a), snapshot(conn, b), catalog_snapshot(conn)) == before
    assert plan.exists
    assert plan.counts == {"check_in_room_messages": 1, "reflections": 1, "scrapbook_photos": 2,
                           "activity_bookmarks": 1, "activity_selections": 1, "recommendations": plan.counts["recommendations"],
                           "check_ins": 1, "moving_forward_check_ins": 1, "ced_usage": 1, "installations": 1}
    assert plan.counts["recommendations"] >= 3
    assert sorted(plan.photo_keys) == sorted(keys_a) and plan.s3_present == 2 and plan.s3_missing == 0
    assert s3.deleted == []


def test_dry_run_output_has_counts_only(two_users, monkeypatch, capsys):
    a, _, keys_a, _ = two_users
    assert ri.main([a]) == 0
    out = capsys.readouterr().out
    assert "Dry run: nothing was changed" in out and "installations" in out
    assert NOTE not in out and not any(k in out for k in keys_a)
    assert "postgresql://" not in out and "https://" not in out


# ─────────────────────────────────────────────
# Reset
# ─────────────────────────────────────────────

def test_reset_deletes_a_and_leaves_b_catalogs_and_files_unchanged(two_users):
    a, b, keys_a, keys_b = two_users
    s3 = FakeS3(keys_a + keys_b + ["scrapbook/" + "0" * 32 + ".jpg", "other/readme.txt"])
    with connect() as conn:
        b_before, catalogs_before = snapshot(conn, b), catalog_snapshot(conn)
        report = ri.execute_reset(conn, a, s3, "bucket")
        assert all(not rows for rows in snapshot(conn, a).values())
        assert snapshot(conn, b) == b_before
        assert catalog_snapshot(conn) == catalogs_before
    assert report["database"] == "deleted" and report["s3_deleted"] == 2 and report["s3_failed"] == 0
    assert sorted(s3.deleted) == sorted(keys_a)
    assert set(keys_b) <= s3.objects and "other/readme.txt" in s3.objects   # nothing else in the bucket
    assert report["deleted_rows"]["installations"] == 1 and report["deleted_rows"]["reflections"] == 1


def test_b_still_works_through_the_api_after_a_is_reset(two_users):
    a, b, keys_a, keys_b = two_users
    with connect() as conn:
        ri.execute_reset(conn, a, FakeS3(keys_a + keys_b), "bucket")
    hb, ha = {"X-Installation-ID": b}, {"X-Installation-ID": a}
    assert len(client.get("/reflections", headers=hb).json()) == 1
    assert client.get("/reflections", headers=ha).json() == []   # A starts fresh


def test_s3_failure_leaves_the_database_unchanged_and_a_retry_finishes(two_users):
    a, b, keys_a, keys_b = two_users
    failing = FakeS3(keys_a + keys_b, fail_keys=[keys_a[0]])
    with connect() as conn:
        a_before = snapshot(conn, a)
        with pytest.raises(ri.PartialReset, match="database was left unchanged") as error:
            ri.execute_reset(conn, a, failing, "bucket")
        assert error.value.report["s3_failed"] == 1 and error.value.report["s3_deleted"] == 1
        assert snapshot(conn, a) == a_before
        # Retry with S3 working again: the already-deleted file "succeeds".
        retry = FakeS3(failing.objects)
        report = ri.execute_reset(conn, a, retry, "bucket")
        assert report["database"] == "deleted" and all(not r for r in snapshot(conn, a).values())
    assert keys_a[0] not in retry.objects and set(keys_b) <= retry.objects


def test_s3_outage_is_reported_and_nothing_is_deleted(two_users):
    a, _, keys_a, keys_b = two_users
    s3 = FakeS3(keys_a + keys_b, raise_on_delete=True)
    with connect() as conn:
        before = snapshot(conn, a)
        with pytest.raises(ri.PartialReset):
            ri.execute_reset(conn, a, s3, "bucket")
        assert snapshot(conn, a) == before
    assert s3.objects == set(keys_a + keys_b)


def test_database_failure_rolls_back_and_a_retry_finishes(two_users):
    a, b, keys_a, keys_b = two_users
    s3 = FakeS3(keys_a + keys_b)
    with connect() as conn:
        conn.execute("""CREATE FUNCTION _test_block_delete() RETURNS trigger LANGUAGE plpgsql AS
                        $$ BEGIN RAISE EXCEPTION 'blocked for the test'; END $$""")
        conn.execute("""CREATE TRIGGER _test_block BEFORE DELETE ON check_ins
                        FOR EACH ROW EXECUTE FUNCTION _test_block_delete()""")
        try:
            before = snapshot(conn, a)
            with pytest.raises(ri.PartialReset, match="rolled back; 2 photo files were already deleted") as error:
                ri.execute_reset(conn, a, s3, "bucket")
            assert error.value.report["deleted_rows"] == {}
            assert snapshot(conn, a) == before                      # rows all still there
        finally:
            conn.execute("DROP TRIGGER _test_block ON check_ins")
            conn.execute("DROP FUNCTION _test_block_delete()")
        report = ri.execute_reset(conn, a, s3, "bucket")            # retry
        assert report["database"] == "deleted" and report["s3_deleted"] == 2
        assert all(not r for r in snapshot(conn, a).values())
        assert len(snapshot(conn, b)["reflections"]) == 1


def test_unknown_installation_is_refused(two_users):
    with connect() as conn:
        with pytest.raises(ri.Refused, match="No installation"):
            ri.execute_reset(conn, str(uuid.uuid4()), FakeS3([]), "bucket")


def test_a_new_user_table_must_be_added_to_the_script_first(two_users):
    a, _, keys_a, _ = two_users
    with connect() as conn:
        conn.execute("""CREATE TABLE _test_new_user_data (
                            installation_id UUID REFERENCES installations (id) ON DELETE CASCADE)""")
        try:
            with pytest.raises(ri.Refused, match="_test_new_user_data"):
                ri.make_plan(conn, a)
            with pytest.raises(ri.Refused, match="_test_new_user_data"):
                ri.execute_reset(conn, a, FakeS3(keys_a), "bucket")
        finally:
            conn.execute("DROP TABLE _test_new_user_data")
        assert ri.make_plan(conn, a).exists          # untouched


# ─────────────────────────────────────────────
# Command line confirmations
# ─────────────────────────────────────────────

def test_execute_needs_the_full_id_typed(two_users, capsys):
    a, b, _, _ = two_users
    assert ri.main([a, "--execute"], ask=lambda _: a[:-1]) == 1
    assert "Cancelled" in capsys.readouterr().out
    with connect() as conn:
        assert ri.make_plan(conn, a).exists
    assert ri.main([a, "--execute"], ask=lambda _: a.upper()) == 0
    out = capsys.readouterr().out
    assert "Done:" in out and NOTE not in out
    with connect() as conn:
        assert not ri.make_plan(conn, a).exists and ri.make_plan(conn, b).exists


def test_production_flag_on_a_local_database_is_refused(two_users, capsys):
    a, _, _, _ = two_users
    assert ri.main([a, "--execute", "--production"], ask=lambda _: a) == 4
    assert "isn't the production database" in capsys.readouterr().out
    with connect() as conn:
        assert ri.make_plan(conn, a).exists


def test_production_needs_the_flag_and_the_typed_phrase(two_users, monkeypatch, capsys):
    """Production is simulated: the local database is fingerprinted as production
    and a fake S3 stands in for the bucket."""
    a, _, keys_a, keys_b = two_users
    host = urlparse(settings.database_url).hostname
    monkeypatch.setitem(ri.PRODUCTION_TARGET, "db_host_sha256", ri._sha256(host))
    monkeypatch.setitem(ri.PRODUCTION_TARGET, "db_name", urlparse(settings.database_url).path.lstrip("/"))
    monkeypatch.setitem(ri.PRODUCTION_TARGET, "bucket_sha256", ri._sha256("fake-prod-bucket"))
    monkeypatch.setattr(ri, "LOCAL_HOSTS", set())
    monkeypatch.setattr(settings, "s3_bucket", "fake-prod-bucket")
    monkeypatch.setattr(settings, "aws_access_key_id", "x")
    monkeypatch.setattr(settings, "aws_secret_access_key", "x")
    monkeypatch.setattr(settings, "aws_region", "us-east-1")
    s3 = FakeS3(keys_a + keys_b)
    from app import media
    monkeypatch.setattr(media, "_s3", lambda: s3)

    assert ri.main([a, "--execute"], ask=lambda _: a) == 4           # no --production
    assert "add --production" in capsys.readouterr().out
    answers = iter([a, "reset production"])                          # wrong phrase
    assert ri.main([a, "--execute", "--production"], ask=lambda _: next(answers)) == 1
    assert s3.deleted == []
    answers = iter([a, "RESET PRODUCTION"])
    assert ri.main([a, "--execute", "--production"], ask=lambda _: next(answers)) == 0
    assert sorted(s3.deleted) == sorted(keys_a)
    out = capsys.readouterr().out
    assert "production" in out and not any(k in out for k in keys_a) and NOTE not in out
