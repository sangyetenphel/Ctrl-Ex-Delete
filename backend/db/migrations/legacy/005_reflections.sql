-- 005: Reflections, and a cleanup of the activity and scrapbook tables.
--
-- The journey, one table per step:
--
--   check_ins ─< recommendations ─< activity_selections ─< reflections >─ scrapbook_photos
--   (answers)    (cards shown)       ("I'll try this")      ("Add to my     (the S3 file)
--                                                           scrapbook")
--
--   * Choosing an activity only adds an activity_selections row.
--   * Saving a reflection linked to a selection is what COMPLETES the activity.
--     A reflection without a selection is a memory not tied to an activity.
--   * The activity is always read through the selection, never stored twice.
--
-- Every row also carries installation_id, and composite foreign keys make the
-- database itself reject a row that points at another installation's data.
--
-- Safe to run again: every step is skipped if it was already done.

-- 1. activity_logs (from 001) was never used by the app. Its required
--    activity_id and 1–10 mood_after score don't fit the reflection flow,
--    so it is replaced by reflections. It only ever held test data.
DROP TABLE IF EXISTS activity_logs;

-- 2. scrapbook_photos (from 004): drop columns nothing uses. The memory that
--    owns the photo has the date, the note and the activity.
ALTER TABLE scrapbook_photos
    DROP COLUMN IF EXISTS activity_id,
    DROP COLUMN IF EXISTS caption,
    DROP COLUMN IF EXISTS local_date;

-- 3. Same-installation foreign keys down the chain.
--    (Postgres has no "ADD CONSTRAINT IF NOT EXISTS", hence the DO blocks.)
DO $$ BEGIN
    ALTER TABLE check_ins ADD CONSTRAINT check_ins_id_installation_key
        UNIQUE (id, installation_id);
EXCEPTION WHEN duplicate_table OR duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    ALTER TABLE recommendations ADD CONSTRAINT recommendations_id_installation_key
        UNIQUE (id, installation_id);
EXCEPTION WHEN duplicate_table OR duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    ALTER TABLE activity_selections ADD CONSTRAINT activity_selections_id_installation_key
        UNIQUE (id, installation_id);
EXCEPTION WHEN duplicate_table OR duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    ALTER TABLE scrapbook_photos ADD CONSTRAINT scrapbook_photos_id_installation_key
        UNIQUE (id, installation_id);
EXCEPTION WHEN duplicate_table OR duplicate_object THEN NULL; END $$;

-- A recommendation belongs to a check-in of the same installation...
DO $$ BEGIN
    ALTER TABLE recommendations ADD CONSTRAINT recommendations_check_in_same_installation_fkey
        FOREIGN KEY (check_in_id, installation_id)
        REFERENCES check_ins (id, installation_id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
ALTER TABLE recommendations DROP CONSTRAINT IF EXISTS recommendations_check_in_id_fkey;

-- ...and a selection to a recommendation of the same installation.
DO $$ BEGIN
    ALTER TABLE activity_selections ADD CONSTRAINT activity_selections_recommendation_same_installation_fkey
        FOREIGN KEY (recommendation_id, installation_id)
        REFERENCES recommendations (id, installation_id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
ALTER TABLE activity_selections DROP CONSTRAINT IF EXISTS activity_selections_recommendation_id_fkey;

-- 4. Reflections: one row = one scrapbook memory.
CREATE TABLE IF NOT EXISTS reflections (
    id                     BIGSERIAL PRIMARY KEY,
    installation_id        UUID NOT NULL REFERENCES installations(id) ON DELETE CASCADE,

    -- The "I'll try this" choice this completes (NULL = not tied to an
    -- activity). UNIQUE: a choice is completed once, so retries can't
    -- create a second memory.
    activity_selection_id  BIGINT UNIQUE,

    -- Optional photo. UNIQUE: one photo belongs to one memory.
    photo_id               BIGINT UNIQUE,

    -- The answers, stored exactly as chosen (no numeric scores).
    note                   TEXT CHECK (char_length(note) <= 1000),
    noticed                TEXT CHECK (char_length(noticed) <= 1000),
    thought_about_ex       TEXT CHECK (thought_about_ex IN ('not_really', 'a_little', 'a_lot')),
    mood_change            TEXT CHECK (mood_change IN
                               ('worse', 'about_the_same', 'a_little_better', 'much_better')),

    local_date             DATE NOT NULL,                    -- the user's calendar day
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),  -- = when it was completed

    -- Deleting a selection or a photo keeps the memory, minus that link.
    FOREIGN KEY (activity_selection_id, installation_id)
        REFERENCES activity_selections (id, installation_id)
        ON DELETE SET NULL (activity_selection_id),
    FOREIGN KEY (photo_id, installation_id)
        REFERENCES scrapbook_photos (id, installation_id)
        ON DELETE SET NULL (photo_id)
);

CREATE INDEX IF NOT EXISTS idx_reflections_install_created
    ON reflections (installation_id, created_at DESC);
