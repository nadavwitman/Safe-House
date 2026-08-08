"""
Static-location scenario, new-model variant -- location/sensor-mismatch flavor.

Unlike the paired plain scenario (routine sensor pulses + routine location, with
the location vector alone stretched into a long stay), this variant forces the
location vector into an anomalous stuck-in-zone stretch while leaving the
sensor vector completely untouched (routine). The model sees a resident whose
location trace says "still in the kitchen" for hours but whose sensor pulses
keep firing on their normal routine schedule -- a location/sensor mismatch
rather than a straightforward long stay.

Every zone except Living Room: 06:00-07:00 routine, 07:00-23:00 anomaly, 23:00-24:00
routine. Living Room instead gets an overnight anomaly (23:00-07:00) -- stuck there
through the night is the anomalous case for that zone, not stuck there during the day.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from test_common import load_trained, baseline_day, extend_with_night, set_location, roll_and_log, clock
from model_handler import ZONE_NAMES, KITCHEN, BATHROOM, TOILET, BEDROOM, LIVING_ROOM

MARGIN = 60            # 1h of routine logged before/after the anomaly, via roll_and_log's margin
NIGHT_EXTENSION = 480  # minutes of day 1's start (00:00 on) replayed onto the end, so
                        # windows can roll past 24:00 into the next morning

# zone -> (anomaly_start, anomaly_end), in minutes since midnight
_WINDOW = (7 * 60, 23 * 60)
_NIGHT_WINDOW = (23 * 60, 23 * 60 + 8 * 60)  # 23:00 -> 07:00 next day
ZONE_WINDOWS = {
    KITCHEN:     _WINDOW,
    BATHROOM:    _WINDOW,
    TOILET:      _WINDOW,
    BEDROOM:     _WINDOW,
    LIVING_ROOM: _NIGHT_WINDOW,
}


def run_zone(model, scaler, zone):
    zone_name = ZONE_NAMES[zone]
    anomaly_start, anomaly_end = ZONE_WINDOWS[zone]

    df = baseline_day(seed=3)
    df = extend_with_night(df, NIGHT_EXTENSION)
    set_location(df, zone, anomaly_start, anomaly_end, fire_sensor=False)

    header = [
        f"STATIC LOCATION (new model) -- location/sensor mismatch, stuck-in-{zone_name}",
        f"Anomaly: location vector pinned to {zone_name} {clock(anomaly_start)}-{clock(anomaly_end)} "
        "while the sensor vector is left untouched (routine schedule, no forced zone-entry "
        "pulse). Rest of the day is a normal generated routine.",
        "Rolling 360-minute window, 1-minute step: 1h of normal routine before the "
        "anomaly, the anomaly itself, and 1h after (to see recovery).",
    ]
    fname = f"results_static_{zone_name.lower().replace(' ', '_')}.txt"
    out_path = os.path.join(os.path.dirname(__file__), fname)
    roll_and_log(model, scaler, df, out_path, header, log_interval=10,
                 focus=('static_location', zone),
                 anomaly_start=anomaly_start, anomaly_end=anomaly_end, margin=MARGIN)
    print(f"wrote {out_path}")


def main():
    model, scaler = load_trained()
    for zone in ZONE_WINDOWS:
        run_zone(model, scaler, zone)


if __name__ == "__main__":
    main()
