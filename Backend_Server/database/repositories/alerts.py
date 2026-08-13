from datetime import datetime, timezone, timedelta
from firebase_admin import firestore

from database.repositories.client import db


def get_house_activity_meta(house_id):
    """Single house-doc read for the dashboard: vacation flag, per-sensor
    last-activity, and the current AI status.

    Returns {'is_vacation': bool,
             'last_activity': {sensor_index(int): iso_time_str},
             'current_status': 'Normal'|'Warning'|'Emergency'}.

    The last-activity map is maintained by log_vector_reading and current_status by
    log_ai_decision, so both reflect live state without scanning any subcollection —
    the whole dashboard renders off this one document.
    """
    doc = db.collection('houses').document(house_id).get()
    if not doc.exists:
        return {'is_vacation': False, 'last_activity': {}, 'current_status': 'Normal'}
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
    return {
        'is_vacation': data.get('is_vacation', False),
        'last_activity': last_activity,
        # Absent on houses that predate this field — a house with no recorded
        # transition has never left Normal.
        'current_status': data.get('current_status') or 'Normal',
    }


def log_ai_decision(house_id, sensor_id, decision, note=None, title=None):
    """
    Records a CHANGE in the house's AI status. Callers must only invoke this on a
    genuine transition (see app/api/analyze_routes.py) — ai_decisions is an event
    log of state changes, not a per-reading heartbeat.

    Writes two documents in one batch:
      * an immutable ai_decisions entry — the alert history the app displays
      * current_status on the house doc — the live signal the dashboard polls,
        so reading "what is the status right now" costs no subcollection query

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
    batch = db.batch()
    batch.set(house_ref.collection('ai_decisions').document(), payload)
    batch.set(house_ref, {'current_status': decision, 'current_status_at': now}, merge=True)
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
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=90)
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
