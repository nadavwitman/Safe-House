import os

from flask import Blueprint, jsonify, request

import database.database as database
from app.auth.decorators import house_member_required
from app.weekly_summary.report_generator import generate_and_store

insights_bp = Blueprint('insights', __name__)

# Reports are normally written by the Sunday scheduler (app/__init__.py) and by
# the catch-up that its failures trigger (app/weekly_summary/catchup.py) — both
# server-side, both gated. The on-demand POST that used to live here was the
# app's Generate button; with that button gone it had no caller, and leaving it
# would have kept an unmetered Gemini call reachable by any house member's
# token. The /ops route below is its replacement: gated by a server-side key
# (like create-admin's X-Admin-Creation-Key), never shipped to the app, so it's
# only ever called from a terminal with access to the deployment's secrets —
# not reachable through any house member's JWT.


@insights_bp.route('/api/insights/ops/regenerate/<house_id>', methods=['POST'])
def regenerate_weekly_report(house_id):
    """Force-regenerates the current house's weekly report on demand.

    Terminal/ops use only (e.g. re-running after a pipeline fix, or a report
    stuck on stale data) — not exposed to the app. Runs `generate_and_store`
    synchronously and burns one Gemini call per request, so it is deliberately
    key-gated rather than tied to any user's auth token.
    """
    key = request.headers.get('X-Ops-Key', '')
    if not key or key != os.environ.get('OPS_API_KEY', ''):
        return jsonify({'error': 'Unauthorized'}), 401

    status, _ = generate_and_store(house_id)
    if status != 'success':
        return jsonify({'status': status}), 200

    # Re-read rather than return generate_and_store's own report dict: that dict's
    # generated_at is still the unresolved firestore.SERVER_TIMESTAMP sentinel
    # (not JSON-serializable) until Firestore resolves it on write.
    report = database.get_weekly_report(house_id)
    generated_at = report.get("generated_at")
    if hasattr(generated_at, 'isoformat'):
        generated_at = generated_at.isoformat()

    return jsonify({
        'status': status,
        'house_id': house_id,
        'period': report.get('period'),
        'generated_at': generated_at,
        'metrics': report.get('metrics'),
        'ai_output': report.get('ai_output'),
    }), 200


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
