"""
Missing-usage scenario: an important sensor stops firing entirely. All of a
zone's sensor pulses are removed from an otherwise-normal day, so as the
rolling 360-minute window slides forward, "minutes since the last real event"
keeps growing -- once past missing_grace, the score should sweep from Normal
into Warning as the model's reconstructed expectation for that stretch goes
unmet (missing usage is capped at Warning, per spec -- it can never alarm).

Runs the same scenario for every zone that has 'missing' enabled in
model_handler.DEFAULT_SENSOR_CONFIG (Kitchen, Bathroom, Toilet, Medications,
Bedroom -- Door and Living Room aren't missing-usage scored), writing one
results_missing_<zone>.txt per zone.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from test_common import load_trained, baseline_day, clear_sensor_events, roll_and_log
from model_handler import DEFAULT_SENSOR_CONFIG, ZONE_NAMES


def run_zone(model, scaler, zone, seed):
    zone_name = ZONE_NAMES[zone]
    df = baseline_day(seed=seed)
    clear_sensor_events(df, zone, 0, len(df))  # this zone's sensor never fires, all day

    header = [
        f"MISSING USAGE -- {zone_name} never used scenario",
        f"Anomaly: every {zone_name} sensor pulse removed for the whole day. Rest of "
        "the day (location, other sensors) is a normal generated routine.",
        "Rolling 360-minute window, 1-minute step, across the full 24h day.",
    ]
    fname = f"results_missing_{zone_name.lower().replace(' ', '_')}.txt"
    out_path = os.path.join(os.path.dirname(__file__), fname)
    roll_and_log(model, scaler, df, out_path, header, log_interval=5,
                 focus=('missing_usage', zone))
    print(f"wrote {out_path}")


def main():
    model, scaler = load_trained()
    seed = 11
    for zone, cfg in DEFAULT_SENSOR_CONFIG.items():
        if 'missing' in cfg['enabled']:
            run_zone(model, scaler, zone, seed)
            seed += 1


if __name__ == "__main__":
    main()
