# app/alerts

Turns an AI anomaly verdict (from [app/ai](../ai/README.md)'s `evaluate_buffer_with_AI`) into a human-readable push notification and delivers it via Firebase Cloud Messaging (FCM). Split into a presentation-free message-composition layer and a presentation-free delivery layer, so neither has to know about the other's concerns.

## Flow

1. **[alert_messages.py](alert_messages.py)** `compose_alert_message()` — takes the AI's structured verdict (severity, anomaly type, zone) and builds a `(title, body)` pair from a deterministic template catalog. No LLM — a fixed catalog keyed by `(anomaly_type, severity)` with `{name}`/`{room}`/`{time}` interpolated.
2. **[notifications.py](notifications.py)** `send_alert_push()` — takes that `(title, body)` and pushes it to every FCM token registered for the house, with no knowledge of how the message was built.

Callers elsewhere in the app (e.g. the anomaly pipeline, device-health checks) call `compose_alert_message` then `send_alert_push` in sequence, or call `notifications.py`'s other trigger functions directly for non-AI alerts (device offline, sensor fault).

## Files

- **[alert_messages.py](alert_messages.py)** — `compose_alert_message(severity, activity_type, room_index, resident_name, when_dt=None, last_location=None, faulty_sensor_names=None)`: looks up `_CATALOG[activity_type][severity]`, formats the template with the resident's name, a room name (via `app.monitoring.device_health.SENSOR_NAMES`, falling back to `'home area'` if `room_index` is `None`), and a resident-local (`Asia/Jerusalem`) 12-hour clock time. Appends a device-fault caveat if `faulty_sensor_names` is given, but never suppresses the alert because of it. Every message is deliberately hedged ("most likely near", never "detected a fall") since PIR sensors can't confirm what actually happened — only that a location/frequency/usage pattern deviated.
- **[notifications.py](notifications.py)** — FCM delivery:
  - `_send_multicast(house_id, title, body, label)` — shared sender: looks up the house's FCM tokens via `database.user_db`, sends one `MulticastMessage`, logs delivery counts, and prunes invalid tokens. Returns `True` if at least one device received it.
  - `send_alert_push(house_id, title, body)` — thin wrapper for AI-composed anomaly alerts.
  - `trigger_device_offline_alert(house_id, resident_name, minutes_silent)` — whole-device (ESP32 master) silence alert, message built inline (not via `alert_messages.py`, since it isn't an AI verdict).
  - `trigger_sensor_fault_alert(house_id, sensor_name, hours_silent)` — single-sensor silence alert, additional context alongside anomaly alerts, never a replacement for them.
  - `_cleanup_invalid_tokens(response, tokens, house_id)` — after a multicast send, removes any token FCM reports as unregistered/invalid from every user doc on the house, so future sends don't keep retrying dead tokens.
