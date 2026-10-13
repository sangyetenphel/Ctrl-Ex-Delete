-- 007: The user's calendar day an activity was completed, on the activity
-- itself.
--
-- Until now the completion date lived only on its reflection. Keeping it on
-- the selection means deleting a memory (photo and answers) doesn't erase the
-- fact that the activity was done, so progress counts never jump backwards.
--
-- Safe to run again.

ALTER TABLE activity_selections
    ADD COLUMN IF NOT EXISTS completed_on DATE;

-- Existing completed activities: the day their reflection was saved.
UPDATE activity_selections s
SET completed_on = rf.local_date
FROM reflections rf
WHERE rf.activity_selection_id = s.id
  AND s.status = 'completed'
  AND s.completed_on IS NULL;

-- Completed activities whose reflection is gone: the UTC day they ended.
UPDATE activity_selections
SET completed_on = (ended_at AT TIME ZONE 'UTC')::date
WHERE status = 'completed' AND completed_on IS NULL;

-- completed_on is set exactly when the activity is completed.
DO $$ BEGIN
    ALTER TABLE activity_selections ADD CONSTRAINT activity_selections_completed_on_matches_status
        CHECK ((status = 'completed') = (completed_on IS NOT NULL));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_activity_selections_completed_on
    ON activity_selections (installation_id, completed_on)
    WHERE status = 'completed';

CREATE INDEX IF NOT EXISTS idx_reflections_install_local_date
    ON reflections (installation_id, local_date);
