from datetime import datetime, timezone, timedelta
from firebase_admin import firestore

from database.repositories.client import db

# How far back the alerts screen looks. The screen says "Last 7 days" in its header,
# so this is the one place that number is defined.
ALERT_WINDOW_DAYS = 7


# Exactly the fields the dashboard poll renders or compares against. The house
# document also carries the full weekly_report (7 days of metrics plus the AI
# text) and the EMA baseline; without this mask every 30-second poll downloads
# both. Nested paths are masked at the leaf, so weekly_report.generated_at costs
# a timestamp rather than the whole report.
_ACTIVITY_META_FIELDS = [
    'is_vacation',
    'last_sensor_activity',
    'current_status',
    'current_status_at',
    'current_alert_key',
    'current_alert_id',
    'current_alert_title',
    'current_alert_note',
    'weekly_report.generated_at',
    'catchup_attempted_at',
]


def get_house_activity_meta(house_id):
    """Single house-doc read for the dashboard: vacation flag, per-sensor
    last-activity, the current AI status, and the weekly report's age.

    Returns {'is_vacation': bool,
             'last_activity': {sensor_index(int): iso_time_str},
             'current_status': 'Normal'|'Warning'|'Emergency',
             'current_status_at': iso_time_str|None,
             'current_alert_key': str|None,
             'current_alert_id': str|None,
             'current_alert_title': str|None,
             'current_alert_note': str|None,
             'weekly_report_at': iso_time_str|None,
             'catchup_attempted_at': timestamp|None}.

    The last-activity map is maintained by log_vector_reading and current_status by
    log_ai_decision, so both reflect live state without scanning any subcollection —
    the whole dashboard renders off this one document.
    """
    doc = db.collection('houses').document(house_id).get(field_paths=_ACTIVITY_META_FIELDS)
    if not doc.exists:
        return {'is_vacation': False, 'last_activity': {}, 'current_status': 'Normal',
                'current_status_at': None, 'current_alert_key': None,
                'current_alert_id': None, 'current_alert_title': None,
                'current_alert_note': None,
                'weekly_report_at': None, 'catchup_attempted_at': None}
    data = doc.to_dict() or {}
    raw = data.get('last_sensor_activity', {}) or {}
    last_activity = {}
    for key, t in raw.items():
        try:
            idx = int(key)
        except (TypeError, ValueError):
            continue
        if hasattr(t, 'isoformat'):
            last_activity[idx] = t.isoformat()
        elif isinstance(t, str):
            last_activity[idx] = t
    status_at = data.get('current_status_at')
    report_at = (data.get('weekly_report') or {}).get('generated_at')
    return {
        'is_vacation': data.get('is_vacation', False),
        'last_activity': last_activity,
        # Absent on houses that predate this field — a house with no recorded
        # transition has never left Normal.
        'current_status': data.get('current_status') or 'Normal',
        # When the current status was entered. The dashboard uses this both as the
        # alert's timestamp and as a change signal: it only re-fetches the alert's
        # title/note when this moves, so a house sitting in Warning costs no reads
        # beyond this one document.
        'current_status_at': status_at.isoformat() if hasattr(status_at, 'isoformat') else status_at,
        'current_alert_key': data.get('current_alert_key'),
        # The banner's content, written by log_ai_decision alongside the status.
        # All three are absent on houses whose current alert predates this field,
        # which the app handles with generic per-severity text until the AI next
        # writes a decision and fills them in.
        'current_alert_id': data.get('current_alert_id'),
        'current_alert_title': data.get('current_alert_title'),
        'current_alert_note': data.get('current_alert_note'),
        # When the stored weekly report was written. Nothing on the dashboard renders
        # it — the Summary tab uses it as a cache key, re-downloading the report only
        # when this moves. Riding along on a read the dashboard already makes is what
        # keeps the summary at zero polling cost of its own.
        'weekly_report_at': report_at.isoformat() if hasattr(report_at, 'isoformat') else report_at,
        # Server-side only, never sent to the app: when a lazy catch-up last tried
        # to rescue an overdue report. Carried on this read so the staleness check
        # costs nothing on the poll path — see app/weekly_summary/catchup.py.
        'catchup_attempted_at': data.get('catchup_attempted_at'),
    }


