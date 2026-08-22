from flask import Blueprint, request, jsonify
from app.state.house_mask_store import house_mask_store
from app.auth.decorators import admin_required, house_member_required
from app.weekly_summary.catchup import maybe_catch_up
import database.database as database

house_bp = Blueprint('house', __name__)


@house_bp.route('/api/house/<house_id>/status', methods=['GET'])
@house_member_required
def get_house_status(house_id):
    """Live dashboard poll — costs exactly ONE Firestore document read.

    Everything the home screen renders is denormalized onto the house document:
    the vacation flag, the per-sensor last-seen map (by log_vector_reading) and the
    current AI status (by log_ai_decision). So this touches no subcollection at all.

    The dashboard used to poll a raw-readings endpoint at limit=50 every 5 seconds
    and discard all 50 readings, then separately query ai_decisions for the live
    status — 51+ reads per poll, ~36k/hour, the bulk of our Firestore bill. That
    endpoint has since been removed; this is the only thing the home screen polls.
    """
    meta = database.get_house_activity_meta(house_id)

    # A running app is the trigger for rescuing an overdue weekly report: if the
    # Sunday job never produced one, this notices and regenerates in the
    # background. Returns immediately, and costs nothing when the report is
    # current — both timestamps it needs came from the read above.
    maybe_catch_up(house_id, meta['weekly_report_at'], meta['catchup_attempted_at'], meta['is_vacation'])

    return jsonify({
        'is_vacation': meta['is_vacation'],
        'last_activity': meta['last_activity'],
        'current_status': meta['current_status'],
        # Timestamp of the current status, which the banner renders as the alert's
        # time. A change in it means a different anomaly has taken over.
        'current_status_at': meta['current_status_at'],
        # Everything else the banner draws, written by log_ai_decision in the same
        # batch as the status. The dashboard used to follow every status change with
        # a query into ai_decisions to get this text; carrying it here removes that
        # request entirely, and removes the question of how far back to look for it.
        # All three are null on a house recovered to Normal (no alert to describe)
        # and on one whose current alert predates these fields.
        'current_alert_id': meta['current_alert_id'],
        'current_alert_title': meta['current_alert_title'],
        'current_alert_note': meta['current_alert_note'],
        # Change signal for the Summary tab, not something the dashboard draws. The
        # app caches the weekly report on the device and only re-downloads it when
        # this timestamp differs from the cached copy's, so a report that lands late
        # (a retried run, a house that only just reached 5 days of data) is picked up
        # within one poll without the summary screen ever polling on its own.
        'weekly_report_at': meta['weekly_report_at'],
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
