-- 012: Energy demand, movement, and research sources for activities.
--
-- Schema only. The 100-activity catalog itself is loaded by
-- `python -m scripts.seed_catalog` (run automatically at the end of
-- `python -m scripts.migrate`), from backend/scripts/catalog_data.py.
--
-- 1. activities.energy_level: the activity's overall demand (physical,
--    cognitive, social and preparation), separate from duration_minutes.
--    A check-in's energy decides which levels are eligible
--    (see app/recommendation_rules.py). Rows that exist before the catalog
--    seed get a duration-based placeholder; the seed sets the real values,
--    and retired rows are never recommended.
-- 2. activities.involves_movement: true when the activity is physical
--    movement (walking, dancing, yoga…). Sitting outside is Outdoor &
--    Movement but not movement; the strong-urge rule prefers real movement.
-- 3. activities.evidence_note: a short, plain description of how this
--    suggestion relates to the research it's adapted from.
-- 4. research_bases: one row per research approach (M, B, E, N, S, K) with
--    its citation, link and evidence scope, so long citations aren't
--    repeated on every activity. activity_research_bases links them.
--
-- Safe to run again.

ALTER TABLE activities ADD COLUMN IF NOT EXISTS energy_level TEXT;
UPDATE activities
SET energy_level = CASE
    WHEN duration_minutes <= 15 THEN 'low'
    WHEN duration_minutes <= 45 THEN 'medium'
    ELSE 'high'
END
WHERE energy_level IS NULL;
ALTER TABLE activities ALTER COLUMN energy_level SET NOT NULL;
DO $$ BEGIN
    ALTER TABLE activities ADD CONSTRAINT activities_energy_level_check
        CHECK (energy_level IN ('low', 'medium', 'high'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE activities ADD COLUMN IF NOT EXISTS involves_movement BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE activities ADD COLUMN IF NOT EXISTS evidence_note TEXT;

CREATE TABLE IF NOT EXISTS research_bases (
    code            TEXT PRIMARY KEY CHECK (code ~ '^[A-Z]$'),
    approach        TEXT NOT NULL,   -- e.g. "Mindfulness-based attention practice"
    citation        TEXT NOT NULL,   -- short reference, e.g. "Goyal et al., …"
    url             TEXT NOT NULL,
    evidence_scope  TEXT NOT NULL    -- what the research did and didn't show
);

CREATE TABLE IF NOT EXISTS activity_research_bases (
    activity_id  BIGINT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    code         TEXT NOT NULL REFERENCES research_bases(code),
    PRIMARY KEY (activity_id, code)
);

-- The candidate query reads active activities in catalog order.
CREATE INDEX IF NOT EXISTS idx_activities_active_order
    ON activities (sort_order, id) WHERE is_active;
