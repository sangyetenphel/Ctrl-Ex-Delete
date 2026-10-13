"""
AWS S3 storage for scrapbook photos.
This is the ONLY file that talks to S3 (like storage.py is for the database).

The bucket stays private: the app only ever gets short-lived presigned URLs.
"""
from functools import cache
from uuid import uuid4

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

from app.config import settings

CONTENT_TYPE = "image/jpeg"


def is_configured() -> bool:
    return settings.s3_configured


@cache
def _s3():
    # Made on first use, so the API can start without AWS settings.
    return boto3.client(
        "s3",
        region_name=settings.aws_region,
        # Regional endpoint: avoids redirects that break presigned URLs.
        endpoint_url=f"https://s3.{settings.aws_region}.amazonaws.com",
        aws_access_key_id=settings.aws_access_key_id,
        aws_secret_access_key=settings.aws_secret_access_key,
        config=Config(signature_version="s3v4"),
    )


def new_key() -> str:
    """
    A random object key. It deliberately does NOT contain the installation ID:
    the key is part of every presigned URL, and the installation ID is what
    gives access to a user's data. The database row links key and owner.
    """
    return f"scrapbook/{uuid4().hex}.jpg"


def upload_url(key: str) -> str:
    """A URL the app can PUT one JPEG to. Works for 5 minutes."""
    return _s3().generate_presigned_url(
        "put_object",
        Params={"Bucket": settings.s3_bucket, "Key": key, "ContentType": CONTENT_TYPE},
        ExpiresIn=300,
    )


def download_url(key: str) -> str:
    """A URL the app can load the photo from. Works for 1 hour."""
    return _s3().generate_presigned_url(
        "get_object", Params={"Bucket": settings.s3_bucket, "Key": key}, ExpiresIn=3600
    )


def object_size(key: str) -> int | None:
    """Size in bytes, or None if nothing has been uploaded to this key."""
    try:
        return _s3().head_object(Bucket=settings.s3_bucket, Key=key)["ContentLength"]
    except ClientError as error:
        if error.response["Error"]["Code"] in ("404", "NoSuchKey", "NotFound"):
            return None
        raise


def delete(key: str) -> None:
    _s3().delete_object(Bucket=settings.s3_bucket, Key=key)
