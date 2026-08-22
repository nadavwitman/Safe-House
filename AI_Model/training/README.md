# training

Colab notebooks that train the weighted-loss LSTM Autoencoder checkpoint consumed by [AI_Model/model_handler/](../model_handler/) (`best_safe_house_model.pth` in [AI_Model/model/](../model/)). Trains on [AI_Model/tests/mock_data_month.csv](../tests/data/) (produced by `AI_Model/tests/data_gen.py`) — 30 days × 1440 minutes of a single generic 70+ resident profile, normal routine only, no anomalies baked in.

## Why this exists

Plain `nn.MSELoss()` over all 18 columns (the original training approach, still used by the production checkpoint behind [Backend_Server/app/ai/model_manager.py](../../Backend_Server/app/ai/model_manager.py)) collapses the sparse `sensor_*` columns (0.14%–1.06% positive per channel) to near-zero reconstruction — the model just learns "always predict near-0" since that minimizes loss on such an imbalanced signal. That makes it useless to threshold sensor reconstructions into event predictions. These notebooks fix that by scaling the squared error on positive sensor targets by `POSITIVE_WEIGHT` (asymmetric weighted MSE), so the model is forced to actually learn per-channel event timing instead of a constant.

## Files

- **[Safe_House_LSTM_Training_weighted_colab.ipynb](Safe_House_LSTM_Training_weighted_colab.ipynb)** — the notebook with cells cleared (no run outputs), meant to be re-run from scratch (e.g. in Colab).
- **[Safe_House_LSTM_Training_weighted_colab_post.ipynb](Safe_House_LSTM_Training_weighted_colab_post.ipynb)** — the same notebook *after* a completed run, outputs retained (loss curves, per-channel verification table). Kept as a record of what a successful training run looks like — compare against this if a re-run's numbers look off.

Both notebooks have the identical 7-cell structure:

1. **Setup** — imports, device selection, seeds (`SEED = 42`) for reproducibility.
2. **Load + scale data** — loads `mock_data_month.csv`, sanity-checks meds/door occupancy aren't degenerate, fits a `MinMaxScaler` and saves it to `scaler.pkl`.
3. **Sequence windows** — `create_sequences()` turns the scaled dataframe into rolling `[360, 18]` windows (6-hour window, stride 1) for the autoencoder.
4. **Model definition** — `Encoder`/`Decoder`/`LSTMAnomalyDetector`, kept byte-for-byte identical in signature/forward-pass to [AI_Model/model_handler/architecture.py](../model_handler/architecture.py) and the production `ai_handler.py` (a comment flags this constraint explicitly — don't let this drift from those).
5. **Weighted loss + training loop** — `weighted_reconstruction_loss()` (one MSE mean over all 18 columns, with positive `sensor_*` targets scaled by `positive_weight`; `positive_weight=1.0` reproduces plain MSE exactly) and `train_model()` (Adam, gradient clipping, early stopping on validation loss, saves `best_safe_house_model_weighted.pth`).
6. **Run training** — chronological (not random) 80/20 train/val split with a `SEQ_LEN` gap between them to prevent window-overlap leakage; sets `POSITIVE_WEIGHT = 100.0` (scalar; a commented-out per-channel tensor is available if some channels stay collapsed under the scalar) and runs `train_model` for up to 50 epochs; plots loss curves.
7. **Verification** — `check_sensor_reconstruction()` measures each sensor channel's reconstruction value at real-event minutes vs. quiet minutes, and prints a table compared inline against the old unweighted-MSE checkpoint's baseline (ratios ~1.0–1.75x). A pass requires both a clearly higher max *and* a clearly higher event/quiet ratio than that baseline — a low max with a near-1.0 ratio means the channel still learned no event timing at all.

The `_post` notebook's cell 6 output is the actual measured result of the current `best_safe_house_model.pth`: every channel reaches ratios of 1.9x–8.7x (vs. the ~1.06x–1.75x baseline), which is why [AI_Model/model_handler/](../model_handler/) can safely threshold reconstructed sensor values at 0.5 instead of falling back to summing raw floats.
