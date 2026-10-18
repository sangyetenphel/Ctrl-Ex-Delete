-- 010: One reflection text answer ("What did you notice?").
--
-- The reflection form used to ask two similar questions, stored in `note`
-- ("A short note about today") and `noticed` ("What did you notice?"). The
-- form now asks once, and the answer is stored in `note`, which is also the
-- quote shown on the scrapbook memory.
--
-- Existing memories keep every word: a `noticed` answer is moved into `note`,
-- after the note and a blank line when both were filled in (an identical
-- answer is kept once). Then the `noticed` column is removed.
--
-- New answers are still limited to 1000 characters by the API. The database
-- allows 2002 so two older 1000-character answers can be joined.
-- Only the reflections table changes. Safe to run again.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'reflections' AND column_name = 'noticed'
    ) THEN
        ALTER TABLE reflections DROP CONSTRAINT IF EXISTS reflections_note_check;

        UPDATE reflections
        SET note = CASE
            WHEN note IS NULL OR btrim(note) = '' THEN noticed
            WHEN btrim(noticed) = btrim(note) THEN note
            ELSE note || E'\n\n' || noticed
        END
        WHERE noticed IS NOT NULL AND btrim(noticed) <> '';

        ALTER TABLE reflections DROP COLUMN noticed;
    END IF;
END $$;

DO $$ BEGIN
    ALTER TABLE reflections ADD CONSTRAINT reflections_note_check
        CHECK (char_length(note) <= 2002);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
