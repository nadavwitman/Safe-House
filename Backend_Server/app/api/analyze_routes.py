from flask import Blueprint, request, jsonify
from app.core.data_buffer import sensor_buffer
import database.database as database
from app.core import notifications
from app.core.ai_handler import evaluate_buffer_with_AI

# Define the blueprint for analysis routing
analyze_bp = Blueprint('analyze', __name__)
@analyze_bp.route('/api/analyze', methods=['POST'])
def analyze_data():
    try:
        data = request.get_json()

        if not data:
            return jsonify({"error": "No data provided"}), 400

        if getattr(sensor_buffer, 'is_active', True):
            sensor_buffer.add_reading(data)

        sensor = data.get('sensor', 'unknown')
        action = data.get('action', 'unknown')
        house_id = data.get('house_id', 'default_house')


        ai_decision = "Normal"
        ai_sensor = sensor

        if sensor_buffer.has_enough_data():
            buffer_data = sensor_buffer.get_all_readings()
            ai_sensor, ai_decision = evaluate_buffer_with_AI(buffer_data, sensor)
            sensor_buffer.clear()

        match ai_decision:
            case "Warning" | "Emergency":
                notifications.trigger_fcm_alert(ai_sensor, ai_decision)
                return jsonify({"status": "success", "decision": ai_decision, "fcm_status": "Sent"}), 200
            case _:
                return jsonify({"status": "success", "decision": "Normal", "fcm_status": "Not Sent"}), 200

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500
