"""
Story 9 — Vacation Mode: pauses LSTM inference/alerts, but keeps tracking
per-sensor last-activity so intrusions can still be noticed.
"""
from helpers import default_house, run_analyze


def test_vacation_mode_skips_inference_but_keeps_activity_tracking():
    with run_analyze(default_house(is_vacation=True)) as ctx:
        assert not ctx['evaluate_buffer_with_AI'].called, "LSTM must not run during vacation"
        assert not ctx['notifications'].send_alert_push.called, "No alerts must fire during vacation"
        assert ctx['database'].log_vector_reading.called, "Last-activity tracking must keep running"
        _, kwargs = ctx['database'].log_vector_reading.call_args
        assert kwargs.get('is_vacation') is True
