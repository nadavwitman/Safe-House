import torch
import torch.nn as nn
import os
import copy
import numpy as np
from app.core.data_preprocessing import run_preprocessing_pipeline
import torch.optim as optim

BASE_DIR = os.path.dirname(__file__)
MODEL_PATH = os.path.join(BASE_DIR, "../../AI_Model/lstm_safe_house_model.pth")

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
        self.dropout = nn.Dropout(0.2) 
        self.rnn2 = nn.LSTM(input_size=self.hidden_dim, hidden_size=embedding_dim, num_layers=1, batch_first=True)

    def forward(self, x):
        x, _ = self.rnn1(x)
        x = self.dropout(x)
        x, (hidden_n, _) = self.rnn2(x)
        return hidden_n.reshape((x.shape[0], 1, self.embedding_dim))

class Decoder(nn.Module):
    """Reconstructs the original sequence from the latent vector produced by the Encoder."""
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
# Helper Logic for Activity Context (Context-Aware Anomaly Detection)
# ===========================================================================

def analyze_activity_context(buffer_data_list):
    """
    Analyzes the raw data pattern in the last 30 minutes to classify the anomaly.
    This helps distinguish between 'Positive Over-activity' (Hosting) 
    and 'Negative Anomaly' (Being stuck/fall).
    """
    last_30 = buffer_data_list[-30:]
    total_movement_events = 0
    multi_person_points = 0
    
    for entry in last_30:
        sensors = entry.get('sensor_vector', [])
        active_count = sum(sensors)
        
        if active_count > 0:
            total_movement_events += active_count
        
        # Multi-person detection: If sensors in more than one room fire in the same minute.
        if active_count > 1:
            multi_person_points += 1
            
    # Classification logic
    is_hosting = multi_person_points > 3  
    is_high_agitation = total_movement_events > 40  
    is_static = total_movement_events < 5  

    if is_hosting:
        return "Social/Hosting"
    elif is_high_agitation:
        return "Abnormal Agitation"
    elif is_static:
        return "Stuck/Fall"
    else:
        return "Unusual Routine"

# ===========================================================================
# Receive the AI decision based on the .pth file from the google collab model
# ===========================================================================
import torch
# Assuming LSTMAnomalyDetector, run_preprocessing_pipeline, and thresholds are imported here

