from datetime import datetime, timezone

from firebase_admin import firestore

from database.repositories.client import db


def get_vacation_mode(house_id) -> bool:
    """Returns the current vacation mode flag for a house."""
    doc = db.collection('houses').document(house_id).get()
    if doc.exists:
        return doc.to_dict().get('is_vacation', False)
    return False


def set_vacation_mode(house_id, is_vacation: bool):
    """Persists vacation mode flag to the house document. Also tracks accrued vacation
    time since the house's last fine-tune (vacation_days_total, reset to 0 on a
    successful retrain — see model_manager.py), so the nightly MLOps pipeline can tell
    a house doesn't have 14 real days of data yet WITHOUT fetching its raw sensor
    history — that fetch is what exhausted the Firestore free-tier quota in one run."""
    now = datetime.now(timezone.utc)
    house_ref = db.collection('houses').document(house_id)

    if is_vacation:
        house_ref.set({'is_vacation': True, 'vacation_started_at': now}, merge=True)
        return

    # Turning vacation off: fold the elapsed stretch into the running total.
    doc = house_ref.get()
    started_at = doc.to_dict().get('vacation_started_at') if doc.exists else None
    elapsed_days = 0.0
    if started_at:
        if started_at.tzinfo is None:
            started_at = started_at.replace(tzinfo=timezone.utc)
        elapsed_days = max(0.0, (now - started_at).total_seconds() / 86400)

    house_ref.set({
        'is_vacation': False,
        'vacation_started_at': firestore.DELETE_FIELD,
        'vacation_days_total': firestore.Increment(elapsed_days),
    }, merge=True)


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


def get_vacation_state(house_id):
    """Single house-doc read returning both the vacation flag and the schedule.

    The 5-minute vacation scheduler needs both together; fetching them via
    get_vacation_schedule() + get_vacation_mode() reads the same document twice
    on every tick, for every house.
    """
    doc = db.collection('houses').document(house_id).get()
    if not doc.exists:
        return {'is_vacation': False, 'schedule': None}
    data = doc.to_dict() or {}
    return {
        'is_vacation': data.get('is_vacation', False),
        'schedule': data.get('vacation_schedule'),
    }


def clear_vacation_schedule(house_id):
    """Removes the vacation schedule from the house document."""
    db.collection('houses').document(house_id).update(
        {'vacation_schedule': firestore.DELETE_FIELD}
    )
