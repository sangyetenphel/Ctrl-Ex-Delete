-- 002: Everything the activity recommendation screen needs.
--
-- 1. Extra columns on activities so a card can be shown from the database
--    (the old table only had title + category).
-- 2. recommendations: which activities were suggested for which check-in.
-- 3. activity_selections: which suggestion the user picked ("I'll try this").

ALTER TABLE activities
    ADD COLUMN IF NOT EXISTS slug             TEXT UNIQUE,  -- stable name, e.g. 'sit_in_sunlight'
    ADD COLUMN IF NOT EXISTS category_label   TEXT,         -- shown on the card, e.g. 'Gentle Reset'
    ADD COLUMN IF NOT EXISTS duration_minutes SMALLINT CHECK (duration_minutes > 0),
    ADD COLUMN IF NOT EXISTS instructions     TEXT,
    ADD COLUMN IF NOT EXISTS why_it_fits      TEXT,
    ADD COLUMN IF NOT EXISTS sort_order       SMALLINT NOT NULL DEFAULT 0;

-- One row per activity suggested after a check-in.
-- position is the card order on screen (1 = first card).
CREATE TABLE IF NOT EXISTS recommendations (
    id               BIGSERIAL PRIMARY KEY,
    installation_id  UUID NOT NULL REFERENCES installations(id) ON DELETE CASCADE,
    check_in_id      BIGINT NOT NULL REFERENCES check_ins(id) ON DELETE CASCADE,
    activity_id      INT NOT NULL REFERENCES activities(id),
    position         SMALLINT NOT NULL CHECK (position >= 1),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (check_in_id, position),
    UNIQUE (check_in_id, activity_id)
);

CREATE INDEX IF NOT EXISTS idx_recommendations_install
    ON recommendations (installation_id, check_in_id);

-- One row when the user taps "I'll try this" on a recommendation.
-- UNIQUE(recommendation_id) means tapping twice never makes two rows.
CREATE TABLE IF NOT EXISTS activity_selections (
    id                 BIGSERIAL PRIMARY KEY,
    installation_id    UUID NOT NULL REFERENCES installations(id) ON DELETE CASCADE,
    recommendation_id  BIGINT NOT NULL UNIQUE REFERENCES recommendations(id) ON DELETE CASCADE,
    selected_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_activity_selections_install
    ON activity_selections (installation_id, selected_at);
