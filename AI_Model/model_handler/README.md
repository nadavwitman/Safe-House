# model_handler

Test-only counterpart to [Backend_Server/app/ai/model_manager.py](../../Backend_Server/app/ai/model_manager.py) (formerly `ai_handler.py`) for evaluating the **new** LSTM Autoencoder checkpoint — `best_safe_house_model.pth` (in [AI_Model/model/](../model/)).

Same architecture, same 6-hour (360-minute) input window, same feature layout as the original `AI_Model/tests/model_handler.py`. The difference is the checkpoint's training loss: an asymmetric weighted MSE on the `sensor_*` columns instead of plain `nn.MSELoss()` over all 18 columns (see notebooks in [AI_Model/training/](../training/)). That changes what the reconstructed `sensor_*` values mean — they now cross 0.5 around real events and can safely be thresholded into 0/1 counts, whereas on the old checkpoint they never exceeded ~0.14 and had to be summed as raw floats instead. `scoring.py` and `signal_utils.py` binarize accordingly; `sensor_config.py`'s tolerances are carried over from the old checkpoint's calibration and have not yet been re-validated against this one (see [__init__.py](__init__.py) docstring).

## Pipeline

`evaluate_window()` in [evaluator.py](evaluator.py) is the entrypoint, run in this order:

1. **[architecture.py](architecture.py)** — `load_model()` loads the checkpoint; `LSTMAnomalyDetector.forward()` reconstructs the input window.
2. **[signal_utils.py](signal_utils.py)** — turns the actual/reconstructed `[360, 18]` arrays into countable signals (location sequence, binarized sensors, run/edge counts).
3. **[scoring.py](scoring.py)** — scores three independent anomaly types per zone from those signals, plus a hosting/guest suppression heuristic.
4. **[evaluator.py](evaluator.py)** — converts scores to severities, picks the single strongest anomaly (`decide()`), and assembles the result dict.

Zone/threshold/column-layout constants used throughout live in **[constants.py](constants.py)**; per-zone calibration knobs live in **[sensor_config.py](sensor_config.py)**.

## Files

- **[__init__.py](__init__.py)** — package docstring explaining the old-vs-new checkpoint distinction in detail, and re-exports the public API (`load_model`, `evaluate_window`, `decide`, the scorers, constants, `DEFAULT_SENSOR_CONFIG`).
- **[architecture.py](architecture.py)** — `Encoder`/`Decoder`/`LSTMAnomalyDetector` (LSTM autoencoder, identical to the production model — do not change) and `load_model(model_path)`.
- **[constants.py](constants.py)** — `WINDOW_SIZE`/`N_FEATURES`, the 18-column layout (`SENSOR_SLICE`, `LOCATION_SLICE`, time-of-day columns), zone indices/names (`DOOR`...`LIVING_ROOM`, `ZONE_NAMES`), severity levels, and the universal `WARNING_THRESHOLD`/`EMERGENCY_THRESHOLD`/`WARNING_WINDOW`.
- **[sensor_config.py](sensor_config.py)** — `DEFAULT_SENSOR_CONFIG`: per-zone dict of which anomaly types are enabled and their tolerance knobs (e.g. bathroom missing-usage grace period, kitchen frequency lookback). Also the hosting/guest heuristic knobs (`HOSTING_*`).
- **[signal_utils.py](signal_utils.py)** — stateless helpers: `_ratio_score`, `_location_sequence` (argmax over location one-hot), `_binarize_sensors` (threshold reconstruction at `SENSOR_THRESHOLD`), `_trailing_run`/`_longest_run`, `_rising_edges` (distinct visit/event counting).
- **[scoring.py](scoring.py)** — the three scorers plus hosting suppression:
  - `compute_static_location_scores` — is the person stuck in one zone longer than the model expects?
  - `compute_missing_usage_scores` — did an expected zone visit (e.g. kitchen, meds) not happen?
  - `compute_frequency_scores` — is a zone being visited more often than expected (e.g. repeated night bathroom trips)?
  - `compute_hosting_score` / `_apply_hosting_suppression` — detects guest/hosting activity (multiple sensors active, frequent room transitions) and softens frequency scores accordingly, since visitors otherwise look like anomalous activity.
- **[evaluator.py](evaluator.py)** — `_severity_for` (universal Normal/Warning/Emergency scale; only Static Location can reach Emergency), `decide` (Static Location wins outright if active, otherwise the higher-scoring of Missing Usage/High Frequency), and `evaluate_window` (runs the model, calls scorers in order, returns `{overall_severity, anomaly_type, zone, zone_name, score, debug: {...}}`).
