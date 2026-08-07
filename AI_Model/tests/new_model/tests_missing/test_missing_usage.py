"""
Missing-usage scenario, new-model variant -- identical scenario logic to
AI_Model/tests/tests_missing/test_missing_usage.py, pointed at the
weighted-loss checkpoint's test_common/model_handler in new_model/.

An important sensor stops firing entirely. A zone's sensor pulses are removed
for 07:00-23:00 (routine 06:00-07:00 and 23:00-24:00 bookend the anomaly), so
as the rolling 360-minute window slides forward, "minutes since the last real
event" keeps growing -- once past missing_grace, the score should sweep from
Normal into Warning as the model's reconstructed expectation for that stretch
goes unmet (missing usage is capped at Warning, per spec -- it can never
alarm).

Runs the same scenario for every zone that has 'missing' enabled in
model_handler.DEFAULT_SENSOR_CONFIG (Kitchen, Bathroom, Toilet, Medications --
Door, Bedroom, and Living Room aren't missing-usage scored), writing one
results_missing_<zone>.txt per zone.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from test_common import load_trained, baseline_day, clear_sensor_events, roll_and_log, clock
from model_handler import DEFAULT_SENSOR_CONFIG, ZONE_NAMES

ANOMALY_START = 7 * 60   # 07:00
ANOMALY_END = 23 * 60    # 23:00


def run_zone(model, scaler, zone, seed):
    zone_name = ZONE_NAMES[zone]
    df = baseline_day(seed=seed)
    # note: seed=3 confirmed clean of coincidental cross-zone anomalies (matches
    # the seed used by tests_static's static-location scenarios)
    clear_sensor_events(df, zone, ANOMALY_START, ANOMALY_END)

    header = [
        f"MISSING USAGE (new model) -- {zone_name} never used scenario",
        f"Anomaly: every {zone_name} sensor pulse removed {clock(ANOMALY_START)}-"
        f"{clock(ANOMALY_END)}. Rest of the day (location, other sensors) is a "
        "normal generated routine.",
        "Rolling 360-minute window, 1-minute step: routine before/after the "
        "anomaly, and the anomaly itself.",
    ]
    fname = f"results_missing_{zone_name.lower().replace(' ', '_')}.txt"
    out_path = os.path.join(os.path.dirname(__file__), fname)
    roll_and_log(model, scaler, df, out_path, header, log_interval=10,
                 focus=('missing_usage', zone),
                 anomaly_start=ANOMALY_START, anomaly_end=ANOMALY_END)
    print(f"wrote {out_path}")


def main():
    model, scaler = load_trained()
    seed = 3
    for zone, cfg in DEFAULT_SENSOR_CONFIG.items():
        if 'missing' in cfg['enabled']:
            run_zone(model, scaler, zone, seed)


if __name__ == "__main__":
    main()
