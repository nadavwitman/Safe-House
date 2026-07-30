import os
import time
import random
import firebase_admin
import pandas as pd
from datetime import datetime, timezone, timedelta
from firebase_admin import credentials, firestore

BASE_DIR = os.path.dirname(__file__)
CRED_PATH = os.environ.get('FIREBASE_CREDENTIALS_PATH') or os.path.join(BASE_DIR, 'firebase-credentials.json')

# Initialize Firebase application if not already initialized
if not firebase_admin._apps:
    cred = credentials.Certificate(CRED_PATH)
    firebase_admin.initialize_app(cred, {
        'storageBucket': 'safe-house-492613.appspot.com'
    })

db = firestore.client()


def get_sensor_mask(house_id='default_house'):
    """Returns the 7-bit sensor mask for the house, defaulting to all-active if not set."""
    doc = db.collection('houses').document(house_id).get()
    if doc.exists:
        mask = doc.to_dict().get('sensor_mask')
        if isinstance(mask, list) and len(mask) == 7 and all(v in (0, 1) for v in mask):
            return mask
    return [1, 1, 1, 1, 1, 1, 1]


def set_sensor_mask(house_id, mask):
    """Persists the 7-bit sensor mask to the house document without overwriting other fields."""
    db.collection('houses').document(house_id).set(
        {'sensor_mask': mask},
        merge=True
    )


def log_vector_reading(data, house_id='default_house'):
    """
    Saves a sensor vector reading to a house's subcollection in Firestore.
    Structure: houses -> {house_id} -> sensor_vectors -> {auto_generated_doc}
    """
    raw_time = data.get('time')
    if isinstance(raw_time, str):
        try:
            # Python < 3.11 doesn't support the Z suffix in fromisoformat
            normalised = raw_time.replace('Z', '+00:00')
            dt = datetime.fromisoformat(normalised)
            # If the string has no timezone info the ESP32 sent local time, not UTC.
            # Use server time so we never store a future timestamp.
            parsed_time = dt.astimezone(timezone.utc) if dt.tzinfo else datetime.now(timezone.utc)
        except ValueError:
            parsed_time = datetime.now(timezone.utc)
    elif isinstance(raw_time, datetime):
        parsed_time = raw_time.astimezone(timezone.utc) if raw_time.tzinfo else datetime.now(timezone.utc)
    else:
        parsed_time = datetime.now(timezone.utc)

    doc_ref = db.collection('houses').document(house_id).collection('sensor_vectors').document()
    doc_ref.set({
        'sensor_vector': data.get('sensor_vector'),
        'time': parsed_time,
        'current_location': data.get('current_location'),
        'is_vacation': get_vacation_mode(house_id),
    })
    # Maintain a denormalized "last time each sensor fired (==1)" map on the house
    # document. Updated incrementally on every write, so the dashboard can show a
    # sensor's last activity in O(1) — even if it last fired weeks ago — without
    # scanning the per-minute history. merge=True merges nested map keys, so only
    # the sensors active *this* minute get a fresh timestamp; the rest are kept.
    # last_reading_at is refreshed on EVERY post (even an all-zeros vector), so the
    # health checks can tell "master online but sensors silent" (per-sensor fault)
    # apart from "master gone dark entirely" (device offline).
    house_update = {
        'last_current_location': data.get('current_location'),
        'last_reading_at': parsed_time,
    }
    sensor_vector = data.get('sensor_vector') or []
    active_now = {
        str(i): parsed_time
        for i, v in enumerate(sensor_vector)
        if v == 1 or v is True
    }
    if active_now:
        house_update['last_sensor_activity'] = active_now
    db.collection('houses').document(house_id).set(house_update, merge=True)


def get_last_current_location(house_id='default_house'):
    """Returns the last known current_location from the house document, or None."""
    doc = db.collection('houses').document(house_id).get()
    if doc.exists:
        return doc.to_dict().get('last_current_location')
    return None


