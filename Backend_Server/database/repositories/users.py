from datetime import datetime, timezone

from database.repositories.client import db


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
