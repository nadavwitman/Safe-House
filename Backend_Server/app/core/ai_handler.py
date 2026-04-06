import torch
import torch.nn as nn
import os
import numpy as np
from app.core.data_preprocessing import run_preprocessing_pipeline

BASE_DIR = os.path.dirname(__file__)
MODEL_PATH = os.path.join(BASE_DIR, "../../../AI_Model/lstm_safe_house_model.pth")

# Updated thresholds based on Colab test results (0.00004 normal vs 0.28 anomaly)
EMERGENCY_THRESHOLD = 0.15
WARNING_THRESHOLD = 0.05    

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
        self.dropout = nn.Dropout(0.2) # Added Dropout to match Colab training
        self.rnn2 = nn.LSTM(input_size=self.hidden_dim, hidden_size=embedding_dim, num_layers=1, batch_first=True)

    def forward(self, x):
        x, _ = self.rnn1(x)
        x = self.dropout(x)
        x, (hidden_n, _) = self.rnn2(x)
        return hidden_n.reshape((x.shape[0], 1, self.embedding_dim))

class Decoder(nn.Module):
    """Reconstructs the original sequence from the latent vector produced by the Encoder."""
    # Updated n_features to 18: 7 sensors + 7 locations + 4 cyclical time features
    def __init__(self, seq_len, embedding_dim=64, n_features=18):
        super(Decoder, self).__init__()
        self.seq_len, self.embedding_dim = seq_len, embedding_dim
        self.hidden_dim, self.n_features = 2 * embedding_dim, n_features
        self.rnn1 = nn.LSTM(input_size=embedding_dim, hidden_size=embedding_dim, num_layers=1, batch_first=True)
        self.dropout = nn.Dropout(0.2) # Added Dropout to match Colab training
        self.rnn2 = nn.LSTM(input_size=embedding_dim, hidden_size=self.hidden_dim, num_layers=1, batch_first=True)
        self.output_layer = nn.Linear(self.hidden_dim, n_features)
        self.sigmoid = nn.Sigmoid() # Added Sigmoid to keep outputs in [0, 1] range

    def forward(self, x):
        x = x.repeat(1, self.seq_len, 1)
        x, _ = self.rnn1(x)
        x = self.dropout(x)
        x, _ = self.rnn2(x)
        x = self.output_layer(x)
        return self.sigmoid(x) # Return through sigmoid to match scaled input

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

    The model reconstructs the input sequence. We focus on the "Smart Anomaly Score":
    calculating MSE for the last 30 minutes of location features (indices 7-13).
    """
    try:
        # 1. Preprocess the raw buffer into a scaled PyTorch tensor (18 features)
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

    # 2. Initialize and load the trained model (Using 18 features)
    model = LSTMAnomalyDetector(seq_len=seq_len, n_features=18, embedding_dim=64)

    try:
        model.load_state_dict(torch.load(MODEL_PATH, map_location=torch.device('cpu')))
        model.eval()
    except Exception as e:
        print(f"Error loading PyTorch model: {e}")
        return (latest_sensor_id, "Normal")

    # 3. Compute reconstruction loss (Smart Anomaly Score)
    with torch.no_grad():
        reconstructed = model(tensor_input)

        # Per-element MSE between input and reconstruction
        raw_loss = (reconstructed - tensor_input) ** 2

        # Apply house sensor mask for both sensor events (0-6) and location states (7-13)
        # If a sensor isn't installed, we mask its event and its corresponding location state.
        # Time features (14-17) are always active.
        full_mask = house_sensor_mask + house_sensor_mask + [1, 1, 1, 1] # 18 features total
        mask_tensor = torch.FloatTensor(full_mask).view(1, 1, -1)
        
        # Apply mask to the raw loss
        masked_loss = raw_loss * mask_tensor

        # --- SMART ANOMALY SCORE LOGIC ---
        # Instead of a global average, focus on the last 30 minutes (most recent state)
        # and only look at location features (indices 7-13) to avoid event noise.
        last_30_mins_loc_loss = masked_loss[0, -30:, 7:14]
        
        # Calculate mean loss only for active sensors in the last 30 minutes
        active_loc_elements = torch.FloatTensor(house_sensor_mask).sum() * 30
        loss_value = last_30_mins_loc_loss.sum().item() / (active_loc_elements + 1e-8)

    print(f"[AI] Evaluated sequence. Smart Anomaly Score: {loss_value:.4f}")

    # Decision logic based on the Smart Anomaly Score
    if loss_value > EMERGENCY_THRESHOLD:   # Sharp deviation in current state
        return (latest_sensor_id, "Emergency")
    elif loss_value > WARNING_THRESHOLD:   # Mild deviation from routine
        return (latest_sensor_id, "Warning")
    else:
        return (latest_sensor_id, "Normal")