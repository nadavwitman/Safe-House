"""
Generates a month of mock Safe-House sensor data for a single, generic 70+ resident
profile — used to initialize/retrain the general baseline LSTM before a house is
fine-tuned on its own resident's real data.

One day is generated at a time (`generate_day`), with every routine anchor (wake,
meals, shower, meds, toilet visits, outings) drawn from a normal/weighted-random
distribution around a population-level mean. `generate_month` calls it 30 times
independently, so no two days are identical. Ranges and cross-activity dependencies
follow the geriatric-routine research summarized for this task (sleep ~21:30-23:30
to ~05:30-08:00, breakfast tightest/most consistent meal, 4-8 toilet visits/day and
0-2/night, resident-specific shower-time cluster, meds tied to wake/breakfast/dinner/
bed with morning tighter than evening, 0-2 outings/day with weekday/weekend bias).
These are priors for *synthetic data generation only* — never anomaly thresholds.

Location vs. events:
  - `location_*` is a sticky one-hot over all 7 zones. It changes whenever the resident
    is detected in a new zone.
  - Door IS the location while the resident is out of the house (leaving freezes/opens
    on Door, not on the last indoor room) — so it is never 0% of occupancy.
  - Medications is almost always just a point pulse on `sensor_*`, but occasionally
    (a couple of times a month) the resident lingers at the meds spot for a minute or
    two, so `location_*` briefly reflects it too — kept rare (~0.2% of the day).
  - Bathroom sees more traffic than a single daily shower: short daytime visits
    (washing up) and 1-2 additional night trips (alongside/instead of the toilet) are
    normal.
  - `sensor_*` events are sparse: they fire once on a zone transition, once for a
    meds pulse, or rarely as idle-movement noise — never continuously while the
    resident stays put.

No anomaly scenarios are generated here by design — this file is normal-routine data
only.

Run directly to regenerate and re-analyze:
    python AI_Model/tests/data_gen.py

Writes into this same tests/ folder (overwritten on every run):
    mock_data_month.csv  - 30 days x 1440 minutes of the 18-feature vector
    data_summary.txt     - validation statistics (sleep, meals, toilet, shower,
                            meds consistency, outings, per-zone activation rates)
"""
import os
import numpy as np
import pandas as pd

OUT_DIR = os.path.dirname(__file__)
MINUTES_PER_DAY = 24 * 60

SENSOR_COLS = [f'sensor_{i}' for i in range(7)]
LOCATION_COLS = [f'location_{i}' for i in range(7)]
COLUMNS = SENSOR_COLS + LOCATION_COLS + ['hour_sin', 'hour_cos', 'day_sin', 'day_cos']

# Canonical zone mapping (Backend_Server/app/weekly_summary/constants.py:ZONE_NAMES)
DOOR, KITCHEN, BATHROOM, TOILET, MEDS, BEDROOM, LIVING_ROOM = 0, 1, 2, 3, 4, 5, 6
ZONE_NAMES = ["Door", "Kitchen", "Bathroom", "Toilet", "Medications", "Bedroom", "Living Room"]
REAL_ROOMS = {KITCHEN, BATHROOM, TOILET, BEDROOM, LIVING_ROOM}  # indoor rooms the resident lives in

