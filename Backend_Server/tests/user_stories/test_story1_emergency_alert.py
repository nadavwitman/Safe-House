"""
Story 1 — Emergency Alert: LSTM detects extreme inactivity -> immediate push.
"""
from helpers import default_house, run_analyze


def test_emergency_decision_sends_push_alert():
    with run_analyze(default_house(), ai_decision='Emergency',
                      ai_meta={'severity': 'Emergency', 'activity_type': 'Stuck', 'room_index': 2}) as ctx:
        assert ctx['notifications'].send_alert_push.called
        args, _ = ctx['notifications'].send_alert_push.call_args
        assert 'house_1' in args
