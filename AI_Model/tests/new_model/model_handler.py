"""
Test-only counterpart to Backend_Server/app/core/ai_handler.py — new-model variant.

Same LSTM Autoencoder architecture, same 6-hour (360-minute) input window, same
preprocessing/feature order as AI_Model/tests/model_handler.py. What's different is the
checkpoint: best_safe_house_model_weighted.pth (this folder) was trained with an
asymmetric weighted MSE on the sensor_* columns (see
Safe_House_LSTM_Training_weighted_colab.ipynb / _post.ipynb in this folder) instead of
plain nn.MSELoss() over all 18 columns.

Why that matters here: on the old MSE-trained checkpoint, reconstructed sensor_* values
never exceeded ~0.14 across a full window, so any 0.5 threshold on them was useless (always
all-zero) and missing_usage/high_frequency had to fall back to summing raw floats as an
"expected count" proxy. On this checkpoint, sensor_* reconstruction genuinely crosses 0.5
around real events (median well under 0.5 at quiet minutes, p90/p99 well above it at likely
event windows) and is now safe to binarize -- so this module thresholds the sensor block of
the reconstruction at SENSOR_THRESHOLD and works with actual 0/1 counts instead of float
sums. This also fixes a latent unit mismatch in the old scoring: actual_count was always a
rising-edge count (integer) while expected_count was a sum of small floats; both are now
edge/1-counts in the same units.

Location and time columns are untouched: the architecture still applies one shared
Sigmoid over all 18 outputs (no separate softmax head), so location scoring still resolves
the "current location" via argmax over the raw (non-binarized) location floats, exactly as
before.

Input:  a [360, 18] window (actual) and its model reconstruction [360, 18].
Output: evaluate_window(...) returns a dict with overall severity/anomaly
        type/responsible sensor plus every component score for debugging.

Column layout (must match data_gen.py / data_preprocessing.py):
  0-6   sensor_*    : sparse per-zone event pulses
  7-13  location_*  : sticky one-hot current-location state
  14-17 hour_sin, hour_cos, day_sin, day_cos

Zone index -> name (Backend_Server/app/weekly_summary/constants.py:ZONE_NAMES):
  0 Door, 1 Kitchen, 2 Bathroom, 3 Toilet, 4 Medications, 5 Bedroom, 6 Living Room

NOTE: DEFAULT_SENSOR_CONFIG below carries over the tolerances calibrated against the OLD
checkpoint's float-sum units unchanged. They are the right order of magnitude (both old and
new "expected_count" are still small integers/near-integers per band), but they have not
been re-validated against this checkpoint's binary counts by running tests_static/
tests_missing/tests_frequency equivalents against it. Retune from that output before relying
on absolute severity numbers from this model.
"""
import torch
import torch.nn as nn
import numpy as np

WINDOW_SIZE = 360
N_FEATURES = 18
N_ZONES = 7

SENSOR_SLICE = slice(0, 7)
LOCATION_SLICE = slice(7, 14)

# Reconstructed sensor probability above this counts as "the model predicts an event here".
# Only meaningful on the weighted-loss checkpoint -- see module docstring.
SENSOR_THRESHOLD = 0.5

DOOR, KITCHEN, BATHROOM, TOILET, MEDS, BEDROOM, LIVING_ROOM = range(7)
ZONE_NAMES = ["Door", "Kitchen", "Bathroom", "Toilet", "Medications", "Bedroom", "Living Room"]

SEVERITY_NORMAL, SEVERITY_WARNING, SEVERITY_EMERGENCY = "Normal", "Warning", "Emergency"

# Universal severity thresholds — one scale for every score type/zone. Missing-usage and
# high-frequency are still hard-capped at Warning (per spec, see _severity_for); only
# Static Location can cross into Emergency.
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

# ===========================================================================
# LSTM Autoencoder (identical architecture to ai_handler.py — do not change).
# Loss function differs at training time only; the forward pass is unchanged.
# ===========================================================================

class Encoder(nn.Module):
    def __init__(self, seq_len, n_features, embedding_dim=64):
        super(Encoder, self).__init__()
        self.seq_len, self.n_features = seq_len, n_features
        self.embedding_dim, self.hidden_dim = embedding_dim, 2 * embedding_dim
        self.rnn1 = nn.LSTM(input_size=n_features, hidden_size=self.hidden_dim, num_layers=1, batch_first=True)
        self.dropout = nn.Dropout(0.2)
        self.rnn2 = nn.LSTM(input_size=self.hidden_dim, hidden_size=embedding_dim, num_layers=1, batch_first=True)

    def forward(self, x):
        x, _ = self.rnn1(x)
        x = self.dropout(x)
        x, (hidden_n, _) = self.rnn2(x)
        return hidden_n.reshape((x.shape[0], 1, self.embedding_dim))


class Decoder(nn.Module):
    def __init__(self, seq_len, embedding_dim=64, n_features=18):
        super(Decoder, self).__init__()
        self.seq_len, self.embedding_dim = seq_len, embedding_dim
        self.hidden_dim, self.n_features = 2 * embedding_dim, n_features
        self.rnn1 = nn.LSTM(input_size=embedding_dim, hidden_size=embedding_dim, num_layers=1, batch_first=True)
        self.dropout = nn.Dropout(0.2)
        self.rnn2 = nn.LSTM(input_size=embedding_dim, hidden_size=self.hidden_dim, num_layers=1, batch_first=True)
        self.output_layer = nn.Linear(self.hidden_dim, n_features)
        self.sigmoid = nn.Sigmoid()

    def forward(self, x):
        x = x.repeat(1, self.seq_len, 1)
        x, _ = self.rnn1(x)
        x = self.dropout(x)
        x, _ = self.rnn2(x)
        x = self.output_layer(x)
        return self.sigmoid(x)


class LSTMAnomalyDetector(nn.Module):
    def __init__(self, seq_len, n_features, embedding_dim=64):
        super(LSTMAnomalyDetector, self).__init__()
        self.encoder = Encoder(seq_len, n_features, embedding_dim)
        self.decoder = Decoder(seq_len, embedding_dim, n_features)

    def forward(self, x):
        return self.decoder(self.encoder(x))


def load_model(model_path, seq_len=WINDOW_SIZE, n_features=N_FEATURES, embedding_dim=64):
    model = LSTMAnomalyDetector(seq_len, n_features, embedding_dim)
    model.load_state_dict(torch.load(model_path, map_location=torch.device('cpu')))
    model.eval()
    return model


# ===========================================================================
# Per-sensor/zone configuration
#
# Every zone gets one config entry (indices match sensor_* / location_* column
# order, i.e. the ZONE_NAMES order above). All numbers here are calibration
# knobs, not physiological facts — carried over from the old MSE-checkpoint's
# calibration; see the module docstring note on re-validating against this
# checkpoint's binary counts.
# ===========================================================================

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
        missing_grace=120, missing_tolerance=2.0,
        frequency_lookback=180, frequency_tolerance=5,
        hosting_suppression=True,
    ),
    BATHROOM: _cfg(
        enabled={'static', 'missing', 'frequency'},
        # Real visits run up to ~22min (p99) -- shower included.
        minimum_expected_run=30,
        missing_grace=180, missing_tolerance=2.0,
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


def _minutes_since_last_event(binary_seq):
    """How many minutes since the last 1 in the trailing lookback (len(seq) if none)."""
    seq = binary_seq.tolist()
    for i, v in enumerate(reversed(seq)):
        if v == 1:
            return i
    return len(seq)


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
    floats as in the old MSE-checkpoint version -- see module docstring.
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


# ===========================================================================
# Final decision
# ===========================================================================

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
