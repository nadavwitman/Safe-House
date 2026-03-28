from flask import Blueprint, request, jsonify
from app.core.house_mask_store import house_mask_store

house_bp = Blueprint('house', __name__)


@house_bp.route('/api/house/sensor-mask', methods=['POST'])
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
