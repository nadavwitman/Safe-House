# app/monitoring

Device/sensor health checks — distinct from anomaly detection ([app/ai](../ai/README.md)). Two scheduled jobs (registered in `app.__init__._setup_scheduler`) detect hardware problems rather than resident behavior problems, and both push through [app/alerts/notifications.py](../alerts/README.md).

**Design principle: fail loud, not silent.** Neither check ever suppresses an anomaly alert — a fully silent house is indistinguishable from a resident who collapsed and stopped triggering sensors, so the anomaly safety net stays active regardless. These checks only *add context*: `analyze_routes.py` annotates Warning/Emergency notifications with any currently-suspected-faulty sensors via `FAULTY_SENSORS_CACHE`, letting the family judge for themselves. The only legitimate way to silence alerts is the explicit, user-controlled vacation mode.

## Files

- **[device_health.py](device_health.py)** — the only file in this package:
  - `SENSOR_NAMES` — index → human-readable zone name, imported elsewhere (e.g. [app/alerts/alert_messages.py](../alerts/README.md)) for message text.
  - `check_device_connectivity()` — scheduled every 10 min. Alerts once when the ESP32 *master gateway* has gone fully silent for `OFFLINE_THRESHOLD_MINUTES` (30 min) — power/Wi-Fi/crash. Costs one Firestore read per house (`last_reading_at` is denormalized onto the house doc precisely so this doesn't need to scan the readings subcollection); the sent-alert flag persists in Firestore so it survives restarts and only fires once per outage.
  - `check_sensor_health()` / `_check_house_sensor_health()` — scheduled hourly. Flags an individual PIR sensor as suspected-faulty if it hasn't fired in `SENSOR_FAULT_HOURS` (24h; 72h for the entrance door, which naturally stays quiet for long stretches) *while the master is still reporting* — this distinguishes "one dead sensor" from "whole gateway down" (the latter is `check_device_connectivity`'s job, so this check backs off during an active outage). Skips entirely during vacation mode. Maintains `FAULTY_SENSORS_CACHE[house_id]` (a plain in-process dict — safe because gunicorn runs a single worker) and sends/clears per-sensor fault alerts as sensors go silent or recover.

Both checks used to live in `run.py`, which is not copied into the Docker image, so they never actually ran in production until moved here into the shipped `app` package.
