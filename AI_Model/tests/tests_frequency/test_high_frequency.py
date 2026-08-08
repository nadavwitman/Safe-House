"""
High-frequency scenario, new-model variant -- identical scenario logic to
AI_Model/tests/tests_frequency/test_high_frequency.py, pointed at the
weighted-loss checkpoint's test_common/model_handler in new_model/.

Unusually frequent non-continuous activity (repeated visits), not one long
stay. A sensor pulse is injected every 5 minutes from 07:00-23:00 (routine
06:00-07:00 and 23:00-24:00 bookend the anomaly) -- far more distinct
visit-starts (rising edges) than the model's reconstructed expectation for
that stretch -- so as the rolling 360-minute window slides across it, the
score should sweep Normal -> Warning (high frequency is capped at Warning,
per spec -- it can never alarm).

Runs the same scenario for every zone that has 'frequency' enabled in
model_handler.DEFAULT_SENSOR_CONFIG (Door, Kitchen, Bathroom, Toilet,
Medications, Bedroom -- Living Room isn't frequency scored), writing one
results_frequency_<zone>.txt per zone.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from test_common import load_trained, baseline_day, inject_repeated_visits, roll_and_log, clock
from model_handler import DEFAULT_SENSOR_CONFIG, ZONE_NAMES

ANOMALY_START = 7 * 60   # 07:00
ANOMALY_END = 23 * 60    # 23:00
INTERVAL = 5            # a sensor pulse every 5 minutes -- repeated wandering/visiting


def run_zone(model, scaler, zone, seed):
    zone_name = ZONE_NAMES[zone]
    df = baseline_day(seed=seed)
    inject_repeated_visits(df, zone, ANOMALY_START, ANOMALY_END, INTERVAL)

    header = [
        f"HIGH FREQUENCY (new model) -- repeated {zone_name} visits scenario",
        f"Anomaly: a {zone_name} sensor pulse every {INTERVAL}min from {clock(ANOMALY_START)}-"
        f"{clock(ANOMALY_END)} (far more distinct visit-starts than baseline). Rest of "
        "the day is a normal generated routine.",
        "Rolling 360-minute window, 1-minute step: 1h of normal routine before the "
        "anomaly, the anomaly itself, and 1h after (to see recovery).",
    ]
    fname = f"results_frequency_{zone_name.lower().replace(' ', '_')}.txt"
    out_path = os.path.join(os.path.dirname(__file__), fname)
    roll_and_log(model, scaler, df, out_path, header, log_interval=10,
                 focus=('high_frequency_raw', zone),
                 anomaly_start=ANOMALY_START, anomaly_end=ANOMALY_END)
    print(f"wrote {out_path}")


def main():
    model, scaler = load_trained()
    seed = 3  # confirmed clean of coincidental cross-zone anomalies, same as tests_missing
    for zone, cfg in DEFAULT_SENSOR_CONFIG.items():
        if 'frequency' in cfg['enabled']:
            run_zone(model, scaler, zone, seed)


if __name__ == "__main__":
    main()