def get_recent_sensor_events(house_id, limit=50):
    """Returns the most recent sensor_vector readings for a house, newest first."""
    # where('time', '>=', cutoff) with a datetime value silently excludes any
    # legacy documents where 'time' was stored as a plain string — Firestore's
    # type-aware comparison only matches the same type. This prevents the
    # mixed-type ordering bug where strings sort before timestamps in DESC order.
    cutoff = datetime.now(timezone.utc) - timedelta(days=90)
    vectors_ref = (
        db.collection('houses').document(house_id)
        .collection('sensor_vectors')
        .where('time', '>=', cutoff)
        .order_by('time', direction=firestore.Query.DESCENDING)
        .limit(limit)
    )
    results = []
    for doc in vectors_ref.get():
        d = doc.to_dict()
        t = d.get('time')
        if hasattr(t, 'isoformat'):
            time_str = t.isoformat()
        elif isinstance(t, str):
            time_str = t
        else:
            time_str = None
        results.append({
            'sensor_vector': d.get('sensor_vector', [0] * 7),
            'current_location': d.get('current_location', [0] * 7),
            'time': time_str,
        })
    return results


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


# ===========================================================================
# Device & sensor health state (single-read helpers for the scheduler)
# ===========================================================================

def get_house_health_doc(house_id):
    """One house-doc read returning everything the sensor-health check needs.

    Returns None if the house doc doesn't exist. Firestore timestamps come back as
    tz-aware datetimes; the sensor-index keys of the activity/alert maps are
    normalized to ints so the caller can index them directly.
    """
    doc = db.collection('houses').document(house_id).get()
    if not doc.exists:
        return None
    data = doc.to_dict() or {}

    def _int_key_map(raw):
        out = {}
        for k, v in (raw or {}).items():
            try:
                out[int(k)] = v
            except (TypeError, ValueError):
                continue
        return out

    return {
        'sensor_mask': data.get('sensor_mask'),
        'last_sensor_activity': _int_key_map(data.get('last_sensor_activity')),
        'faulty_sensor_alert_sent': _int_key_map(data.get('faulty_sensor_alert_sent')),
        'activated_at': data.get('activated_at'),
        'last_reading_at': data.get('last_reading_at'),
        'is_vacation': data.get('is_vacation', False),
    }


def set_activated_at(house_id, ts):
    """Records when the house first came online — the reference point from which a
    never-fired sensor's silence is measured, so a fresh install gets a grace window."""
    db.collection('houses').document(house_id).set({'activated_at': ts}, merge=True)


def update_faulty_sensor_flags(house_id, set_indices, clear_indices):
    """Marks/clears the per-sensor 'fault alert already sent' flags in a single write.

    Uses dotted field paths so only the changed sensor keys are touched — a set marks
    the flag True (so we alert once per outage), a clear removes it (so the sensor can
    alert again if it fails a second time after recovering).
    """
    updates = {}
    for i in set_indices:
        updates[f'faulty_sensor_alert_sent.{i}'] = True
    for i in clear_indices:
        updates[f'faulty_sensor_alert_sent.{i}'] = firestore.DELETE_FIELD
    if not updates:
        return
    db.collection('houses').document(house_id).update(updates)


def log_sensor_fault_alert(house_id, sensor_index, sensor_name, hours_silent):
    """Logs a suspected-sensor-fault alert into ai_decisions so it appears in the
    in-app alert history alongside AI anomalies and device-offline events."""
    doc_ref = db.collection('houses').document(house_id).collection('ai_decisions').document()
    doc_ref.set({
        'sensor_id': sensor_name,
        'decision': 'Sensor Fault',
        'type': 'sensor_fault',
        'sensor_index': sensor_index,
        'hours_silent': hours_silent,
        'time': datetime.now(timezone.utc),
    })


def get_vacation_mode(house_id) -> bool:
    """Returns the current vacation mode flag for a house."""
    doc = db.collection('houses').document(house_id).get()
    if doc.exists:
        return doc.to_dict().get('is_vacation', False)
    return False


def set_vacation_mode(house_id, is_vacation: bool):
    """Persists vacation mode flag to the house document."""
    db.collection('houses').document(house_id).set(
        {'is_vacation': is_vacation}, merge=True
    )


