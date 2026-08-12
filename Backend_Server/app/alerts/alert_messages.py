"""
Human-readable alert composition.

Turns the AI's structured verdict — severity (Warning/Emergency), anomaly type
(Static Location, Missing Usage, High Frequency, from model_handler.evaluate_window)
and the zone it's centred on — into a focused, situation-specific notification.

Deterministic and template-based (no LLM): a small catalog keyed by
(anomaly_type, severity), with {name}, {room}, {time} interpolated.

Honesty constraints baked in:
  * The room is only a SIGN of where the anomaly is (the zone the score is attached
    to), never a certainty — every message hedges with "most likely near", and we
    never claim a fall was "detected" (PIR can't measure that).
  * All times are resident-local (Asia/Jerusalem, matching the preprocessing pipeline).
"""
import pandas as pd

from app.monitoring.device_health import SENSOR_NAMES

LOCAL_TZ = 'Asia/Jerusalem'

# anomaly_type -> severity -> (title, body_template)
_CATALOG = {
    'Static Location': {
        'Emergency': (
            'Emergency — extended time in one place',
            "{name} has been in the {room} much longer than their usual pattern. This "
            "can indicate they're stuck, unwell, or unable to move — please check on "
            "them right away.",
        ),
        'Warning': (
            'Warning — longer than usual in one place',
            "{name} has been in the {room} longer than their usual routine, around "
            "{time}. Probably fine, but worth making sure they're okay.",
        ),
    },
    'Missing Usage': {
        'Warning': (
            'Warning — usual activity missing',
            "{name} hasn't used the {room} in longer than expected for this time of "
            "day (as of {time}). It may be nothing, but it's worth checking in.",
        ),
    },
    'High Frequency': {
        'Warning': (
            'Warning — more activity than usual',
            "{name} is visiting the {room} more often than usual, around {time}. This "
            "can signal restlessness, confusion, or distress — worth keeping an eye on.",
        ),
    },
}


def _room_name(room_index):
    # Templates always read "the {room}", so the fallback must slot in after "the"
    # without a duplicate article — "the home area", not "the the home".
    if room_index is None:
        return 'home area'
    return SENSOR_NAMES.get(room_index, f'Sensor {room_index}')


def format_clock(dt):
    """12-hour clock with minutes, leading zero stripped, e.g. '2:15 PM'."""
    return dt.strftime('%I:%M %p').lstrip('0')


def local_now():
    """Current resident-local wall-clock time (tz-aware)."""
    return pd.Timestamp.now(tz=LOCAL_TZ)


def _to_local(dt):
    """Converts any datetime (naive treated as UTC) to a resident-local tz-aware stamp."""
    if dt is None:
        return None
    ts = pd.Timestamp(dt)
    if ts.tzinfo is None:
        ts = ts.tz_localize('UTC')
    return ts.tz_convert(LOCAL_TZ)


def compose_alert_message(severity, activity_type, room_index, resident_name,
                          when_dt=None, last_location=None,
                          faulty_sensor_names=None):
    """Builds (title, body) for a Warning/Emergency.

    @severity            : 'Warning' | 'Emergency'
    @activity_type       : 'Static Location' | 'Missing Usage' | 'High Frequency' | None
                           (model_handler.evaluate_window's anomaly_type)
    @room_index          : the zone the score is attached to (or None)
    @resident_name       : the resident's name, for a personal message
    @when_dt             : "now" for the message; defaults to resident-local now
    @last_location       : unused (kept for call-site compatibility)
    @faulty_sensor_names : appended as a device-fault caveat (never suppresses the alert)
    """
    name = resident_name or 'your resident'
    now_local = _to_local(when_dt) or local_now()
    now_str = format_clock(now_local)

    by_severity = _CATALOG.get(activity_type) or _CATALOG['High Frequency']
    title, body_t = by_severity.get(severity, by_severity['Warning'])

    body = body_t.format(name=name, room=_room_name(room_index), time=now_str)

    if faulty_sensor_names:
        joined = ', '.join(faulty_sensor_names)
        body += (f" Note: the {joined} sensor(s) haven't reported recently and may be "
                 f"faulty — please verify both the resident and the device.")

    return title, body
