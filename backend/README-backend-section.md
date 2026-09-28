# Running the Backend

The backend is a FastAPI server in the `backend/` folder. The full API contract is in [`docs/api.md`](../docs/api.md).

### Requirements
- Python 3.11 or newer (check with `python3 --version`)
- Terminal commands below are for macOS

### First-time setup (only once)

From the repo root:

```bash
git switch main
git pull
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

If your prompt starts with `(base)`, you have Anaconda active. Run `conda deactivate` **before** creating the venv.

### Starting the server (every time)

```bash
cd backend
source venv/bin/activate
uvicorn app.main:app --reload
```

Your prompt should show `(venv)`. The server runs at `http://127.0.0.1:8000` until you press **Ctrl + C**. `--reload` restarts it automatically when you save a file.

### Checking that it works

- `http://127.0.0.1:8000/health` should show `{"status":"ok"}`
- `http://127.0.0.1:8000/docs` is an interactive page where you can send test requests with **Try it out**
- Endpoints that need an `X-Installation-ID` header need a UUID. Run `uuidgen` in Terminal to get one.

### Using it from the iOS Simulator

With the server running on the same Mac, the app can call `http://127.0.0.1:8000`. See the "Notes for the Swift side" section of [`docs/api.md`](../docs/api.md) for key naming, date decoding, and the App Transport Security exception needed for plain `http`.

### Environment variables

Secrets like the database connection string go in `backend/.env`, which is **never committed**. Copy the template and fill in the real values (ask the team for them privately):

```bash
cp .env.example .env
```

### Troubleshooting

| Problem | Fix |
|---|---|
| `command not found: uvicorn` or `No module named fastapi` | The venv isn't active. Run `source venv/bin/activate` from `backend/`. |
| `No module named 'app'` | You're in the wrong folder. Run uvicorn from inside `backend/`, not the repo root. |
| `Address already in use` | The server is already running in another Terminal tab. Stop that one with Ctrl + C. |
| Check-ins disappear after restarting | Expected for now. Storage is in memory until Neon is connected. |
| `422` response | The request doesn't match `docs/api.md`. The `loc` field in the error shows which field is wrong. |
| New packages were added by a teammate | Pull, activate the venv, then run `pip install -r requirements.txt` again. |
