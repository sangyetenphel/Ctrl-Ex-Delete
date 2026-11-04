-- 008: How many messages each installation sent to Ced per day.
--
-- Only a count, for the daily limit that protects the AI provider's quota.
-- Conversation text is never stored anywhere (see app/ced/).
--
-- Safe to run again.

CREATE TABLE IF NOT EXISTS ced_usage (
    installation_id  UUID NOT NULL REFERENCES installations(id) ON DELETE CASCADE,
    usage_date       DATE NOT NULL,          -- UTC day
    messages         INT NOT NULL DEFAULT 0 CHECK (messages >= 0),
    PRIMARY KEY (installation_id, usage_date)
);