# A single generic 70+ resident profile (population-level priors, not per-user tuning).
# Stds/ranges are intentionally wide — this is init data, so day-to-day noise matters
# more than pinpoint accuracy.
PROFILE = {
    'wake_mean_hour': 6.9, 'wake_std_min': 55,            # ~05:00-08:30
    'bed_mean_hour': 22.5, 'bed_std_min': 55,             # ~21:00-24:00
    'breakfast_mean_hour': 8.0, 'breakfast_std_min': 20, 'breakfast_dur': 25,   # tightest/most consistent meal
    'lunch_mean_hour': 12.6, 'lunch_std_min': 55, 'lunch_dur': 35, 'lunch_skip_prob': 0.15,
    'dinner_mean_hour': 18.2, 'dinner_std_min': 55, 'dinner_dur': 35,
    'shower_pref_hour': 7.3, 'shower_std_min': 40, 'shower_daily_prob': 0.8,
    'shower_dur_mean': 12, 'shower_dur_std': 6,           # clipped to 5-25, occasionally more
    'bathroom_visit_rate_mean': 1.6,                       # extra daytime washing-up visits, not the shower
    'bathroom_visit_dur': (2, 8),
    'meds_anchors': [                                     # {relative to, offset mean/std in minutes}
        {'name': 'morning', 'anchor': 'breakfast', 'offset_mean': 15, 'offset_std': 5},   # consistent
        {'name': 'evening', 'anchor': 'bed', 'offset_mean': -25, 'offset_std': 15},       # looser
    ],
    'meds_location_prob': 0.5,             # chance a meds anchor also briefly becomes the *location*, not just a pulse
    'meds_location_dur': (1, 4),
    'toilet_day_visits_mean': 6, 'toilet_day_visits_std': 1.5,    # clipped to 4-8
    'toilet_night_visits_p': [0.35, 0.4, 0.25],                    # P(0), P(1), P(2) — 1-2/night is normal
    'night_visit_bathroom_prob': 0.35,     # each night visit is toilet unless this rolls bathroom instead
    'toilet_visit_dur_mean': 3, 'toilet_visit_dur_std': 1.5,
    'kitchen_snack_rate_mean': 2.2,                        # extra coffee/snack/water visits per day
    'kitchen_snack_dur': (2, 6),
    # Tuned so average total time outside lands near the ~3h47m/day population average
    # from the research (report explicitly notes "substantial variation" and "some days
    # with no outside activity" — so this is a distribution, not a daily guarantee).
    'outing_prob_weekday': 0.7, 'outing_prob_weekend': 0.9,
    'outing_second_prob': 0.3,
    'outing_window_hours': (9, 17),
    'outing_duration_bins': {'short': (15, 45), 'medium': (60, 150), 'long': (150, 420)},
    'outing_duration_weights': [0.15, 0.3, 0.55],
}


def _clock(minute):
    minute = int(minute) % MINUTES_PER_DAY
    return f"{minute // 60:02d}:{minute % 60:02d}"


def _sample_minute(rng, mean_hour, std_min, lo_hour, hi_hour):
    minute = rng.normal(mean_hour * 60, std_min)
    return int(np.clip(minute, lo_hour * 60, hi_hour * 60 - 1))


