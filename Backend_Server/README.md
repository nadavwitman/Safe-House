# Backend_Server

The Flask backend: ingests per-minute ESP32 sensor readings, runs the LSTM anomaly model, pushes alerts, serves the mobile app's API, and generates AI weekly wellness reports. Deployed as a single-worker gunicorn container (see [Dockerfile](Dockerfile)) alongside [AI_Model/](../AI_Model/README.md), which it imports directly rather than vendoring.

## Layout

- **[app/](app/README.md)** — the Flask application package: the app factory, the scheduler setup, and every concern (routes, AI integration, alerts, auth, monitoring, scheduling, in-process state, weekly summaries) in its own subfolder. This is the only backend code copied into the Docker image, together with `database/`, `entrypoints/`, and `AI_Model/`.
- **[database/](database/README.md)** — all Firestore access: two flat facade modules (`database.py`, `user_db.py`) over a [repositories/](database/repositories/README.md) package with one module per collection/concern.
- **[entrypoints/](entrypoints/README.md)** — the two ways to start the app: [wsgi.py](entrypoints/wsgi.py) (production, gunicorn) and [run.py](entrypoints/run.py) (local dev, Flask's built-in server), differing in which one owns starting the background scheduler.
- **[scripts/](scripts/README.md)** — one-off maintenance scripts run manually, not part of the request pipeline or the scheduler; not copied into the Docker image.
- **[tests/](tests/)** — pytest suite covering the API routes, database layer, IoT ping flow, and weekly-insights pipeline. `conftest.py` stubs out Firebase, PyTorch, pandas, numpy, and scikit-learn at import time so the suite runs on just Flask + pytest without needing real credentials or heavy ML dependencies (`test_database.py` is the exception — meant to be run standalone against real Firebase credentials, not as part of the stubbed suite). Not copied into the Docker image.
- **[Dockerfile](Dockerfile)** — builds the production image. Build context is the *repo root* (not this folder), since it also copies in `AI_Model/` from outside `Backend_Server/`. Runs `gunicorn` with exactly one worker — APScheduler runs in-process, so more than one worker would register every scheduled job multiple times.
- **[requirements.txt](requirements.txt)** — Python dependencies (Flask, PyTorch, Firebase Admin SDK, APScheduler, google-genai, etc.).
- **.env** — local-dev environment variables (`JWT_SECRET_KEY`, `GEMINI_API_KEY`, etc.); not present in the Docker image, where these are injected at runtime instead.
