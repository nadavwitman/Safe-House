import torch
import numpy as np
from datetime import datetime, timedelta
from app.core.ai_handler import evaluate_buffer_with_AI
import warnings
warnings.filterwarnings("ignore", category=UserWarning)

def generate_mock_buffer(scenario="normal"):
    """
    Generates a list of 360 one-minute readings (6-hour window) to simulate the buffer.

    Scenarios:
        "normal"  - Person is in the living room until 22:00 then goes to sleep (expected routine)
        "anomaly" - Person enters the bathroom at 21:00 and never leaves (stuck / emergency)
    """
    buffer = []
    start_time = datetime(2026, 3, 15, 20, 0, 0)  # Simulation starts at 20:00

    for i in range(360):
        current_time = start_time + timedelta(minutes=i)
        hour = current_time.hour

        # Empty sensor vector [Door, Kitchen, Bath, Toilet, Meds, Bed, Living]
        sensor_vector = [0, 0, 0, 0, 0, 0, 0]

        if scenario == "normal":
            # Routine: person in living room until 22:00, then goes to bed
            if hour < 22:
                sensor_vector[6] = 1  # Living
            else:
                sensor_vector[5] = 1  # Bed

        elif scenario == "anomaly":
            # Anomaly: person enters the bathroom at 21:00 and does not leave
            if hour < 21:
                sensor_vector[6] = 1  # Living
            else:
                sensor_vector[2] = 1  # Bath (STUCK!)

        buffer.append({
            "sensor_vector": sensor_vector,
            "time": current_time
        })

    return buffer


# --- Run Tests ---

# Dummy mask: all 7 sensors are installed in this house
house_mask = [1, 1, 1, 1, 1, 1, 1]

print("--- Safe House Sync Test ---")

# 1. Normal routine test
normal_log = generate_mock_buffer(scenario="normal")
_, res_normal = evaluate_buffer_with_AI(normal_log, "sensor_5", house_mask)
print(f"Normal scenario (sleeping): result = {res_normal}")

print("-" * 30)

# 2. Anomaly test
anomaly_log = generate_mock_buffer(scenario="anomaly")
_, res_anomaly = evaluate_buffer_with_AI(anomaly_log, "sensor_2", house_mask)
print(f"Anomaly scenario (stuck in bathroom): result = {res_anomaly}")
