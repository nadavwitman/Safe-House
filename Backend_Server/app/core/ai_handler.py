import torch
import torch.nn as nn
import os
import numpy as np
from app.core.data_preprocessing import run_preprocessing_pipeline

BASE_DIR = os.path.dirname(__file__)
MODEL_PATH = os.path.join(BASE_DIR, "../../../AI_Model/lstm_safe_house_model.pth")

# ===============================================================================================================================
# Create the classes that will generate the weights by running the data in the encoder and out through the decoder
# ===============================================================================================================================

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
    # 9 default n_features: 7 sensors + hour + day_of_week
    def __init__(self, seq_len, embedding_dim=32, n_features=9):
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
def evaluate_buffer_with_AI(buffer_data_list, latest_sensor_id: str) -> tuple[str, str]:
    """
    This function will receive and clean the buffer and then send it to the model to get a decision
    """
    try:
        clean_data_df = run_preprocessing_pipeline(buffer_data_list, is_training=False)

        # Pull the 7 sensor columns plus the 2 time columns
        features_to_use = [f'sensor_{i}' for i in range(7)] + ['hour', 'day_of_week']
        clean_data_array = clean_data_df[features_to_use].values

    except Exception as e:
        print(f"[Bypass] Preprocessing failed ({e}). Forcing AI with random chaos data!")
        # Fallback random array in the case of a crash
        clean_data_array = np.random.rand(len(buffer_data_list), 9) * 10

    seq_len = len(clean_data_array)

    # Building the tensor that will be sent to the model
    tensor_input = torch.FloatTensor(clean_data_array).unsqueeze(0)

    # nstantiating the model with n_features=9
    model = LSTMAnomalyDetector(seq_len=seq_len, n_features=9, embedding_dim=32)

    try:
        model.load_state_dict(torch.load(MODEL_PATH, map_location=torch.device('cpu')))
        model.eval() # Inference Mode
    except Exception as e:
        print(f"Error loading PyTorch model: {e}")
        return (latest_sensor_id, "Normal")

    # Anomaly calculation
    with torch.no_grad():
        reconstructed = model(tensor_input)
        loss = nn.functional.mse_loss(reconstructed, tensor_input).item()

    print(f"[AI] Evaluated sequence of length {seq_len}. Anomaly Loss: {loss:.4f}")

    # Make a decision based on the loss number
    if loss > 0.5:
        return (latest_sensor_id, "Emergency")
    elif loss > 0.3:
        return (latest_sensor_id, "Warning")
    else:
        return (latest_sensor_id, "Normal")
