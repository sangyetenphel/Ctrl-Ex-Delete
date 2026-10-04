# Ctrl+Ex+Delete API

This is the contract between the iOS app and the FastAPI backend.
**Field names and allowed values must match exactly.** If something here needs to change, update this doc in the same pull request as the code.

- **Status:** Week 1, check-ins only
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

## Errors

| Code | Meaning | Common cause |
|---|---|---|
| `422` | Validation error | Missing or invalid `X-Installation-ID`, a misspelled value (e.g. `"missing"` instead of `"missing_them"`), `contact_urge` outside 1–10, wrong date format |

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

- **Key names:** use `encoder.keyEncodingStrategy = .convertToSnakeCase` and `decoder.keyDecodingStrategy = .convertFromSnakeCase` so Swift's `contactUrge` maps to `contact_urge` automatically.
- **Enums:** a Swift `enum Feeling: String, Codable` with raw values matching the table above works well (e.g. `case gettingThrough = "getting_through"`). Set the raw values explicitly; don't rely on the key strategy for enum values.
- **Dates:** Swift's built-in `.iso8601` date decoding **fails on fractional seconds** like `.053814Z`. For Week 1, the simplest fix is to decode `created_at` and `local_date` as `String`. Proper date parsing can come later.
- **Plain HTTP:** iOS blocks `http://` by default (App Transport Security). For local testing, add an ATS exception for local networking in the app's Info settings. This goes away once the backend is deployed with HTTPS.
- **Real iPhone:** `127.0.0.1` only works in the Simulator. A physical phone needs the Mac's local IP address or a deployed backend.

---

## Coming later

- Neon database storage (currently data is kept in memory and resets when the server restarts)
- Activity endpoints (Week 2)
- Insights endpoints: urge trend, mood after activities, activity categories