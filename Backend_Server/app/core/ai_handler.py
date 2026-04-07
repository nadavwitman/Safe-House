import torch
import torch.nn as nn
import os
import copy
import numpy as np
from app.core.data_preprocessing import run_preprocessing_pipeline
import torch.optim as optim


BASE_DIR = os.path.dirname(__file__)
MODEL_PATH = os.path.join(BASE_DIR, "../../../AI_Model/lstm_safe_house_model.pth")
EMERGENCY_THRESHOLD = 0.11
WARNING_THRESHOLD = 0.10
# ================================================================================================================
# LSTM Autoencoder: the Encoder compresses the input sequence into a latent representation,
# the Decoder reconstructs it. High reconstruction error = anomaly.
# ================================================================================================================

class Encoder(nn.Module):
    """Compresses a sequence of sensor readings into a fixed-size latent vector."""
    def __init__(self, seq_len, n_features, embedding_dim=64):
        super(Encoder, self).__init__()
        self.seq_len, self.n_features = seq_len, n_features
        self.embedding_dim, self.hidden_dim = embedding_dim, 2 * embedding_dim
        self.rnn1 = nn.LSTM(input_size=n_features, hidden_size=self.hidden_dim, num_layers=1, batch_first=True)
        self.rnn2 = nn.LSTM(input_size=self.hidden_dim, hidden_size=embedding_dim, num_layers=1, batch_first=True)

    def forward(self, x):
        x, _ = self.rnn1(x)
        x, (hidden_n, _) = self.rnn2(x)
        return hidden_n.reshape((x.shape[0], 1, self.embedding_dim))

class Decoder(nn.Module):
    """Reconstructs the original sequence from the latent vector produced by the Encoder."""
    # 12 default n_features: 7 sensors + hour_sin + hour_cos + day_sin + day_cos + current_location
    def __init__(self, seq_len, embedding_dim=64, n_features=12):
        super(Decoder, self).__init__()
        self.seq_len, self.embedding_dim = seq_len, embedding_dim
        self.hidden_dim, self.n_features = 2 * embedding_dim, n_features
        self.rnn1 = nn.LSTM(input_size=embedding_dim, hidden_size=embedding_dim, num_layers=1, batch_first=True)
        self.rnn2 = nn.LSTM(input_size=embedding_dim, hidden_size=self.hidden_dim, num_layers=1, batch_first=True)
        self.output_layer = nn.Linear(self.hidden_dim, n_features)

    def forward(self, x):
        x = x.repeat(1, self.seq_len, 1)
        x, _ = self.rnn1(x)
        x, _ = self.rnn2(x)
        return self.output_layer(x)

class LSTMAnomalyDetector(nn.Module):
    """Full autoencoder: wraps Encoder + Decoder into a single model."""
    def __init__(self, seq_len, n_features, embedding_dim=64):
        super(LSTMAnomalyDetector, self).__init__()
        self.encoder = Encoder(seq_len, n_features, embedding_dim)
        self.decoder = Decoder(seq_len, embedding_dim, n_features)

    def forward(self, x):
        x = self.encoder(x)
        x = self.decoder(x)
        return x

