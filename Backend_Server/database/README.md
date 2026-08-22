# database

All Firestore access for the backend. The actual per-collection logic lives in **[repositories/](repositories/README.md)**; this top level holds the two facade modules every other part of the app imports, plus the Firebase credentials file.

## Why the facade split

`database.py` and `user_db.py` don't contain logic themselves — they just re-export functions from `repositories/*` under one flat import surface, so call sites do `import database.database as database` / `import database.user_db as user_db` without needing to know which repository module actually owns a given function (e.g. `database.get_baseline` really lives in `repositories/model_state.py`). This keeps the repository split (one file per collection/concern — see [repositories/README.md](repositories/README.md)) an internal organization detail rather than something every caller has to track.

## Files

- **[database.py](database.py)** — facade re-exporting everything except users/houses CRUD: sensor readings, device health, vacation, alerts, model state (baseline + weekly reports). Used throughout [app/api](../app/api/README.md), [app/monitoring](../app/monitoring/README.md), and [app/weekly_summary](../app/weekly_summary/README.md).
- **[user_db.py](user_db.py)** — facade re-exporting `repositories/users.py` + `repositories/houses.py`: user accounts, house membership, invite codes, device tokens, FCM tokens. Used throughout [app/api](../app/api/README.md) and [app/ai](../app/ai/README.md).
- **[firebase-credentials.json](firebase-credentials.json)** — the Firebase Admin SDK service account key, loaded by `repositories/client.py` to initialize the Firestore client (overridable via the `FIREBASE_CREDENTIALS_PATH` env var, e.g. in the Docker image). Not something to read casually — it's a live service-account credential.
- **[repositories/](repositories/README.md)** — the actual Firestore access, one module per collection/concern (users, houses, sensor readings, vacation, alerts, device health, model state). See its own README for details.
