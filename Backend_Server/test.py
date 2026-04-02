import torch
import numpy as np
from datetime import datetime, timedelta
from app.core.ai_handler import evaluate_buffer_with_AI
import warnings

# Suppress unnecessary warnings for cleaner output
warnings.filterwarnings("ignore", category=UserWarning)

def generate_mock_buffer(scenario="normal"):
    """
    Generates a list of 360 one-minute readings (6-hour window).
    Start time: 10:00 AM
    Window: 10:00 to 16:00
    """
    buffer = []
    start_time = datetime(2026, 3, 15, 10, 0, 0) 
    
    # Initial state
    current_loc = 6 # Starts in Living Room

    for i in range(360):
        current_time = start_time + timedelta(minutes=i)
        sensor_vector = [0, 0, 0, 0, 0, 0, 0]
        
        if scenario == "normal":
            # Routine: Kitchen at 12:00 for one hour, else Living Room
            if current_time.hour == 12 and current_time.minute == 0:
                current_loc = 1 # Transition to Kitchen
                sensor_vector[1] = 1 # Entry event
            elif current_time.hour == 13 and current_time.minute == 0:
                current_loc = 6 # Back to Living Room
                sensor_vector[6] = 1 # Entry event
            elif i == 0:
                sensor_vector[6] = 1 # Initial event

        elif scenario == "anomaly":
            # Anomaly: Goes to Bathroom at 11:00 and gets stuck
            if current_time.hour == 11 and current_time.minute == 0:
                current_loc = 2 # Bathroom
                sensor_vector[2] = 1 # Entry event
            elif i == 0:
                sensor_vector[6] = 1 # Initial event

        buffer.append({
            "sensor_vector": sensor_vector,
            "current_location": current_loc,
            "time": current_time
        })

    return buffer

# --- Run Evaluation Tests ---

house_mask = [1, 1, 1, 1, 1, 1, 1]

print("--- SAFE HOUSE SYSTEM INTEGRATION TEST (DAYTIME) ---")

# 1. Test Normal Daytime Scenario (Kitchen at Lunch)
normal_log = generate_mock_buffer(scenario="normal")
_, res_normal = evaluate_buffer_with_AI(normal_log, "sensor_1", house_mask)
print(f"[TEST 1] Normal daytime (Kitchen lunch): Result = {res_normal}")

print("-" * 40)

# 2. Test Anomaly Daytime Scenario (Stuck in bathroom at 11 AM)
anomaly_log = generate_mock_buffer(scenario="anomaly")
_, res_anomaly = evaluate_buffer_with_AI(anomaly_log, "sensor_2", house_mask)
print(f"[TEST 2] Anomaly daytime (Stuck in bath): Result = {res_anomaly}")