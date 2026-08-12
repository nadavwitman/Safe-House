"""
Test-only counterpart to Backend_Server/app/core/ai_handler.py — new-model variant.

Same LSTM Autoencoder architecture, same 6-hour (360-minute) input window, same
preprocessing/feature order as the original AI_Model/tests/model_handler.py. What's
different is the checkpoint: best_safe_house_model.pth (AI_Model/model/) was trained
with an asymmetric weighted MSE on the sensor_* columns (see the notebooks in
AI_Model/training/) instead of plain nn.MSELoss() over all 18 columns.

Why that matters here: on the old MSE-trained checkpoint, reconstructed sensor_*
values never exceeded ~0.14 across a full window, so any 0.5 threshold on them was
useless (always all-zero) and missing_usage/high_frequency had to fall back to
summing raw floats as an "expected count" proxy. On this checkpoint, sensor_*
reconstruction genuinely crosses 0.5 around real events (median well under 0.5 at
quiet minutes, p90/p99 well above it at likely event windows) and is now safe to
binarize -- so scoring.py thresholds the sensor block of the reconstruction at
SENSOR_THRESHOLD and works with actual 0/1 counts instead of float sums. This also
fixes a latent unit mismatch in the old scoring: actual_count was always a
rising-edge count (integer) while expected_count was a sum of small floats; both are
now edge/1-counts in the same units.

Location and time columns are untouched: the architecture still applies one shared
Sigmoid over all 18 outputs (no separate softmax head), so location scoring still
resolves the "current location" via argmax over the raw (non-binarized) location
floats, exactly as before.

NOTE: sensor_config.DEFAULT_SENSOR_CONFIG carries over the tolerances calibrated
against the OLD checkpoint's float-sum units unchanged. They are the right order of
magnitude (both old and new "expected_count" are still small integers/near-integers
per band), but they have not been re-validated against this checkpoint's binary
counts by running tests_static/tests_missing/tests_frequency equivalents against it.
Retune from that output before relying on absolute severity numbers from this model.

Module layout:
  architecture.py    Encoder/Decoder/LSTMAnomalyDetector, load_model
  constants.py       window/feature dims, column layout, zone identity, severity levels
  sensor_config.py   per-zone calibration knobs (DEFAULT_SENSOR_CONFIG) + hosting knobs
  signal_utils.py    stateless array/sequence helpers
  scoring.py         the three anomaly-type scorers + hosting-suppression
  evaluator.py        severity/decision logic + evaluate_window entrypoint
"""

from .architecture import Encoder, Decoder, LSTMAnomalyDetector, load_model

from .constants import (
    WINDOW_SIZE, N_FEATURES,
    SENSOR_SLICE, LOCATION_SLICE, SENSOR_THRESHOLD,
    DOOR, KITCHEN, BATHROOM, TOILET, MEDS, BEDROOM, LIVING_ROOM, ZONE_NAMES,
    SEVERITY_NORMAL, SEVERITY_WARNING, SEVERITY_EMERGENCY,
    WARNING_THRESHOLD, EMERGENCY_THRESHOLD, WARNING_WINDOW,
)

from .sensor_config import (
    DEFAULT_SENSOR_CONFIG,
    HOSTING_LOOKBACK, HOSTING_MULTI_SENSOR_TOLERANCE, HOSTING_TRANSITION_TOLERANCE,
    HOSTING_ROOM_SPREAD_TOLERANCE, HOSTING_SUPPRESSION_THRESHOLD,
)

from .scoring import (
    compute_static_location_scores, compute_missing_usage_scores, compute_frequency_scores,
    compute_hosting_score,
)

from .evaluator import decide, evaluate_window

__all__ = [
    "Encoder", "Decoder", "LSTMAnomalyDetector", "load_model",
    "WINDOW_SIZE", "N_FEATURES",
    "SENSOR_SLICE", "LOCATION_SLICE", "SENSOR_THRESHOLD",
    "DOOR", "KITCHEN", "BATHROOM", "TOILET", "MEDS", "BEDROOM", "LIVING_ROOM", "ZONE_NAMES",
    "SEVERITY_NORMAL", "SEVERITY_WARNING", "SEVERITY_EMERGENCY",
    "WARNING_THRESHOLD", "EMERGENCY_THRESHOLD", "WARNING_WINDOW",
    "DEFAULT_SENSOR_CONFIG",
    "HOSTING_LOOKBACK", "HOSTING_MULTI_SENSOR_TOLERANCE", "HOSTING_TRANSITION_TOLERANCE",
    "HOSTING_ROOM_SPREAD_TOLERANCE", "HOSTING_SUPPRESSION_THRESHOLD",
    "compute_static_location_scores", "compute_missing_usage_scores", "compute_frequency_scores",
    "compute_hosting_score",
    "decide", "evaluate_window",
]
