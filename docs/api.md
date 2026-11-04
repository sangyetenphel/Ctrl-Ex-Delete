# Ctrl+Ex+Delete API

This is the contract between the iOS app and the FastAPI backend.
**Field names and allowed values must match exactly.** If something here needs to change, update this doc in the same pull request as the code.

- **Status:** check-ins, recommendations, activity status (one in progress), bookmarks, scrapbook photos, reflections (completion), progress summary, insights, Ced chat, Ced voice calls
- **Deployed base URL:** `https://ctrl-ex-delete-api.onrender.com` (Render Free; see `backend/README.md`, "Deploying to Render")
- **Local base URL:** `http://127.0.0.1:8000` (works from the iOS Simulator on the same Mac)
- **Interactive docs:** `http://127.0.0.1:8000/docs` (while the backend is running)

---

## Installation ID (how users are identified)

There are no accounts. Instead:

1. On first launch, the app generates a UUID (`UUID().uuidString`).
2. The app saves it in the **Keychain** and reuses it forever after.
3. Every request (except `/health` and `/health/db`) sends it in this header:

```
X-Installation-ID: A4781CB6-8637-4789-BD52-9AB075D2AB1C
```

Notes:
- It must be a valid UUID, or the request is rejected with `422`.
- Uppercase or lowercase both work. The server always **returns it lowercase**, so don't compare IDs as plain strings in Swift. Compare them as `UUID` values.
- The server registers a new installation automatically on its first check-in. No separate signup call is needed.

---

## General rules

- All request and response bodies are JSON (`Content-Type: application/json`).
- All JSON keys are **snake_case** (`contact_urge`, not `contactUrge`).
- Dates:
  - `local_date` is the user's calendar day, sent by the app: `"YYYY-MM-DD"` (e.g. `"2026-09-27"`).
  - `created_at` is set by the server in UTC with fractional seconds: `"2026-09-28T03:35:34.053814Z"`.

---

## `GET /health`

Checks that the server is running. No header needed.

**Response `200`**
```json
{ "status": "ok" }
```
It doesn't touch the database, so it answers quickly (Render's health check uses it).

## `GET /health/db`

Checks that the server can reach the database. No header needed.

**Response `200`:** `{ "status": "ok", "database": "ok" }`. **`503`** when Neon can't be reached (same body as other database errors).

---

## `POST /check-ins`

Saves a check-in. Called when the user taps **Enter my room**.

**Headers:** `X-Installation-ID` (required), `Content-Type: application/json`

**Request body**
```json
{
  "feeling": "missing_them",
  "contact_urge": 4,
  "energy_level": "medium",
  "hardest_areas": ["feeling_lonely", "resisting_contact"],
  "local_date": "2026-09-27"
}
```

| Field | Type | Required | Allowed values |
|---|---|---|---|
| `feeling` | string | yes | `heavy`, `getting_through`, `missing_them`, `hopeful` |
| `contact_urge` | integer | yes | `1` to `10` (the app's slider starts at `1`, so an untouched slider sends `1`; there's no server default) |
| `energy_level` | string | yes | `low`, `medium`, `high` |
| `hardest_areas` | array of strings | no (defaults to `[]`) | `feeling_lonely`, `missing_relationship`, `wanting_answers`, `resisting_contact`, `rebuilding_confidence` |
| `local_date` | string (date) | yes | `"YYYY-MM-DD"` |

**How the screen maps to values**

| On screen | Value sent |
|---|---|
| Heavy | `heavy` |
| Getting through | `getting_through` |
| Missing them | `missing_them` |
| Hopeful | `hopeful` |
| Feeling lonely | `feeling_lonely` |
| Missing the relationship | `missing_relationship` |
| Wanting answers | `wanting_answers` |
| Resisting contact | `resisting_contact` |
| Rebuilding confidence | `rebuilding_confidence` |

The UI text can change freely. Only the values sent to the API need to stay the same.

Saving a check-in also creates its activity recommendations (same database transaction), so they're ready for `GET /recommendations/latest`.

