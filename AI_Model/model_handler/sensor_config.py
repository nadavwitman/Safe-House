"""
Per-sensor/zone configuration.

Every zone gets one config entry (indices match sensor_* / location_* column order,
i.e. the ZONE_NAMES order in constants.py). All numbers here are calibration knobs,
not physiological facts — carried over from the old MSE-checkpoint's calibration;
see the package __init__.py note on re-validating against this checkpoint's binary
counts.
"""
from .constants import DOOR, KITCHEN, BATHROOM, TOILET, MEDS, BEDROOM, LIVING_ROOM


def _cfg(
    enabled,                       # set of {'static', 'missing', 'frequency'}
    minimum_expected_run=None,
    missing_grace=None, missing_tolerance=None,
    frequency_lookback=None, frequency_tolerance=None,
    hosting_suppression=True,
):
    return {
        'enabled': set(enabled),
        'minimum_expected_run': minimum_expected_run,
        'missing_grace': missing_grace,
        'missing_tolerance': missing_tolerance,
        'frequency_lookback': frequency_lookback,
        'frequency_tolerance': frequency_tolerance,
        'hosting_suppression': hosting_suppression,
    }


DEFAULT_SENSOR_CONFIG = {
    # Door: leaving the house for hours is normal, not a "stuck" location — never
    # static-scored. Repeated door-opening (wandering) can still be flagged via
    # high-frequency.
    DOOR: _cfg(
        enabled={'frequency'},
        frequency_lookback=60, frequency_tolerance=5,
        hosting_suppression=True,
    ),
    KITCHEN: _cfg(
        enabled={'static', 'missing', 'frequency'},
        minimum_expected_run=60,
        missing_grace=120, missing_tolerance=1.0,
        frequency_lookback=180, frequency_tolerance=5,
        hosting_suppression=True,
    ),
    BATHROOM: _cfg(
        enabled={'static', 'missing', 'frequency'},
        # Real visits run up to ~22min (p99) -- shower included.
        minimum_expected_run=30,
        missing_grace=90, missing_tolerance=1.0,
        frequency_lookback=240, frequency_tolerance=4,
        hosting_suppression=True,
    ),
    TOILET: _cfg(
        enabled={'static', 'missing', 'frequency'},
        minimum_expected_run=30,
        missing_grace=90, missing_tolerance=2.0,
        frequency_lookback=180, frequency_tolerance=3,   # sensitive to repeated night visits
        hosting_suppression=True,
    ),
    # Medications is event-only: never static-location scored, per spec.
    MEDS: _cfg(
        enabled={'missing', 'frequency'},
        missing_grace=120, missing_tolerance=0.1,
        frequency_lookback=360, frequency_tolerance=2,
        hosting_suppression=False,
    ),
    BEDROOM: _cfg(
        enabled={'static', 'frequency'},
        minimum_expected_run=60,
        frequency_lookback=240, frequency_tolerance=4,
        hosting_suppression=True,
    ),
    LIVING_ROOM: _cfg(
        enabled={'static'},
        minimum_expected_run=60,
        hosting_suppression=True,
    ),
}

# Hosting/guest heuristic knobs
HOSTING_LOOKBACK = 60
HOSTING_MULTI_SENSOR_TOLERANCE = 8     # minutes with >1 active sensor before hosting_score saturates
HOSTING_TRANSITION_TOLERANCE = 6       # location transitions before hosting_score saturates
HOSTING_ROOM_SPREAD_TOLERANCE = 4      # distinct rooms active before hosting_score saturates
HOSTING_SUPPRESSION_THRESHOLD = 0.5    # hosting_score above this starts suppressing frequency scores
