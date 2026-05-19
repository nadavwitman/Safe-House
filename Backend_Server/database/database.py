import os
import time
import random
import firebase_admin
import pandas as pd
from datetime import datetime, timezone, timedelta
from firebase_admin import credentials, firestore

BASE_DIR = os.path.dirname(__file__)
CRED_PATH = os.path.join(BASE_DIR, 'firebase-credentials.json')

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


def log_ai_decision(house_id, sensor_id, decision):
    """
    Logs the finalized, normalized AI decision into a dedicated subcollection.
    Essential for historical parsing and the weekly summary generation pipeline.
    """
    doc_ref = db.collection('houses').document(house_id).collection('ai_decisions').document()
    doc_ref.set({
        'sensor_id': sensor_id,
        'decision': decision,
        'time': datetime.now(timezone.utc)
    })


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
    """Retrieves all data recorded during the last 14 days for model fine-tuning."""
    vectors_ref = db.collection('houses').document(house_id).collection('sensor_vectors')
    cutoff_date = datetime.now(timezone.utc) - timedelta(days=14)

    new_docs = vectors_ref.where('time', '>=', cutoff_date).get()
    new_data = [doc.to_dict() for doc in new_docs]

    # Sort documents chronologically by timestamp
    new_data.sort(key=lambda x: x['time'])

    return new_data