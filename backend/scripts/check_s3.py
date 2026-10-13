"""
Checks that the backend can use the S3 bucket in backend/.env, and that
photos are private. Run from the backend/ folder:

    python -m scripts.check_s3

It uploads ONE small test object (scrapbook/_check-s3-<random>.txt), reads it
back through a presigned URL, confirms a plain (unsigned) request is refused,
then deletes that same object. Nothing else in the bucket is touched.
Secrets are never printed.
"""
import sys
import urllib.error
import urllib.request
from uuid import uuid4

from botocore.exceptions import ClientError

from app import media
from app.config import settings


def step(label: str, ok: bool, detail: str = "") -> bool:
    print(f"  {'ok  ' if ok else 'FAIL'}  {label}{f'  ({detail})' if detail else ''}")
    return ok


def http_status(url: str, method: str = "GET") -> int:
    try:
        with urllib.request.urlopen(urllib.request.Request(url, method=method), timeout=15) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def main() -> int:
    print(f"S3 check for bucket '{settings.s3_bucket}' in {settings.aws_region}")
    if not step("AWS settings present in .env", media.is_configured(),
                "need AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, S3_BUCKET"):
        return 1

    s3 = media._s3()
    key = f"scrapbook/_check-s3-{uuid4().hex}.txt"
    try:
        s3.put_object(Bucket=settings.s3_bucket, Key=key, Body=b"ced s3 check", ContentType="text/plain")
        step("upload a test object", True, key)
    except ClientError as error:
        step("upload a test object", False, error.response["Error"]["Code"])
        return 1

    all_ok = True
    try:
        all_ok &= step("find it again (HeadObject)", media.object_size(key) == len(b"ced s3 check"))
        all_ok &= step("missing objects report 'not found'", media.object_size(f"{key}.missing") is None,
                       "needs s3:ListBucket")
        all_ok &= step("presigned download works", http_status(media.download_url(key)) == 200)
        plain = f"https://{settings.s3_bucket}.s3.{settings.aws_region}.amazonaws.com/{key}"
        status = http_status(plain)
        all_ok &= step("object is private (unsigned request refused)", status in (401, 403), f"HTTP {status}")
        try:
            block = s3.get_public_access_block(Bucket=settings.s3_bucket)["PublicAccessBlockConfiguration"]
            step("bucket 'Block all public access'", all(block.values()), str(block))
        except ClientError as error:
            print(f"  info  couldn't read the public-access settings ({error.response['Error']['Code']}); "
                  "check them in the AWS console")
    finally:
        try:
            s3.delete_object(Bucket=settings.s3_bucket, Key=key)
            all_ok &= step("delete the test object", media.object_size(key) is None)
        except ClientError as error:
            all_ok &= step("delete the test object", False, error.response["Error"]["Code"])

    print("All good." if all_ok else "Some checks failed (see above).")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
