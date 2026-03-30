import torch
import numpy as np
from datetime import datetime, timedelta
from app.core.ai_handler import evaluate_buffer_with_AI
import warnings
warnings.filterwarnings("ignore", category=UserWarning)
def generate_mock_buffer(scenario="normal"):
    """
    מייצר רשימה של 360 דקות (חלון זמן) עבור המודל
    """
    buffer = []
    start_time = datetime(2026, 3, 15, 20, 0, 0) # מתחיל ב-20:00 בערב
    
    for i in range(360):
        current_time = start_time + timedelta(minutes=i)
        hour = current_time.hour
        
        # וקטור חיישנים ריק [Door, Kitchen, Bath, Toilet, Meds, Bed, Living]
        sensor_vector = [0, 0, 0, 0, 0, 0, 0]
        
        if scenario == "normal":
            # שגרה: סבא בסלון עד 22:00 ואז הולך לישון
            if hour < 22:
                sensor_vector[6] = 1 # Living
            else:
                sensor_vector[5] = 1 # Bed
        
        elif scenario == "anomaly":
            # אנומליה: סבא נכנס למקלחת ב-21:00 ולא יוצא
            if hour < 21:
                sensor_vector[6] = 1 # Living
            else:
                sensor_vector[2] = 1 # Bath (STUCK!)

        buffer.append({
            "sensor_vector": sensor_vector,
            "time": current_time
        })
    
    return buffer

# --- הרצת המבחן ---

# מסכה דמיונית (כל החיישנים קיימים בבית הזה)
house_mask = [1, 1, 1, 1, 1, 1, 1]

print("--- 🧪 מריץ בדיקת סנכרון SAFE HOUSE ---")

# 1. בדיקת שגרה
normal_log = generate_mock_buffer(scenario="normal")
_, res_normal = evaluate_buffer_with_AI(normal_log, "sensor_5", house_mask)
print(f"✅ תרחיש שגרה (שינה): התוצאה היא {res_normal}")

print("-" * 30)

# 2. בדיקת אנומליה
anomaly_log = generate_mock_buffer(scenario="anomaly")
_, res_anomaly = evaluate_buffer_with_AI(anomaly_log, "sensor_2", house_mask)
print(f"🚨 תרחיש אנומליה (מקלחת): התוצאה היא {res_anomaly}")