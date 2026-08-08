from datetime import datetime, timezone

from database.repositories.client import db
from database.repositories.users import get_user_by_id, remove_house_from_user


def create_house(house_id, resident_name, address, emergency_contact_phone, invite_code, device_token, admin_user_id):
    now = datetime.now(timezone.utc)
    db.collection('houses').document(house_id).set({
        'house_id': house_id,
        'resident_name': resident_name,
        'address': address,
        'emergency_contact_phone': emergency_contact_phone,
        'invite_code': invite_code,
        'device_token': device_token,
        'admin_user_id': admin_user_id,
        'user_ids': [],
        'is_active': False,
        'sensor_mask': [1, 1, 1, 1, 1, 1, 1],
        'created_at': now,
    }, merge=True)


def get_house(house_id):
    doc = db.collection('houses').document(house_id).get()
    if doc.exists:
        return doc.to_dict()
    return None


def get_house_by_invite_code(invite_code):
    docs = db.collection('houses').where('invite_code', '==', invite_code).limit(1).stream()
    for doc in docs:
        return doc.id, doc.to_dict()
    return None, None


def add_user_to_house(house_id, user_id):
    from google.cloud.firestore_v1 import ArrayUnion
    db.collection('houses').document(house_id).set(
        {'user_ids': ArrayUnion([user_id])},
        merge=True
    )


def remove_user_from_house(house_id, user_id):
    from google.cloud.firestore_v1 import ArrayRemove
    db.collection('houses').document(house_id).set(
        {'user_ids': ArrayRemove([user_id])},
        merge=True
    )


def activate_house(house_id):
    # activated_at is the reference point for the sensor-health check: a sensor that
    # has never fired is measured from here, giving a fresh install its grace window.
    db.collection('houses').document(house_id).set(
        {'is_active': True, 'activated_at': datetime.now(timezone.utc)}, merge=True
    )


def update_house_device_token(house_id, token):
    db.collection('houses').document(house_id).set({'device_token': token}, merge=True)


def update_house_invite_code(house_id, code):
    db.collection('houses').document(house_id).set({'invite_code': code}, merge=True)


def get_house_fcm_tokens(house_id):
    """Returns a flat list of all FCM tokens for every user in the house."""
    house = get_house(house_id)
    if not house:
        return []
    user_ids = house.get('user_ids', [])
    tokens = []
    for uid in user_ids:
        user = get_user_by_id(uid)
        if user:
            tokens.extend(user.get('fcm_tokens', []))
    return tokens


def get_admin_houses(admin_user_id):
    """Returns all house dicts installed by this admin."""
    docs = db.collection('houses').where('admin_user_id', '==', admin_user_id).stream()
    return [doc.to_dict() for doc in docs]


def delete_house(house_id):
    """Hard-deletes a house and all its subcollection data from Firestore."""
    house = get_house(house_id)
    if not house:
        return

    # Remove house reference from every member user
    for uid in house.get('user_ids', []):
        remove_house_from_user(uid, house_id)

    # Delete subcollections (Firestore does not cascade-delete children)
    house_ref = db.collection('houses').document(house_id)
    for subcollection in ('sensor_vectors', 'ai_decisions'):
        for doc in house_ref.collection(subcollection).list_documents():
            doc.delete()

    house_ref.delete()


def get_all_active_house_ids():
    """Returns IDs of all houses with is_active == True."""
    docs = db.collection('houses').where('is_active', '==', True).stream()
    return [doc.id for doc in docs]


def validate_device_token(house_id, token):
    """Returns True if the token matches the stored device_token for this house."""
    house = get_house(house_id)
    if not house:
        return False
    return house.get('device_token') == token
