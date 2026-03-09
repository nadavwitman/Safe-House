from flask import Blueprint, request, jsonify
from app.core.data_buffer import sensor_buffer

# Define the API blueprint for modular routing
api_bp = Blueprint('api', __name__)

@api_bp.route('/api/analyze', methods=['POST'])
def analyze_data():
    """
    Endpoint for processing and buffering sensor data
    """
    data = request.get_json()
    
    # Validate that the request body is present
    if not data:
        return jsonify({"error": "No data provided"}), 400
        
    # Store the incoming data in the application's memory buffer
    sensor_buffer.add_reading(data)
    
    # Return processing results and notification status
    return jsonify({
        "status": "success",
        "decision": "Normal", 
        "fcm_status": "Not Sent"
    }), 200