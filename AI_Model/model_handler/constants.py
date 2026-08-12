"""
Structural constants: window/feature dimensions, column layout, zone identity,
and severity levels/thresholds.

Column layout (must match data_gen.py / data_preprocessing.py):
  0-6   sensor_*    : sparse per-zone event pulses
  7-13  location_*  : sticky one-hot current-location state
  14-17 hour_sin, hour_cos, day_sin, day_cos

Zone index -> name (Backend_Server/app/weekly_summary/constants.py:ZONE_NAMES):
  0 Door, 1 Kitchen, 2 Bathroom, 3 Toilet, 4 Medications, 5 Bedroom, 6 Living Room
"""

WINDOW_SIZE = 360
N_FEATURES = 18

SENSOR_SLICE = slice(0, 7)
LOCATION_SLICE = slice(7, 14)

# Reconstructed sensor probability above this counts as "the model predicts an event here".
# Only meaningful on the weighted-loss checkpoint -- see package __init__.py docstring.
SENSOR_THRESHOLD = 0.5

DOOR, KITCHEN, BATHROOM, TOILET, MEDS, BEDROOM, LIVING_ROOM = range(7)
ZONE_NAMES = ["Door", "Kitchen", "Bathroom", "Toilet", "Medications", "Bedroom", "Living Room"]

SEVERITY_NORMAL, SEVERITY_WARNING, SEVERITY_EMERGENCY = "Normal", "Warning", "Emergency"

# Universal severity thresholds — one scale for every score type/zone. Missing-usage and
# high-frequency are still hard-capped at Warning (per spec, see evaluator._severity_for);
# only Static Location can cross into Emergency.
#
# 0.5 is not a safe cutoff for the static-location ratio: current_run/(current_run+expected)
# is exactly 0.5 whenever the actual matches the model's own reconstruction perfectly (e.g.
# a completely normal full night's sleep) -- confirmed on the real trained model. Raised
# above that parity point so a perfect match never itself reads as an alarm.
WARNING_THRESHOLD = 0.65
EMERGENCY_THRESHOLD = 0.85

# Shared 30-minute window for missing-usage and high-frequency: how close a real event
# must be to the reconstruction's peak to count as satisfying it (missing-usage), and how
# far back to count rising edges (high-frequency). One number instead of a per-zone field
# for each.
WARNING_WINDOW = 30
