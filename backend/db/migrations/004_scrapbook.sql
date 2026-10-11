-- 004: Scrapbook photos. The image file is in S3; this row says where.

CREATE TABLE IF NOT EXISTS scrapbook_photos (
    id               BIGSERIAL PRIMARY KEY,
    installation_id  UUID NOT NULL REFERENCES installations(id) ON DELETE CASCADE,
    activity_id      INT REFERENCES activities(id),   -- not used yet
    object_key       TEXT NOT NULL UNIQUE,            -- the file's path in the S3 bucket
    byte_size        INT,                             -- set when the upload is confirmed
    caption          TEXT,
    local_date       DATE NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    uploaded_at      TIMESTAMPTZ                      -- NULL = upload not confirmed yet
);

CREATE INDEX IF NOT EXISTS idx_scrapbook_photos_install
    ON scrapbook_photos (installation_id, created_at DESC);