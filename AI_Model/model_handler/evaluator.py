"""
Severity/decision logic and the top-level evaluate_window entrypoint that ties the
model, scoring, and decision together.

Input:  a [360, 18] window (actual) and its model reconstruction [360, 18].
Output: evaluate_window(...) returns a dict with overall severity/anomaly
        type/responsible sensor plus every component score for debugging.
"""
import torch

from .constants import (
    SEVERITY_NORMAL, SEVERITY_WARNING, SEVERITY_EMERGENCY,
    WARNING_THRESHOLD, EMERGENCY_THRESHOLD, ZONE_NAMES, SENSOR_THRESHOLD,
)
from .sensor_config import DEFAULT_SENSOR_CONFIG
from .signal_utils import _as_numpy, _location_sequence, _binarize_sensors
from .scoring import (
    compute_static_location_scores, compute_missing_usage_scores, compute_frequency_scores,
    compute_hosting_score, _apply_hosting_suppression,
)


def _severity_for(score, anomaly_type):
    """One universal scale for every zone/type. Missing usage and high frequency are
    hard-capped at Warning, per spec — only Static Location can reach Emergency."""
    if anomaly_type == 'Static Location':
        if score >= EMERGENCY_THRESHOLD:
            return SEVERITY_EMERGENCY
        if score >= WARNING_THRESHOLD:
            return SEVERITY_WARNING
        return SEVERITY_NORMAL
    return SEVERITY_WARNING if score >= WARNING_THRESHOLD else SEVERITY_NORMAL


def decide(static_scores, missing_scores, frequency_scores):
    """Picks the single strongest applicable anomaly.

    Static location is checked first and wins outright whenever it's active — it's the
    only score type that can alarm (reach Emergency), so it's reported ahead of missing/
    frequency regardless of their score. Missing and frequency can never alarm (capped at
    Warning by _severity_for); between those two, whichever has the higher score/loss wins.
    """
    static_candidates = []
    for zone, res in static_scores.items():
        if not res['active']:
            continue
        severity = _severity_for(res['score'], 'Static Location')
        if severity != SEVERITY_NORMAL:
            static_candidates.append((severity, res['score'], 'Static Location', zone))

    if static_candidates:
        severity_rank = {SEVERITY_EMERGENCY: 2, SEVERITY_WARNING: 1}
        severity, score, anomaly_type, zone = max(static_candidates, key=lambda c: (severity_rank[c[0]], c[1]))
        return {
            'severity': severity, 'anomaly_type': anomaly_type,
            'zone': zone, 'zone_name': ZONE_NAMES[zone], 'score': score,
        }

    other_candidates = []
    for zone, res in missing_scores.items():
        if not res['active']:
            continue
        severity = _severity_for(res['score'], 'Missing Usage')
        if severity != SEVERITY_NORMAL:
            other_candidates.append((severity, res['score'], 'Missing Usage', zone))

    for zone, res in frequency_scores.items():
        severity = _severity_for(res['score'], 'High Frequency')
        if severity != SEVERITY_NORMAL:
            other_candidates.append((severity, res['score'], 'High Frequency', zone))

    if not other_candidates:
        return {'severity': SEVERITY_NORMAL, 'anomaly_type': None, 'zone': None, 'zone_name': None, 'score': 0.0}

    severity, score, anomaly_type, zone = max(other_candidates, key=lambda c: c[1])
    return {
        'severity': severity, 'anomaly_type': anomaly_type,
        'zone': zone, 'zone_name': ZONE_NAMES[zone], 'score': score,
    }


def evaluate_window(model, window, sensor_config=DEFAULT_SENSOR_CONFIG, sensor_threshold=SENSOR_THRESHOLD):
    """
    Runs the model on a single 6-hour window and returns the full anomaly evaluation.

    window: [360, 18] or [1, 360, 18] tensor/array (actual, unscaled-or-scaled the
            same way the model was trained on).
    """
    tensor_input = window if isinstance(window, torch.Tensor) else torch.FloatTensor(window)
    if tensor_input.dim() == 2:
        tensor_input = tensor_input.unsqueeze(0)

    model.eval()
    with torch.no_grad():
        reconstructed = model(tensor_input)

    window_np = _as_numpy(tensor_input)[0]
    recon_np = _as_numpy(reconstructed)[0]

    actual_loc_seq = _location_sequence(window_np)
    recon_loc_seq = _location_sequence(recon_np)
    recon_sensor_binary = _binarize_sensors(recon_np, threshold=sensor_threshold)

    static_scores = compute_static_location_scores(actual_loc_seq, recon_loc_seq, sensor_config)
    missing_scores = compute_missing_usage_scores(window_np, recon_sensor_binary, sensor_config)
    frequency_scores_raw = compute_frequency_scores(window_np, recon_sensor_binary, sensor_config)

    hosting = compute_hosting_score(window_np)
    frequency_scores = _apply_hosting_suppression(frequency_scores_raw, hosting['score'], sensor_config)

    decision = decide(static_scores, missing_scores, frequency_scores)

    return {
        'overall_severity': decision['severity'],
        'anomaly_type': decision['anomaly_type'],
        'zone': decision['zone'],
        'zone_name': decision['zone_name'],
        'score': decision['score'],
        'debug': {
            'static_location': static_scores,
            'missing_usage': missing_scores,
            'high_frequency_raw': frequency_scores_raw,
            'high_frequency_suppressed': frequency_scores,
            'hosting': hosting,
            'recon_sensor_binary': recon_sensor_binary,
        },
    }
