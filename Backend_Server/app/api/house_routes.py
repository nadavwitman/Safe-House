from flask import Blueprint, request, jsonify
from app.core.house_mask_store import house_mask_store
from app.auth.decorators import admin_required, house_member_required
import database.database as database

house_bp = Blueprint('house', __name__)


@house_bp.route('/api/house/<house_id>/recent-events', methods=['GET'])
@house_member_required
def get_recent_events(house_id):
    """Returns the most recent sensor readings for the dashboard activity feed,
    plus a per-sensor last-activity map so each sensor's last-seen time is shown
    even if it fired long before the recent window."""
    limit = min(int(request.args.get('limit', 50)), 100)
    readings = database.get_recent_sensor_events(house_id, limit=limit)
    meta = database.get_house_activity_meta(house_id)
    return jsonify({
        'readings': readings,
        'is_vacation': meta['is_vacation'],
        'last_activity': meta['last_activity'],
    }), 200


@house_bp.route('/api/house/sensor-mask', methods=['POST'])
@admin_required
def set_sensor_mask():
    data = request.get_json()
    if not data:
        return jsonify({"error": "No data provided"}), 400

    house_id = data.get('house_id', 'default_house')
    mask = data.get('sensor_mask')

    if mask is None:
        return jsonify({"error": "sensor_mask is required"}), 400
    if not (isinstance(mask, list) and len(mask) == 7 and all(v in (0, 1) for v in mask)):
        return jsonify({"error": "sensor_mask must be a list of exactly 7 values (0 or 1)"}), 400

    house_mask_store.set_mask(house_id, mask)
    return jsonify({"status": "success", "house_id": house_id, "sensor_mask": mask}), 200
