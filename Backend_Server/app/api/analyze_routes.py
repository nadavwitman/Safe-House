from flask import Blueprint, request, jsonify
from app.core.data_buffer import sensor_buffer
import Backend_Server.database.database as database
from app.core import notifications
from app.core.data_preprocessing import run_preprocessing_pipeline
from app.core.ai_handler import send_buffer_to_AI, recieve_AI_decision

# Define the blueprint for analysis routing
analyze_bp = Blueprint('analyze', __name__)

@analyze_bp.route('/api/analyze', methods=['POST'])
def analyze_data():
    """
    Endpoint for processing and buffering sensor data.
    """
    data = request.get_json()

    if not data:
        return jsonify({"error": "No data provided"}), 400

    # Pass raw data through the preprocessing pipeline
    try:
        processed_df = run_preprocessing_pipeline(data, is_training=False)
        processed_data = processed_df.to_dict(orient='records')[0]
    except Exception as e:
        return jsonify({"error": f"Preprocessing failed: {str(e)}"}), 500

    # Store preprocessed data in the memory buffer 
    sensor_buffer.add_reading(processed_data)
    
    if sensor_buffer.has_enough_data():
        send_buffer_to_AI(sensor_buffer)

    # Acquire sensor information
    sensor = processed_data.get('sensor', 'unknown')
    action = processed_data.get('action', 'unknown')
    
    # Retrieve house_id from the incoming JSON data 
    # Falls back to 'default_house' if not provided by the ESP32
    house_id = data.get('house_id', 'default_house')

    # Log the event with the new house-specific structure 
    database.log_sensor_event(sensor, action, house_id)

    # Receive AI decision
    ai_sensor, ai_decision = recieve_AI_decision()
    
    # Handle response and notifications
    match ai_decision:
        case "Warning":
            notifications.trigger_fcm_alert(ai_sensor, ai_decision)
            return jsonify({"status": "success", "decision": "Warning", "fcm_status": "Sent"}), 200
        case "Emergency":
            notifications.trigger_fcm_alert(ai_sensor, ai_decision)
            return jsonify({"status": "success", "decision": "Emergency", "fcm_status": "Sent"}), 200
        case _:
            return jsonify({"status": "success", "decision": "Normal", "fcm_status": "Not Sent"}), 200