# Ctrl+Ex+Delete API

This is the contract between the iOS app and the FastAPI backend.
**Field names and allowed values must match exactly.** If something here needs to change, update this doc in the same pull request as the code.

- **Status:** check-ins, recommendations, activity selection, scrapbook photos, reflections (completion), progress summary
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
- `selected_at` is set once the user has tapped "I'll try this" on that card.
- `completed_at` is set once a reflection was saved for that card's selection (the app shows "Completed ✓").
- `category` is one of `outdoor_movement`, `mindfulness_rest`, `solo_exploration`, `social_connection`. The app picks the card's icon and colors from it.
- **No check-ins yet:** `200` with `"check_in_id": null`, `"check_in_local_date": null`, `"recommendations": []`. The app shows "Check in first".

**Current recommendation rule:** every active activity, in catalog order, up to 3, which is the same as the prototype. The check-in answers don't change the result yet. The rule lives in `backend/app/recommendation_rules.py`.

---

## `POST /recommendations/{id}/selection`

Records that the user tapped **I'll try this** on a recommendation. No request body.

**Headers:** `X-Installation-ID` (required)

**Response `201 Created`** (first time) or **`200 OK`** (already selected; returns the existing row, so tapping twice never creates two rows):
```json
{
  "id": 7,
  "recommendation_id": 31,
  "activity_id": 1,
  "check_in_id": 12,
  "selected_at": "2026-10-04T22:21:32.136186Z"
}
```

**`404`** if the recommendation doesn't exist **or belongs to a different installation**.

---

## `GET /activity-selections/current`

The activity the user most recently chose with **I'll try this**, as long as no reflection has been saved for it yet. Choosing another activity replaces it; saving its reflection completes it. This is how the chosen activity survives an app restart.

**Response `200 OK`:**
```json
{
  "selection": {
    "selection_id": 15,
    "recommendation_id": 53,
    "check_in_id": 21,
    "selected_at": "2026-10-13T04:37:02.118Z",
    "activity": { "id": 2, "slug": "walk_without_social_media", "title": "Take a 20-minute walk without checking their social media.", "category": "outdoor_movement", "category_label": "Fresh Air", "duration_minutes": 20, "instructions": "…", "why_it_fits": "…" }
  }
}
```
`"selection": null` when nothing is waiting for a reflection.

**Selection is not completion.** Tapping "I'll try this" never creates a completed-activity record.

---

## Scrapbook photos (`/scrapbook/photos`)

Photos go straight from the app to a **private** S3 bucket through short-lived presigned URLs; the API never sees the image bytes and never exposes AWS credentials. Answers `503` until the server has AWS settings.

1. `POST /scrapbook/photos` with `{"caption": null, "local_date": "2026-10-13"}` → `201` `{"id": 10, "upload_url": "https://…"}` (URL valid 5 minutes).
2. `PUT` the JPEG to `upload_url` with `Content-Type: image/jpeg` (no `X-Installation-ID` header).
3. `POST /scrapbook/photos/{id}/complete` → `200` with a temporary `image_url` (1 hour). `409` if the file isn't in S3 yet, `413` if it's over 5 MB.

Also: `GET /scrapbook/photos` (uploaded photos) and `DELETE /scrapbook/photos/{id}` (`204`). S3 object keys are random (`scrapbook/<uuid>.jpg`) and never contain the installation ID.

---

## `POST /reflections`

**Add to my scrapbook.** Saves a memory and **completes** the selected activity. Upload the photo first (above) and pass its `id`. Every answer is optional.

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

Leave out `activity_selection_id` for a memory that isn't tied to an activity.

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
  "completed_at": "2026-10-13T04:38:31.554Z",
  "photo_id": 10,
  "image_url": "https://…"
}
```
`image_url` is temporary (1 hour) and `null` without a photo. **`404`** for a selection or photo that isn't yours; **`409`** if the photo isn't uploaded yet or already belongs to another memory.

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
- Insights endpoints: urge trend, mood after activities, activity categories
- Ced chat, the no-contact companion and the moving-forward check-in