def log_ai_decision(house_id, sensor_id, decision, note=None, title=None, alert_key=None):
    """
    Records a CHANGE in the house's AI status. Callers must only invoke this on a
    genuine transition (see app/api/analyze_routes.py) — ai_decisions is an event
    log of state changes, not a per-reading heartbeat.

    A "change" is a change of ANOMALY, not merely of severity: moving from a
    Missing-Usage Warning to a High-Frequency Warning is a new alert with a new
    title/note, even though the severity is unchanged. `alert_key` carries that
    finer identity (severity + activity type + zone) and is denormalized onto the
    house doc so a process restart can tell an ongoing alert from a new one
    without re-pushing it — current_status alone is too coarse for that.

    Writes two documents in one batch:
      * an immutable ai_decisions entry — the alert history the app displays
      * current_status on the house doc — the live signal the dashboard polls,
        so reading "what is the status right now" costs no subcollection query

    The title, note and the new entry's document id are denormalized onto the house
    alongside the status. The dashboard needs all three to draw its banner, and
    without them it had to follow up every status change with a query into
    ai_decisions — a second request, and one that could only find the alert if it
    fell inside whatever window that query used. Carrying them here costs nothing:
    they ride along in a batch that was already writing to this document.

    `decision` stays the clean severity ('Normal'/'Warning'/'Emergency') so consumers
    that key off it are unaffected; `title` and `note` carry the focused,
    human-readable message the app displays.

    This used to be called on every analysis cycle, which wrote ~1,440 documents a
    day per house and forced get_alert_history to over-fetch 10x to find the handful
    of non-Normal entries buried among them.
    """
    now = datetime.now(timezone.utc)
    payload = {
        'sensor_id': sensor_id,
        'decision': decision,
        'type': 'ai',
        'time': now,
    }
    if title:
        payload['title'] = title
    if note:
        payload['note'] = note

    house_ref = db.collection('houses').document(house_id)
    # The ref is created up front rather than inline so its id can be denormalized
    # onto the house below — that id is what the app acknowledges against, and it
    # has to be the same one this entry is stored under.
    entry_ref = house_ref.collection('ai_decisions').document()

    batch = db.batch()
    batch.set(entry_ref, payload)
    batch.set(house_ref, {
        'current_status': decision,
        'current_status_at': now,
        'current_alert_key': alert_key,
        'current_alert_id': entry_ref.id,
        # Explicitly None rather than omitted on a recovery to Normal, which carries
        # no message: merge=True would otherwise leave the previous alert's text in
        # place and the dashboard would describe an alert that is over.
        'current_alert_title': title,
        'current_alert_note': note,
    }, merge=True)
    batch.commit()


def get_alert_history(house_id, limit=50, exclude_normal=False):
    """Returns the most recent alerts (AI + device-offline) for a house, newest first.

    `exclude_normal` drops 'Normal' AI decisions — with log_ai_decision now writing
    only on a state CHANGE, a Normal entry means "recovered back to normal", which is
    real history but not something the alerts screen lists. We over-fetch slightly and
    filter in Python rather than adding a second Firestore inequality filter on
    `decision` alongside the existing range filter on `time`.

    The multiplier is 3x, not the 10x this used before: back when every analysis cycle
    logged a Normal heartbeat, ~99% of fetched docs were discarded. Now the worst case
    is a house alternating Warning -> Normal -> Warning, i.e. half the entries Normal,
    so 3x leaves comfortable headroom.

    The window is a fixed 7 days, which is exactly what the alerts screen shows, and
    there is no parameter to widen it. The dashboard used to need more — it queried
    here for the text of whatever alert was currently in effect, which for a house
    stuck in Warning for weeks meant reaching well past 7 days. That text now lives
    on the house document itself (see log_ai_decision), so this query serves one
    screen with one window and nothing has a reason to ask for history.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=ALERT_WINDOW_DAYS)
    fetch_limit = limit * 3 if exclude_normal else limit
    docs = (
        db.collection('houses').document(house_id)
        .collection('ai_decisions')
        .where('time', '>=', cutoff)
        .order_by('time', direction=firestore.Query.DESCENDING)
        .limit(fetch_limit)
        .get()
    )
    results = []
    for doc in docs:
        d = doc.to_dict()
        if exclude_normal and d.get('type', 'ai') == 'ai' and d.get('decision') == 'Normal':
            continue
        t = d.get('time')
        results.append({
            # The app acknowledges alerts against this id, so it has to be stable
            # across refetches — the Firestore document id is, and nothing else on
            # the record is guaranteed unique (two sensors can fault in one second).
            'id': doc.id,
            'sensor_id': d.get('sensor_id'),
            'decision': d.get('decision'),
            'type': d.get('type', 'ai'),
            'minutes_silent': d.get('minutes_silent'),
            'hours_silent': d.get('hours_silent'),
            'title': d.get('title'),
            'note': d.get('note'),
            'time': t.isoformat() if hasattr(t, 'isoformat') else str(t),
        })
        if len(results) >= limit:
            break
    return results
