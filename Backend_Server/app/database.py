import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore

cred = credentials.Certificate('firebase-credentials.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

def log_sensor_event(sensor_id, action):
    """
    Recieve the sensor's log with a sensor id and a timestamp and save it in the database
    """

    doc_ref = db.collection('sensor_logs').document()
    doc_ref.set({
        'sensor': sensor_id,
        'action': action,
        'timestamp': firestore.SERVER_TIMESTAMP
    })
    print(f"Logged {sensor_id}: {action} to Firestore successfully!")
