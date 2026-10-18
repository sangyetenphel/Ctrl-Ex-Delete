-- 011: Descriptive category names, defined once and stored on every activity.
--
--   category (stable key, unchanged)   category_label (stored display name)
--   mindfulness_rest                   Mindfulness & Rest   (was "Gentle Reset")
--   outdoor_movement                   Outdoor & Movement   (was "Fresh Air")
--   solo_exploration                   Solo Exploration     (was "Solo Adventure")
--   social_connection                  Social Connection    (was "Reconnect")
--
-- 1. activity_categories is the one definition: each key, its display name,
--    and the order Insights lists them in. The API and Insights read names
--    from the database, so there is no second list in the code.
-- 2. activities.category_label is kept and filled from it: existing rows are
--    updated now, and a trigger sets it on every insert or update, so seeds
--    (even old ones re-run) and any other write path store the right name.
-- 3. A foreign key on (category, category_label) makes a mismatched pair
--    impossible to store. ON UPDATE CASCADE: renaming a category here
--    renames it on every activity.
--
-- Only names change. Keys, activity ids, and every recommendation, bookmark,
-- reflection, photo and history row stay as they are. Safe to run again.

CREATE TABLE IF NOT EXISTS activity_categories (
    category    TEXT PRIMARY KEY,
    label       TEXT NOT NULL UNIQUE,
    sort_order  SMALLINT NOT NULL,
    UNIQUE (category, label)  -- what activities' (category, category_label) points at
);

INSERT INTO activity_categories (category, label, sort_order) VALUES
    ('outdoor_movement',  'Outdoor & Movement', 1),
    ('mindfulness_rest',  'Mindfulness & Rest', 2),
    ('solo_exploration',  'Solo Exploration',   3),
    ('social_connection', 'Social Connection',  4)
ON CONFLICT (category) DO UPDATE SET
    label      = EXCLUDED.label,
    sort_order = EXCLUDED.sort_order;

-- Every write to an activity takes its name from activity_categories. An
-- unknown category gets no name, so NOT NULL rejects it.
CREATE OR REPLACE FUNCTION activities_set_category_label() RETURNS trigger AS $$
BEGIN
    SELECT label INTO NEW.category_label
    FROM activity_categories
    WHERE category = NEW.category;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS activities_category_label ON activities;
CREATE TRIGGER activities_category_label
    BEFORE INSERT OR UPDATE OF category, category_label ON activities
    FOR EACH ROW EXECUTE FUNCTION activities_set_category_label();

-- Existing activities get the descriptive names (the trigger fills them in).
UPDATE activities a
SET category_label = c.label
FROM activity_categories c
WHERE c.category = a.category
  AND a.category_label IS DISTINCT FROM c.label;

DO $$ BEGIN
    ALTER TABLE activities ADD CONSTRAINT activities_category_label_fkey
        FOREIGN KEY (category, category_label)
        REFERENCES activity_categories (category, label)
        ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
