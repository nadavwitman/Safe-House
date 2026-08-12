from flask import Blueprint, request, jsonify
from app.state.data_buffer import sensor_buffer
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
        sensor_buffer.pause_house(house_id)
        sensor_buffer.clear_house(house_id)
        database.set_vacation_mode(house_id, True)
        return jsonify({"status": "success", "mode": "Vacation", "model_updated": False}), 200

    elif mode == "Normal":
        sensor_buffer.resume_house(house_id)
        database.set_vacation_mode(house_id, False)
        # Only clear a schedule that already started — don't delete future trips.
        from datetime import datetime
        schedule = database.get_vacation_schedule(house_id)
        if schedule:
            try:
                start = datetime.fromisoformat(
                    f"{schedule['startDate']}T{schedule['startTime']}")
                if start <= datetime.now():
                    database.clear_vacation_schedule(house_id)
            except Exception:
                pass
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
    # Immediately activate if we're already within the scheduled window.
    from datetime import datetime
    try:
        start = datetime.fromisoformat(f"{schedule['startDate']}T{schedule['startTime']}")
        end = datetime.fromisoformat(f"{schedule['endDate']}T{schedule['endTime']}")
        now = datetime.now()
        if start <= now <= end:
            database.set_vacation_mode(house_id, True)
            from app.state.data_buffer import sensor_buffer
            sensor_buffer.pause_house(house_id)
            sensor_buffer.clear_house(house_id)
    except Exception:
        pass
    return jsonify({'status': 'success'}), 200


@config_bp.route('/api/config/vacation-schedule', methods=['DELETE'])
@house_member_required
def clear_vacation_schedule():
    data = request.get_json() or {}
    house_id = data.get('house_id')
    if not house_id:
        return jsonify({'error': 'house_id is required'}), 400
    database.clear_vacation_schedule(house_id)
    database.set_vacation_mode(house_id, False)
    sensor_buffer.resume_house(house_id)
    return jsonify({'status': 'success'}), 200