def get_offline_alert_sent_at(house_id):
    """Returns the datetime an offline alert was last sent, or None."""
    doc = db.collection('houses').document(house_id).get()
    if doc.exists:
        val = doc.to_dict().get('offline_alert_sent_at')
        if isinstance(val, datetime):
            return val
    return None


def set_offline_alert_sent_at(house_id, ts):
    db.collection('houses').document(house_id).set(
        {'offline_alert_sent_at': ts}, merge=True
    )


def clear_offline_alert_sent_at(house_id):
    db.collection('houses').document(house_id).set(
        {'offline_alert_sent_at': None}, merge=True
    )


def set_vacation_schedule(house_id, schedule: dict):
    """Persists a vacation schedule {startDate, startTime, endDate, endTime} to the house document."""
    db.collection('houses').document(house_id).set(
        {'vacation_schedule': schedule}, merge=True
    )


def get_vacation_schedule(house_id):
    """Returns the vacation schedule for a house, or None if not set."""
    doc = db.collection('houses').document(house_id).get()
    if doc.exists:
        return doc.to_dict().get('vacation_schedule')
    return None


def clear_vacation_schedule(house_id):
    """Removes the vacation schedule from the house document."""
    db.collection('houses').document(house_id).update(
        {'vacation_schedule': firestore.DELETE_FIELD}
    )


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


def log_device_offline_alert(house_id, minutes_silent):
    """Logs a device-offline alert so it appears in the in-app alert history."""
    doc_ref = db.collection('houses').document(house_id).collection('ai_decisions').document()
    doc_ref.set({
        'sensor_id': 'Device',
        'decision': 'Offline',
        'type': 'device_offline',
        'minutes_silent': minutes_silent,
        'time': datetime.now(timezone.utc)
    })


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


def get_weekly_sensor_data(house_id='default_house'):
    """
    Returns all sensor vector readings from the past 7 days for the given house.
    Optimized to query filtered subsets from Firestore instead of heavy streaming.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    vectors_ref = db.collection('houses').document(house_id).collection('sensor_vectors')
    
    # Query only the required 7 days from the server side
    docs = vectors_ref.where('time', '>=', cutoff).get()
    results = []
    
    for doc in docs:
        try:
            d = doc.to_dict()
            t = pd.to_datetime(d.get('time'), utc=True)
            results.append({
                'sensor_vector': d.get('sensor_vector', [0] * 7),
                'time': t,
                'current_location': d.get('current_location', [0, 0, 0, 0, 0, 0, 1]),
            })
        except Exception:
            continue
            
    return results


def get_baseline(house_id='default_house'):
    """Returns the EMA baseline dict for the house, or None if not yet established."""
    doc = db.collection('houses').document(house_id).get()
    if doc.exists:
        return doc.to_dict().get('baseline')
    return None


def save_baseline(house_id, baseline):
    """Persists the EMA baseline to the house document without overwriting other fields."""
    db.collection('houses').document(house_id).set(
        {'baseline': baseline},
        merge=True
    )


def save_weekly_report(house_id, report_dict):
    """Saves the weekly report to the house document."""
    db.collection('houses').document(house_id).set(
        {'weekly_report': report_dict}, merge=True
    )


def get_weekly_report(house_id):
    """Returns the last saved weekly report for a house, or None if none exists."""
    doc = db.collection('houses').document(house_id).get()
    if not doc.exists:
        return None
    return doc.to_dict().get('weekly_report')


def fetch_finetuning_data(house_id='default_house'):
    """Retrieves non-vacation data recorded during the last 14 days for model fine-tuning.
    Vacation-period readings are excluded so the model learns only the resident's real routine."""
    vectors_ref = db.collection('houses').document(house_id).collection('sensor_vectors')
    cutoff_date = datetime.now(timezone.utc) - timedelta(days=14)

    new_docs = vectors_ref.where('time', '>=', cutoff_date).get()
    new_data = [
        doc.to_dict() for doc in new_docs
        if not doc.to_dict().get('is_vacation', False)
    ]

    new_data.sort(key=lambda x: x['time'])
    return new_data