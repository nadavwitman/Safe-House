"""
Story 3 — Live Status: dashboard polls /api/house/<id>/status and gets the
denormalized house state in a single Firestore read.
"""
from helpers import run_house_status


def test_status_endpoint_returns_current_house_state():
    meta = {
        'is_vacation': False,
        'last_activity': {0: '2026-08-20T09:00:00Z'},
        'current_status': 'Normal',
        'current_status_at': '2026-08-20T09:00:00Z',
        'catchup_attempted_at': None,
        'current_alert_id': None,
        'current_alert_title': None,
        'current_alert_note': None,
        'weekly_report_at': '2026-08-16T00:00:00Z',
    }

    with run_house_status(meta) as response:
        assert response.status_code == 200
        body = response.get_json()
        assert body['current_status'] == 'Normal'
        assert body['is_vacation'] is False
        assert body['weekly_report_at'] == meta['weekly_report_at']
