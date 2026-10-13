# Ctrl+Ex+Delete API

This is the contract between the iOS app and the FastAPI backend.
**Field names and allowed values must match exactly.** If something here needs to change, update this doc in the same pull request as the code.

- **Status:** check-ins, recommendations, activity status (one in progress), bookmarks, scrapbook photos, reflections (completion), progress summary, insights
- **Local base URL:** `http://127.0.0.1:8000` (works from the iOS Simulator on the same Mac)
- **Interactive docs:** `http://127.0.0.1:8000/docs` (while the backend is running)

---

## Installation ID (how users are identified)

There are no accounts. Instead:

1. On first launch, the app generates a UUID (`UUID().uuidString`).
2. The app saves it in the **Keychain** and reuses it forever after.
3. Every request (except `/health`) sends it in this header:

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
| `contact_urge` | integer | yes | `1` to `10` |
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

**Response `201 Created`**: the saved check-in, with three server-generated fields added:
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
        "category_label": "Gentle Reset",
        "duration_minutes": 10,
        "instructions": "No productivity needed. ...",
        "why_it_fits": "Your energy is low and ..."
      }
    }
  ]
}
```

- `recommendations` is in card order (`position` 1, 2, 3...).
- `id` is the **recommendation** id. Use it to record a selection.
- `status`: `null` (not chosen, or the attempt was abandoned), `in_progress` or `completed`. `selected_at` and `completed_at` go with it.
- `is_saved`: bookmarked with **Save for later**. Saved activities are placed first when the next check-in's cards are made.
- `category` is one of `outdoor_movement`, `mindfulness_rest`, `solo_exploration`, `social_connection`. The app picks the card's icon and colors from it.
- **No check-ins yet:** `200` with `"check_in_id": null`, `"check_in_local_date": null`, `"recommendations": []`. The app shows "Check in first".

**Current recommendation rule:** every active activity, in catalog order, up to 3, which is the same as the prototype. The check-in answers don't change the result yet. The rule lives in `backend/app/recommendation_rules.py`.

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

**Add to my scrapbook.** Saves the memory and **completes** the activity in progress, in one transaction. `activity_selection_id`, `thought_about_ex` and `mood_change` are **required**; the notes and photo are optional. Upload the photo first (above) and pass its `id`.

```json
{
  "activity_selection_id": 15,
  "photo_id": 10,
  "note": "The walk cleared my head",
  "noticed": null,
  "thought_about_ex": "a_little",
  "mood_change": "a_little_better",
  "local_date": "2026-10-13"
}
```

| Field | Allowed values |
|---|---|
| `thought_about_ex` | `not_really`, `a_little`, `a_lot` |
| `mood_change` | `worse`, `about_the_same`, `a_little_better`, `much_better` (stored as chosen, never as a score) |
| `note`, `noticed` | up to 1000 characters |


**Response `201 Created`**, or **`200 OK`** if that selection already has a reflection (the first one is returned unchanged, so retries never duplicate):
```json
{
  "id": 8,
  "activity_selection_id": 15,
  "activity": { "id": 2, "slug": "walk_without_social_media", "…": "…" },
  "note": "The walk cleared my head",
  "noticed": null,
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

## `GET /insights?period=week|month&today=YYYY-MM-DD`

The Progress screen, calculated from this installation's records. `today` is the user's **local** calendar day, so the week (Monday–Sunday) and month boundaries follow their time zone, like `local_date` everywhere else.

```json
{
  "period": "week", "start": "2026-10-12", "end": "2026-10-18",
  "has_data": true, "check_in_days": 1, "completed": 2,
  "urges": [ { "label": "Mon", "start": "2026-10-12", "end": "2026-10-12", "value": 6, "check_ins": 2 } ],
  "moods": [ { "response": "worse", "label": "Worse", "count": 0 } ],
  "categories": [ { "category": "outdoor_movement", "label": "Outdoor & movement", "count": 1, "percent": 50 } ],
  "takeaway": { "headline": "…", "body": "…" },
  "observations": [ "You completed 2 activities this week." ]
}
```

- **urges:** one bar per day (week) or per week of the month (`W1` = days 1–7 … `W5`). `value` is the average `contact_urge` (1–10) of that bar's check-ins; `null` = no check-in (urges are never 0).
- **moods:** how many times each answer to "How do you feel now compared to before?" was given by completed activities in the period. Counted, never converted to scores.
- **categories:** completed activities only (by `completed_on`). Bookmarked, abandoned and in-progress activities never count, and each activity counts once.
- **takeaway / observations:** generated by `backend/app/insights.py` from these numbers only; they describe what happened, never why. With no records, `has_data` is false and the takeaway is a gentle empty state.

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

- **Base URL:** `APIConfig.swift` is the only place it's set. Debug uses `http://127.0.0.1:8000` (Simulator); override it with the launch argument `-CEDAPIBaseURL http://Your-Mac-Name.local:8000` for a physical iPhone. Release must be an `https://` URL.
- **Installation ID:** `InstallationID.swift` creates the UUID once, stores it in the Keychain, and `APIClient` sends it on every request.
- **Key names:** `APIClient` uses `.convertToSnakeCase` / `.convertFromSnakeCase`, so Swift's `contactUrge` maps to `contact_urge` automatically.
- **Enums:** `Emotion`, `EnergyLevel` and `HardestArea` (in `Models/SampleData.swift`) have raw values matching the tables above. The UI labels can change freely; the raw values can't.
- **Dates:** `created_at`, `selected_at` and `local_date` are decoded as `String` (Swift's `.iso8601` fails on fractional seconds).
- **Plain HTTP:** the Simulator reaches `127.0.0.1` without any exception. Debug builds add `NSAllowsLocalNetworking` (in `CtrlExDelete/Config/Debug-Info.plist`) so a physical phone can reach `http://*.local`. Release builds have no exception.
- **Neon's `DATABASE_URL` is not the API URL** and must never be in the app.

---

## Coming later

- Real recommendation rules based on the check-in answers
- Saving activities for later (the Save button is local-only for now)
- Ced chat, the no-contact companion and the moving-forward check-in
