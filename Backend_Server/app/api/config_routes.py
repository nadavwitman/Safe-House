from flask import Blueprint, request, jsonify

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
        # TODO: Insert function to stop the AI model from processing data
        return jsonify({"status": "success", "mode": "Vacation", "model_updated": False}), 200

    return jsonify({"status": "success", "message": "Configuration updated"}), 200