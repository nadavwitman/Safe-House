# app/scheduling

Timezone-correct resolution of stored vacation schedules into absolute instants. One file, used by both the 5-minute vacation-check scheduler job (`app.__init__.check_vacation_schedules`) and by [app/api/config_routes.py](../api/README.md) when a schedule is created or cleared.

## Why this exists

A vacation schedule is entered by the family in *their* local wall-clock time (e.g. "2026-05-22", "08:30"). Comparing those raw strings against the server's own clock silently assumed the server ran in the same timezone as the phone that wrote them — on a UTC host with a UTC+3 user, a trip meant to start at 09:00 local actually started monitoring-off at noon UTC, leaving monitoring live for three hours after the resident had already left.

The app now sends absolute UTC instants (`startUtc`/`endUtc`) alongside the wall-clock fields, computed on-device where the timezone (and any DST offset for that specific date) is actually known. The wall-clock fields (`startDate`/`startTime`/`endDate`/`endTime`) stay in the document purely for display — they're the user's stated intent, not what gets compared against.

Schedules written before this change carry no UTC fields; for those, `parse_window` falls back to interpreting the wall-clock fields in the *server's* timezone (the old, timezone-wrong behavior) rather than dropping the trip outright — it self-corrects the next time the user re-saves it.

## Files

- **[vacation_window.py](vacation_window.py)**:
  - `parse_window(schedule)` — returns `(start, end)` as tz-aware UTC datetimes, preferring `startUtc`/`endUtc` and falling back to the legacy wall-clock fields (interpreted in the server's local zone) if those are absent. Returns `None` if the schedule is missing, malformed, or only half-specified — callers treat `None` as "no usable trip" and leave vacation mode untouched, since acting on a half-parsed window is worse than ignoring it.
  - `now_utc()` — the clock every comparison in this module (and its callers) is made against.
