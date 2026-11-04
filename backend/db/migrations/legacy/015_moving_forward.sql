-- 015: The moving-forward check-in ("Do you feel ready to close this chapter?").
--
-- One row per installation, saved when the user chooses "I'm ready to move
-- forward". Saving again (a repeated tap, a retry, or revisiting later)
-- updates the same row, so there is never more than one final reflection.
-- moved_forward_on keeps the day they first chose it.
--
-- Moving forward deletes nothing and locks nothing: all other data stays,
-- and the app keeps working as before. Safe to run again.

CREATE TABLE IF NOT EXISTS moving_forward_check_ins (
    installation_id   UUID PRIMARY KEY REFERENCES installations(id) ON DELETE CASCADE,

    -- The reflection questions they ticked (may be empty).
    reflected_on      TEXT[] NOT NULL DEFAULT '{}'
        CHECK (reflected_on <@ ARRAY[
            'without_overwhelm',
            'own_routines',
            'urge_manageable',
            'connected_to_self',
            'ready_not_pressured'
        ]::TEXT[]),

    -- "Anything you want to remember from this chapter?" In their own words.
    note              TEXT CHECK (note IS NULL OR char_length(note) <= 4000),

    -- The user's local calendar day when they first chose to move forward.
    moved_forward_on  DATE NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
