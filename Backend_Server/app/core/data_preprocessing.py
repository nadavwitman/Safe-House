import pandas
from datetime import datetime
from sklearn.preprocessing import MinMaxScaler
import joblib
import os
import numpy as np
import torch

# Define the path to save/load the scaler object
# This path goes up from 'core', up from 'app', into 'AI_Model'
SCALER_PATH = os.path.join(os.path.dirname(__file__), "../../../AI_Model/scaler.pkl")

# This function will receive the sensors vector from the ESP32 and will transform it into a panda's data frame
def format_sensor_data(raw_data):
    """
    Converts raw buffer readings (list of dicts) into a structured DataFrame.

    Each dict contains a 7-bit sensor_vector, a timestamp, and current_location.
    The timestamp is encoded as circular sin/cos features to preserve the cyclical
    nature of time (hours wrap around 24, days wrap around 7).

    Returns a DataFrame with 18 columns:
        sensor_0..6, location_0..6, hour_sin, hour_cos, day_sin, day_cos
    """
    # Ensure we are working with a list
    if isinstance(raw_data, dict):
        raw_data = [raw_data]
    
    # Convert to DataFrame
    df = pandas.DataFrame(raw_data)

    # Handle Time-Series columns
    if 'time' in df.columns:
        df['time'] = pandas.to_datetime(df['time'])
    else:
        # Fallback to current server time if missing
        current_time = datetime.now()
        df['time'] = current_time

    # Extract the raw hour (with float precision for minutes) and day of the week
    hour_raw = df['time'].dt.hour + (df['time'].dt.minute / 60.0)
    day_raw = df['time'].dt.dayofweek

    # Sin and Cos encoding to create circular (continuous) time features
    df['hour_sin'] = np.sin(2 * np.pi * hour_raw / 24)
    df['hour_cos'] = np.cos(2 * np.pi * hour_raw / 24)

    df['day_sin'] = np.sin(2 * np.pi * day_raw / 7)
    df['day_cos'] = np.cos(2 * np.pi * day_raw / 7)

    df = df.sort_values(by='time').reset_index(drop=True)

    # Expand the 7-bit sensor_vector into individual columns (sensor_0 .. sensor_6)
    if 'sensor_vector' in df.columns:
        sensor_cols = pandas.DataFrame(df['sensor_vector'].tolist(), columns=[f'sensor_{i}' for i in range(0,7)])
        df = pandas.concat([df, sensor_cols], axis=1)
        df = df.drop(columns=['sensor_vector'])
    else:
        for i in range(7):
            df[f'sensor_{i}'] = 0

    # --- CRITICAL CHANGE: Convert current_location to 7 binary location columns ---
    # This creates location_0 to location_6 to match the 18-feature architecture
    for i in range(7):
        df[f'location_{i}'] = 0
    
    if 'current_location' in df.columns:
        for i in range(7):
            # If the current_location matches the index, set that column to 1
            df.loc[df['current_location'] == i, f'location_{i}'] = 1
        df = df.drop(columns=['current_location'])

    # Forward-fill then zero-fill any remaining NaN values
    df = df.ffill().fillna(0)
    return df


# The 'main' function of this module. Receives raw buffer data and returns a tensor ready for the AI model.
def run_preprocessing_pipeline(raw_data):
    """
    Full preprocessing pipeline: format → select features → scale → convert to tensor.

    Steps:
        1. Format raw dicts into a structured DataFrame (format_sensor_data)
        2. Select the 18 feature columns fed to the model
        3. Apply MinMaxScaler (loaded from Colab training) to normalize values to [0, 1]
        4. Convert to a Float32 PyTorch tensor with a batch dimension

    Returns:
        torch.Tensor of shape [1, seq_length, 18]
    """
    # 1. Organize the data into a DataFrame
    df = format_sensor_data(raw_data)
    
    # --- CRITICAL CHANGE: Updated list to exactly 18 features in training order ---
    cols_for_ai = (
        [f'sensor_{i}' for i in range(7)] +     # Features 0-6
        [f'location_{i}' for i in range(7)] +   # Features 7-13
        ['hour_sin', 'hour_cos', 'day_sin', 'day_cos'] # Features 14-17
    )
    
    data_raw = df[cols_for_ai]

    # 2. Load the MinMaxScaler saved during Colab training
    # Ensure scaler.pkl is present at SCALER_PATH
    scaler = joblib.load(SCALER_PATH)

    # 3. Normalize all features to [0, 1]
    data_scaled = scaler.transform(data_raw)

    # 4. Convert to a PyTorch tensor and add a batch dimension
    # Input shape will be [1, 360, 18] if raw_data has 360 minutes
    input_tensor = torch.tensor(data_scaled, dtype=torch.float32).unsqueeze(0)

    return input_tensor