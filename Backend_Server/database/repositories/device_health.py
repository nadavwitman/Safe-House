from datetime import datetime, timezone
from firebase_admin import firestore

from database.repositories.client import db


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
        # Used by check_device_connectivity, which is driven entirely off this
        # single read — see app/monitoring/device_health.py.
        'offline_alert_sent_at': data.get('offline_alert_sent_at'),
        'resident_name': data.get('resident_name'),
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


# There is no per-house getter for offline_alert_sent_at. check_device_connectivity
# reads that field off the bulk house scan it already performs, so fetching it one
# document at a time would add a read per house on every sweep.


def set_offline_alert_sent_at(house_id, ts):
    db.collection('houses').document(house_id).set(
        {'offline_alert_sent_at': ts}, merge=True
    )


def clear_offline_alert_sent_at(house_id):
    db.collection('houses').document(house_id).set(
        {'offline_alert_sent_at': None}, merge=True
    )


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
