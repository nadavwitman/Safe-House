# app/api

Flask Blueprints for every HTTP route in the backend. Each file registers one `Blueprint` (mounted in `app/__init__.py`) and stays a thin HTTP layer — auth/permission checks via decorators from [app/auth](../auth/), state via [app/state](../state/), and any real logic delegated to `database/`, [app/ai](../ai/README.md), [app/alerts](../alerts/README.md), [app/weekly_summary](../weekly_summary/), or [app/scheduling](../scheduling/).

## Files

- **[auth_routes.py](auth_routes.py)** (`/api/auth/*`) — signup, signin, JWT refresh, signout, change-password, change-username. Issues access+refresh JWTs (`_make_tokens`) carrying `role` and `house_ids` as claims.
- **[user_routes.py](user_routes.py)** (`/api/user/*`) — the logged-in *user's* own view: `GET /me` (profile + all their houses, each with sensor mask, vacation state, emergency contact), `POST /house/join` (redeem an invite code), FCM token registration/removal for push notifications.
- **[admin_routes.py](admin_routes.py)** (`/api/admin/*`) — installer/company-side house management: create an admin account (gated by an `X-Admin-Creation-Key` header, dev-team-only), create/list/get/delete a house, remove a user from a house, regenerate invite codes, rotate device tokens. All but account creation require `@admin_required`.
- **[house_routes.py](house_routes.py)** (`/api/house/*`) — `GET /<house_id>/status`: the single endpoint the live dashboard polls, costing exactly one Firestore document read because everything it needs (vacation flag, last activity, current AI status/alert text, weekly-report timestamp) is denormalized onto the house doc; also triggers `maybe_catch_up` to regenerate a missed weekly report in the background. `POST /sensor-mask`: admin sets which of the 7 zone sensors are physically installed.
- **[config_routes.py](config_routes.py)** (`/api/config`, `/api/config/vacation-schedule`) — vacation mode: immediate on/off (pauses/clears the sensor buffer, flips the Firestore flag) and scheduling a future vacation window (validated via `app.scheduling.vacation_window.parse_window`, auto-activates immediately if the window already started).
- **[insights_routes.py](insights_routes.py)** (`/api/insights/*`) — read-only: `GET /weekly/<house_id>` fetches the latest AI-generated weekly report (reports are only ever written server-side by the Sunday scheduler or its catch-up path — there is deliberately no on-demand "generate" route here anymore, to avoid an unmetered Gemini call reachable by any house member). `GET /alerts/<house_id>` returns the last 7 days of alert history.
- **[analyze_routes.py](analyze_routes.py)** (`/api/analyze`) — the core IoT ingestion endpoint, hit once a minute per house by the ESP32 master. By far the most involved route; see below.

## analyze_routes.py in detail

`POST /api/analyze` is the pipeline every sensor reading flows through:

1. Validate the device token (`X-Device-Token` header, cached in-process after first success).
2. Read the house document once (`user_db.get_house`) and reuse it for activation status, fine-tune count, vacation flag — avoiding the N separate reads earlier versions made.
3. `_ensure_buffer_warm()` — on a cold process start, replay up to one window (360 readings) from Firestore into the in-memory [sensor_buffer](../state/) so an established house doesn't have to wait 6 hours to refill after a restart.
4. Resolve `current_location` (payload → last buffer reading → last DB value → default), buffer and persist the reading.
5. Once the buffer holds a full 6-hour window, load the house's personalized model from `HOUSES_MODELS_CACHE` (RAM) or disk, and call [app.ai.inference.evaluate_buffer_with_AI](../ai/README.md).
6. Map the AI decision to `Normal` / `Warning` / `Emergency` (hosting/social activity is folded back into `Normal`).
7. `_alert_key()` computes a signature of `(decision, anomaly_type, zone)` so a push/DB write only happens on a genuine transition to a *different* alert, not on every repeated minute of the same one — recovered from the house doc on cold start so a restart doesn't re-fire a duplicate alert.
8. On a real change, compose the message via [app.alerts.alert_messages](../alerts/README.md) (enriched with any sensors [app.monitoring.device_health](../monitoring/) currently suspects are faulty), log it (`database.log_ai_decision`), and push it (`app.alerts.notifications.send_alert_push`).
