import pandas as pd
import numpy as np
from datetime import datetime
from sklearn.preprocessing import MinMaxScaler
import joblib
import os

# Define the path to save/load the scaler object
# This path goes up from 'core', up from 'app', into 'AI_Model'
SCALER_PATH = os.path.join(os.path.dirname(__file__), "../../../AI_Model/scaler.pkl")

def format_sensor_data(raw_data):
    """
    Step 1: Format incoming JSON data into a Pandas DataFrame.
    Extracts time-based features and encodes categorical statuses.
    """
    # Convert to DataFrame - ensure we are working with a list
    if isinstance(raw_data, dict):
        raw_data = [raw_data]

    df = pd.DataFrame(raw_data)

    # Handle Time-Series columns
    if 'time' in df.columns:
        df['time'] = pd.to_datetime(df['time'])
        df['hour'] = df['time'].dt.hour
        df['day_of_week'] = df['time'].dt.dayofweek
        df = df.sort_values(by='time').reset_index(drop=True)
    else:
        # Fallback to current server time if missing
        current_time = datetime.now()
        df['time'] = current_time
        df['hour'] = current_time.hour
        df['day_of_week'] = current_time.weekday()

    # Encode sensor states using NumPy (e.g., 'open' -> 1, 'closed' -> 0)
    if 'status' in df.columns:
        df['status_num'] = np.where(df['status'] == 'open', 1, 0)

    # Handle missing data (NaN)
    df = df.ffill().fillna(0)

    return df

def scale_sensor_data(df, is_training=False):
    """
    Step 2: Scale and normalize numerical features using Scikit-Learn.
    Uses MinMaxScaler to bound values between 0 and 1 for the LSTM model.
    """
    numerical_cols = ['hour', 'day_of_week']
    if 'inactivity_minutes' in df.columns:
        numerical_cols.append('inactivity_minutes')

    cols_to_scale = [col for col in numerical_cols if col in df.columns]

    if not cols_to_scale:
        return df

    if is_training:
        scaler = MinMaxScaler()
        #df[cols_to_scale] = scaler.fit_transform(df[cols_to_scale].values)

        # Save the scaler for future inference
        os.makedirs(os.path.dirname(SCALER_PATH), exist_ok=True)
        joblib.dump(scaler, SCALER_PATH)
        print(f"Scaler saved successfully to {SCALER_PATH}")

    else:
        # Inference mode: Load existing scaler
        try:
            scaler = joblib.load(SCALER_PATH)
            df[cols_to_scale] = scaler.transform(df[cols_to_scale])
        except FileNotFoundError:
            print(f"Warning: Scaler file not found at {SCALER_PATH}. Returning unscaled data.")

    return df

def run_preprocessing_pipeline(raw_data, is_training=False):
    """
    Main function to run the full preprocessing pipeline.
    This is the function you will call from your routes.py.
    """
    # 1. Format the data
    df = format_sensor_data(raw_data)

    # 2. Scale the data
    df_scaled = scale_sensor_data(df, is_training=is_training)

    return df_scaled
