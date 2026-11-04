-- 018: Ced's personalised message in the healing room.
--
-- Additive only. The catalog is loaded by scripts/seed_room_messages.py
-- (`scripts.migrate` runs it); the rules that pick a pattern from a check-in
-- live in app/room_messages.py.
--
--   room_messages            the curated catalog: stable id, pattern, text,
--                            active flag, order, timestamps
--   check_in_room_messages   the message given to a check-in, with the text
--                            as it was shown (later catalog edits don't change
--                            it). One per check-in: check_in_id is the key, so
--                            two requests at once can't assign two messages.
--
-- The message describes the check-in's answers gently; it is not an
-- assessment, diagnosis or risk score. Safe to run again.

CREATE TABLE IF NOT EXISTS room_messages (
    id          TEXT PRIMARY KEY,                    -- e.g. 'strong-urge-01'
    pattern     TEXT NOT NULL CHECK (pattern IN (
                    'before_check_in', 'strong_urge', 'heavy_low_energy', 'low_energy',
                    'lonely', 'heavy_some_energy', 'lighter_with_energy', 'general')),
    text        TEXT NOT NULL CHECK (char_length(text) BETWEEN 10 AND 110),
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order  INT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_room_messages_pattern
    ON room_messages (pattern, is_active, sort_order);

CREATE TABLE IF NOT EXISTS check_in_room_messages (
    check_in_id  BIGINT PRIMARY KEY REFERENCES check_ins(id) ON DELETE CASCADE,
    message_id   TEXT NOT NULL REFERENCES room_messages(id),
    pattern      TEXT NOT NULL,
    text         TEXT NOT NULL,                      -- exactly what was shown
    assigned_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
