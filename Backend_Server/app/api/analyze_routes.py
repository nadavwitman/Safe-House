from flask import Blueprint, request, jsonify
from app.core.data_buffer import sensor_buffer
import database.database as database
from app.core import notifications
from app.core.ai_handler import evaluate_buffer_with_AI

analyze_bp = Blueprint('analyze', __name__)


# TODO: Right now this is a mock mask built for 4 sensors, implement a real one when database logic is ready
def get_house_mask_from_db(house_id):
    return [1, 1, 1, 1, 0, 0, 0]


@analyze_bp.route('/api/analyze', methods=['POST'])
def analyze_data():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No data provided"}), 400
        # Insert the data to the buffer
        if getattr(sensor_buffer, 'is_active', True):
            sensor_buffer.add_reading(data)
        house_id = data.get('house_id', 'default_house')
        ai_sensor = "System_Vector"
        ai_decision = "Normal"
        # Aquire all current buffer data for processing
        buffer_data = sensor_buffer.get_all_readings()
        # Making sure we have at least 1 minute to send to the model
        if len(buffer_data) > 0:
            house_mask = get_house_mask_from_db(house_id)
            # get the AI model decision
            ai_sensor, ai_decision = evaluate_buffer_with_AI(buffer_data, ai_sensor, house_mask)
        # Act accordingly to the model's decision
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
