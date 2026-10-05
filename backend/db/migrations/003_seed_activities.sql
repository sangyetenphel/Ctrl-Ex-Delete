-- 003: The activity catalog.
--
-- These are the three activities from the Figma prototype, copied word for
-- word from the app's original sample data. To add an activity later, write a
-- new migration file (004_..., 005_...) with another INSERT like these.

INSERT INTO activities
    (slug, title, category, category_label, duration_minutes,
     instructions, why_it_fits, sort_order)
VALUES
    ('sit_in_sunlight',
     'Sit somewhere with sunlight.',
     'mindfulness_rest', 'Gentle Reset', 10,
     'No productivity needed. Notice three things you can see and take five slow breaths.',
     'Your energy is low and the urge to reach out is moderate. This activity gives your nervous system a soft reset.',
     1),
    ('walk_without_social_media',
     'Take a 20-minute walk without checking their social media.',
     'outdoor_movement', 'Fresh Air', 20,
     'Leave your phone in your pocket. Pay attention to sounds around you — birds, wind, footsteps.',
     'Movement helps interrupt rumination loops. Walking without scrolling gives your mind space to settle.',
     2),
    ('solo_outing',
     'Visit a café, movie, or event by yourself.',
     'solo_exploration', 'Solo Adventure', 120,
     'Choose somewhere you’ve been curious about. You don’t need company to enjoy something new.',
     'Building comfort with your own company is one of the most powerful steps in healing.',
     3)
ON CONFLICT (slug) DO UPDATE SET
    title            = EXCLUDED.title,
    category         = EXCLUDED.category,
    category_label   = EXCLUDED.category_label,
    duration_minutes = EXCLUDED.duration_minutes,
    instructions     = EXCLUDED.instructions,
    why_it_fits      = EXCLUDED.why_it_fits,
    sort_order       = EXCLUDED.sort_order;

-- Every activity must now have the fields a card needs. If this fails, the
-- activities table has old rows without a slug: see backend/README.md.
ALTER TABLE activities
    ALTER COLUMN slug             SET NOT NULL,
    ALTER COLUMN category_label   SET NOT NULL,
    ALTER COLUMN duration_minutes SET NOT NULL,
    ALTER COLUMN instructions     SET NOT NULL,
    ALTER COLUMN why_it_fits      SET NOT NULL;
