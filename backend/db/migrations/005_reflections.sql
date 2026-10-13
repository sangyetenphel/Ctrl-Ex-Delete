-- 005: Reflections (scrapbook memories).
--
-- "I'll try this" only records a CHOICE (activity_selections). Saving the
-- reflection afterwards is what marks the activity as COMPLETED. activity_logs
-- was created in 001 for exactly that ("one row each time a user completes an
-- activity"), so it is extended here instead of adding a second table.
--
-- Additive only: existing rows keep their values and get NULL in new columns.

ALTER TABLE activity_logs
    -- A memory can be captured without a chosen activity.
    ALTER COLUMN activity_id DROP NOT NULL,

    -- The "I'll try this" choice this completes. UNIQUE: a choice can be
    -- completed once, so retries never create a second memory.
    ADD COLUMN IF NOT EXISTS activity_selection_id BIGINT UNIQUE
        REFERENCES activity_selections(id) ON DELETE SET NULL,

    -- Optional photo (file in S3, row in scrapbook_photos). UNIQUE: one
    -- photo belongs to one memory.
    ADD COLUMN IF NOT EXISTS photo_id BIGINT UNIQUE
        REFERENCES scrapbook_photos(id) ON DELETE SET NULL,

    -- The reflection answers, stored exactly as chosen (no numeric scores).
    ADD COLUMN IF NOT EXISTS note TEXT
        CHECK (char_length(note) <= 1000),
    ADD COLUMN IF NOT EXISTS noticed TEXT
        CHECK (char_length(noticed) <= 1000),
    ADD COLUMN IF NOT EXISTS thought_about_ex TEXT
        CHECK (thought_about_ex IN ('not_really', 'a_little', 'a_lot')),
    ADD COLUMN IF NOT EXISTS mood_change TEXT
        CHECK (mood_change IN ('worse', 'about_the_same', 'a_little_better', 'much_better'));

CREATE INDEX IF NOT EXISTS idx_activity_logs_install_completed
    ON activity_logs (installation_id, completed_at DESC);
