# app

The Flask application package — the only backend code copied into the Docker image (see [Dockerfile](../Dockerfile) and [entrypoints/README.md](../entrypoints/README.md)). `app/__init__.py`'s `create_app()` is the single Flask app factory both entrypoints call; everything else here is organized by concern into its own subfolder, each with its own README.

## [\_\_init\_\_.py](__init__.py)

`create_app()`:
- Configures JWT (30-min access / 30-day refresh tokens) and CORS.
- Registers every blueprint from [api/](api/README.md).
- Conditionally starts the in-process APScheduler (`_setup_scheduler()`), gated by `ENABLE_SCHEDULER` so only one process ever owns the scheduled jobs — see [entrypoints/README.md](../entrypoints/README.md) for why two entrypoints exist and which one sets that flag.

`_setup_scheduler()` registers five recurring jobs (mirrored, for local dev, in [entrypoints/run.py](../entrypoints/README.md)):

| Job | Schedule | Does |
|---|---|---|
| `scheduled_weekly_insights` | Sun 06:00 (1h misfire grace) | Generates every active house's weekly report — see [weekly_summary/](weekly_summary/README.md) |
| `scheduled_nightly_fine_tuning` | 03:00 daily | Fine-tunes any house 14+ days overdue — see [ai/](ai/README.md) |
| `check_vacation_schedules` | every 5 min | Auto-activates/deactivates vacation mode from stored schedules — see [scheduling/](scheduling/README.md) |
| `check_device_connectivity` | every 10 min | Flags a fully-silent ESP32 master — see [monitoring/](monitoring/README.md) |
| `check_sensor_health` | every 60 min | Flags an individual suspected-faulty sensor — see [monitoring/](monitoring/README.md) |

## Subfolders

- **[ai/](ai/README.md)** — inference, per-house fine-tuning, and the nightly MLOps orchestration around the LSTM model.
- **[alerts/](alerts/README.md)** — turns an AI verdict into a push notification and delivers it via FCM.
- **[api/](api/README.md)** — every Flask Blueprint / HTTP route, including the core `/api/analyze` ingestion pipeline.
- **[auth/](auth/README.md)** — JWT route decorators and auth helper functions (hashing, token/code generation).
- **[monitoring/](monitoring/README.md)** — device/sensor health checks, distinct from anomaly detection.
- **[scheduling/](scheduling/README.md)** — timezone-correct resolution of stored vacation schedules.
- **[state/](state/README.md)** — in-process RAM caches (sensor buffer, sensor-mask cache) shared across requests and the scheduler.
- **[weekly_summary/](weekly_summary/README.md)** — the AI-written weekly wellness report pipeline, including its [metrics/](weekly_summary/metrics/README.md) subpackage.
