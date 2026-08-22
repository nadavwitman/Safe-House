# scripts

One-off maintenance scripts, run manually from the `Backend_Server` directory — not part of the request pipeline or the scheduler.

## Files

- **[backfill_last_activity.py](backfill_last_activity.py)** — one-time migration for houses whose sensor history predates `last_sensor_activity` (the denormalized per-sensor last-fired map that [database/repositories/sensor_readings.py](../database/repositories/README.md)'s `log_vector_reading` now maintains automatically on every new reading — see [database/README.md](../database/README.md)). Scans each house's `sensor_vectors` subcollection newest-first, fetching only `sensor_vector`/`time`, and stops early once every sensor's most recent firing has been found (a house with no history for some sensor gets scanned in full, since that's the only way to prove it). Writes the result onto the house doc so the dashboard shows a true last-activity time immediately instead of waiting for that sensor to fire again.
  ```
  python scripts/backfill_last_activity.py            # all houses
  python scripts/backfill_last_activity.py <house_id>  # one or more specific houses
  ```
