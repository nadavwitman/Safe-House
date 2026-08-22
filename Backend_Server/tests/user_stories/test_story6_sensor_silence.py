"""
Story 6 — Sensor Silence Alert: a sensor quiet past its fault threshold
triggers a "may need attention" alert.
"""
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from helpers import make_health_state
import app.monitoring.device_health as device_health


def test_silent_sensor_past_threshold_triggers_fault_alert():
    now = datetime.now(timezone.utc)
    state = make_health_state(
        last_sensor_activity={1: now - timedelta(hours=25)},  # Kitchen, > 24h threshold
    )

    with patch('app.monitoring.device_health.database') as mock_db, \
         patch('app.monitoring.device_health.notifications') as mock_notifications:
        mock_db.get_house_health_doc.return_value = state
        device_health._check_house_sensor_health('house_1', now)

    assert mock_notifications.trigger_sensor_fault_alert.called
    args, _ = mock_notifications.trigger_sensor_fault_alert.call_args
    assert args[0] == 'house_1'
    assert args[1] == 'Kitchen'
