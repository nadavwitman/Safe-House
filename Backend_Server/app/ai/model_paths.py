import os
import sys

BASE_DIR = os.path.dirname(__file__)

# AI_Model lives at the repo root, three levels up from app/ai.
AI_MODEL_DIR = os.path.abspath(os.path.join(BASE_DIR, "../../../AI_Model"))
sys.path.insert(0, AI_MODEL_DIR)
from model_handler import (
    LSTMAnomalyDetector, evaluate_window, DEFAULT_SENSOR_CONFIG,
    WINDOW_SIZE, N_FEATURES,
)

MODEL_PATH = os.path.join(AI_MODEL_DIR, "model", "best_safe_house_model.pth")


def masked_sensor_config(house_sensor_mask):
    """Per-house sensor_config: zones with no sensor installed get enabled=set(), so
    scoring.py's per-zone loops (`if 'X' not in cfg['enabled']: continue`) skip them
    outright instead of scoring and then discarding the result."""
    if not house_sensor_mask:
        return DEFAULT_SENSOR_CONFIG
    masked = {}
    for zone, cfg in DEFAULT_SENSOR_CONFIG.items():
        if zone < len(house_sensor_mask) and house_sensor_mask[zone] == 0:
            masked[zone] = {**cfg, 'enabled': set()}
        else:
            masked[zone] = cfg
    return masked
