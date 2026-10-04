-- Ctrl+Ex+Delete: Neon PostgreSQL schema
-- Week 1: installations + check_ins
-- Week 2 (preview): activities + activity_logs (feeds the Insights charts)

-- ─────────────────────────────────────────────
-- WEEK 1
-- ─────────────────────────────────────────────

-- One row per app install. The iOS app generates the UUID on first launch,
-- stores it in the Keychain, and sends it in the X-Installation-ID header.
CREATE TABLE installations (
    id            UUID PRIMARY KEY,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- "Where are you right now?" screen
CREATE TABLE check_ins (
    id               BIGSERIAL PRIMARY KEY,
    installation_id  UUID NOT NULL REFERENCES installations(id) ON DELETE CASCADE,

    -- "How are you feeling?" (single choice)
    feeling          TEXT NOT NULL
        CHECK (feeling IN ('heavy', 'getting_through', 'missing_them', 'hopeful')),

    -- "How strong is the urge to contact them?" (slider 1-10)
    contact_urge     SMALLINT NOT NULL
        CHECK (contact_urge BETWEEN 1 AND 10),

    -- "How is your energy today?"
    energy_level     TEXT NOT NULL
        CHECK (energy_level IN ('low', 'medium', 'high')),

    -- "What feels hardest right now?" (multi-select chips; may be empty)
    hardest_areas    TEXT[] NOT NULL DEFAULT '{}'
        CHECK (hardest_areas <@ ARRAY[
            'feeling_lonely',
            'missing_relationship',
            'wanting_answers',
            'resisting_contact',
            'rebuilding_confidence'
        ]::TEXT[]),

    -- The user's calendar day, sent by the app, so Mon-Sun charts
    -- don't break on timezones. created_at is the exact moment.
    local_date       DATE NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_check_ins_install_date
    ON check_ins (installation_id, local_date);


-- ─────────────────────────────────────────────
-- WEEK 2 PREVIEW (activity recommendations + Insights)
-- ─────────────────────────────────────────────

-- Catalog of activities the app can suggest
CREATE TABLE activities (
    id          SERIAL PRIMARY KEY,
    title       TEXT NOT NULL,
    category    TEXT NOT NULL
        CHECK (category IN ('outdoor_movement', 'mindfulness_rest',
                            'solo_exploration', 'social_connection')),
    is_active   BOOLEAN NOT NULL DEFAULT TRUE
);

-- One row each time a user completes an activity
-- Feeds "Mood after activities" and "What you made time for"
CREATE TABLE activity_logs (
    id               BIGSERIAL PRIMARY KEY,
    installation_id  UUID NOT NULL REFERENCES installations(id) ON DELETE CASCADE,
    activity_id      INT NOT NULL REFERENCES activities(id),
    mood_after       SMALLINT
        CHECK (mood_after BETWEEN 1 AND 10),   -- "Rated 1-10 after each activity"
    local_date       DATE NOT NULL,
    completed_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_activity_logs_install_date
    ON activity_logs (installation_id, local_date);
