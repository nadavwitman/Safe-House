"""
Shared helpers for the anomaly-scenario tests in tests_static/, tests_missing/,
tests_frequency/: build a 24h baseline routine (the same generator used to make
the training data), inject one specific anomaly into it, then roll the model's
fixed 360-minute window across the day one minute at a time and log how the
score evolves as the window slides from all-normal into fully covering the
anomaly and back out.

The real trained model only ever saw MinMax-scaled input (see
Backend_Server/app/core/data_preprocessing.py), so every window here is scaled
with the same scaler.pkl before being handed to evaluate_window. Columns 0-13
(sensor_*/location_*) are exactly binary in the training data, so the scaler
maps them 0->0 / 1->1 unchanged -- only the time columns actually get rescaled,
and none of the anomaly-scoring logic reads those, so this doesn't change how
the injected scenarios read out.
"""
import os
import numpy as np
import joblib

import data_gen
from model_handler import load_model, evaluate_window, WINDOW_SIZE, N_FEATURES

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(TESTS_DIR, "train", "best_safe_house_model.pth")
SCALER_PATH = os.path.join(TESTS_DIR, "train", "scaler.pkl")

MINUTES_PER_DAY = data_gen.MINUTES_PER_DAY  # 1440


def load_trained():
    """Real trained model + the MinMaxScaler it was trained with."""
    model = load_model(MODEL_PATH, seq_len=WINDOW_SIZE, n_features=N_FEATURES)
    scaler = joblib.load(SCALER_PATH)
    return model, scaler


def clock(minute):
    minute = int(minute) % MINUTES_PER_DAY
    return f"{minute // 60:02d}:{minute % 60:02d}"


def baseline_day(seed=1, day_of_week=2):
    """One normal 24h day (1440 x 18), drawn from the same profile/generator as
    the training data -- not hand-crafted, so everything except the injected
    anomaly is a realistic routine the model has actually seen the shape of."""
    rng = np.random.default_rng(seed)
    df, _ = data_gen.generate_day(data_gen.PROFILE, day_of_week=day_of_week, rng=rng)
    return df


def set_location(df, zone, start, end):
    """Forces the sticky location one-hot to `zone` for [start, end) and fires a
    zone-entry sensor pulse at `start` -- mirrors how data_gen derives events
    from location transitions. Used for static-location scenarios."""
    end = min(end, len(df))
    for i in range(7):
        df.loc[start:end - 1, f'location_{i}'] = 1 if i == zone else 0
    df.loc[start, f'sensor_{zone}'] = 1


def clear_sensor_events(df, zone, start, end):
    """Zeroes sensor_<zone> pulses in [start, end) -- the usage that stops
    happening. Used for missing-usage scenarios."""
    end = min(end, len(df))
    df.loc[start:end - 1, f'sensor_{zone}'] = 0


def inject_repeated_visits(df, zone, start, end, interval):
    """Fires a sensor_<zone> pulse every `interval` minutes across [start, end)
    -- far more distinct visit-starts than the baseline routine produces. Used
    for high-frequency scenarios."""
    end = min(end, len(df))
    for t in range(start, end, interval):
        df.loc[t, f'sensor_{zone}'] = 1


def last_sensor_event(df, zone):
    """Minute of the last sensor_<zone> pulse in the day (None if there are none)."""
    idx = np.flatnonzero(df[f'sensor_{zone}'].values == 1)
    return int(idx[-1]) if len(idx) else None


def roll_and_log(model, scaler, df, out_path, header_lines, log_interval=5, focus=None,
                  focus_fields=(), anomaly_start=None, anomaly_end=None, margin=60):
    """
    Slides the model's fixed 360-minute window one minute at a time and scores
    each chunk with evaluate_window, writing one line to out_path every
    `log_interval` minutes -- plus every time the overall severity changes, so
    no Normal<->Warning<->Emergency transition is missed just because it fell
    between sampled minutes.

    anomaly_start/anomaly_end: if given, only "now" times from `margin` minutes
    before anomaly_start through `margin` minutes after anomaly_end are scored
    -- one hour of normal routine before the anomaly, the anomaly itself, and
    one hour after (recovery should show up inside that hour, not need the
    rest of the day). If omitted, rolls across the whole day.

    The logged clock/`now` column is the window's END minute, not its start --
    in production the model always scores the most recent 6 hours ending "now",
    so that's the instant a real alarm would actually fire at. A window
    starting at 00:10 that happens to reach 10 minutes into a 06:00 anomaly is
    logged as "now = 06:10", not "00:10".

    focus: optional (debug_group, zone) e.g. ('static_location', BATHROOM) to
    also print that zone's own raw score next to the overall decision.
    focus_fields: extra keys from that same debug entry to print alongside it,
    e.g. ('since_last', 'expected_count', 'tolerance') -- the inputs the score
    was built from, so a scenario log shows *why* it moved, not just that it did.
    """
    values = df.values.astype(np.float32)
    n = len(df)
    lines = list(header_lines)
    lines.append("")
    header = f"{'now':>5}  {'win_start':>9}  {'severity':<10}  {'type':<16}  {'zone':<12}  {'score':>6}"
    if focus:
        header += "  focus_score"
        header += "".join(f"  {name:>14}" for name in focus_fields)
    lines.append(header)

    if anomaly_start is not None:
        now_lo = max(WINDOW_SIZE, anomaly_start - margin)
        now_hi = min(n, anomaly_end + margin)
    else:
        now_lo, now_hi = WINDOW_SIZE, n

    last_severity = None
    for now in range(now_lo, now_hi + 1):
        start = now - WINDOW_SIZE
        window = values[start:start + WINDOW_SIZE]
        scaled = scaler.transform(window)
        result = evaluate_window(model, scaled)

        severity = result['overall_severity']
        if now % log_interval == 0 or severity != last_severity:
            zone_name = result['zone_name'] or '-'
            anomaly_type = result['anomaly_type'] or '-'
            line = (f"{clock(now):>5}  {start:>9}  {severity:<10}  {anomaly_type:<16}  "
                    f"{zone_name:<12}  {result['score']:.4f}")
            if focus:
                group, zone = focus
                entry = result['debug'][group].get(zone, {})
                line += f"  {entry.get('score', 0.0):.4f}"
                line += "".join(f"  {entry.get(name, 0.0):>14.2f}" for name in focus_fields)
            lines.append(line)
        last_severity = severity

    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")

    return out_path
