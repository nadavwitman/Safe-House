from flask import Blueprint, request, jsonify
from app.core.data_buffer import sensor_buffer
import database
from app.core import notifications

# Define the API blueprint for modular routing
api_bp = Blueprint('api', __name__)

def send_buffer_to_AI(buffer):
    """
    TODO: Implement this function which will send the buffer to the AI model for processing
    """
    pass

def recieve_AI_decision() -> tuple[str,str] :
    """
    TODO: Implement this function which will recieve the conclusion of the AI model and will decide if:
    everything is normal, there is a moderate warning or if there is an emergency.
    This function will return a tuple of : (sensor, decision) where sensor is the sensor which triggered the anomaly and
    decision indicates Normal/Warning/Emergency status determined by the AI model
    """
    return ("unknown", "Noraml")



# This API will recieving the sensor's data from the ESP32
@api_bp.route('/api/analyze', methods=['POST'])
def analyze_data():
    """
    Endpoint for processing and buffering sensor data
    """
    data = request.get_json()

    # Validate that the request body is present
    if not data:
        return jsonify({"error": "No data provided"}), 400

    # Store the incoming data in the application's memory buffer for future delivery to the AI model
    sensor_buffer.add_reading(data)
    if sensor_buffer.has_enough_data():
        send_buffer_to_AI(sensor_buffer)

    # Aquire the sensor's information and save it in the database
    sensor = data.get('sensor', 'unknown')
    action = data.get('action', 'unknown')
    database.log_sensor_event(sensor, action)

    # Recieve the current decision from the AI model regarding the current situation and the sensor which invoked the decision
    ai_sensor, ai_decision = recieve_AI_decision()
    match ai_decision:
        case "Warning":
            notifications.trigger_fcm_alert(ai_sensor,ai_decision)
            return jsonify({
                "status": "success",
                "decision": "Warning",
                "fcm_status": "Sent"
            }), 200
        case "Emergency":
            notifications.trigger_fcm_alert(ai_sensor,ai_decision)
            return jsonify({
                "status": "success",
                "decision": "Emergency",
                "fcm_status": "Sent"
            }), 200
        case _:
            return jsonify({
                "status": "success",
                "decision": "Normal",
                "fcm_status": "Not Sent"
            }), 200




# Use this API in order to send requirements from the user to the system (for example 'Vacation mode' activation)
@api_bp.route('/api/config', methods=['POST'])
def config_system():
    """
    Endpoint for system configuration (e.g., Vacation Mode)
    """
    config_data = request.get_json()

    # Configuration request's data validation
    if not config_data:
         return jsonify({"error": "No configuration data provided"}), 400

    mode = config_data.get('mode')
    # Mode request handling
    if mode == "Vacation":
        # TODO: Insert function to stop the AI model from processing data sent while vacation mode is active

        # Return status without updating the AI model
        return jsonify({"status": "success", "mode": "Vacation", "model_updated": False}), 200

    # Successfully send data for the AI model
    return jsonify({"status": "success", "message": "Configuration updated"}), 200
