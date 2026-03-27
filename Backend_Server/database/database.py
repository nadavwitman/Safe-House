import os
import firebase_admin
from firebase_admin import credentials, firestore
BASE_DIR = os.path.dirname(__file__)
CRED_PATH = os.path.join(BASE_DIR, 'firebase-credentials.json')
# Auth loading
cred = credentials.Certificate(CRED_PATH)
firebase_admin.initialize_app(cred)
db = firestore.client()

def log_vector_reading(data, house_id='default_house'):
    """
    Saves a sensor vector reading to a house's subcollection in Firestore.
    Structure: houses -> {house_id} -> sensor_vectors -> {auto_generated_doc}
    """
    doc_ref = db.collection('houses').document(house_id).collection('sensor_vectors').document()

    doc_ref.set({
        'sensor_vector': data.get('sensor_vector'),
        'time': data.get('time')
    })
