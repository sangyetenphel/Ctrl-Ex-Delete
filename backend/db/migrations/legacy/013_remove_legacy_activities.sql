-- 013: Remove the 21 legacy activities that the 100-activity catalog replaced.
--
-- 003 and 008 seeded 49 activities. 28 of them are part of the new catalog
-- (same slug, same activity) and stay. The other 21 are deleted, unless a
-- user was recommended, chose or saved one: then it's retired instead
-- (is_active = false), so a migration never deletes user history.
-- scripts/seed_catalog.py applies the same rule to anything else that isn't
-- in the catalog, and `python -m scripts.reset_dev_data` wipes test history
-- when a completely clean start is wanted.
--
-- On a fresh database there is no history, so the activities table ends with
-- exactly the 100 catalog activities. Safe to run again.

CREATE TEMPORARY TABLE legacy_activities ON COMMIT DROP AS
SELECT a.id,
       EXISTS (SELECT 1 FROM recommendations r WHERE r.activity_id = a.id)
       OR EXISTS (SELECT 1 FROM activity_bookmarks b WHERE b.activity_id = a.id) AS has_history
FROM activities a
WHERE a.slug IN (
    'bake_and_share', 'box_breathing', 'brain_game', 'budget_outfit', 'build_a_puzzle',
    'deep_clean_space', 'farmers_market', 'live_show', 'pot_a_plant', 'self_care_night',
    'sit_in_sunlight', 'solo_picnic', 'space_revamp', 'start_a_book', 'tea_and_journal',
    'three_good_things', 'treat_outside', 'try_new_sport', 'unsent_letter', 'vision_board',
    'walk_without_social_media'
);

UPDATE activities SET is_active = FALSE
WHERE id IN (SELECT id FROM legacy_activities WHERE has_history);

-- Research links go too (ON DELETE CASCADE).
DELETE FROM activities
WHERE id IN (SELECT id FROM legacy_activities WHERE NOT has_history);
