from flask import Blueprint, jsonify, request

import database.database as database
from app.auth.decorators import house_member_required

insights_bp = Blueprint('insights', __name__)

# There is no route here that generates a report. Reports are written by the
# Sunday scheduler (app/__init__.py) and by the catch-up that its failures
# trigger (app/weekly_summary/catchup.py) — both server-side, both gated. The
# on-demand POST that used to live here was the app's Generate button; with that
# button gone it had no caller, and leaving it would have kept an unmetered
# Gemini call reachable by any house member's token.


@insights_bp.route('/api/insights/weekly/<house_id>', methods=['GET'])
@house_member_required
def get_weekly_report(house_id):
    report = database.get_weekly_report(house_id)
    if not report:
        return jsonify({"status": "no_report", "message": "No weekly report available yet."}), 200

    # ISO-8601, not str(): the stored value is a DatetimeWithNanoseconds, whose repr
    # no date parser accepts. The app both displays this ("Generated Sun 6:02 AM")
    # and matches it against the weekly_report_at it gets from the dashboard poll to
    # decide whether its cached copy is current, so the two must be the same format.
    generated_at = report.get("generated_at")
    if hasattr(generated_at, 'isoformat'):
        generated_at = generated_at.isoformat()

    return jsonify({
        "status": "success",
        "house_id": house_id,
        "period": report.get("period"),
        "generated_at": generated_at,
        "metrics": report.get("metrics"),
        "ai_output": report.get("ai_output"),
    }), 200


@insights_bp.route('/api/insights/alerts/<house_id>', methods=['GET'])
@house_member_required
def get_alerts(house_id):
    """Returns the last 7 days of alerts (AI anomalies + device-offline) for a house.

    The window is fixed, not a parameter — 7 days is what the alerts screen shows and
    the only thing this endpoint serves. Nothing needs older history: the dashboard
    reads the current alert's text straight off the house document.
    """
    limit = min(int(request.args.get('limit', 50)), 100)
    exclude_normal = request.args.get('exclude_normal', 'false').lower() == 'true'
    alerts = database.get_alert_history(house_id, limit=limit, exclude_normal=exclude_normal)
    return jsonify({'alerts': alerts}), 200
