"""
Static-location scenario: the resident is home the whole time but doesn't leave
one room. A normal room stay is stretched into a long continuous stay -- long
enough that as the rolling 360-minute window slides across it, current_run
climbs past minimum_expected_run and the score should sweep Normal -> Warning
-> Emergency (Static Location is the only anomaly type allowed to reach
Emergency).

Runs the same scenario for every zone that has 'static' enabled in
model_handler.DEFAULT_SENSOR_CONFIG (Kitchen, Bathroom, Toilet, Bedroom,
Living Room -- Door and Medications are never static-location scored, per
spec), writing one results_static_<zone>.txt per zone.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from test_common import load_trained, baseline_day, set_location, roll_and_log, clock
from model_handler import DEFAULT_SENSOR_CONFIG, ZONE_NAMES

ANOMALY_START = 360      # 06:00
# Stretch each zone's stay well past its own minimum_expected_run, capped so it
# still fits in the day.
DURATION_MARGIN = 400
MAX_DURATION = 900


def run_zone(model, scaler, zone):
    cfg = DEFAULT_SENSOR_CONFIG[zone]
    zone_name = ZONE_NAMES[zone]
    min_expected = cfg['minimum_expected_run']
    duration = min(min_expected + DURATION_MARGIN, MAX_DURATION)
    anomaly_end = ANOMALY_START + duration

    df = baseline_day(seed=7)
    set_location(df, zone, ANOMALY_START, anomaly_end)

    header = [
        f"STATIC LOCATION -- stuck-in-{zone_name} scenario",
        f"Anomaly: continuous {zone_name} stay {clock(ANOMALY_START)}-{clock(anomaly_end)} "
        f"({duration}min, vs a minimum_expected_run of {min_expected}min). Rest of the day "
        "is a normal generated routine.",
        "Rolling 360-minute window, 1-minute step: 1h of normal routine before the "
        "anomaly, the anomaly itself, and 1h after (to see recovery).",
    ]
    fname = f"results_static_{zone_name.lower().replace(' ', '_')}.txt"
    out_path = os.path.join(os.path.dirname(__file__), fname)
    roll_and_log(model, scaler, df, out_path, header, log_interval=10,
                 focus=('static_location', zone),
                 anomaly_start=ANOMALY_START, anomaly_end=anomaly_end)
    print(f"wrote {out_path}")


def main():
    model, scaler = load_trained()
    for zone, cfg in DEFAULT_SENSOR_CONFIG.items():
        if 'static' in cfg['enabled']:
            run_zone(model, scaler, zone)


if __name__ == "__main__":
    main()
