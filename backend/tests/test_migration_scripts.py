"""The account-migration helpers: scripts/copy_s3.py and scripts/compare_databases.py."""
import base64
import hashlib

from botocore.exceptions import ClientError

from scripts.compare_databases import same_database
from scripts.copy_s3 import copy_all


class FakeBody:
    def __init__(self, data: bytes):
        self.data = data

    def read(self) -> bytes:
        return self.data


class FakeS3:
    """Just enough of boto3's S3 client for copy_all."""

    def __init__(self, objects: dict[str, bytes] | None = None, refuse: set[str] | None = None):
        self.objects = dict(objects or {})
        self.refuse = refuse or set()
        self.puts: list[str] = []

    def get_paginator(self, _name):
        objects = self.objects

        class Paginator:
            def paginate(self, Bucket):
                yield {"Contents": [{"Key": key, "Size": len(data)} for key, data in objects.items()]}

        return Paginator()

    def get_object(self, Bucket, Key):
        return {"Body": FakeBody(self.objects[Key]), "ContentType": "image/jpeg"}

    def head_object(self, Bucket, Key):
        data = self.objects[Key]
        return {"ContentLength": len(data), "ETag": f'"{hashlib.md5(data).hexdigest()}"'}

    def put_object(self, Bucket, Key, Body, ContentType, ContentMD5):
        if Key in self.refuse:
            raise ClientError({"Error": {"Code": "AccessDenied"}}, "PutObject")
        assert ContentMD5 == base64.b64encode(hashlib.md5(Body).digest()).decode()
        self.objects[Key] = Body
        self.puts.append(Key)


def test_copy_keeps_keys_and_bytes():
    source = FakeS3({"scrapbook/a.jpg": b"photo a", "scrapbook/b.jpg": b"photo b"})
    target = FakeS3()
    assert copy_all(source, "old", target, "new") == (2, 0, 0)
    assert target.objects == source.objects


def test_rerun_skips_identical_objects_and_recopies_changed_ones():
    source = FakeS3({"scrapbook/a.jpg": b"photo a", "scrapbook/b.jpg": b"photo b"})
    target = FakeS3({"scrapbook/a.jpg": b"photo a", "scrapbook/b.jpg": b"photo B"})  # same size, different bytes
    assert copy_all(source, "old", target, "new") == (1, 1, 0)
    assert target.puts == ["scrapbook/b.jpg"]
    assert target.objects["scrapbook/b.jpg"] == b"photo b"


def test_refused_upload_is_reported_not_hidden():
    source = FakeS3({"scrapbook/a.jpg": b"photo a"})
    target = FakeS3(refuse={"scrapbook/a.jpg"})
    assert copy_all(source, "old", target, "new") == (0, 0, 1)


def test_dry_run_changes_nothing():
    source = FakeS3({"scrapbook/a.jpg": b"photo a"})
    target = FakeS3()
    copy_all(source, "old", target, "new", dry_run=True)
    assert target.objects == {}


def test_same_database_sees_through_the_neon_pooler():
    pooled = "postgresql://u:p@ep-x-123-pooler.us-east-2.aws.neon.tech/neondb"
    direct = "postgresql://u:p@ep-x-123.us-east-2.aws.neon.tech/neondb"
    assert same_database(pooled, direct)
    assert not same_database(direct, "postgresql://u:p@ep-y-456.us-east-2.aws.neon.tech/neondb")
    assert not same_database(direct, "postgresql://u:p@ep-x-123.us-east-2.aws.neon.tech/otherdb")


def test_settings_come_from_the_environment_first_then_the_migration_file(tmp_path, monkeypatch):
    from scripts import compare_databases as cd

    saved = tmp_path / ".env.migration"
    # A real Neon string has ? and &, which is why the scripts read the file themselves.
    saved.write_text("TARGET_DATABASE_URL=postgresql://u:p@ep-a-1-pooler.us-east-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require\n"
                     "TARGET_S3_BUCKET=\n")
    monkeypatch.setattr(cd, "MIGRATION_SETTINGS", saved)
    monkeypatch.delenv("TARGET_DATABASE_URL", raising=False)
    monkeypatch.delenv("TARGET_S3_BUCKET", raising=False)
    assert cd.migration_setting("TARGET_DATABASE_URL").endswith("?sslmode=require&channel_binding=require")
    assert cd.migration_setting("TARGET_S3_BUCKET") is None          # left empty in the file
    monkeypatch.setenv("TARGET_DATABASE_URL", "postgresql://u:p@localhost/other")
    assert cd.migration_setting("TARGET_DATABASE_URL") == "postgresql://u:p@localhost/other"


def test_database_option_changes_only_the_database_name():
    from scripts.compare_databases import with_database

    url = "postgresql://u:p@ep-a-1-pooler.us-east-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require"
    assert with_database(url, "rehearsal") == \
        "postgresql://u:p@ep-a-1-pooler.us-east-1.aws.neon.tech/rehearsal?sslmode=require&channel_binding=require"
    assert with_database(url, None) == url
