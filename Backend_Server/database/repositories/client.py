import os
import firebase_admin
from firebase_admin import credentials, firestore

BASE_DIR = os.path.dirname(os.path.dirname(__file__))
CRED_PATH = os.environ.get('FIREBASE_CREDENTIALS_PATH') or os.path.join(BASE_DIR, 'firebase-credentials.json')

# Initialize Firebase application if not already initialized
if not firebase_admin._apps:
    cred = credentials.Certificate(CRED_PATH)
    firebase_admin.initialize_app(cred, {
        'storageBucket': 'safe-house-492613.appspot.com'
    })

db = firestore.client()
