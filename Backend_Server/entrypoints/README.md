# entrypoints

The two ways to start the Flask app — local dev vs. production (gunicorn) — plus each one's own copy of the APScheduler setup. Both create the app via `app.create_app()` ([Backend_Server/app/\_\_init\_\_.py](../app/__init__.py)); they differ only in *who* owns starting the background scheduler.

## Why two schedulers exist

`app/__init__.py` can start its own APScheduler internally, gated by the `ENABLE_SCHEDULER` env var, so only one process ever owns the scheduled jobs:

- **[wsgi.py](wsgi.py)** — the production entrypoint (gunicorn). Sets `ENABLE_SCHEDULER=true` (default) so `create_app()`'s internal `_setup_scheduler()` owns everything: the weekly insights report ([app/weekly_summary](../app/weekly_summary/README.md)), nightly fine-tuning ([app/ai/model_manager](../app/ai/README.md)), the 5-minute vacation-schedule checker ([app/scheduling](../app/scheduling/README.md)), and the device/sensor health checks ([app/monitoring](../app/monitoring/README.md)).
- **[run.py](run.py)** — the local dev entrypoint (`python run.py`, Flask's built-in server). Sets `ENABLE_SCHEDULER=false` so `create_app()` skips its internal scheduler, and instead defines and starts its *own* `BackgroundScheduler` with the identical five jobs (same cron/interval schedules) directly in this file. It also guards against Flask's debug-mode reloader spawning the scheduler twice (`WERKZEUG_RUN_MAIN` check).

Both files insert the repo root onto `sys.path` before importing `app`, since neither lives inside the `app` package itself.

## Files

- **[wsgi.py](wsgi.py)** — minimal: sets `ENABLE_SCHEDULER=true`, exposes `application = create_app()` for gunicorn to serve.
- **[run.py](run.py)** — sets `ENABLE_SCHEDULER=false`, defines `scheduled_weekly_insights`, `scheduled_fine_tuning_job`, and `check_vacation_schedules` (near-duplicates of the versions in `app/__init__.py`'s `_setup_scheduler`, kept in sync manually), registers all five jobs on its own `BackgroundScheduler`, and runs `app.run(host='0.0.0.0', port=5000, debug=True, use_reloader=False)` when executed directly.

Note: neither file is copied into the Docker image (only the `app` package is) — this is why [app/monitoring/device_health.py](../app/monitoring/README.md) explicitly notes its checks had to be moved *into* the `app` package to actually run in production, rather than staying here.