# ===========================================================================
# Receive the AI decision based on the .pth file from the google collab model
# ===========================================================================
def evaluate_buffer_with_AI(buffer_data_list, latest_sensor_id: str, house_sensor_mask: list) -> tuple[str, str]:
    """
    Runs the LSTM Autoencoder on the current buffer and returns an anomaly decision.

    The model reconstructs the input sequence; a high MSE loss indicates the pattern
    deviates from the learned routine. The house_sensor_mask disables loss contribution
    from sensors that are not installed in this specific house.

    Returns:
        (sensor_id, decision) where decision is "Normal", "Warning", or "Emergency"
    """
    try:
        # 1. Preprocess the raw buffer into a scaled PyTorch tensor
        tensor_input = run_preprocessing_pipeline(buffer_data_list)

        # Ensure Float32 format
        if not isinstance(tensor_input, torch.Tensor):
            tensor_input = torch.FloatTensor(tensor_input)

        # Add batch dimension if missing: [seq_len, features] -> [1, seq_len, features]
        if tensor_input.dim() == 2:
            tensor_input = tensor_input.unsqueeze(0)

        seq_len = tensor_input.shape[1]

    except Exception as e:
        print(f"Preprocessing failed: {e}")
        return (latest_sensor_id, "Normal")

    # 2. Initialize and load the trained model
    # Note: embedding_dim must match the value used during Colab training
    model = LSTMAnomalyDetector(seq_len=seq_len, n_features=12, embedding_dim=64)

    try:
        model.load_state_dict(torch.load(MODEL_PATH, map_location=torch.device('cpu')))
        model.eval()
    except Exception as e:
        print(f"Error loading PyTorch model: {e}")
        return (latest_sensor_id, "Normal")

    # 3. Compute reconstruction loss (anomaly score)
    with torch.no_grad():
        reconstructed = model(tensor_input)

        # Per-element MSE between input and reconstruction
        raw_loss = nn.functional.mse_loss(reconstructed, tensor_input, reduction='none')

        # Apply house sensor mask so disabled sensors don't contribute to the loss.
        # Time features and current_location are always active (trailing 1s).
        full_mask = house_sensor_mask + [1, 1, 1, 1, 1]  # 7 sensors + 4 time + 1 location = 12
        mask_tensor = torch.FloatTensor(full_mask).view(1, 1, -1)

        masked_loss = raw_loss * mask_tensor
        active_elements = mask_tensor.sum() * seq_len
        final_loss = masked_loss.sum() / active_elements
        loss_value = final_loss.item()

    print(f"[AI] Evaluated sequence. Anomaly Loss: {loss_value:.4f}")

    # Thresholds re-calibrated based on server test results (0.089 normal vs 0.117 anomaly)
    if loss_value > EMERGENCY_THRESHOLD:   # Sharp anomaly — immediate danger
        return (latest_sensor_id, "Emergency")
    elif loss_value > WARNING_THRESHOLD: # Mild / borderline anomaly
        return (latest_sensor_id, "Warning")
    else:
        return (latest_sensor_id, "Normal")



def fine_tune_house_model(house_id: str, raw_training_data: list, house_sensor_mask: list, epochs=5, lr=0.001):
    """
    Fine tune the existing data with new data aquired in the last 14 days
    """
    if not raw_training_data or len(raw_training_data) < 720:
        print(f"[AI] Not enough recent data to fine-tune house {house_id}")
        return False

    print(f"[AI] Starting Fine-Tuning for house {house_id} on {len(raw_training_data)} NEW records...")
    try:
        # Normalise and adjust the dimention of the tensor representing the new data
        tensor_data = run_preprocessing_pipeline(raw_training_data)
        if not isinstance(tensor_data, torch.Tensor):
            tensor_data = torch.FloatTensor(tensor_data)
        if tensor_data.dim() == 2:
            tensor_data = tensor_data.unsqueeze(0)
        seq_len = tensor_data.shape[1]
    except Exception as e:
        print(f"Error preprocessing fine-tuning data: {e}")
        return False
    # The mask for the 7 bit sensor vector, 7 bit last location vector, hour and day sin and cos and which should always be included
    full_mask = house_sensor_mask + house_sensor_mask + [1, 1, 1, 1]
    mask_tensor = torch.FloatTensor(full_mask).view(1, 1, -1)

    house_model_path = os.path.join(BASE_DIR, f"../../../AI_Model/lstm_safe_house_{house_id}.pth")
    load_path = house_model_path if os.path.exists(house_model_path) else MODEL_PATH

    model = LSTMAnomalyDetector(seq_len=seq_len, n_features=13, embedding_dim=64)
    model.load_state_dict(torch.load(load_path, map_location=torch.device('cpu')))

    # A snapshot of the current pre-fine-tuning data based on the current .pth file
    old_state_dict = copy.deepcopy(model.state_dict())

    # Training the data based only of the last 14 days, for future merge
    model.train()
    optimizer = optim.Adam(model.parameters(), lr=lr)

    for epoch in range(epochs):
        optimizer.zero_grad()
        reconstructed = model(tensor_data)

        raw_loss = nn.functional.mse_loss(reconstructed, tensor_data, reduction='none')
        masked_loss = raw_loss * mask_tensor
        active_elements = mask_tensor.sum() * seq_len
        loss = masked_loss.sum() / active_elements

        loss.backward()
        optimizer.step()

    # Interpolate the old data based on 30 percent weight for the new data
    new_trained_state_dict = model.state_dict()
    blended_state_dict = {}

    for key in old_state_dict:
        blended_state_dict[key] = (0.7 * old_state_dict[key]) + (0.3 * new_trained_state_dict[key])

    # Load the new weights from the interpolation back to the AI model
    model.load_state_dict(blended_state_dict)

    # Saving the new .pth file instead of the existing .pth file
    torch.save(model.state_dict(), house_model_path)
    print(f"[AI] Weight Interpolation completed! Model saved to {house_model_path}")
    return True
