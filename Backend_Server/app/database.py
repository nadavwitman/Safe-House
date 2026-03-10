import firebase_admin
from firebase_admin import credentials, firestore

# Initialize Firebase with the service account key [cite: 253, 255]
cred = credentials.Certificate('firebase-credentials.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

# def log_sensor_event(sensor_id, action):
#     """Saves sensor activity to the Firestore 'sensor_logs' collection [cite: 219, 220]"""
    
#     # Create a new document with an auto-generated ID [cite: 255]
#     doc_ref = db.collection('sensor_logs').document()

#     # Store the sensor ID, the action performed, and a global server timestamp [cite: 220]
#     doc_ref.set({
#         'sensor': sensor_id,
#         'action': action,
#         'timestamp': firestore.SERVER_TIMESTAMP
#     })

#     print(f"Logged {sensor_id}: {action} successfully!")

def log_sensor_event(sensor_id, action, house_id='default_house'):
    """
    Saves sensor activity to a specific house's subcollection in Firestore.
    The structure follows: houses -> {house_id} -> sensor_logs -> {auto_generated_doc}.
    """
    
    # Navigate to the specific house and its sensor_logs subcollection 
    doc_ref = db.collection('houses').document(house_id).collection('sensor_logs').document()

    # Store the original data structure (sensor, action, and server timestamp) 
    doc_ref.set({
        'sensor': sensor_id,
        'action': action,
        'timestamp': firestore.SERVER_TIMESTAMP
    })

    # Output log for development tracking
    print(f"Logged {sensor_id} for house {house_id}: {action} successfully!")