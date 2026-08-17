"""Resolving a stored vacation schedule into absolute UTC instants.

A schedule records a trip in the family's local wall-clock time ("2026-05-22",
"08:30"), because that is what the user typed and what the app renders back to
them. Comparing those strings against the server's own clock quietly assumed the
server ran in the same timezone as the phone that wrote them: on a UTC host with
a UTC+3 user, a trip set to begin at 09:00 began at noon, and monitoring stayed
live for three hours after the resident left.

The app now sends the absolute instants (`startUtc`/`endUtc`) alongside the
wall-clock fields, computed on the device where the timezone — including whatever
DST offset applies on that particular date — is actually known. Those are what we
compare. The wall-clock fields stay in the document because they are the user's
stated intent and the only sensible thing to display back.

Schedules written before this carry no UTC fields; for them we fall back to the
old naive-local reading, which keeps trips already sitting in Firestore working
instead of dropping them. That fallback is exactly as timezone-wrong as it always
was, and corrects itself the next time the user saves the trip.
"""
from datetime import datetime, timezone


def _parse_utc(value):
    """Reads an ISO-8601 instant that carries an offset. Returns None for the
    naive or malformed values that mean 'fall back to the wall-clock fields'."""
    if not isinstance(value, str) or not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace('Z', '+00:00'))
    except (ValueError, TypeError):
        return None
    if dt.tzinfo is None:
        return None
    return dt.astimezone(timezone.utc)


def _parse_wall_clock(date_str, time_str):
    """Legacy path: interprets a zone-less date/time in the server's own
    timezone, which is the only clock available once the writer's is unknown."""
    if not isinstance(date_str, str) or not isinstance(time_str, str):
        return None
    try:
        naive = datetime.fromisoformat(f"{date_str}T{time_str}")
    except (ValueError, TypeError):
        return None
    # astimezone() on a naive datetime attaches the system zone, reproducing the
    # original behaviour rather than inventing a new one.
    return naive.astimezone(timezone.utc)


def parse_window(schedule):
    """Returns the trip as a (start, end) pair of tz-aware UTC datetimes.

    Returns None if the schedule is missing, malformed, or only half-specified —
    callers treat that as "no usable trip" and leave vacation mode alone, since
    acting on a half-parsed window is worse than ignoring it.
    """
    if not isinstance(schedule, dict):
        return None

    start = _parse_utc(schedule.get('startUtc')) or _parse_wall_clock(
        schedule.get('startDate'), schedule.get('startTime'))
    end = _parse_utc(schedule.get('endUtc')) or _parse_wall_clock(
        schedule.get('endDate'), schedule.get('endTime'))

    if start is None or end is None:
        return None
    return start, end


def now_utc():
    """The clock every comparison in this module is made against."""
    return datetime.now(timezone.utc)
