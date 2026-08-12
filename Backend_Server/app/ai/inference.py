import torch

from app.ai.data_preprocessing import run_preprocessing_pipeline
from app.ai.model_paths import (
    LSTMAnomalyDetector, evaluate_window, N_FEATURES, MODEL_PATH, masked_sensor_config,
)

# Returned alongside a "Normal" verdict (or when inference can't run) so every caller
# gets the same (sensor_id, decision, meta) shape. meta carries the structured context
# the message composer needs: severity, anomaly type, and the most-anomalous room.
_NORMAL_META = {'severity': 'Normal', 'activity_type': None, 'room_index': None}


# ===========================================================================
# Receive the AI decision based on the .pth file from the google colab model
# ===========================================================================

def evaluate_buffer_with_AI(
    buffer_data_list,
    latest_sensor_id: str,
    house_sensor_mask: list,
    model_instance=None,
    fine_tune_count: int = 0
) -> tuple[str, str, dict]:
    """
    Runs the LSTM Autoencoder on the current buffer and returns an anomaly decision.
    Utilizes the cached personalized house model if available, otherwise falls back to
    the global baseline. Scoring itself (static-location / missing-usage / high-frequency,
    severity thresholds, hosting suppression) lives in model_handler.evaluate_window.
    """
    try:
        tensor_input = run_preprocessing_pipeline(buffer_data_list)

        if not isinstance(tensor_input, torch.Tensor):
            tensor_input = torch.FloatTensor(tensor_input)

        if tensor_input.dim() == 2:
            tensor_input = tensor_input.unsqueeze(0)

        seq_len = tensor_input.shape[1]

    except Exception as e:
        print(f"Preprocessing failed: {e}")
        return (latest_sensor_id, "Normal", _NORMAL_META)

    # Check if a custom-trained baseline model object was passed from the RAM cache
    if model_instance is not None and isinstance(model_instance, LSTMAnomalyDetector):
        print(f"[AI] Executing inference using custom model. Fine-tune generations: {fine_tune_count}")
        model = model_instance
        model.eval()
    else:
        # Fallback logic: Load default global weights
        print("[AI] No custom house model provided. Falling back to global baseline.")
        model = LSTMAnomalyDetector(seq_len=seq_len, n_features=N_FEATURES, embedding_dim=64)
        try:
            model.load_state_dict(torch.load(MODEL_PATH, map_location=torch.device('cpu')))
            model.eval()
        except Exception as e:
            print(f"Error loading fallback PyTorch model from disk: {e}")
            return (latest_sensor_id, "Normal", _NORMAL_META)

    # Force the decoder to reconstruct a sequence matching the current input length,
    # regardless of the seq_len the model was originally built with. Defends against
    # legacy personalized models that were saved with a different window length.
    model.decoder.seq_len = seq_len

    sensor_config = masked_sensor_config(house_sensor_mask)
    result = evaluate_window(model, tensor_input, sensor_config=sensor_config)

    severity = result['overall_severity']
    anomaly_type = result['anomaly_type']
    zone = result['zone']

    print(f"[AI] Evaluated sequence. severity={severity} type={anomaly_type} "
          f"zone={result['zone_name']} score={result['score']:.4f}")

    meta = {'severity': severity, 'activity_type': anomaly_type, 'room_index': zone}

    if severity == 'Emergency':
        return (latest_sensor_id, f"Emergency: {anomaly_type}", meta)
    elif severity == 'Warning':
        return (latest_sensor_id, f"Warning: {anomaly_type}", meta)
    else:
        return (latest_sensor_id, "Normal", meta)
