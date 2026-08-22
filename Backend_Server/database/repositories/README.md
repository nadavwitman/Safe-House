# database/repositories

All Firestore access for the backend, one module per document/subcollection family. Every collection lives under a single `houses/{house_id}` document tree (`sensor_vectors`, `ai_decisions` as subcollections; everything else denormalized directly onto the house doc) plus a separate top-level `users` collection. Callers never import these directly — they go through the two facades in the parent [database/](../) folder: `database.database` (re-exports everything except users/houses CRUD) and `database.user_db` (re-exports `users.py` + `houses.py`), so call sites don't need to know which repository module owns a given function.

## Recurring patterns

- **Denormalization over subcollection scans.** Live-read paths (the dashboard poll, health checks) are optimized to cost exactly one Firestore document read by writing derived state — `last_reading_at`, `last_sensor_activity`, `current_status`, `current_alert_*`, `weekly_report.generated_at` — directly onto the house document as a side effect of the writes that produce it (`log_vector_reading`, `log_ai_decision`). See `alerts.py`'s `get_house_activity_meta` and `device_health.py`'s `get_house_health_doc` for the read side of this.
- **`field_paths=` / dotted-path updates.** Reads that only need a few fields off a large house doc pass `field_paths` to avoid downloading the whole document (e.g. the full `weekly_report`); writes to per-sensor maps use dotted field paths (`f'faulty_sensor_alert_sent.{i}'`) so only the changed key is touched.
- **`merge=True` almost everywhere**, since nearly every write is a partial update to a shared house document that many independent code paths touch.

## Files

- **[client.py](client.py)** — Firebase Admin SDK initialization; exports the shared `db` Firestore client every other repository imports.
- **[users.py](users.py)** — the `users` collection: lookup by id/email/username, `create_user`, `update_user`, house membership (`add_house_to_user`/`remove_house_from_user`), FCM token management.
- **[houses.py](houses.py)** — the `houses` collection's core CRUD: create/get/delete a house, invite-code lookup, membership (`add_user_to_house`/`remove_user_from_house`), activation, device token/invite code rotation, `get_house_fcm_tokens` (fans out to `users.py` for each member), `delete_house` (also purges the `sensor_vectors`/`ai_decisions` subcollections, since Firestore doesn't cascade-delete).
- **[sensor_readings.py](sensor_readings.py)** — the highest-traffic module, hit once a minute per house:
  - `log_vector_reading()` — writes one `sensor_vectors` doc and, in the same call, updates the house doc's `last_current_location`, `last_reading_at`, and per-sensor `last_sensor_activity` map.
  - `get_recent_sensor_events()` — used to warm-start the in-memory buffer on cold start (see [app/state](../../app/state/README.md)).
  - `get_weekly_sensor_data()` — feeds [app/weekly_summary](../../app/weekly_summary/README.md)'s report pipeline; excludes vacation-flagged readings (`is_vacation == False`), the same filter `fetch_finetuning_data()` below applies, so a week that straddles a trip is reported on its remaining real days instead of averaging in the silence.
  - `fetch_finetuning_data()` — asks Firestore directly for the last ~14 days' worth of *non-vacation* readings (`FINETUNING_READING_TARGET = 20,160`), sidestepping calendar-date vacation-time arithmetic; feeds [app/ai/fine_tuning.py](../../app/ai/README.md).
  - `get_sensor_mask()` / `set_sensor_mask()` — the installed-sensor mask, backing [app/state/house_mask_store.py](../../app/state/README.md).
- **[vacation.py](vacation.py)** — vacation flag and schedule: `get_vacation_mode`/`set_vacation_mode` (also accrues `vacation_days_total` — elapsed time since the flag was last turned on — so the nightly MLOps pipeline can judge fine-tune eligibility without fetching raw sensor history), `set_vacation_schedule`/`get_vacation_schedule`/`clear_vacation_schedule`, and `get_vacation_state` (flag + schedule in one read, for the 5-minute vacation scheduler).
- **[alerts.py](alerts.py)** — the dashboard/alerts backbone:
  - `get_house_activity_meta()` — the single masked read [app/api/house_routes.py](../../app/api/README.md)'s status endpoint uses for the entire live dashboard.
  - `log_ai_decision()` — called only on a genuine anomaly-state *transition* (not every reading): writes an immutable `ai_decisions` history entry and updates the house doc's live `current_status`/`current_alert_*` fields in one batch.
  - `get_alert_history()` — the last 7 days of alerts for the alerts screen, with `exclude_normal` filtering recovered-to-Normal entries client-side (a 3x over-fetch instead of a second Firestore inequality filter).
- **[device_health.py](device_health.py)** — backs [app/monitoring/device_health.py](../../app/monitoring/README.md): `get_house_health_doc()` (one read covering both the connectivity and per-sensor-fault checks), fault-flag set/clear helpers, and alert logging (`log_sensor_fault_alert`, `log_device_offline_alert`) into the same `ai_decisions` subcollection `alerts.py` reads from.
- **[model_state.py](model_state.py)** — the EMA `baseline` and the stored `weekly_report`, both simple get/save pairs on the house document; backs [app/weekly_summary](../../app/weekly_summary/README.md).
