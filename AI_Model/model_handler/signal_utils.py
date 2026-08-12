"""Small stateless helpers for turning raw/reconstructed windows into countable signals."""
import torch
import numpy as np

from .constants import SENSOR_SLICE, LOCATION_SLICE, SENSOR_THRESHOLD


def _clamp01(x):
    return max(0.0, min(1.0, float(x)))


def _ratio_score(numerator, denominator_extra):
    """numerator / (numerator + denominator_extra), clamped to [0, 1]."""
    denom = numerator + denominator_extra
    if denom <= 1e-8:
        return 0.0
    return _clamp01(numerator / denom)


def _as_numpy(window):
    if isinstance(window, torch.Tensor):
        return window.detach().cpu().numpy()
    return np.asarray(window)


def _location_sequence(window_np):
    """[360, 7] one-hot/probabilities -> [360] argmax zone-index sequence."""
    return np.argmax(window_np[:, LOCATION_SLICE], axis=1)


def _binarize_sensors(window_np, threshold=SENSOR_THRESHOLD):
    """[360, 18] -> [360, 7] sensor block thresholded to {0.0, 1.0}.

    Only safe to call on a RECONSTRUCTION from the weighted-loss checkpoint -- on the old
    MSE checkpoint sensor floats never exceeded ~0.14 and this would always return zeros.
    The actual (input) window is already exactly binary and doesn't need this.
    """
    return (window_np[:, SENSOR_SLICE] > threshold).astype(np.float64)


def _trailing_run(seq, value):
    """Count consecutive occurrences of `value` at the END of seq."""
    run = 0
    for v in reversed(seq.tolist()):
        if v == value:
            run += 1
        else:
            break
    return run


def _longest_run(seq, value):
    """Longest consecutive run of `value` anywhere in seq."""
    best = cur = 0
    for v in seq.tolist():
        if v == value:
            cur += 1
            best = max(best, cur)
        else:
            cur = 0
    return best


def _rising_edges(binary_seq):
    """Count 0->1 transitions (distinct visit/event starts), first minute counts if it's 1."""
    seq = binary_seq.tolist()
    count = 1 if seq and seq[0] == 1 else 0
    for prev, cur in zip(seq, seq[1:]):
        if cur == 1 and prev == 0:
            count += 1
    return count
