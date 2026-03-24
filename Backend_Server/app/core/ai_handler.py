import torch
import torch.nn as nn
import os
import numpy as np
from app.core.data_preprocessing import run_preprocessing_pipeline

BASE_DIR = os.path.dirname(__file__)
MODEL_PATH = os.path.join(BASE_DIR, "../../../AI_Model/lstm_safe_house_model.pth")

# ================================================================================================================
# Create the classes that will generate the weights by running the data in the encoder and out through the decoder
# ================================================================================================================

class Encoder(nn.Module):
    def __init__(self, seq_len, n_features, embedding_dim=32):
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
    # 11 default n_features: 7 sensors + hour_sin + hour_cos + day_sin + day_cos
    def __init__(self, seq_len, embedding_dim=32, n_features=11):
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
    def __init__(self, seq_len, n_features, embedding_dim=32):
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
    This function will receive and clean the buffer and then send it to the model to get a decision
    """
    try:
        # Pull the 7 sensor columns plus the 4 time columns
        clean_data_df = run_preprocessing_pipeline(buffer_data_list)
        clean_data_array = clean_data_df.values
    except Exception as e:
        print(f"[Bypass] Preprocessing failed ({e}). Forcing AI with random chaos data!")
        return (latest_sensor_id, "Normal")

    seq_len = len(clean_data_array)
    # Building the tensor that will be sent to the model
    tensor_input = torch.FloatTensor(clean_data_array).unsqueeze(0)
    # Create the complete mask include 1 value for the last 4 bits (because they represent the time and day and not a sensor)
    full_mask = house_sensor_mask + [1, 1, 1, 1]
    # Transforming the tesor mask into a 3 dimentional tenzor
    mask_tensor = torch.FloatTensor(full_mask).view(1, 1, -1)
    # Initiate the model with 11 features
    model = LSTMAnomalyDetector(seq_len=seq_len, n_features=11, embedding_dim=32)
    try:
        model.load_state_dict(torch.load(MODEL_PATH, map_location=torch.device('cpu')))
        model.eval() # Inference Mode
    except Exception as e:
        print(f"Error loading PyTorch model: {e}")
        return (latest_sensor_id, "Normal")

    # Anomaly calculation with mask regulator
    with torch.no_grad():
        # Pass through the encoder and the decoder
        reconstructed = model(tensor_input)
        # Loss in the format of seperate individual loss per column
        raw_loss = nn.functional.mse_loss(reconstructed, tensor_input, reduction='none')
        # Filter the loss using the mask
        masked_loss = raw_loss * mask_tensor
        # Calculate the loss concidering only the active parts of the tensor to keep the average sensitive to actual anomalities
        active_elements = mask_tensor.sum() * seq_len
        final_loss = masked_loss.sum() / active_elements
        loss_value = final_loss.item()

    print(f"[AI] Evaluated sequence of length {seq_len}. Anomaly Loss: {loss_value:.4f}")
    # Make a decision based on the loss number
    if loss_value > 0.5:
        return (latest_sensor_id, "Emergency")
    elif loss_value > 0.3:
        return (latest_sensor_id, "Warning")
    else:
        return (latest_sensor_id, "Normal")
