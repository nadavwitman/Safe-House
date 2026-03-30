import os
import firebase_admin
from firebase_admin import credentials, firestore
BASE_DIR = os.path.dirname(__file__)
CRED_PATH = os.path.join(BASE_DIR, 'firebase-credentials.json')
# Auth loading
cred = credentials.Certificate(CRED_PATH)
firebase_admin.initialize_app(cred)
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
    doc_ref = db.collection('houses').document(house_id).collection('sensor_vectors').document()
    doc_ref.set({
        'sensor_vector': data.get('sensor_vector'),
        'time': data.get('time'),
        'current_location': data.get('current_location'),
    })
    db.collection('houses').document(house_id).set(
        {'last_current_location': data.get('current_location')}, merge=True
    )


def get_last_current_location(house_id='default_house'):
    """Returns the last known current_location from the house document, or None."""
    doc = db.collection('houses').document(house_id).get()
    if doc.exists:
        return doc.to_dict().get('last_current_location')
    return None
