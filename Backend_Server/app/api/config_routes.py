from flask import Blueprint, request, jsonify
from app.core.data_buffer import sensor_buffer
from app.auth.decorators import house_member_required
import database.database as database

# Define the blueprint for configuration routing
config_bp = Blueprint('config', __name__)

@config_bp.route('/api/config', methods=['POST'])
@house_member_required
def config_system():
    """Endpoint for system configuration (e.g., Vacation Mode)."""
    config_data = request.get_json()

    if not config_data:
        return jsonify({"error": "No configuration data provided"}), 400

    mode = config_data.get('mode')
    house_id = config_data.get('house_id', 'default_house')

    if mode == "Vacation":
        sensor_buffer.is_active = False
        sensor_buffer.clear_house(house_id)
        database.set_vacation_mode(house_id, True)
        return jsonify({"status": "success", "mode": "Vacation", "model_updated": False}), 200

    elif mode == "Normal":
        sensor_buffer.is_active = True
        database.set_vacation_mode(house_id, False)
        return jsonify({"status": "success", "mode": "Normal", "model_updated": True}), 200

    return jsonify({"status": "success", "message": "Configuration updated"}), 200


@config_bp.route('/api/config/vacation-schedule', methods=['POST'])
@house_member_required
def set_vacation_schedule():
    data = request.get_json() or {}
    house_id = data.get('house_id')
    schedule = data.get('schedule')
    if not house_id or not schedule:
        return jsonify({'error': 'house_id and schedule are required'}), 400
    for field in ('startDate', 'startTime', 'endDate', 'endTime'):
        if not schedule.get(field):
            return jsonify({'error': f'{field} is required in schedule'}), 400
    database.set_vacation_schedule(house_id, schedule)
    return jsonify({'status': 'success'}), 200


@config_bp.route('/api/config/vacation-schedule', methods=['DELETE'])
@house_member_required
def clear_vacation_schedule():
    data = request.get_json() or {}
    house_id = data.get('house_id')
    if not house_id:
        return jsonify({'error': 'house_id is required'}), 400
    database.clear_vacation_schedule(house_id)
    return jsonify({'status': 'success'}), 200