def generate_day(profile, day_of_week, rng):
    """
    Generates one day (1440 minutes) for the given profile. Builds a per-minute
    "sticky room" baseline (sleep -> meals/snacks/shower/toilet -> outings, applied
    in that order so later layers correctly interrupt earlier ones), then derives
    sparse sensor events from room transitions plus independent Door/Meds pulses.
    Returns (DataFrame[1440, 18], stats: dict) — stats feeds the month-level summary.
    """
    is_weekend = day_of_week >= 5
    stats = {}

    wake = _sample_minute(rng, profile['wake_mean_hour'], profile['wake_std_min'], 5, 8)
    bed = _sample_minute(rng, profile['bed_mean_hour'], profile['bed_std_min'], 21, 24)
    stats['wake'], stats['bed'] = wake, bed

    # --- Baseline: sleep, then living room by default while awake ---
    location = [BEDROOM] * MINUTES_PER_DAY
    for m in range(wake, bed):
        location[m] = LIVING_ROOM

    # --- Meals (kitchen windows) ---
    def place_meal(mean_hour, std_min, lo_hour, hi_hour, dur, skip_prob=0.0):
        if rng.random() < skip_prob:
            return None
        start = _sample_minute(rng, mean_hour, std_min, lo_hour, hi_hour)
        start = max(start, wake + 5)
        for m in range(start, min(start + dur, bed)):
            location[m] = KITCHEN
        return start

    breakfast = place_meal(profile['breakfast_mean_hour'], profile['breakfast_std_min'], 6, 10, profile['breakfast_dur'])
    lunch = place_meal(profile['lunch_mean_hour'], profile['lunch_std_min'], 11, 14, profile['lunch_dur'], profile['lunch_skip_prob'])
    dinner = place_meal(profile['dinner_mean_hour'], profile['dinner_std_min'], 17, 20, profile['dinner_dur'])
    stats['breakfast'], stats['lunch'], stats['dinner'] = breakfast, lunch, dinner

    # --- Kitchen snacks / coffee / water / cleaning: short, low-consistency blips ---
    n_snacks = rng.poisson(profile['kitchen_snack_rate_mean'])
    for _ in range(n_snacks):
        t = rng.integers(wake, bed)
        dur = rng.integers(*profile['kitchen_snack_dur'])
        for m in range(t, min(t + dur, bed)):
            location[m] = KITCHEN

    # --- Shower: resident-preferred cluster, not literally every day ---
    shower_happened = rng.random() < profile['shower_daily_prob']
    shower_start = shower_dur = None
    if shower_happened:
        shower_start = _sample_minute(rng, profile['shower_pref_hour'], profile['shower_std_min'], 5, 22)
        shower_dur = int(np.clip(rng.normal(profile['shower_dur_mean'], profile['shower_dur_std']), 5, 25))
        for m in range(shower_start, min(shower_start + shower_dur, MINUTES_PER_DAY)):
            location[m] = BATHROOM
    stats['shower_happened'], stats['shower_start'], stats['shower_dur'] = shower_happened, shower_start, shower_dur

    # --- Extra daytime bathroom visits: washing up, unrelated to the shower ---
    n_bathroom_visits = rng.poisson(profile['bathroom_visit_rate_mean'])
    for _ in range(n_bathroom_visits):
        t = rng.integers(wake, bed)
        dur = rng.integers(*profile['bathroom_visit_dur'])
        for m in range(t, min(t + dur, bed)):
            location[m] = BATHROOM

    # --- Toilet visits: daytime (4-8, irregular) and nighttime (0-2, toilet or bathroom) ---
    n_day_visits = int(np.clip(round(rng.normal(profile['toilet_day_visits_mean'], profile['toilet_day_visits_std'])), 4, 8))
    for _ in range(n_day_visits):
        t = rng.integers(wake, bed)
        dur = int(np.clip(rng.normal(profile['toilet_visit_dur_mean'], profile['toilet_visit_dur_std']), 1, 6))
        for m in range(t, min(t + dur, bed)):
            location[m] = TOILET
    stats['toilet_day_visits'] = n_day_visits

    n_night_visits = rng.choice([0, 1, 2], p=profile['toilet_night_visits_p'])
    n_night_bathroom = 0
    for _ in range(n_night_visits):
        # Anywhere in the sleep window: [bed, 1440) or [0, wake)
        t = rng.integers(bed, MINUTES_PER_DAY) if rng.random() < 0.5 else rng.integers(0, wake)
        dur = int(np.clip(rng.normal(profile['toilet_visit_dur_mean'], profile['toilet_visit_dur_std']), 1, 6))
        zone = BATHROOM if rng.random() < profile['night_visit_bathroom_prob'] else TOILET
        n_night_bathroom += (zone == BATHROOM)
        for m in range(t, min(t + dur, MINUTES_PER_DAY)):
            location[m] = zone
    stats['toilet_night_visits'] = int(n_night_visits - n_night_bathroom)
    stats['bathroom_night_visits'] = int(n_night_bathroom)

    # --- Outings: away from home, location becomes Door for the whole outing ---
    outing_prob = profile['outing_prob_weekend'] if is_weekend else profile['outing_prob_weekday']
    outings = []
    if rng.random() < outing_prob:
        outings.append(1)
        if rng.random() < profile['outing_second_prob']:
            outings.append(1)

    lo_h, hi_h = profile['outing_window_hours']
    for _ in outings:
        start = int(rng.integers(lo_h * 60, hi_h * 60))
        bin_name = rng.choice(list(profile['outing_duration_bins'].keys()), p=profile['outing_duration_weights'])
        lo_dur, hi_dur = profile['outing_duration_bins'][bin_name]
        dur = int(rng.integers(lo_dur, hi_dur))
        end = min(start + dur, bed)
        if end <= start:
            continue
        for m in range(start, end):
            location[m] = DOOR
    stats['outing_count'] = len(outings)

    # --- Meds: point events tied to daily anchors; sometimes briefly the location too ---
    anchor_values = {'wake': wake, 'breakfast': breakfast if breakfast is not None else wake + 90,
                      'dinner': dinner if dinner is not None else bed - 120, 'bed': bed}
    meds_minutes = {}
    for spec in profile['meds_anchors']:
        base = anchor_values[spec['anchor']]
        t = int(np.clip(rng.normal(base + spec['offset_mean'], spec['offset_std']), 0, MINUTES_PER_DAY - 1))
        meds_minutes[spec['name']] = t
        if rng.random() < profile['meds_location_prob']:
            dur = int(rng.integers(*profile['meds_location_dur']))
            for m in range(t, min(t + dur, MINUTES_PER_DAY)):
                location[m] = MEDS
    stats['meds_minutes'] = meds_minutes

    # --- Derive sensor events from the finished location timeline ---
    events = [[0] * 7 for _ in range(MINUTES_PER_DAY)]
    prev = location[0]
    events[0][prev] = 1
    for m in range(1, MINUTES_PER_DAY):
        if location[m] != prev:
            events[m][location[m]] = 1
            prev = location[m]
        elif rng.random() > 0.994:
            # Idle-movement noise (rolling over in bed, shifting in a chair)
            events[m][location[m]] = 1

    for t in meds_minutes.values():
        events[t][MEDS] = 1

    # --- Assemble rows ---
    rows = []
    for m in range(MINUTES_PER_DAY):
        hour_frac = m / 60.0
        h_sin = np.sin(2 * np.pi * hour_frac / 24)
        h_cos = np.cos(2 * np.pi * hour_frac / 24)
        d_sin = np.sin(2 * np.pi * day_of_week / 7)
        d_cos = np.cos(2 * np.pi * day_of_week / 7)
        loc_state = [0] * 7
        loc_state[location[m]] = 1
        rows.append(events[m] + loc_state + [h_sin, h_cos, d_sin, d_cos])

    return pd.DataFrame(rows, columns=COLUMNS), stats


