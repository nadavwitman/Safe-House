"""
The three anomaly-type scorers (static-location, missing-usage, high-frequency) plus
the hosting/guest heuristic that can suppress high-frequency scores.
"""
from .constants import SENSOR_SLICE, WARNING_WINDOW
from .sensor_config import (
    DEFAULT_SENSOR_CONFIG,
    HOSTING_LOOKBACK, HOSTING_MULTI_SENSOR_TOLERANCE, HOSTING_TRANSITION_TOLERANCE,
    HOSTING_ROOM_SPREAD_TOLERANCE, HOSTING_SUPPRESSION_THRESHOLD,
)
from .signal_utils import _clamp01, _ratio_score, _location_sequence, _trailing_run, _longest_run, _rising_edges


# ===========================================================================
# 1. Static-location anomaly
# ===========================================================================

def compute_static_location_scores(actual_loc_seq, recon_loc_seq, sensor_config=DEFAULT_SENSOR_CONFIG):
    """Returns {zone_index: {'score', 'current_run', 'reconstructed_max_run', 'active'}}."""
    current_zone = int(actual_loc_seq[-1])
    current_run = _trailing_run(actual_loc_seq, current_zone)

    results = {}
    for zone, cfg in sensor_config.items():
        if 'static' not in cfg['enabled']:
            continue
        if zone != current_zone or current_run <= 0:
            # Not the current location right now -> recovers immediately, no active score.
            results[zone] = {'score': 0.0, 'current_run': 0, 'reconstructed_max_run': None, 'active': False}
            continue

        reconstructed_max_run = _longest_run(recon_loc_seq, zone)
        min_expected = cfg['minimum_expected_run']
        score = _ratio_score(current_run, max(reconstructed_max_run, min_expected))
        results[zone] = {
            'score': score, 'current_run': current_run,
            'reconstructed_max_run': reconstructed_max_run, 'active': True,
        }
    return results


# ===========================================================================
# 2. Missing-usage anomaly
# ===========================================================================

def compute_missing_usage_scores(window_np, recon_sensor_binary, sensor_config=DEFAULT_SENSOR_CONFIG):
    """Returns {zone_index: {'score', 'active', 'actual_count', 'expected_count'}}.

    missing_grace gates WHEN it's scored: the window is cut to the
    [missing_grace, missing_grace + WARNING_WINDOW) slice (in minutes-ago terms) and the
    expected count is taken only over that slice -- outside it a missed peak can't keep
    firing for the rest of the day. WARNING_WINDOW also sets the width of that band.

    expected_count is a count of thresholded 1s (recon_sensor_binary), not a sum of raw
    floats as in the old MSE-checkpoint version -- see package __init__.py docstring.
    """
    results = {}
    for zone, cfg in sensor_config.items():
        if 'missing' not in cfg['enabled']:
            continue

        recon_zone = recon_sensor_binary[:, zone]
        n = len(recon_zone)
        grace = cfg['missing_grace']

        hi = max(0, n - grace)
        lo = max(0, n - grace - WARNING_WINDOW)
        if lo >= hi:
            results[zone] = {
                'score': 0.0, 'active': False,
                'actual_count': 0.0, 'expected_count': 0.0,
            }
            continue

        matched = bool(window_np[:, zone].sum() > 0)
        expected_count = float(recon_zone[lo:hi].sum())

        score = 0.0 if matched else _ratio_score(expected_count, cfg['missing_tolerance'])
        results[zone] = {
            'score': score, 'active': not matched,
            'actual_count': 0.0 if matched else float(window_np[lo:hi, zone].sum()),
            'expected_count': expected_count,
        }
    return results


# ===========================================================================
# 3. High-frequency anomaly
# ===========================================================================

def compute_frequency_scores(window_np, recon_sensor_binary, sensor_config=DEFAULT_SENSOR_CONFIG):
    """Returns {zone_index: {'score', 'actual_count', 'expected_count'}} (pre hosting-suppression).

    Both actual_count and expected_count are rising-edge counts on binary sequences.
    Previously actual_count was edges but expected_count was a sum of raw floats -- a unit
    mismatch masked by the old checkpoint's floats being uniformly tiny; both sides now
    count the same thing.
    """
    results = {}
    for zone, cfg in sensor_config.items():
        if 'frequency' not in cfg['enabled']:
            continue

        lookback = min(cfg['frequency_lookback'], window_np.shape[0])
        actual_sensor = window_np[-lookback:, zone]
        recon_zone = recon_sensor_binary[-lookback:, zone]

        # Count distinct visit/event entries, not raw active-minute totals, so one
        # long continuous stay isn't mistaken for repeated non-continuous activity.
        actual_count = float(_rising_edges(actual_sensor))
        expected_count = float(_rising_edges(recon_zone))
        excess = max(0.0, actual_count - expected_count)
        score = _ratio_score(excess, cfg['frequency_tolerance'])
        results[zone] = {'score': score, 'actual_count': actual_count, 'expected_count': expected_count}
    return results


# ===========================================================================
# Hosting/guest heuristic
# ===========================================================================

def compute_hosting_score(window_np, lookback=HOSTING_LOOKBACK):
    recent = window_np[-lookback:]
    sensors = recent[:, SENSOR_SLICE]
    loc_seq = _location_sequence(recent)

    multi_sensor_minutes = float((sensors.sum(axis=1) > 1).sum())
    distinct_rooms_active = float((sensors.sum(axis=0) > 0).sum())
    transitions = float((loc_seq[1:] != loc_seq[:-1]).sum())

    multi_sensor_component = _ratio_score(multi_sensor_minutes, HOSTING_MULTI_SENSOR_TOLERANCE)
    transition_component = _ratio_score(transitions, HOSTING_TRANSITION_TOLERANCE)
    spread_component = _ratio_score(distinct_rooms_active, HOSTING_ROOM_SPREAD_TOLERANCE)

    hosting_score = _clamp01((multi_sensor_component + transition_component + spread_component) / 3.0)
    return {
        'score': hosting_score,
        'multi_sensor_minutes': multi_sensor_minutes,
        'distinct_rooms_active': distinct_rooms_active,
        'transitions': transitions,
    }


def _apply_hosting_suppression(frequency_results, hosting_score, sensor_config=DEFAULT_SENSOR_CONFIG):
    if hosting_score <= HOSTING_SUPPRESSION_THRESHOLD:
        return frequency_results
    suppression_factor = 1.0 - hosting_score  # softer, not a hard zero
    suppressed = {}
    for zone, res in frequency_results.items():
        cfg = sensor_config[zone]
        if cfg['hosting_suppression']:
            suppressed[zone] = {**res, 'score': res['score'] * suppression_factor}
        else:
            suppressed[zone] = res
    return suppressed
