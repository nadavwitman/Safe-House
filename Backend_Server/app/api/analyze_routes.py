from flask import Blueprint, request, jsonify
from app.core.data_buffer import sensor_buffer
from app.core.house_mask_store import house_mask_store
import database.database as database
import database.user_db as user_db
from app.core import notifications
from app.core.ai_handler import evaluate_buffer_with_AI

analyze_bp = Blueprint('analyze', __name__)

# Sensor index mapping: 0=Door  1=Kitchen  2=Bath  3=Toilet  4=Meds  5=Bed  6=Living Room
DEFAULT_LOCATION = [0, 0, 0, 0, 0, 0, 1]

# In-memory cache for validated device tokens: {house_id: token}
_device_token_cache = {}


def _validate_device_token(house_id, token):
    if not token:
        return False
    if _device_token_cache.get(house_id) == token:
        return True
    if user_db.validate_device_token(house_id, token):
        _device_token_cache[house_id] = token
        return True
    return False


@analyze_bp.route('/api/analyze', methods=['POST'])
def analyze_data():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No data provided"}), 400

        house_id = data.get('house_id', 'default_house')

        device_token = request.headers.get('X-Device-Token')
        if not _validate_device_token(house_id, device_token):
            return jsonify({"error": "Unauthorized device"}), 401

        # Activate house on first valid ping
        house = user_db.get_house(house_id)
        if house and not house.get('is_active', False):
            user_db.activate_house(house_id)
            print(f"[Activation] House {house_id} activated by first IoT reading.")

        # Resolve current_location: payload → last buffer reading → last DB value → default
        current_location = data.get('current_location')
        if not (isinstance(current_location, list) and len(current_location) == 7 and all(b in (0, 1) for b in current_location)):
            last_reading = sensor_buffer.get_last_reading(house_id)
            last_loc = last_reading.get('current_location') if last_reading else None
            if isinstance(last_loc, list) and len(last_loc) == 7 and all(b in (0, 1) for b in last_loc):
                current_location = last_loc
            else:
                current_location = database.get_last_current_location(house_id)

        # Inject resolved value into data before buffering
        data['current_location'] = current_location if current_location is not None else DEFAULT_LOCATION
        ai_sensor = "System_Vector"
        ai_decision = "Normal"

        # Add to buffer and persist (now with resolved current_location)
        if getattr(sensor_buffer, 'is_active', True):
            sensor_buffer.add_reading(data)
        database.log_vector_reading(data, house_id)

        # Aquire all current buffer data for processing
        buffer_data = sensor_buffer.get_all_readings()

        # Making sure we have at least 1 minute to send to the model
        if len(buffer_data) > 0:
            house_mask = house_mask_store.get_mask(house_id)
            # get the AI model decision
            ai_sensor, ai_decision = evaluate_buffer_with_AI(buffer_data, ai_sensor, house_mask)

        # Act accordingly to the model's decision
        match ai_decision:
            case "Warning" | "Emergency":
                notifications.trigger_fcm_alert(ai_sensor, ai_decision, house_id)
                return jsonify({"status": "success", "decision": ai_decision, "fcm_status": "Sent"}), 200
            case _:
                return jsonify({"status": "success", "decision": "Normal", "fcm_status": "Not Sent"}), 200

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500
