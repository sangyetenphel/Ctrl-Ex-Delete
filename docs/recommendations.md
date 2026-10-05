# Activity Recommendations (Week 2 Backend)

Owner: Alexa. This covers how recommendations get made, the new endpoints, and how to change the rules.

## How it works

1. The app sends a check-in (`POST /check-ins`). Nothing changed for the app here.
2. In the same database transaction, the backend picks activities for that check-in and saves them to the `recommendations` table with a `position` (1, 2, 3).
3. The app fetches the cards (`GET /recommendations`).
4. The user picks a card (`POST /recommendations/{recommendation_id}/select`) and saves it to `activity_selections`.
5. When they finish it, the app logs it (`POST /activities/{activity_id}/logs`) to `activity_logs`.

The Python code is the only thing that creates recommendations.

## Endpoints

Every request except `GET /activities` needs the `X-Installation-ID` header (a UUID), the same as check-ins.

| Method | Path | Body | Returns |
|---|---|---|---|
| GET | `/recommendations` | none | Cards for the user's latest check-in. 404 if they haven't checked in yet. |
| POST | `/recommendations/{recommendation_id}/select` | none | The saved selection. Tapping twice returns the same selection, not an error. 404 if the card doesn't belong to this installation. |
| POST | `/activities/{activity_id}/logs` | `{"mood_after": 7, "local_date": "2026-10-05"}` | The saved log. `mood_after` is optional, 1–10. 404 if the activity doesn't exist. |
| GET | `/activities` | none | Full active catalog (for testing). |

Example card from `GET /recommendations`:

```json
{
  "recommendation_id": 7,
  "position": 1,
  "activity": { "id": 2, "slug": "walk_without_social_media", "title": "...", "category": "outdoor_movement", "duration_minutes": 20, "...": "..." },
  "reason": "Moving your body helps break up looping thoughts. Your urge to reach out is high, and getting away from your phone helps you ride it out."
}
```

**For the iOS app:** show `reason`, not `activity.why_it_fits`. `reason` is written from the user's actual check-in. `why_it_fits` is fixed text in the table and can be wrong.

## The rules (`backend/app/recommendations.py`)

Every category starts with a score of 1.0, and check-in answers add to it:

| Check-in answer | Boost |
|---|---|
| feeling: heavy | mindfulness_rest +2 |
| feeling: getting_through | mindfulness_rest +1, social_connection +0.5 |
| feeling: missing_them | outdoor_movement +1.5, mindfulness_rest +0.5 |
| feeling: hopeful | solo_exploration +1.5, social_connection +1 |
| hardest area: feeling_lonely | social_connection +2 |
| hardest area: missing_relationship | outdoor_movement +1, mindfulness_rest +1 |
| hardest area: wanting_answers | mindfulness_rest +1.5 |
| hardest area: resisting_contact | outdoor_movement +2 |
| hardest area: rebuilding_confidence | solo_exploration +2 |
| contact urge 7–10 | outdoor_movement +2 |
| contact urge 4–6 | outdoor_movement +1 |

Then:

- **Energy filters by length.** Low energy only gets activities of 15 minutes or less, medium gets 45 or less, and high gets anything.
- **Already done today is skipped.** Anything logged today doesn't get recommended again that day.
- **Up to 3 cards.** They're picked one per category, highest score first, so the list is varied but led by the best fit. Within a category, `sort_order` decides.

These weights are a first draft. They should be reviewed against what we learn from the psychology professor.

## Changing things

- **To tweak weights:** edit the dictionaries at the top of `recommendations.py`, then run the tests.
- **To add or rename a category** (for example, moving to the README's four categories): update `Category` in `schemas.py`, the dictionaries in `recommendations.py`, and the `activities_category_check` constraint in the database (that needs a new migration).
- **To change the number of cards:** change `limit` in `recommend()`.

## Testing

From `backend/` with the venv active:

```bash
python -m pytest
```

There are 6 tests covering the rules (no database needed). To try the endpoints by hand, run `uvicorn app.main:app --reload` and open `http://127.0.0.1:8000/docs`.

## Known gaps

- **The catalog is too small.** With only 3 activities, a low-energy check-in gets 1 card, because the other two are 20 and 120 minutes. We need a few short activities in every category, and none exist for `social_connection` yet.
- **Multiple check-ins per day are allowed.** Each one gets its own cards, and `GET /recommendations` always uses the latest. We should decide as a team if that's what we want.