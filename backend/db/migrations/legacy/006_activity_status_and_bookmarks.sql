-- 006: Activity status (one activity in progress at a time) and bookmarks.
--
-- An "I'll try this" choice now has a status:
--   in_progress → completed   (its reflection was saved; see 005)
--   in_progress → abandoned   ("Change activity"; never counts as completed)
-- The database allows at most ONE in_progress activity per installation, so
-- two requests at once can't both start an activity.
--
-- Safe to run again: every step is skipped if it was already done.

ALTER TABLE activity_selections
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'in_progress'
        CHECK (status IN ('in_progress', 'completed', 'abandoned')),
    ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ;   -- when it was completed or abandoned

-- Existing rows: a selection with a reflection is completed...
UPDATE activity_selections s
SET status = 'completed', ended_at = rf.created_at
FROM reflections rf
WHERE rf.activity_selection_id = s.id AND s.status = 'in_progress';

-- ...and only the newest unfinished one per installation stays in progress
-- (it is what the app already showed as the current activity).
UPDATE activity_selections
SET status = 'abandoned', ended_at = now()
WHERE status = 'in_progress'
  AND id NOT IN (
      SELECT DISTINCT ON (installation_id) id
      FROM activity_selections
      WHERE status = 'in_progress'
      ORDER BY installation_id, selected_at DESC, id DESC
  );

-- ended_at is set exactly when the activity has ended.
DO $$ BEGIN
    ALTER TABLE activity_selections ADD CONSTRAINT activity_selections_ended_at_matches_status
        CHECK ((status = 'in_progress') = (ended_at IS NULL));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- One activity in progress per installation.
CREATE UNIQUE INDEX IF NOT EXISTS activity_selections_one_in_progress
    ON activity_selections (installation_id)
    WHERE status = 'in_progress';

-- A card can be tried again after "Change activity", so the old
-- one-selection-per-card rule now ignores abandoned attempts.
CREATE UNIQUE INDEX IF NOT EXISTS activity_selections_one_live_per_recommendation
    ON activity_selections (recommendation_id)
    WHERE status <> 'abandoned';
ALTER TABLE activity_selections DROP CONSTRAINT IF EXISTS activity_selections_recommendation_id_key;

-- "Save for later": bookmarks an activity from the catalog. Saving never
-- selects or completes anything; saved activities come first in later
-- recommendations. The primary key prevents duplicate bookmarks.
CREATE TABLE IF NOT EXISTS activity_bookmarks (
    installation_id  UUID NOT NULL REFERENCES installations(id) ON DELETE CASCADE,
    activity_id      INT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (installation_id, activity_id)
);
