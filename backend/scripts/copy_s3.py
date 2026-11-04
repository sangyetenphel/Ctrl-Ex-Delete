"""
Copies every object from the S3 bucket in backend/.env to a bucket in
another AWS account, keeping the same keys, then checks each copy. Read-only
on the source; never deletes anything. Run from the backend/ folder:

    TARGET_AWS_ACCESS_KEY_ID=... TARGET_AWS_SECRET_ACCESS_KEY=... \\
    TARGET_AWS_REGION=us-east-2 TARGET_S3_BUCKET=... python -m scripts.copy_s3 [--dry-run]

Each object is downloaded from the source and uploaded to the target, so the
two accounts need no access to each other. Uploads carry their MD5, so S3
rejects a corrupted copy. Objects already in the target with the same size
and MD5 are skipped, which makes it safe to run again just before the
cutover to pick up new photos. Keys stay the same, so the database needs no
changes. Secrets are never printed.
"""
import base64
import hashlib
import os
import sys

import boto3
from botocore.exceptions import ClientError

from app import media
from app.config import settings

TARGET_SETTINGS = ["TARGET_AWS_ACCESS_KEY_ID", "TARGET_AWS_SECRET_ACCESS_KEY", "TARGET_AWS_REGION", "TARGET_S3_BUCKET"]


def target_client():
    region = os.environ["TARGET_AWS_REGION"]
    return boto3.client(
        "s3",
        aws_access_key_id=os.environ["TARGET_AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["TARGET_AWS_SECRET_ACCESS_KEY"],
        region_name=region,
        endpoint_url=f"https://s3.{region}.amazonaws.com",
    )


def list_objects(client, bucket: str) -> dict[str, int]:
    found = {}
    for page in client.get_paginator("list_objects_v2").paginate(Bucket=bucket):
        for item in page.get("Contents", []):
            found[item["Key"]] = item["Size"]
    return found


def copy_all(source, source_bucket: str, target, target_bucket: str, dry_run: bool = False) -> tuple[int, int, int]:
    """Returns (copied, skipped, failed)."""
    already = list_objects(target, target_bucket)
    copied = skipped = failed = 0
    for key, size in sorted(list_objects(source, source_bucket).items()):
        if dry_run:
            print(f"  would copy  {key}  ({size} bytes)")
            continue
        got = source.get_object(Bucket=source_bucket, Key=key)
        body = got["Body"].read()
        digest = hashlib.md5(body)
        if already.get(key) == size:
            etag = target.head_object(Bucket=target_bucket, Key=key)["ETag"].strip('"')
            if etag == digest.hexdigest():
                skipped += 1
                continue
        try:
            target.put_object(Bucket=target_bucket, Key=key, Body=body,
                              ContentType=got.get("ContentType", "application/octet-stream"),
                              ContentMD5=base64.b64encode(digest.digest()).decode())
            ok = target.head_object(Bucket=target_bucket, Key=key)["ContentLength"] == size
        except ClientError as error:
            print(f"  FAIL  {key}  ({error.response['Error']['Code']})")
            ok = False
        copied += ok
        failed += not ok
    return copied, skipped, failed


def main() -> int:
    missing = [name for name in TARGET_SETTINGS if not os.environ.get(name)]
    if missing or not media.is_configured():
        print("Need the source bucket in backend/.env and these target settings: " + ", ".join(missing))
        return 2
    target_bucket = os.environ["TARGET_S3_BUCKET"]
    if target_bucket == settings.s3_bucket and os.environ["TARGET_AWS_REGION"] == settings.aws_region:
        print("Refusing: the target is the source bucket.")
        return 2
    source, target = media._s3(), target_client()
    try:
        block = target.get_public_access_block(Bucket=target_bucket)["PublicAccessBlockConfiguration"]
        print(f"  {'ok  ' if all(block.values()) else 'WARN'}  target blocks all public access")
    except ClientError as error:
        print(f"  WARN  couldn't read the target's public-access settings ({error.response['Error']['Code']})")

    dry_run = "--dry-run" in sys.argv
    copied, skipped, failed = copy_all(source, settings.s3_bucket, target, target_bucket, dry_run)
    if dry_run:
        return 0
    source_keys, target_keys = list_objects(source, settings.s3_bucket), list_objects(target, target_bucket)
    missing_keys = [key for key, size in source_keys.items() if target_keys.get(key) != size]
    print(f"  copied {copied}, already there {skipped}, failed {failed}; "
          f"source {len(source_keys)} objects, target {len(target_keys)}; {len(missing_keys)} missing or different")
    return 0 if not failed and not missing_keys else 1


if __name__ == "__main__":
    sys.exit(main())
