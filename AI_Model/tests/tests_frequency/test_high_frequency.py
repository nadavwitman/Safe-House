"""
High-frequency scenario: unusually frequent non-continuous activity (repeated
visits), not one long stay. A sensor pulse is injected every 5 minutes for 5
hours -- far more distinct visit-starts (rising edges) than the model's
reconstructed expectation for that stretch -- so as the rolling 360-minute
window slides across it, the score should sweep Normal -> Warning (high
frequency is capped at Warning, per spec -- it can never alarm).

Runs the same scenario for every zone that has 'frequency' enabled in
model_handler.DEFAULT_SENSOR_CONFIG (Door, Kitchen, Bathroom, Toilet,
Medications -- Living Room isn't frequency scored), writing one
results_frequency_<zone>.txt per zone.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from test_common import load_trained, baseline_day, inject_repeated_visits, roll_and_log, clock
from model_handler import DEFAULT_SENSOR_CONFIG, ZONE_NAMES

ANOMALY_START = 600     # 10:00
ANOMALY_DURATION = 300  # 5 hours
ANOMALY_END = ANOMALY_START + ANOMALY_DURATION
INTERVAL = 5            # a sensor pulse every 5 minutes -- repeated wandering/visiting


def run_zone(model, scaler, zone, seed):
    zone_name = ZONE_NAMES[zone]
    df = baseline_day(seed=seed)
    inject_repeated_visits(df, zone, ANOMALY_START, ANOMALY_END, INTERVAL)

    header = [
        f"HIGH FREQUENCY -- repeated {zone_name} visits scenario",
        f"Anomaly: a {zone_name} sensor pulse every {INTERVAL}min from {clock(ANOMALY_START)}-"
        f"{clock(ANOMALY_END)} (far more distinct visit-starts than baseline). Rest of "
        "the day is a normal generated routine.",
        "Rolling 360-minute window, 1-minute step: 1h of normal routine before the "
        "anomaly, the anomaly itself, and 1h after (to see recovery).",
    ]
    fname = f"results_frequency_{zone_name.lower().replace(' ', '_')}.txt"
    out_path = os.path.join(os.path.dirname(__file__), fname)
    roll_and_log(model, scaler, df, out_path, header, log_interval=5,
                 focus=('high_frequency_raw', zone),
                 anomaly_start=ANOMALY_START, anomaly_end=ANOMALY_END)
    print(f"wrote {out_path}")


def main():
    model, scaler = load_trained()
    seed = 23
    for zone, cfg in DEFAULT_SENSOR_CONFIG.items():
        if 'frequency' in cfg['enabled']:
            run_zone(model, scaler, zone, seed)
            seed += 1


if __name__ == "__main__":
    main()
