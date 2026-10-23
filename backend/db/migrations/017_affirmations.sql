-- 017: The affirmation catalog for the "Grow with Kindness" plant game.
--
-- Additive only. The catalog itself (30 affirmations in 5 themes, the
-- research sources and how they relate) is loaded by
-- scripts/seed_affirmations.py, which `scripts.migrate` runs after migrating.
--
--   affirmation_themes        the five themes, with display labels
--   affirmations              what the game shows: stable id, text, theme,
--                             language, active flag, timestamps
--   affirmation_sources       peer-reviewed sources, what they found and
--                             their limits
--   affirmation_theme_sources which principle each source supports for a
--                             theme, and why (sources informed the themes and
--                             wording; none tested these exact sentences)
--   affirmation_notes         editorial notes per affirmation, kept apart
--                             from the text the game shows
--
-- Nothing here is about users: the game saves no audio, transcripts or
-- progress. Safe to run again.

CREATE TABLE IF NOT EXISTS affirmation_themes (
    code        TEXT PRIMARY KEY,
    label       TEXT NOT NULL,
    sort_order  INT  NOT NULL
);

CREATE TABLE IF NOT EXISTS affirmations (
    id          TEXT PRIMARY KEY,                    -- stable, e.g. 'kindness-01'; the app bundles the same ids
    text        TEXT NOT NULL CHECK (char_length(text) BETWEEN 3 AND 120),
    theme       TEXT NOT NULL REFERENCES affirmation_themes(code),
    language    TEXT NOT NULL DEFAULT 'en',
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order  INT  NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (language, text)
);

CREATE INDEX IF NOT EXISTS idx_affirmations_active
    ON affirmations (language, is_active, sort_order);

CREATE TABLE IF NOT EXISTS affirmation_sources (
    code         TEXT PRIMARY KEY,                   -- e.g. 'NEFF2003'
    citation     TEXT NOT NULL,
    url          TEXT NOT NULL,                      -- the DOI link
    kind         TEXT NOT NULL CHECK (kind IN (
                     'values_self_affirmation', 'positive_self_statements', 'self_compassion',
                     'breakup_research', 'acceptance', 'self_efficacy')),
    finding      TEXT NOT NULL,                      -- what the source actually reports
    limitations  TEXT NOT NULL                       -- what it does not show
);

CREATE TABLE IF NOT EXISTS affirmation_theme_sources (
    theme        TEXT NOT NULL REFERENCES affirmation_themes(code),
    source_code  TEXT NOT NULL REFERENCES affirmation_sources(code),
    principle    TEXT NOT NULL,                      -- the idea the source supports
    rationale    TEXT NOT NULL,                      -- how it shaped this theme's wording
    PRIMARY KEY (theme, source_code)
);

CREATE TABLE IF NOT EXISTS affirmation_notes (
    affirmation_id  TEXT PRIMARY KEY REFERENCES affirmations(id),
    note            TEXT NOT NULL
);