**One check-in per local calendar day.** `local_date` is the user's own calendar day: the app's current date in the phone's current time zone (midnight to midnight). The server never uses its own clock, UTC or a rolling 24 hours. If this installation already has a check-in for that `local_date`, nothing is saved and no new recommendations are made: the response is **`200 OK`** with the day's existing check-in (its original answers). This covers a repeated tap, a retry after a lost response, and two requests at the same moment (the database's unique index lets exactly one through). An activity in progress from an earlier day stays in progress.

**Response `201 Created`** (or `200 OK` with the existing one, see above): the saved check-in, with three server-generated fields added:
```json
{
  "feeling": "missing_them",
  "contact_urge": 4,
  "energy_level": "medium",
  "hardest_areas": ["feeling_lonely", "resisting_contact"],
  "local_date": "2026-09-27",
  "id": 1,
  "installation_id": "a4781cb6-8637-4789-bd52-9ab075d2ab1c",
  "created_at": "2026-09-28T03:35:34.053814Z"
}
```

---

## Ced's room message (`room_message`)

`POST /check-ins` and `GET /check-ins/today` include Ced's message for the healing room, so the app needs no extra request:

```json
"room_message": {"id": "strong-urge-01", "pattern": "strong_urge", "text": "That pull can feel strong. Let’s pause and make a little space for you."}
```
- **With a check-in:** one message is chosen by the rules in `backend/app/room_messages.py` and saved with the check-in (`check_in_room_messages`, text included), so it never changes, even if the catalog is edited later. Check-ins made before this get theirs the first time it's needed; two requests at once still give one.
- **Before today's check-in:** `GET /check-ins/today` returns a "let's check in" message (`pattern: "before_check_in"`), the same all day.
- `null` only if no message could be loaded; the check-in itself is never affected.
- It describes today's answers gently. It is not a risk assessment or a judgement about readiness.

---

## `GET /check-ins/today?local_date=YYYY-MM-DD`

Has the user checked in on their local day? The app asks on every start (including after a force-close) and when it returns on a new day, before choosing the welcome, check-in or room screen. Changes nothing.

**Headers:** `X-Installation-ID` (required)

**Response `200`**
```json
{"local_date": "2026-10-17", "check_in": null, "has_any_check_in": true}
```
- `check_in`: that day's check-in (same shape as above), or `null` if there isn't one yet.
- `has_any_check_in`: `false` for someone who has never checked in (the app shows the welcome screen).

If this request fails, the app shows a connection message with Try again. It never treats a failure as "hasn't checked in".

---

## `GET /check-ins`

Returns all check-ins for this installation, **newest first**.

**Headers:** `X-Installation-ID` (required)

**Response `200`**: an array of check-ins in the same shape as the `201` response above. It returns `[]` if there are none yet. Each installation only ever sees its own check-ins.

---

## `GET /recommendations/latest`

Activity cards for this installation's **most recent** check-in. Called when the Activities screen opens.

**Headers:** `X-Installation-ID` (required)

**Response `200`**
```json
{
  "check_in_id": 12,
  "check_in_local_date": "2026-10-04",
  "check_in": {
    "feeling": "heavy",
    "contact_urge": 8,
    "energy_level": "low",
    "hardest_areas": ["wanting_answers"]
  },
  "recommendations": [
    {
      "id": 31,
      "position": 1,
      "selected_at": null,
      "activity": {
        "id": 1,
        "slug": "sit_in_sunlight",
        "title": "Sit somewhere with sunlight.",
        "category": "mindfulness_rest",
        "category_label": "Mindfulness & Rest",
        "duration_minutes": 10,
        "instructions": "No productivity needed. ...",
        "why_it_fits": "A few quiet minutes in natural light ..."
      }
    }
  ]
}
```

- `recommendations` is in card order (`position` 1, 2, 3), never more than 3, and never the same activity twice.
- `id` is the **recommendation** id. Use it to record a selection.
- `status`: `null` (not chosen, or the attempt was abandoned), `in_progress` or `completed`. `selected_at` and `completed_at` go with it.
- `is_saved`: bookmarked with **Save for later**. A saved activity can only be the **last** card of a later check-in, and only if it suits that check-in (see below).
- `energy_level` (`low`, `medium`, `high`): the activity's overall demand, separate from `duration_minutes`. Both are editorial estimates.
- **Retired activities** (no longer in the catalog) aren't recommended or offered. A card from an older check-in whose activity was retired is left out of this list unless it was already chosen (in progress or completed), so history still shows and an activity in progress can still be finished. Choosing an unchosen retired card answers `409`.
- `category` is one of `outdoor_movement`, `mindfulness_rest`, `solo_exploration`, `social_connection`: the stable key. The app picks the card's icon and colors from it; never show it.
- `category_label` is the category's display name, the same everywhere (cards, reflections, Story, bookmarks, Insights). It is stored on each activity and kept in step by the database (migration `011`): the names are defined once in the `activity_categories` table, a trigger fills `category_label` on every insert or update, and a foreign key on (`category`, `category_label`) rejects any mismatched pair. To rename a category, update its row in `activity_categories`; the change cascades to every activity.

  | `category` | `category_label` |
  |---|---|
  | `mindfulness_rest` | Mindfulness & Rest |
  | `outdoor_movement` | Outdoor & Movement |
  | `solo_exploration` | Solo Exploration |
  | `social_connection` | Social Connection |
- `check_in`: the answers these cards were chosen from. The app uses `feeling` for the page heading.
- **No check-ins yet:** `200` with `"check_in_id": null`, `"check_in_local_date": null`, `"check_in": null`, `"recommendations": []`. The app shows "Check in first".

**How the cards are chosen** (`backend/app/recommendation_rules.py`, run when the check-in is saved):

| Answer | Effect |
|---|---|
| `energy_level` | Decides which activities are eligible, by each activity's own `energy_level` (its overall physical, cognitive, social and preparation demand, separate from its duration). Low: low-demand only. Medium: low or medium. High: any. An activity whose demand matches today's energy gets a small bonus. Nothing above today's allowance is added to fill the deck, so it can have fewer than 3 cards. |
| `feeling` | Pushes categories up: heavy → Mindfulness & Rest; getting through → Outdoor & Movement; missing them → Outdoor & Movement, then Mindfulness & Rest; hopeful → Solo Exploration and Social Connection. |
| `hardest_areas` | Each one pushes categories up (strongest signal): feeling lonely → Social Connection; missing the relationship → Solo Exploration; wanting answers → Mindfulness & Rest; resisting contact → Outdoor & Movement; rebuilding confidence → Solo Exploration. |
| `contact_urge` | 7 or more: quick, gentle movement comes first: activities marked as movement (`involves_movement`, e.g. a short walk or dance; sitting outside doesn't count), 20 min or less, and not high demand. Other activities of 20 min or less get a smaller boost. A strong urge never boosts strenuous activities. Below 7 it doesn't change the cards. |

**Card order:**

1. At most **3** unique cards. Only activities short enough for today's energy are suitable; nothing too long is added just to fill the deck, so a low-energy day can get fewer.
2. Every card but the last comes from today's answers only (best score first, at most 2 cards per category). Saved activities are never picked here.
3. The last card may be **one** saved activity, if it fits today's energy **and** today's feeling, hardest areas or a strong urge point to its category. A saved activity completed in the last 3 days isn't offered. Otherwise the last card is the next regular recommendation.

Activities from the last 5 check-ins or completed in the last 7 days go to the back of the line. Ties keep catalog order. Which activities were chosen is saved with the check-in, so the same cards come back every time the screen opens.

---

## Activity status: one activity at a time

An **I'll try this** choice is an `activity_selections` row with a `status`:

```
in_progress ──(POST /reflections)──────────────▶ completed
     └──────(POST /activity-selections/{id}/abandon)──▶ abandoned
```

The database allows **at most one `in_progress` activity per installation** (a partial unique index), so two simultaneous requests can't both start one. Choosing an activity never completes it.

### `POST /recommendations/{id}/selection`

**I'll try this.** No body. **`201`** with the new selection; **`200`** if this card is already the activity in progress (repeated taps never create a second row):
```json
{ "id": 57, "recommendation_id": 120, "activity_id": 1, "check_in_id": 43,
  "status": "in_progress", "selected_at": "2026-10-13T05:49:20Z", "ended_at": null }
```
**`409`** if another activity is in progress (`"You already have an activity in progress. Finish its reflection or change activity first."`) or this card is already completed. **`404`** if the card isn't yours.

### `GET /activity-selections/current`

The activity in progress, or `{"selection": null}`. This is how it survives an app restart.
```json
{ "selection": { "selection_id": 57, "recommendation_id": 120, "check_in_id": 43,
                 "selected_at": "…", "activity": { "id": 1, "slug": "sit_in_sunlight", "…": "…" } } }
```

### `POST /activity-selections/{id}/abandon`

**Change activity.** Sets the activity in progress aside: it does **not** count as completed, the card can be chosen again later, and saved memories are untouched. Returns the selection with `"status": "abandoned"`. Repeating it is harmless. **`409`** if it's already completed.

---

## Bookmarks (`/bookmarks`)

**Save for later.** Never selects or completes anything.

| Call | Result |
|---|---|
| `PUT /bookmarks/{activity_id}` | `201` saved, `200` if already saved (no duplicates), `404` unknown activity |
| `DELETE /bookmarks/{activity_id}` | `204` (also when it wasn't saved) |
| `GET /bookmarks` | `[{"activity": {…}, "saved_at": "…"}]`, newest first |

---

## Scrapbook photos (`/scrapbook/photos`)

Photos go straight from the app to a **private** S3 bucket through short-lived presigned URLs; the API never sees the image bytes and never exposes AWS credentials. Answers `503` until the server has AWS settings.

1. `POST /scrapbook/photos` (no body) → `201` `{"id": 10, "upload_url": "https://…"}` (URL valid 5 minutes).
2. `PUT` the JPEG to `upload_url` with `Content-Type: image/jpeg` (no `X-Installation-ID` header).
3. `POST /scrapbook/photos/{id}/complete` → `200` with a temporary `image_url` (1 hour). `409` if the file isn't in S3 yet, `413` if it's over 5 MB. Uploads that never become part of a memory are deleted (row and file) a day later, the next time that installation starts an upload.

The photo becomes part of a memory through `POST /reflections`. `DELETE /scrapbook/photos/{id}` (`204`) removes the file; its memory is kept without the photo. S3 object keys are random (`scrapbook/<uuid>.jpg`) and never contain the installation ID.

---

## `POST /reflections`

**Add to my scrapbook.** Saves the memory and **completes** the activity in progress, in one transaction. **Every field is required**: `activity_selection_id`, `thought_about_ex`, `mood_change`, a non-blank `note` ("What did you notice?"; whitespace-only counts as blank, and it is saved trimmed) and `photo_id`. Upload the photo first (above) and pass its `id`. Anything missing or invalid is rejected with **`422`** before anything is saved, so the activity stays in progress.

```json
{
  "activity_selection_id": 15,
  "photo_id": 10,
  "note": "The walk cleared my head",
  "thought_about_ex": "a_little",
  "mood_change": "a_little_better",
  "local_date": "2026-10-13"
}
```

| Field | Allowed values |
|---|---|
| `thought_about_ex` | `not_really`, `a_little`, `a_lot` |
| `mood_change` | `worse`, `about_the_same`, `a_little_better`, `much_better` (stored as chosen; the mood chart derives fixed internal scores from it, see `GET /insights`) |
| `note` | **required**, not blank. The one text answer, "What did you notice?". Up to 1000 characters; shown as the memory's quote |
| `photo_id` | **required**. A photo of **this installation** that finished uploading (`POST /scrapbook/photos` → PUT → `/complete`) and isn't in another memory. Another installation's or an unknown photo: `404`; not uploaded yet or already used: `409` |
| `noticed` | **deprecated.** Older app builds sent a second text answer here. It is still accepted (up to 1000 characters) and joined into `note`, so it isn't lost. Migration `010` did the same for saved memories and removed the column |


**Response `201 Created`**, or **`200 OK`** if that selection already has a reflection (the first one is returned unchanged, so retries never duplicate):
```json
{
  "id": 8,
  "activity_selection_id": 15,
  "activity": { "id": 2, "slug": "walk_without_social_media", "…": "…" },
  "note": "The walk cleared my head",
  "thought_about_ex": "a_little",
  "mood_change": "a_little_better",
  "local_date": "2026-10-13",
  "created_at": "2026-10-13T04:38:31.554Z",
  "photo_id": 10,
  "image_url": "https://…"
}
```
`created_at` is when it was saved, which is also when the activity was completed. `image_url` is temporary (1 hour) and `null` without a photo. **`404`** for a selection or photo that isn't yours; **`409`** if the activity was abandoned, or the photo isn't uploaded yet or already belongs to another memory.

## `DELETE /reflections/{id}`

Deletes a memory: its answers, its photo row and the photo file in S3 (`204`; `404` if it isn't yours). The activity **still counts as completed**, because its completion date is stored on the activity itself.

## `GET /reflections`

Every memory, newest first, in the same shape. The Scrapbook's "Recent Memories".

---

## `GET /progress/summary`

```json
{
  "journey_started_on": "2026-10-13",
  "check_ins": 1,
  "activities_selected": 1,
  "activities_completed": 1,
  "memories": 1,
  "photos": 1,
  "milestones": [
    { "label": "Started the journey", "reached_on": "2026-10-13" },
    { "label": "Completed a first activity", "reached_on": "2026-10-13" },
    { "label": "Added a first photo memory", "reached_on": "2026-10-13" },
    { "label": "5 activities milestone", "reached_on": null },
    { "label": "Moving forward check-in", "reached_on": null }
  ]
}
```
`journey_started_on` is the first check-in's `local_date`; the app shows "Day N" from it. `reached_on: null` means not reached yet ("Upcoming").

---

## `GET /affirmations`

The curated catalog for the **Grow with Kindness** plant game: the active affirmations in catalog order. The same for everyone (`X-Installation-ID` isn't needed). Editorial notes and research sources are never included.

```json
{"language": "en",
 "affirmations": [{"id": "kindness-01", "text": "I can be gentle with myself today.", "theme": "self_kindness", "theme_label": "Self-kindness"}]}
```
- `id`s are stable; the app bundles the same catalog (`Resources/Affirmations.json`) and caches the last successful fetch, so the game never waits for this request and works offline.
- `?language=` defaults to `en`; other languages return an empty list for now.
- The game saves nothing: no audio, transcripts or progress reach the backend.

---

## `GET /progress/bookshelf`

The healing room's bookshelf: **one book per completed activity** (an activity counts as completed once its reflection is saved), earliest first, so each book keeps its place. Read-only.

```json
{"capacity": 32, "total_completed": 3,
 "books": [{"selection_id": 7, "category": "mindfulness_rest", "completed_on": "2026-10-12"}]}
```
- Only completions count: "I'll try this", "Save for later" and check-ins never add a book. Repeating a reflection submission returns the first one, so it adds nothing; the same activity completed again on another day is a new book.
- Deleting a memory keeps its book (the activity stays completed). Abandoned activities have none.
- `books` holds at most `capacity` (the first 32 completions); `total_completed` keeps counting. Nothing else depends on it (the moving-forward check-in doesn't).

---

## `GET /insights?period=week|month&today=YYYY-MM-DD`

The Progress screen, calculated from this installation's records. `today` is the user's **local** calendar day, so the week (Monday–Sunday) and month boundaries follow their time zone, like `local_date` everywhere else.

```json
{
  "period": "week", "start": "2026-10-12", "end": "2026-10-18",
  "has_data": true, "check_in_days": 1, "completed": 2,
  "urges": [ { "label": "Mon", "start": "2026-10-12", "end": "2026-10-12", "value": 6, "check_ins": 2 } ],
  "moods": [ { "response": "worse", "label": "Worse", "count": 0 } ],
  "mood_points": [ { "label": "Mon", "start": "2026-10-12", "end": "2026-10-12", "value": 4.5,
                     "answers": ["worse", "a_little_better"] } ],
  "categories": [ { "category": "outdoor_movement", "label": "Outdoor & Movement", "count": 1, "percent": 50 } ],
  "takeaway": { "headline": "…", "body": "…" },
  "observations": [ "You completed 2 activities this week." ]
}
```

- **urges:** one bar per day (week) or per week of the user's own journey (month). Month bars are seven-day weeks counted from the first check-in's `local_date`, the same day 1 as "Day N": `W1` = days 1–7, `W2` = days 8–14, and so on, so a bar can hold days from two calendar months and `start`/`end` can fall outside the month. Always five bars: `W1`–`W5`, then the latest five once the journey is longer (`W2`–`W6` on day 36). Before any check-in, `W1` starts on `today`. `value` is the average `contact_urge` (1–10) of that bar's check-ins; `null` = no check-in, including weeks still ahead (urges are never 0).
- **moods:** how many times each answer to "How do you feel now compared to before?" was given by completed activities in the period.
- **mood_points:** the "Mood after activities" chart, with the same bars as `urges`. Only completed activities with a saved answer count, grouped by the day the reflection was saved (`local_date`), not the day the activity was chosen. `value` is the average of the answers' fixed internal scores (`worse` 2, `about_the_same` 5, `a_little_better` 7, `much_better` 9; defined once in `backend/app/insights.py` as `MOOD_SCORES`), rounded to one decimal. It only sizes the bar on a 0–10 scale; it is **not** a rating the user entered, so the app never shows it. `answers` lists the answers behind the bar for accessibility. `null` = no answers that day (a gap, never 0). Unrecognized answers are skipped, never guessed.
- **categories:** completed activities only (by `completed_on`), grouped by the `category` key and named (and ordered) from `activity_categories`, so `label` matches the activity cards. Bookmarked, abandoned and in-progress activities never count, and each activity counts once.
- **Month totals:** `start`, `end`, `has_data`, `check_in_days`, `completed`, `moods`, `categories`, `takeaway` and `observations` stay on the calendar month containing `today`; only the two charts follow the journey weeks.
- **takeaway / observations:** generated by `backend/app/insights.py` from these numbers only; they describe what happened, never why. With no records, `has_data` is false and the takeaway is a gentle empty state.

---

## Moving forward (`/moving-forward`)

Saved when the user chooses **I'm ready to move forward**, which the app only allows with all five readiness questions ticked. The app then makes a fresh farewell scrapbook every time. Moving forward deletes nothing and locks nothing; the app keeps working as before, and the questionnaire can be done again later.

### `GET /moving-forward`
`200`: `{"moving_forward": null}` until it's chosen, otherwise:
```json
{"moving_forward": {"reflected_on": ["without_overwhelm", "own_routines", "urge_manageable", "connected_to_self", "ready_not_pressured"], "moved_forward_on": "2026-10-20", "updated_at": "2026-10-20T19:02:11Z"}}
```

### `PUT /moving-forward`
```json
{"reflected_on": ["without_overwhelm", "own_routines", "urge_manageable", "connected_to_self", "ready_not_pressured"], "local_date": "2026-10-20"}
```
- `reflected_on`: **all five** readiness questions, in any order (stored in this order). Anything missing answers `422`, and nothing is saved.
- One per installation: the first save answers **`201`**, any later one (a repeated tap, a retry, a later attempt) **`200`** and updates the same record. `moved_forward_on` stays the first day it was chosen. It also marks the "Moving forward check-in" milestone in `GET /progress/summary`.

---

## `GET /farewell-scrapbook`

Everything the keepsake PDF is made from, for this installation only, **oldest first**. The app draws the PDF itself and includes all of it; nothing here is summarised or left out, and reading it changes nothing.

```json
{
  "journey_started_on": "2026-10-12",
  "journey_last_on": "2026-10-20",
  "check_ins": [{"id": 1, "local_date": "2026-10-12", "feeling": "heavy", "contact_urge": 9, "energy_level": "low", "hardest_areas": ["feeling_lonely"]}],
  "completed_activities": [{
    "selection_id": 7, "activity": {"...": "same shape as in recommendations"}, "completed_on": "2026-10-12",
    "memory": {"id": 3, "note": "...", "thought_about_ex": "a_lot", "mood_change": "about_the_same", "local_date": "2026-10-12",
               "created_at": "...", "photo_id": 12, "image_url": "https://... (about 1 hour)"}
  }],
  "other_memories": [],
  "moving_forward": null
}
```
- `check_ins`: one per day (migration 014's counting check-ins).
- `completed_activities[].memory`: `null` if the user deleted that memory (the activity still counts as completed).
- `journey_last_on`: the latest date of any record, including `moved_forward_on`.
- `image_url`s are fresh private links on every request; the bucket stays private.

## `GET /scrapbook/photos/{id}`

A fresh private link (about an hour) for one of this installation's uploaded photos, e.g. when an older link has expired. `404` for anyone else's photo or one that was never uploaded.

---

## `POST /ced/messages`

Ced's reply to the conversation so far. **Nothing is stored:** the app keeps the conversation in memory while the chat is open, sends the recent turns each time, and forgets them when the user ends the chat. Only a per-day message count is kept (`ced_usage`), for limits.

```json
{ "messages": [ { "role": "user", "content": "Can we talk? I keep thinking about us." } ],
  "mode": "unsent_message" }
```
- `messages`: 1–40 turns, roles `user` / `assistant`, each 1–2000 characters, ending with `user`. The server sends at most the last 12 (≈6,000 characters) to the AI, plus Ced's instructions. No check-ins, scrapbook or other app data is ever included.
- `mode`: `chat`, or `unsent_message` when the first message was written on **Say it here first** (words for the ex that were not sent; nothing is ever sent to anyone).

**Response `200`:** Ced's reply as 1–3 short chat bubbles, in order.
```json
{ "messages": ["I'm really sorry you're feeling like this right now.", "Are you safe where you are at this moment?"],
  "risk": "self_harm", "support": "crisis", "source": "ai" }
```
- `risk`: `none`, `distress`, `harm_to_others`, `self_harm`, `in_danger` or `violence`. Two independent reads are combined and the more serious wins: backend patterns (`app/ced/safety.py`) and the model's own rating of the message (it replies in JSON with a `risk` field), which catches indirect wording.
- `support`: crisis resources the app shows **directly under the reply**: `crisis` (self-harm: Call/Text 988, 911 for immediate danger) or `danger` (in danger / violence: Call 911 first), else `null`. The app never opens a call, text, browser or sheet by itself.
- Self-harm and in-danger replies always include a direct "are you safe right now?" question (added by the backend if the model leaves it out). A pattern hit is passed to the model as a safety note; stalking/harassment gets a reply that doesn't help and encourages stopping, without crisis resources.
- `source`: `ai`, or `fallback` when a crisis message couldn't reach the AI (no key, limits, provider error): a short human-written reply plus the resources. Crisis messages are always answered.
- Replies that claim to be a therapist, diagnose, give medication advice or promise outcomes are replaced with a safe fallback.

| Status | When | Body `detail` (shown to the user) |
|---|---|---|
| `429` | Per-installation (8/min, 60/day) or server-wide (25/min) limit, or the provider's own limit. `Retry-After` header. | "Ced needs a short pause…" / "…today's limit…" |
| `503` | `GROQ_API_KEY` not set, or rejected | "Ced isn't available right now…" |
| `504` / `502` | Provider timeout (20 s) / other provider error | "Ced is taking too long…" / "Ced couldn't answer just now…" |

Crisis replies work even without a key and past the limits. Provider and model are set in `.env` (`AI_PROVIDER`, `AI_MODEL`); the app is unaffected by a switch.

---

## `WebSocket /ced/voice`: voice calls with Ced

The app streams microphone audio here; the backend relays it to **Gemini Live** (`GEMINI_LIVE_MODEL`, default `gemini-3.8-live`, voice `GEMINI_VOICE`, default `Vindemiatrix`). The Gemini key never reaches the app. Header: `X-Installation-ID`. Full message format: `backend/app/ced/voice.py`.

- **App → server:** binary PCM 16-bit LE, **16 kHz**, mono (≈100 ms chunks); JSON `{"type":"mute"}`, `{"type":"unmute"}`, `{"type":"end"}`.
- **Server → app:** binary PCM 16-bit LE, **24 kHz**, mono (Ced's voice, streamed); JSON `ready`, `state` (`listening` / `thinking` / `speaking` / `reconnecting`), `interrupted` (stop playback: the user talked over Ced), `safety` (`support`: `crisis` / `danger`), `ended` (`time_limit`), `error` (`unavailable` / `busy` / `limit` / `dropped`, with a `message` for the user).
- **Turn-taking:** Gemini's automatic voice-activity detection (700 ms of silence ends a turn); users can interrupt Ced. Long calls use context compression. States follow Gemini's own speech start/end events.
- **Never stuck:** Gemini doesn't answer everything it hears (an "um", a cough, a half sentence). If no reply starts within 7 s of the user stopping, the call returns to `listening` (and the safety checks still run on what was said). If Ced's audio stalls for 10 s mid-reply, the same happens.
- **Dropped or expired Gemini connections** (a connection lasts about 10 minutes): the backend reconnects up to 3 times per call, sending `state: reconnecting`. It resumes the same conversation with Gemini's session-resumption handle; if Gemini refuses the handle, it starts a fresh session where Ced briefly says it's back. Only after that does the app get `error`/`dropped`.
- **App side:** a WebSocket ping every 10 s detects a dead connection, and a 25 s watchdog ends a call that hears nothing from the server while waiting on Ced. Ended calls offer **Call again**.
- **Voice:** `GEMINI_VOICE` is checked against Gemini's 30 voices (case-insensitive); an unknown name logs a warning and uses the default, because Gemini would otherwise silently pick its own.
- **Safety:** each finished user turn's transcript is checked by the backend patterns and by an independent Groq classifier. Self-harm or danger → a `safety` event (the app shows 988 / 911 on the call screen; nothing is dialled automatically) and a note to the voice model so its next words address safety. Stalking/harassment → a note only.
- **Limits:** one call per installation, `CED_VOICE_MAX_CONCURRENT` calls server-wide (3), `CED_VOICE_CALLS_PER_HOUR` calls started server-wide per hour (30; then `busy`), `CED_VOICE_MAX_MINUTES` per call (15); each call counts as one message toward the daily Ced limit.
- **Privacy:** audio and transcripts pass through memory only; nothing is stored or logged.
- Without `GEMINI_API_KEY` the server sends `error`/`unavailable`. Debug builds of the app then fall back to a clearly labelled practice mock (`-CEDMockVoice YES` forces it; `-CEDMockVoiceCrisis YES` also simulates a crisis).

---

## Errors

| Code | Meaning | Common cause |
|---|---|---|
| `404` | Not found | Using a recommendation, selection or photo id that isn't yours |
| `409` | Conflict | Using a photo that isn't uploaded yet or is already in another memory |
| `422` | Validation error | Missing or invalid `X-Installation-ID`, a misspelled value (e.g. `"missing"` instead of `"missing_them"`), `contact_urge` outside 1–10, wrong date format |
| `503` | Service unavailable | The backend can't reach Neon (body: `{"detail": "The database is unavailable. Please try again shortly."}`), or, for scrapbook photos, AWS isn't configured on the server |

Example `422` body:
```json
{
  "detail": [
    {
      "type": "less_than_equal",
      "loc": ["body", "contact_urge"],
      "msg": "Input should be less than or equal to 10",
      "input": 15,
      "ctx": { "le": 10 }
    }
  ]
}
```
`loc` tells you exactly which field was wrong.

---

## Notes for the Swift side

These are already implemented in `CtrlExDelete/CtrlExDelete/Networking/`:

- **Base URL:** `APIConfig.swift` is the only place it's set. Every build uses the deployed backend, `https://ctrl-ex-delete-api.onrender.com` (`APIConfig.deployedBaseURL`); voice calls use `wss://` on the same host. Debug builds can opt into a local server with `CED_BACKEND = local` in `CtrlExDelete/Config/DeveloperSettings.xcconfig` (gitignored, one per Mac; see `backend/README.md`). The launch argument `-CEDAPIBaseURL http://Your-Mac-Name.local:8000` still overrides it for runs started from Xcode.
- **Installation ID:** `InstallationID.swift` creates the UUID once, stores it in the Keychain, and `APIClient` sends it on every request.
- **Key names:** `APIClient` uses `.convertToSnakeCase` / `.convertFromSnakeCase`, so Swift's `contactUrge` maps to `contact_urge` automatically.
- **Enums:** `Emotion`, `EnergyLevel` and `HardestArea` (in `Models/SampleData.swift`) have raw values matching the tables above. The UI labels can change freely; the raw values can't.
- **Dates:** `created_at`, `selected_at` and `local_date` are decoded as `String` (Swift's `.iso8601` fails on fractional seconds).
- **Plain HTTP:** the Simulator reaches `127.0.0.1` without any exception. Debug builds add `NSAllowsLocalNetworking` (in `CtrlExDelete/Config/Debug-Info.plist`) so a physical phone can reach `http://*.local`. Release builds have no exception.
- **Neon's `DATABASE_URL` is not the API URL** and must never be in the app.

