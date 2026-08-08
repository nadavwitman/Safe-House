import copy
import torch
import torch.optim as optim

from app.ai.data_preprocessing import run_preprocessing_pipeline
from app.ai.model_paths import LSTMAnomalyDetector, WINDOW_SIZE, N_FEATURES, MODEL_PATH


def fine_tune_house_model(house_id: str, raw_training_data: list, house_sensor_mask: list,
                          current_model=None, epochs=5, lr=0.001, batch_size=64):
    """
    Continual-learning fine-tune on the resident's recent (last-14-day) routine.

    The data is sliced into overlapping 6-hour windows — the exact regime the base model was
    trained on — and the freshly trained weights are blended 70/30 with the previous weights
    to avoid catastrophic forgetting. Works with in-memory models for cloud storage integration.

    No equivalent exists in model_handler (inference-only) -- this stays a from-scratch
    training loop, just built on model_handler's architecture/weights.
    """
    if not raw_training_data or len(raw_training_data) < 2 * WINDOW_SIZE:
        have = len(raw_training_data) if raw_training_data else 0
        print(f"[AI] Not enough recent data to fine-tune house {house_id} "
              f"({have} rows, need >= {2 * WINDOW_SIZE}).")
        return None

    print(f"[AI] Starting Fine-Tuning for house {house_id} on {len(raw_training_data)} NEW records...")
    try:
        tensor_data = run_preprocessing_pipeline(raw_training_data)  # [1, N, 18], scaled
        scaled = tensor_data.squeeze(0)
        windows = _build_training_windows(scaled)                    # [W, 360, 18]
        if windows is None:
            print(f"[AI] Could not build any {WINDOW_SIZE}-min window for {house_id}. Aborting.")
            return None
    except Exception as e:
        print(f"Error preprocessing fine-tuning data: {e}")
        return None

    full_mask = house_sensor_mask + house_sensor_mask + [1, 1, 1, 1]
    mask_tensor = torch.FloatTensor(full_mask).view(1, 1, -1)
    active_per_window = mask_tensor.sum() * WINDOW_SIZE  # active elements per window

    # Use the RAM model if provided by the manager, otherwise load the generic baseline
    if current_model is not None:
        print(f"[AI] Using existing personalized model for {house_id} as base.")
        model = current_model
    else:
        print(f"[AI] No custom model provided. Loading default generic weights for {house_id}.")
        model = LSTMAnomalyDetector(seq_len=WINDOW_SIZE, n_features=N_FEATURES, embedding_dim=64)
        try:
            model.load_state_dict(torch.load(MODEL_PATH, map_location=torch.device('cpu')))
        except Exception as e:
            print(f"Error loading base model weights: {e}")
            return None

    # Align the decoder's reconstruction length with our training window, so a legacy
    # personalized model built with a different seq_len still trains correctly.
    model.encoder.seq_len = WINDOW_SIZE
    model.decoder.seq_len = WINDOW_SIZE

    # Snapshot the pre-fine-tuning weights for the 70/30 blend below
    old_state_dict = copy.deepcopy(model.state_dict())

    model.train()
    optimizer = optim.Adam(model.parameters(), lr=lr, weight_decay=1e-5)
    num_windows = windows.shape[0]

    for epoch in range(epochs):
        perm = torch.randperm(num_windows)
        epoch_loss = 0.0
        num_batches = 0
        for i in range(0, num_windows, batch_size):
            batch = windows[perm[i:i + batch_size]]
            optimizer.zero_grad()
            reconstructed = model(batch)

            raw_loss = torch.nn.functional.mse_loss(reconstructed, batch, reduction='none')
            masked_loss = raw_loss * mask_tensor
            loss = masked_loss.sum() / (active_per_window * batch.shape[0] + 1e-8)

            loss.backward()
            # Gradient clipping keeps LSTM training stable (prevents exploding gradients)
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()
            epoch_loss += loss.item()
            num_batches += 1
        print(f"[AI] {house_id} epoch {epoch + 1}/{epochs} — "
              f"loss {epoch_loss / max(num_batches, 1):.6f} over {num_windows} windows")

    # Blend 70% previous / 30% newly trained to avoid catastrophic forgetting
    new_trained_state_dict = model.state_dict()
    blended_state_dict = {
        key: (0.7 * old_state_dict[key]) + (0.3 * new_trained_state_dict[key])
        for key in old_state_dict
    }
    model.load_state_dict(blended_state_dict)

    print(f"[AI] Weight Interpolation completed for {house_id} in RAM!")
    return model


def _build_training_windows(scaled, window_size=WINDOW_SIZE, stride=30, max_windows=1000):
    """Slices a scaled [N, 18] sequence into overlapping [W, window_size, 18] windows.

    Replicates the sliding-window regime the base model was trained on. Feeding the whole
    14-day period as one sequence instead would collapse it into a single latent vector and
    train the autoencoder to output the mean — degrading the model. The window count is capped
    to bound memory/compute on small instances (t3.micro).
    """
    n = scaled.shape[0]
    starts = list(range(0, n - window_size + 1, stride))
    if not starts:
        return None
    if len(starts) > max_windows:
        step = len(starts) / max_windows
        starts = [starts[int(i * step)] for i in range(max_windows)]
    return torch.stack([scaled[s:s + window_size] for s in starts])
