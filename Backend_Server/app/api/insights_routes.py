import traceback

from firebase_admin import firestore
from flask import Blueprint, jsonify, request

import database.database as database
from app.weekly_summary.report_generator import run_insights_pipeline
from app.auth.decorators import house_member_required

insights_bp = Blueprint('insights', __name__)


@insights_bp.route('/api/insights/weekly', methods=['POST'])
@house_member_required
def trigger_weekly_insights():
    try:
        data = request.get_json() or {}
        house_id = data.get('house_id', 'default_house')

        raw_docs = database.get_weekly_sensor_data(house_id)
        if not raw_docs:
            return jsonify({
                "status": "no_data",
                "message": "No sensor data found for the past 7 days.",
            }), 200

        metrics, ai_output = run_insights_pipeline(house_id, raw_docs)

        if metrics is None:
            return jsonify({
                "status": "insufficient_data",
                "message": "At least 5 days of data are required to generate a report.",
            }), 200

        period_start = min(d['date'] for d in metrics['days'])
        period_end = max(d['date'] for d in metrics['days'])

        report_dict = {
            'period': {'start': period_start, 'end': period_end},
            'generated_at': firestore.SERVER_TIMESTAMP,
            'metrics': metrics,
            'ai_output': ai_output,
        }
        database.save_weekly_report(house_id, report_dict)

        return jsonify({
            "status": "success",
            "house_id": house_id,
            "period": report_dict['period'],
            "summary_preview": ai_output.get("summary", "")[:150],
        }), 200

    except RuntimeError as e:
        return jsonify({"error": str(e)}), 503

    except Exception as e:
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@insights_bp.route('/api/insights/weekly/<house_id>', methods=['GET'])
@house_member_required
def get_weekly_report(house_id):
    report = database.get_weekly_report(house_id)
    if not report:
        return jsonify({"status": "no_report", "message": "No weekly report available yet."}), 200

    return jsonify({
        "status": "success",
        "house_id": house_id,
        "period": report.get("period"),
        "generated_at": str(report.get("generated_at", "")),
        "metrics": report.get("metrics"),
        "ai_output": report.get("ai_output"),
    }), 200


@insights_bp.route('/api/insights/alerts/<house_id>', methods=['GET'])
@house_member_required
def get_alerts(house_id):
    """Returns the recent alert history (AI anomalies + device-offline) for a house."""
    limit = min(int(request.args.get('limit', 50)), 100)
    exclude_normal = request.args.get('exclude_normal', 'false').lower() == 'true'
    alerts = database.get_alert_history(house_id, limit=limit, exclude_normal=exclude_normal)
    return jsonify({'alerts': alerts}), 200
