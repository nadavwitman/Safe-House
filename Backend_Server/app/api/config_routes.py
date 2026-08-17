from flask import Blueprint, request, jsonify
from app.state.data_buffer import sensor_buffer
from app.auth.decorators import house_member_required
from app.scheduling.vacation_window import parse_window, now_utc
import database.database as database

# Define the blueprint for configuration routing
config_bp = Blueprint('config', __name__)


@config_bp.route('/api/config', methods=['POST'])
@house_member_required
def config_system():
    """Endpoint for system configuration (e.g., Vacation Mode).

    Every response reports the vacation flag as it stands *after* the change,
    along with whether a stored trip was dropped. These endpoints move that state
    as a side effect, and the app cannot re-derive it without duplicating the
    window arithmetic below — so the server states the outcome and the app
    applies it verbatim.
    """
    config_data = request.get_json()

    if not config_data:
        return jsonify({"error": "No configuration data provided"}), 400

    mode = config_data.get('mode')
    house_id = config_data.get('house_id', 'default_house')

    if mode == "Vacation":
        sensor_buffer.pause_house(house_id)
        sensor_buffer.clear_house(house_id)
        database.set_vacation_mode(house_id, True)
        return jsonify({
            "status": "success",
            "mode": "Vacation",
            "is_vacation": True,
            "schedule_cleared": False,
            "model_updated": False,
        }), 200

    elif mode == "Normal":
        sensor_buffer.resume_house(house_id)
        database.set_vacation_mode(house_id, False)
        # Only clear a schedule that already started — turning monitoring back on
        # ends the trip you are on, it does not cancel one you have planned.
        schedule = database.get_vacation_schedule(house_id)
        window = parse_window(schedule) if schedule else None
        schedule_cleared = False
        if window and window[0] <= now_utc():
            database.clear_vacation_schedule(house_id)
            schedule_cleared = True
        return jsonify({
            "status": "success",
            "mode": "Normal",
            "is_vacation": False,
            "schedule_cleared": schedule_cleared,
            "model_updated": True,
        }), 200

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

    # Parsed before the write, not after: a schedule this server cannot resolve
    # into a window is one the scheduler will skip forever, so it would sit in
    # Firestore looking active while never starting or ending a trip.
    window = parse_window(schedule)
    if window is None:
        return jsonify({'error': 'schedule dates/times are malformed'}), 400
    start, end = window
    if end <= start:
        return jsonify({'error': 'schedule end must be after start'}), 400

    database.set_vacation_schedule(house_id, schedule)

    # Immediately activate if we're already within the scheduled window — the
    # 5-minute scheduler would otherwise leave the house monitored for up to
    # five minutes of a trip the user just said had already begun.
    activated = start <= now_utc() <= end
    if activated:
        database.set_vacation_mode(house_id, True)
        sensor_buffer.pause_house(house_id)
        sensor_buffer.clear_house(house_id)

    return jsonify({'status': 'success', 'is_vacation': activated}), 200


@config_bp.route('/api/config/vacation-schedule', methods=['DELETE'])
@house_member_required
def clear_vacation_schedule():
    data = request.get_json() or {}
    house_id = data.get('house_id')
    if not house_id:
        return jsonify({'error': 'house_id is required'}), 400
    database.clear_vacation_schedule(house_id)
    # Cancelling the trip also ends any pause it caused, so monitoring resumes
    # here — which is why the response has to say so.
    database.set_vacation_mode(house_id, False)
    sensor_buffer.resume_house(house_id)
    return jsonify({'status': 'success', 'is_vacation': False}), 200
