from firebase_admin import firestore

from database.repositories.client import db


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
