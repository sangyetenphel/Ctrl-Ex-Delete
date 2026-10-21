-- 015: A personal reason on each recommendation ("Why this fits today").
--
-- recommendations.reason is one sentence naming the check-in answer that
-- picked the card (app/recommendation_rules.py reason()), e.g. "You said not
-- reaching out is one of the hardest parts right now, so getting outside or
-- moving a little might help." It is saved with the card, so the text stays
-- the same however often the cards are loaded.
--
-- Existing cards keep reason = NULL; the app then shows only the activity's
-- own why_it_fits, as before. No other table changes. Safe to run again.

ALTER TABLE recommendations ADD COLUMN IF NOT EXISTS reason TEXT;
