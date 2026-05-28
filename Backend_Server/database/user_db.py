from datetime import datetime, timezone
from database.database import db


def get_user_by_id(user_id):
    doc = db.collection('users').document(user_id).get()
    if doc.exists:
        return doc.to_dict()
    return None


def get_user_by_email(email):
    docs = db.collection('users').where('email', '==', email).limit(1).stream()
    for doc in docs:
        return doc.to_dict()
    return None


def get_user_by_username(username):
    docs = db.collection('users').where('username', '==', username).limit(1).stream()
    for doc in docs:
        return doc.to_dict()
    return None


def create_user(user_id, username, email, password_hash, role='user'):
    now = datetime.now(timezone.utc)
    db.collection('users').document(user_id).set({
        'user_id': user_id,
        'username': username,
        'email': email,
        'password_hash': password_hash,
        'role': role,
        'house_ids': [],
        'fcm_tokens': [],
        'created_at': now,
        'updated_at': now,
    })


def update_user(user_id, updates):
    updates['updated_at'] = datetime.now(timezone.utc)
    db.collection('users').document(user_id).set(updates, merge=True)


def add_house_to_user(user_id, house_id):
    from google.cloud.firestore_v1 import ArrayUnion
    db.collection('users').document(user_id).set(
        {'house_ids': ArrayUnion([house_id]), 'updated_at': datetime.now(timezone.utc)},
        merge=True
    )


def remove_house_from_user(user_id, house_id):
    from google.cloud.firestore_v1 import ArrayRemove
    db.collection('users').document(user_id).set(
        {'house_ids': ArrayRemove([house_id]), 'updated_at': datetime.now(timezone.utc)},
        merge=True
    )


def add_fcm_token(user_id, token):
    from google.cloud.firestore_v1 import ArrayUnion
    db.collection('users').document(user_id).set(
        {'fcm_tokens': ArrayUnion([token]), 'updated_at': datetime.now(timezone.utc)},
        merge=True
    )


def remove_fcm_token(user_id, token):
    from google.cloud.firestore_v1 import ArrayRemove
    db.collection('users').document(user_id).set(
        {'fcm_tokens': ArrayRemove([token]), 'updated_at': datetime.now(timezone.utc)},
        merge=True
    )


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
    db.collection('houses').document(house_id).set({'is_active': True}, merge=True)


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
