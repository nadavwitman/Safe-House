# AI_Model

Everything related to the LSTM Autoencoder anomaly-detection model: the scoring package the backend imports at runtime, the trained checkpoint/scaler, the notebooks that produced it, and the test suite that validates its scoring logic against synthetic scenarios. Consumed by [Backend_Server/app/ai](../Backend_Server/app/ai/README.md), which adds `AI_MODEL_DIR` (this folder) to `sys.path` to import from `model_handler` directly.

## Layout

- **[model_handler/](model_handler/README.md)** — the scoring package itself: model architecture, constants, per-zone calibration, and the three anomaly-type scorers (static-location, missing-usage, high-frequency). This is what the backend imports.
- **[training/](training/README.md)** — the Colab notebooks that trained `model/best_safe_house_model.pth`, and why they use an asymmetric weighted loss instead of plain MSE.
- **[model/](model/)** — the trained artifacts consumed by both `model_handler` and the backend:
  - `best_safe_house_model.pth` — the weighted-loss LSTM Autoencoder checkpoint (state dict).
  - `scaler.pkl` — the `MinMaxScaler` fit during training, used to normalize incoming sensor data the same way at inference time.
- **[trained_models/](trained_models/)** — empty at rest (just a `.gitkeep`); this is where per-house fine-tuned models get persisted at runtime by [Backend_Server/app/ai/model_manager.py](../Backend_Server/app/ai/model_manager.py) (`trained_models/<house_id>/anomaly_detector.pkl`), not something populated in the repo itself.
- **[tests/](tests/)** — validates `model_handler`'s scoring against synthetic scenarios, independent of the backend:
  - `data/data_gen.py` — generates synthetic 30-day sensor logs for a generic resident routine (`mock_data_month.csv`, also used by the training notebooks); `data_summary.txt` documents the generated routine's statistical shape (sleep, meals, toilet visits, showers, medication timing, outings).
  - `test_common.py` — shared fixtures for the scenario tests: loads the trained model/scaler from `model/`, and imports `data_gen` for scenario generation so there's one source of truth for synthetic data across training and testing.
  - `tests_static/`, `tests_missing/`, `tests_frequency/` — one pytest file each (`test_static_location.py`, `test_missing_usage.py`, `test_high_frequency.py`) exercising the three anomaly types per zone, with `results_*.txt` files recording per-zone measured scores/thresholds from the last run.
