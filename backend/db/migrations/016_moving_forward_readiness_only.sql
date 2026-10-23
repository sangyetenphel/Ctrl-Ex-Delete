-- 016: The moving-forward check-in is now the five readiness questions only.
--
-- The optional "Anything you want to remember from this chapter?" note was
-- removed from the app, so its column goes too (any saved notes with it).
-- "I'm ready to move forward" now needs all five questions ticked; the API
-- checks that (MovingForwardSave), and existing rows are left as they are.
-- Safe to run again.

ALTER TABLE moving_forward_check_ins DROP COLUMN IF EXISTS note;
