"""
Human-readable alert composition.

Turns the AI's structured verdict — severity (Warning/Emergency), activity type
(Stuck/Fall, Abnormal Agitation, Unusual Routine) and the room the model
reconstructed worst — into a focused, situation-specific notification.

Deterministic and template-based (no LLM): a small catalog keyed by
(activity_type, severity), with {name}, {room}, {time} interpolated.

Honesty constraints baked in:
  * The room is only a SIGN of where the anomaly is (the worst-reconstructed
    location column), never a certainty — every message hedges with "most likely
    near", and we never claim a fall was "detected" (PIR can't measure that).
  * Extended stillness whose last known location is the entrance door is surfaced
    as a possible out-of-home situation (the resident may be stuck outside).
  * "last seen / last active" messages (Stuck/Fall, out-of-home) show the REAL time a
    sensor last fired — with the date and how many days ago when it wasn't today — so a
    week-old signal never reads as if it just happened. Present-tense messages
    (agitation, off-routine) use the current clock. All times are resident-local
    (Asia/Jerusalem, matching the preprocessing pipeline).
"""
import pandas as pd

from app.core.device_health import SENSOR_NAMES, DOOR_INDEX

LOCAL_TZ = 'Asia/Jerusalem'

# activity_type -> severity -> (title, body_template)
_CATALOG = {
    'Stuck/Fall': {
        'Emergency': (
            'Emergency — possible fall or immobility',
            "There's been no movement for an extended period, most likely near the "
            "{room}, where {name} was last active around {time}. {name} may have fallen "
            "or be unable to move — please check on them right away.",
        ),
        'Warning': (
            'Warning — unusually still',
            "Very little movement recently, most likely near the {room} (last seen "
            "around {time}). It may be nothing, but it's worth making sure {name} is okay.",
        ),
    },
    'Abnormal Agitation': {
        'Emergency': (
            'Emergency — intense restlessness',
            "An unusually high amount of movement is showing, most likely around the "
            "{room}, around {time}. This can signal distress, confusion, or wandering — "
            "please check on {name}.",
        ),
        'Warning': (
            'Warning — more restless than usual',
            "{name} seems more active than usual, most likely around the {room}, around "
            "{time}. Keep an eye out in case it continues.",
        ),
    },
    'Unusual Routine': {
        'Emergency': (
            'Emergency — strongly off-routine',
            "Activity right now is very different from {name}'s usual pattern for {time}, "
            "most likely around the {room}. Please check in.",
        ),
        'Warning': (
            'Warning — off-routine activity',
            "A slightly unusual pattern for {time}, most likely around the {room}. "
            "Probably fine, but worth a look.",
        ),
    },
}

# Special case: extended stillness whose last known location is the entrance door →
# the resident likely went out and hasn't returned (they may be stuck outside).
_OUT_OF_HOME = {
    'Emergency': (
        'Emergency — no return detected',
        "There's been no movement since {name} was last near the Front Door around "
        "{time}. They may be stuck outside, out and not back yet, or in need of help — "
        "please check on them.",
    ),
    'Warning': (
        'Warning — quiet since the door',
        "No activity since {name} was last near the Front Door around {time}. They may "
        "simply be out — worth a quick check.",
    ),
}


def _room_name(room_index):
    # Templates always read "the {room}", so the fallback must slot in after "the"
    # without a duplicate article — "the home area", not "the the home".
    if room_index is None:
        return 'home area'
    return SENSOR_NAMES.get(room_index, f'Sensor {room_index}')


def _is_door_only(location):
    """True when the sticky last-known location is exactly the entrance door."""
    return (
        isinstance(location, list)
        and len(location) > DOOR_INDEX
        and location[DOOR_INDEX] == 1
        and sum(1 for v in location if v in (1, True)) == 1
    )


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


def _format_last_seen(dt, now):
    """Formats a real last-activity time and makes staleness obvious: a clock time if it
    was today, otherwise the clock plus the date and how many days ago — so a week-old
    signal never reads as if it happened just now."""
    if dt is None:
        return 'an unknown time'
    clock = format_clock(dt)
    if dt.date() == now.date():
        return clock
    date_str = f"{dt.strftime('%b')} {dt.day}"   # e.g. "Jul 22"
    days = (now.date() - dt.date()).days
    if days == 1:
        return f'{clock} yesterday ({date_str})'
    return f'{clock} on {date_str} ({days} days ago)'


# Activity types whose message says "last active / last seen" — these must use the REAL
# last-activity time, never the current clock, or a stale signal reads as if it just happened.
_LAST_SEEN_ACTIVITIES = {'Stuck/Fall'}


def compose_alert_message(severity, activity_type, room_index, resident_name,
                          when_dt=None, last_seen_dt=None, last_location=None,
                          faulty_sensor_names=None):
    """Builds (title, body) for a Warning/Emergency.

    @severity            : 'Warning' | 'Emergency'
    @activity_type       : 'Stuck/Fall' | 'Abnormal Agitation' | 'Unusual Routine' | None
    @room_index          : index of the most-anomalous room (or None)
    @resident_name       : the resident's name, for a personal message
    @when_dt             : "now" for present-tense messages; defaults to resident-local now
    @last_seen_dt        : REAL time a sensor last fired — used by the Stuck/Fall and
                           out-of-home messages that say "last active/seen around {time}"
    @last_location       : sticky current_location one-hot (drives the out-of-home case)
    @faulty_sensor_names : appended as a device-fault caveat (never suppresses the alert)
    """
    name = resident_name or 'your resident'
    now_local = _to_local(when_dt) or local_now()
    now_str = format_clock(now_local)
    last_seen_str = _format_last_seen(_to_local(last_seen_dt), now_local)

    # Out-of-home: extended stillness whose last known location is the front door.
    if activity_type == 'Stuck/Fall' and _is_door_only(last_location) and severity in _OUT_OF_HOME:
        title, body_t = _OUT_OF_HOME[severity]
        time_str = last_seen_str
    else:
        # Fall back to the "Unusual Routine" family for any unrecognised activity type.
        by_severity = _CATALOG.get(activity_type) or _CATALOG['Unusual Routine']
        title, body_t = by_severity.get(severity, by_severity['Warning'])
        time_str = last_seen_str if activity_type in _LAST_SEEN_ACTIVITIES else now_str

    body = body_t.format(name=name, room=_room_name(room_index), time=time_str)

    if faulty_sensor_names:
        joined = ', '.join(faulty_sensor_names)
        body += (f" Note: the {joined} sensor(s) haven't reported recently and may be "
                 f"faulty — please verify both the resident and the device.")

    return title, body
