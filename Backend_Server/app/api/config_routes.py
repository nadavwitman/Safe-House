from flask import Blueprint, request, jsonify
from app.core.data_buffer import sensor_buffer

# Define the blueprint for configuration routing
config_bp = Blueprint('config', __name__)

@config_bp.route('/api/config', methods=['POST'])
def config_system():
    """
    Endpoint for system configuration (e.g., Vacation Mode)
    """
    config_data = request.get_json()

    if not config_data:
         return jsonify({"error": "No configuration data provided"}), 400

    mode = config_data.get('mode')

    if mode == "Vacation":
        sensor_buffer.is_active = False
        sensor_buffer.clear()
        return jsonify({"status": "success", "mode": "Vacation", "model_updated": False}), 200

    elif mode == "Normal":
        sensor_buffer.is_active = True
        return jsonify({"status": "success", "mode": "Normal", "model_updated": True}), 200

    return jsonify({"status": "success", "message": "Configuration updated"}), 200
