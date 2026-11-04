-- 014: At most one check-in per installation per local calendar day.
--
-- "Today" is the user's own calendar day: the app sends it as local_date
-- (YYYY-MM-DD in the phone's current time zone), never a rolling 24 hours or
-- the server's UTC date. POST /check-ins reuses the day's check-in instead of
-- adding a second one (storage.create_check_in).
--
-- Non-destructive. Check-ins made before this rule may already repeat a day
-- (find them with the query below). They are all kept, with their
-- recommendations and selections; only the latest one of such a day counts
-- for the day (it's the one whose cards the app shows), and the earlier ones
-- get counts_for_day = false. The unique index covers counting rows only.
--
--   SELECT installation_id, local_date, count(*) FROM check_ins
--   GROUP BY 1, 2 HAVING count(*) > 1;
--
-- Safe to run again.

ALTER TABLE check_ins
    ADD COLUMN IF NOT EXISTS counts_for_day BOOLEAN NOT NULL DEFAULT TRUE;

UPDATE check_ins c
SET counts_for_day = FALSE
WHERE c.counts_for_day
  AND EXISTS (
      SELECT 1 FROM check_ins later
      WHERE later.installation_id = c.installation_id
        AND later.local_date = c.local_date
        AND (later.created_at, later.id) > (c.created_at, c.id)
  );

CREATE UNIQUE INDEX IF NOT EXISTS check_ins_one_per_day
    ON check_ins (installation_id, local_date)
    WHERE counts_for_day;