def generate_month(profile=PROFILE, days=30, seed=42):
    """Builds a month by generating `days` independently-sampled days back to back."""
    rng = np.random.default_rng(seed)
    frames, day_stats = [], []
    for day in range(days):
        df, stats = generate_day(profile, day % 7, rng)
        frames.append(df)
        day_stats.append(stats)
    return pd.concat(frames, ignore_index=True), day_stats


def _mean_std_clock(minutes):
    minutes = [m for m in minutes if m is not None]
    if not minutes:
        return "n/a (always skipped)"
    arr = np.array(minutes)
    return f"mean {_clock(arr.mean())}  std {arr.std():.0f}min  range [{_clock(arr.min())}, {_clock(arr.max())}]"


def summarize(df, day_stats, days):
    lines = []
    lines.append(f"Rows: {len(df)}  ({days} days x {MINUTES_PER_DAY} minutes)")
    lines.append("")

    # Sleep: bedtime of day N -> wake time of day N+1
    sleep_durations = []
    for i in range(len(day_stats) - 1):
        bed = day_stats[i]['bed']
        wake_next = day_stats[i + 1]['wake']
        sleep_durations.append((MINUTES_PER_DAY - bed + wake_next) / 60.0)
    lines.append("SLEEP")
    lines.append(f"  Average duration: {np.mean(sleep_durations):.2f}h  (std {np.std(sleep_durations):.2f}h)")
    lines.append(f"  Bedtime:  {_mean_std_clock([s['bed'] for s in day_stats])}")
    lines.append(f"  Wake-up:  {_mean_std_clock([s['wake'] for s in day_stats])}")
    lines.append("")

    lines.append("MEALS")
    lines.append(f"  Breakfast: {_mean_std_clock([s['breakfast'] for s in day_stats])}")
    n_lunch_skipped = sum(1 for s in day_stats if s['lunch'] is None)
    lines.append(f"  Lunch:     {_mean_std_clock([s['lunch'] for s in day_stats])}  "
                  f"({n_lunch_skipped}/{days} days skipped/away)")
    lines.append(f"  Dinner:    {_mean_std_clock([s['dinner'] for s in day_stats])}")
    lines.append("")

    lines.append("TOILET / NIGHT BATHROOM")
    day_visits = [s['toilet_day_visits'] for s in day_stats]
    night_toilet = [s['toilet_night_visits'] for s in day_stats]
    night_bathroom = [s['bathroom_night_visits'] for s in day_stats]
    night_total = [t + b for t, b in zip(night_toilet, night_bathroom)]
    lines.append(f"  Daytime toilet visits/day: mean {np.mean(day_visits):.1f}  (std {np.std(day_visits):.1f}, expect 4-8)")
    lines.append(f"  Night visits/day (toilet+bathroom): mean {np.mean(night_total):.2f}  "
                  f"(std {np.std(night_total):.2f}, expect 0-2; of which bathroom: {np.mean(night_bathroom):.2f})")
    lines.append("")

    lines.append("SHOWER")
    n_showers = sum(1 for s in day_stats if s['shower_happened'])
    shower_starts = [s['shower_start'] for s in day_stats if s['shower_happened']]
    shower_durs = [s['shower_dur'] for s in day_stats if s['shower_happened']]
    lines.append(f"  Frequency: {n_showers}/{days} days ({100 * n_showers / days:.0f}%)")
    lines.append(f"  Time:      {_mean_std_clock(shower_starts)}")
    if shower_durs:
        lines.append(f"  Duration:  mean {np.mean(shower_durs):.1f}min  (std {np.std(shower_durs):.1f}min, "
                      f"range [{min(shower_durs)}, {max(shower_durs)}]min)")
    lines.append("")

    lines.append("MEDICATION TIMING CONSISTENCY")
    for name in [spec['name'] for spec in PROFILE['meds_anchors']]:
        times = [s['meds_minutes'][name] for s in day_stats]
        arr = np.array(times)
        lines.append(f"  {name.capitalize():<8}: {_clock(arr.mean())} +/- {arr.std():.0f}min "
                      f"(range [{_clock(arr.min())}, {_clock(arr.max())}])")
    lines.append("")

    lines.append("OUTINGS")
    outing_counts = [s['outing_count'] for s in day_stats]
    lines.append(f"  Outings/day: mean {np.mean(outing_counts):.2f}  (std {np.std(outing_counts):.2f})")
    lines.append(f"  Days with >=1 outing: {sum(1 for c in outing_counts if c > 0)}/{days}")
    lines.append("")

    lines.append("PER-ZONE SENSOR ACTIVATION RATE (events/day)")
    for i, col in enumerate(SENSOR_COLS):
        total = int(df[col].sum())
        lines.append(f"  {ZONE_NAMES[i]:<12}: {total / days:5.1f}/day  ({total} total over {days} days)")
    lines.append("")

    lines.append("LOCATION OCCUPANCY (% of minutes, sticky one-hot over all 7 zones)")
    for i, col in enumerate(LOCATION_COLS):
        pct = 100 * df[col].sum() / len(df)
        lines.append(f"  {ZONE_NAMES[i]:<12}: {pct:5.1f}%")

    return "\n".join(lines)


if __name__ == "__main__":
    DAYS = 30
    df, day_stats = generate_month(PROFILE, days=DAYS, seed=42)

    data_path = os.path.join(OUT_DIR, "mock_data_month.csv")
    summary_path = os.path.join(OUT_DIR, "data_summary.txt")

    df.to_csv(data_path, index=False)

    summary_text = summarize(df, day_stats, DAYS)
    with open(summary_path, "w") as f:
        f.write(summary_text)

    print(summary_text)
    print(f"\nSaved mock data -> {data_path}")
    print(f"Saved summary   -> {summary_path}")
