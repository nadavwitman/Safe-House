from datetime import datetime, timezone, timedelta
from firebase_admin import firestore

from database.repositories.client import db


def get_house_activity_meta(house_id):
    """Single house-doc read for the dashboard: vacation flag + per-sensor last-activity.

    Returns {'is_vacation': bool, 'last_activity': {sensor_index(int): iso_time_str}}.
    The last-activity map is maintained by log_vector_reading, so it reflects the
    last time each sensor fired regardless of how far back that was.
    """
    doc = db.collection('houses').document(house_id).get()
    if not doc.exists:
        return {'is_vacation': False, 'last_activity': {}}
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
    return {'is_vacation': data.get('is_vacation', False), 'last_activity': last_activity}


def log_ai_decision(house_id, sensor_id, decision, note=None, title=None):
    """
    Logs the finalized, normalized AI decision into a dedicated subcollection.
    Essential for historical parsing and the weekly summary generation pipeline.
    `decision` stays the clean severity ('Emergency'/'Warning') so consumers that key
    off it are unaffected; `title` and `note` carry the focused, human-readable message
    the app displays.
    """
    doc_ref = db.collection('houses').document(house_id).collection('ai_decisions').document()
    payload = {
        'sensor_id': sensor_id,
        'decision': decision,
        'type': 'ai',
        'time': datetime.now(timezone.utc)
    }
    if title:
        payload['title'] = title
    if note:
        payload['note'] = note
    doc_ref.set(payload)


def get_alert_history(house_id, limit=50):
    """Returns the most recent alerts (AI + device-offline) for a house, newest first."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=90)
    docs = (
        db.collection('houses').document(house_id)
        .collection('ai_decisions')
        .where('time', '>=', cutoff)
        .order_by('time', direction=firestore.Query.DESCENDING)
        .limit(limit)
        .get()
    )
    results = []
    for doc in docs:
        d = doc.to_dict()
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
    return results
