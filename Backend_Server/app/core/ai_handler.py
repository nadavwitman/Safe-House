import torch
import torch.nn as nn
import os
import numpy as np
from app.core.data_preprocessing import run_preprocessing_pipeline

BASE_DIR = os.path.dirname(__file__)
MODEL_PATH = os.path.join(BASE_DIR, "../../../AI_Model/lstm_safe_house_model.pth")
THRESHOLD = 0.025
# ================================================================================================================
# Create the classes that will generate the weights by running the data in the encoder and out through the decoder
# ================================================================================================================

class Encoder(nn.Module):
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
    # 11 default n_features: 7 sensors + hour_sin + hour_cos + day_sin + day_cos
    def __init__(self, seq_len, embedding_dim=64, n_features=11):
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
    פונקציה מעודכנת המטפלת בטנזורים ופותרת את שגיאת ה-TypeError
    """
    try:
        # 1. קבלת הנתונים המעובדים (כבר מגיעים כטנזור מה-Preprocessing)
        tensor_input = run_preprocessing_pipeline(buffer_data_list)
        
        # מוודא שהטנזור בפורמט Float32
        if not isinstance(tensor_input, torch.Tensor):
            tensor_input = torch.FloatTensor(tensor_input)
            
        # הוספת ממד Batch אם חסר (צריך להיות [1, 360, 11])
        if tensor_input.dim() == 2:
            tensor_input = tensor_input.unsqueeze(0)

        # חילוץ אורך הרצף (בדרך כלל 360)
        seq_len = tensor_input.shape[1]

    except Exception as e:
        print(f"[🚨] Preprocessing failed: {e}")
        return (latest_sensor_id, "Normal")

    # 2. אתחול וטעינת המודל
    # הערה: וודא ש-embedding_dim תואם למה שהגדרת ב-Colab (אם זה היה 64, שנה ל-64)
    model = LSTMAnomalyDetector(seq_len=seq_len, n_features=11, embedding_dim=64)
    
    try:
        model.load_state_dict(torch.load(MODEL_PATH, map_location=torch.device('cpu')))
        model.eval()
    except Exception as e:
        print(f"[🚨] Error loading PyTorch model: {e}")
        return (latest_sensor_id, "Normal")

    # 3. חישוב האנומליה
    with torch.no_grad():
        reconstructed = model(tensor_input)
        
        # חישוב השגיאה הגולמית
        raw_loss = nn.functional.mse_loss(reconstructed, tensor_input, reduction='none')
        
        # החלת ה-Mask כדי להתעלם מחיישנים שלא קיימים בבית
        full_mask = house_sensor_mask + [1, 1, 1, 1]
        mask_tensor = torch.FloatTensor(full_mask).view(1, 1, -1)
        
        masked_loss = raw_loss * mask_tensor
        active_elements = mask_tensor.sum() * seq_len
        final_loss = masked_loss.sum() / active_elements
        loss_value = final_loss.item()

    print(f"[AI] Evaluated sequence. Anomaly Loss: {loss_value:.4f}")

# כיול מחדש לפי תוצאות הבדיקה בשרת (0.089 מול 0.117)
    if loss_value > 0.11: # רק אנומליה חריפה באמת
        return (latest_sensor_id, "Emergency")
    elif loss_value > 0.10: # אנומליה קלה או גבולית
        return (latest_sensor_id, "Warning")
    else:
        return (latest_sensor_id, "Normal")