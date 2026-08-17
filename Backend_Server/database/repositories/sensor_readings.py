import pandas as pd
from datetime import datetime, timezone, timedelta
from firebase_admin import firestore

from database.repositories.client import db
from database.repositories.vacation import get_vacation_mode


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


def log_vector_reading(data, house_id='default_house', is_vacation=None):
    """
    Saves a sensor vector reading to a house's subcollection in Firestore.
    Structure: houses -> {house_id} -> sensor_vectors -> {auto_generated_doc}

    `is_vacation` should be passed in by callers that already hold the house
    document (the analyze route does — see app/api/analyze_routes.py). Leaving it
    None makes this re-read the house doc, which on a per-minute sensor feed is a
    second read of a document the caller just fetched.
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

    if is_vacation is None:
        is_vacation = get_vacation_mode(house_id)

    doc_ref = db.collection('houses').document(house_id).collection('sensor_vectors').document()
    doc_ref.set({
        'sensor_vector': data.get('sensor_vector'),
        'time': parsed_time,
        'current_location': data.get('current_location'),
        'is_vacation': bool(is_vacation),
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


# One ESP32 reading/minute (see app/state/data_buffer.py) * 14 days.
FINETUNING_READING_TARGET = 14 * 24 * 60  # 20,160


def fetch_finetuning_data(house_id='default_house'):
    """Retrieves the most recent ~14 real (non-vacation) days of readings for model
    fine-tuning, by asking Firestore directly for the last FINETUNING_READING_TARGET
    non-vacation readings instead of a calendar-date cutoff. This sidesteps having to
    separately account for vacation time: vacation-flagged readings are excluded
    server-side, so the count returned is already real, non-vacation data no matter how
    much vacation time falls within that stretch."""
    vectors_ref = (
        db.collection('houses').document(house_id).collection('sensor_vectors')
        .where('is_vacation', '==', False)
        .order_by('time', direction=firestore.Query.DESCENDING)
        .limit(FINETUNING_READING_TARGET)
    )

    new_data = [doc.to_dict() for doc in vectors_ref.get()]
    new_data.sort(key=lambda x: x['time'])
    return new_data