def evaluate_buffer_with_AI(
    buffer_data_list, 
    latest_sensor_id: str, 
    house_sensor_mask: list, 
    model_instance=None,
    fine_tune_count: int = 0
) -> tuple[str, str]:
    """
    Runs the LSTM Autoencoder on the current buffer and returns an anomaly decision.
    Utilizes the cached personalized house model if available, otherwise falls back to the global baseline.
    Applies a confidence-based threshold decay based on the number of fine-tuning generations.
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
        return (latest_sensor_id, "Normal")

    # Check if a custom-trained baseline model object was passed from the RAM cache
    if model_instance is not None and isinstance(model_instance, LSTMAnomalyDetector):
        print(f"[AI] Executing inference using custom model. Fine-tune generations: {fine_tune_count}")
        model = model_instance
        model.eval()
    else:
        # Fallback logic: Load default global weights and reset fine-tune count
        fine_tune_count = 0
        print("[AI] No custom house model provided. Falling back to global baseline.")
        model = LSTMAnomalyDetector(seq_len=seq_len, n_features=18, embedding_dim=64)
        try:
            model.load_state_dict(torch.load(MODEL_PATH, map_location=torch.device('cpu')))
            model.eval()
        except Exception as e:
            print(f"Error loading fallback PyTorch model from disk: {e}")
            return (latest_sensor_id, "Normal")

    with torch.no_grad():
        reconstructed = model(tensor_input)
        raw_loss = (reconstructed - tensor_input) ** 2

        full_mask = house_sensor_mask + house_sensor_mask + [1, 1, 1, 1] 
        mask_tensor = torch.FloatTensor(full_mask).view(1, 1, -1)
        masked_loss = raw_loss * mask_tensor

        last_30_mins_loc_loss = masked_loss[0, -30:, 7:14]
        active_loc_elements = torch.FloatTensor(house_sensor_mask).sum() * 30
        loss_value = last_30_mins_loc_loss.sum().item() / (active_loc_elements + 1e-8)

    print(f"[AI] Evaluated sequence. Smart Anomaly Score: {loss_value:.4f}")

    # Extract the activity type context
    activity_type = analyze_activity_context(buffer_data_list)

    # Dynamic Threshold Decay Logic
    # Starts at 1.5x for generic models, decreases by 0.1 per training iteration, locks at 1.0x
    decay_multiplier = max(1.0, 1.5 - (0.1 * fine_tune_count))
    
    current_warning_threshold = WARNING_THRESHOLD * decay_multiplier
    current_emergency_threshold = EMERGENCY_THRESHOLD * decay_multiplier

    print(f"[AI] Threshold Multiplier applied: x{decay_multiplier:.2f}")

    # Context-Aware Decision Logic
    if loss_value > current_emergency_threshold:   
        if activity_type == "Social/Hosting":
            return (latest_sensor_id, "Notice: Social Activity (High Loss)")
        return (latest_sensor_id, f"Emergency: {activity_type}")
        
    elif loss_value > current_warning_threshold:   
        if activity_type == "Social/Hosting":
            return (latest_sensor_id, "Normal: Hosting")
        return (latest_sensor_id, f"Warning: {activity_type}")
        
    else:
        return (latest_sensor_id, "Normal")
    
import copy
import os
import torch
import torch.nn as nn
import torch.optim as optim
# Assuming run_preprocessing_pipeline, LSTMAnomalyDetector, MODEL_PATH are imported

def fine_tune_house_model(house_id: str, raw_training_data: list, house_sensor_mask: list, current_model=None, epochs=5, lr=0.001):
    """
    Fine tune the existing data with new data acquired in the last 14 days.
    Modified to work with in-memory models for cloud storage integration.
    """
    if not raw_training_data or len(raw_training_data) < 720:
        print(f"[AI] Not enough recent data to fine-tune house {house_id}")
        return None

    print(f"[AI] Starting Fine-Tuning for house {house_id} on {len(raw_training_data)} NEW records...")
    try:
        tensor_data = run_preprocessing_pipeline(raw_training_data)
        if not isinstance(tensor_data, torch.Tensor):
            tensor_data = torch.FloatTensor(tensor_data)
        if tensor_data.dim() == 2:
            tensor_data = tensor_data.unsqueeze(0)
        seq_len = tensor_data.shape[1]
    except Exception as e:
        print(f"Error preprocessing fine-tuning data: {e}")
        return None

    full_mask = house_sensor_mask + house_sensor_mask + [1, 1, 1, 1]
    mask_tensor = torch.FloatTensor(full_mask).view(1, 1, -1)

    # --- CLOUD INTEGRATION CHANGE ---
    # Use the RAM model if provided by the manager, otherwise load the generic baseline
    if current_model is not None:
        print(f"[AI] Using existing personalized model for {house_id} as base.")
        model = current_model
    else:
        print(f"[AI] No custom model provided. Loading default generic weights for {house_id}.")
        model = LSTMAnomalyDetector(seq_len=seq_len, n_features=18, embedding_dim=64)
        try:
            model.load_state_dict(torch.load(MODEL_PATH, map_location=torch.device('cpu')))
        except Exception as e:
            print(f"Error loading base model weights: {e}")
            return None
    # --------------------------------

    # A snapshot of the current pre-fine-tuning data
    old_state_dict = copy.deepcopy(model.state_dict())

    # Training the data based only on the last 14 days
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

    print(f"[AI] Weight Interpolation completed for {house_id} in RAM!")
    
    # Return the fully updated model object instead of saving to local disk
    return model