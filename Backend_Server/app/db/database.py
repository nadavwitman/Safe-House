import firebase_admin
from firebase_admin import credentials, firestore

# Initialize Firebase with the service account key [cite: 253, 255]
cred = credentials.Certificate('firebase-credentials.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

def log_sensor_event(sensor_id, action):
    """Saves sensor activity to the Firestore 'sensor_logs' collection [cite: 219, 220]"""
    
    # Create a new document with an auto-generated ID [cite: 255]
    doc_ref = db.collection('sensor_logs').document()

    # Store the sensor ID, the action performed, and a global server timestamp [cite: 220]
    doc_ref.set({
        'sensor': sensor_id,
        'action': action,
        'timestamp': firestore.SERVER_TIMESTAMP
    })

    print(f"Logged {sensor_id}: {action} successfully!")