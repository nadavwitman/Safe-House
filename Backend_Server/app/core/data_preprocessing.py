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

# This function will recieve the sensors vector from the ESP32 and will transform it into a panda's data frame
def format_sensor_data(raw_data):
    """
    Step 1: Format incoming 7 bit vector into format
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

    # Extract the raw hour and day of the week
    hour_raw = df['time'].dt.hour
    day_raw = df['time'].dt.dayofweek

    # Sin and Cos encoding in ordere to create circular data
    df['hour_sin'] = np.sin(2 * np.pi * hour_raw / 24)
    df['hour_cos'] = np.cos(2 * np.pi * hour_raw / 24)

    df['day_sin'] = np.sin(2 * np.pi * day_raw / 7)
    df['day_cos'] = np.cos(2 * np.pi * day_raw / 7)

    df = df.sort_values(by='time').reset_index(drop=True)
    # Encode sensor states using NumPy (e.g., 'open' -> 1, 'closed' -> 0)
    if 'sensor_vector' in df.columns:
        # Parse the 7-bit vector into seperate columns for each vector
        sensor_cols = pandas.DataFrame(df['sensor_vector'].tolist(), columns=[f'sensor_{i}' for i in range(0,7)])
        # Merge the 7 columns into one table
        df = pandas.concat([df, sensor_cols], axis=1)
        # To save memory drop the original unfiltered vector
        df = df.drop(columns=['sensor_vector'])
    else: # Avoid collapse in case of missing data
        for i in range(7):
            df[f'sensor_{i}'] = 0
    # Handle missing data (NaN)
    df = df.ffill().fillna(0)
    return df




# The 'main' function of this class. Recieves raw data and returns a df that can be an input for the AI model
def run_preprocessing_pipeline(raw_data):
    """
    הפונקציה המעודכנת שכוללת נרמול (Scaling)
    """
    # 1. סידור הנתונים ל-DataFrame (מה שחבר שלך כבר כתב)
    df = format_sensor_data(raw_data)
    cols_for_ai = [f'sensor_{i}' for i in range(7)] + ['hour_sin', 'hour_cos', 'day_sin', 'day_cos']
    data_raw = df[cols_for_ai]

    # --- הקטע שחסר (התיקון): ---
    
    # 2. טעינת ה-Scaler ששמרנו ב-Colab
    # הערה: וודא שהקובץ scaler.pkl נמצא בנתיב שמוגדר ב-SCALER_PATH
    scaler = joblib.load(SCALER_PATH)
    
    # 3. נרמול הנתונים (הופך אותם לערכים בין 0 ל-1)
    data_scaled = scaler.transform(data_raw)
    
    # 4. המרה לטנזור של PyTorch (כדי שהמודל יוכל לעבוד איתו)
    # מוסיפים ממד נוסף (unsqueeze) כדי שזה ייראה כמו Batch
    input_tensor = torch.tensor(data_scaled, dtype=torch.float32).unsqueeze(0)
    
    return input_tensor
