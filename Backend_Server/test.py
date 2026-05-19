import torch
import numpy as np
from datetime import datetime, timedelta
import warnings
from app.core.ai_handler import evaluate_buffer_with_AI

# Suppress unnecessary warnings for cleaner output
warnings.filterwarnings("ignore", category=UserWarning)

def generate_mock_buffer(scenario="normal"):
    buffer = []
    # Default start time 10:00 AM
    base_start = datetime(2026, 3, 15, 10, 0, 0)
    
    # Update start time for Night Agitation
    if scenario == "agitation":
        base_start = datetime(2026, 3, 16, 2, 0, 0)

    current_loc_idx = 6 # Default Living Room index
    if scenario == "agitation": current_loc_idx = 5 # Should be Bedroom index

    for i in range(360):
        current_time = base_start + timedelta(minutes=i)
        sensor_vector = [0, 0, 0, 0, 0, 0, 0]
        
        if scenario == "normal":
            current_loc_idx = 6
            if i % 60 == 0: sensor_vector[6] = 1

        elif scenario == "anomaly":
            if i < 330: current_loc_idx = 6
            else:
                current_loc_idx = 2 # Stuck in bathroom
                if i == 330: sensor_vector[2] = 1

        elif scenario == "hosting":
            if i < 330: current_loc_idx = 6
            else:
                current_loc_idx = 1 # In Kitchen (Anomaly)
                sensor_vector[1] = 1
                if i < 336: # Guests moving in the first 6 mins
                    sensor_vector[6] = 1
                    sensor_vector[0] = 1

        elif scenario == "agitation":
            if i < 330: current_loc_idx = 5 # Sleeping
            else:
                # Pacing between Living room and Kitchen at 2 AM
                current_loc_idx = 1 if i % 4 < 2 else 6 
                sensor_vector[current_loc_idx] = 1 

        # --- THE FIX: Convert current_loc_idx integer into a 7-bit One-Hot Vector ---
        location_vector = [0, 0, 0, 0, 0, 0, 0]
        location_vector[current_loc_idx] = 1

        buffer.append({
            "sensor_vector": sensor_vector,
            "current_location": location_vector, # Sending it as a full vector!
            "time": current_time
        })
    return buffer

house_mask = [1, 1, 1, 1, 1, 1, 1]
scenarios = ["normal", "anomaly", "hosting", "agitation"]
sensor_ids = ["sensor_6", "sensor_2", "sensor_1", "sensor_1"]

print("\n" + "="*60)
print("SAFE HOUSE - ADVANCED SCENARIO TESTING")
print("="*60 + "\n")

for sc, s_id in zip(scenarios, sensor_ids):
    log = generate_mock_buffer(sc)
    _, res = evaluate_buffer_with_AI(log, s_id, house_mask)
    print(f"Scenario: {sc.upper()} | Result: {res}\n" + "-"*30)

print("="*60)