# app/weekly_summary/metrics

Per-category daily metric computations, called by [app/weekly_summary/aggregator.py](../aggregator.py) (not documented here — see parent folder) to build each day's row before it's rolled into the weekly report and the personal EMA baseline ([app/weekly_summary/baseline.py](../baseline.py)). Every function takes a day's (or, for sleep, an overnight window's) sensor readings as a DataFrame plus the house's 7-element `house_mask`, and returns `None` (or a dict with `None` fields) when the relevant sensor isn't installed — a metric a house has no sensor for must never silently read as zero.

Time-based metrics share the same "time-delta" approach: sort readings by time, take the gap to the next reading, and attribute that gap to the *current* zone — capped at `MAX_ATTRIBUTABLE_GAP_MINUTES` (from [../constants.py](../constants.py)) so a connectivity outage or dropped write can't be miscounted as hours of continuous presence in the last-seen zone.

## Files

- **[cognitive.py](cognitive.py)** — duration-based metrics via the shared `_time_in_zones` helper:
  - `_compute_bath_duration` — minutes in Bathroom (zone 2).
  - `_compute_toilet_duration` — minutes in Toilet (zone 3).
  - `_compute_food_prep_duration` — minutes in Kitchen (zone 1).
- **[meds.py](meds.py)** — `_compute_meds`: counts distinct medication-taking sessions from `sensor_4` rising edges, grouping edges within `MEDS_SESSION_GAP_MINUTES` (10 min) into one session. Returns `{'count', 'hours'}` (sorted hour-of-day floats of each session's first trigger), or `None` if unmasked.
- **[mobility.py](mobility.py)** — `_compute_mobility_metrics`: counts location transitions (`current_location` value changes) across the day. No masking check — it's always computable since it only needs the location column, which every house has.
- **[nutrition.py](nutrition.py)** — `_compute_nutrition_metrics`: counts distinct kitchen (`sensor_1`) trigger events (rising-edge clustering of consecutive 1s). Returns `{'kitchen_triggers': None}` if the kitchen sensor is masked (note: unlike most metrics here, this returns a dict with a `None` value rather than bare `None`).
- **[sleep.py](sleep.py)** — `_compute_sleep_metrics`: operates on a 14-hour overnight window (20:00 prior day → 10:00 current day, built by the aggregator) rather than a calendar day. Computes `sleep_hours` (time in Bedroom/zone 5, clipped to `[0, 16]`) and `interruptions` (count of out-of-bedroom stretches longer than `INTERRUPTION_THRESHOLD_MINUTES` = 10 min within the window). Returns `{'sleep_hours': None, 'interruptions': None}` if unmasked.
- **[socialization.py](socialization.py)** — `_compute_outside_duration`: minutes where `current_location == 0` (the Door zone is treated as "outside"). Returns `None` if the door sensor is masked.

All the time-delta functions (`cognitive.py`, `sleep.py`, `socialization.py`) import `MAX_ATTRIBUTABLE_GAP_MINUTES` from [../constants.py](../constants.py) to keep the outage-capping behavior identical across metrics.
