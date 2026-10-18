-- 009: Make "Sit somewhere with sunlight" explain itself without assuming an answer.
--
-- Its "Why this fits today" text came from the prototype and said
-- "Your energy is low and the urge to reach out is moderate." The activity is
-- now recommended to anyone it suits, including people who said their energy
-- is high, so that sentence could contradict their check-in. Every other
-- activity's text already describes the activity, not the user's answers.
-- Only this one catalog row changes; no user data is touched.

UPDATE activities
SET why_it_fits = 'A few quiet minutes in natural light give your nervous system a soft reset.'
WHERE slug = 'sit_in_sunlight';
