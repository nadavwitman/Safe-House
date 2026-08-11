import io
import pickle
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor
import torch  # kept so unpickling serialized torch models resolves cleanly
from firebase_admin import storage
from database.database import db, fetch_finetuning_data
from app.state.house_mask_store import house_mask_store
from app.ai.fine_tuning import fine_tune_house_model

# Global In-Memory Cache (RAM) to store loaded house models
HOUSES_MODELS_CACHE = {}

# Bounded capacity for the concurrent worker pool to throttle CPU/RAM usage
MAX_CONCURRENT_WORKERS = 2  # Scaled down to 2 since PyTorch training consumes more resources than network I/O


def download_model_from_firebase(house_id):
    """
    Fetches a serialized house-specific model from Firebase Storage 
    and deserializes it directly into RAM to eliminate disk I/O bottlenecks.
    """
    try:
        bucket = storage.bucket()
        blob = bucket.blob(f"models/{house_id}/anomaly_detector.pkl")
        
        if not blob.exists():
            print(f"[MLOps] No custom model found in Firebase Storage for house: {house_id}")
            return None

        # Download blob binary stream straight into a local RAM variable
        model_bytes = blob.download_as_bytes()
        model_instance = pickle.loads(model_bytes)
        print(f"[MLOps] Successfully fetched and deserialized model for house: {house_id}")
        return model_instance
        
    except Exception as e:
        print(f"[MLOps] Exception raised during model retrieval for house {house_id}: {str(e)}")
        return None


def auto_train_house_model(house_id):
    """
    Background worker that fetches data, delegates fine-tuning to the AI handler,
    and uploads the newly blended model directly to Firebase Storage.
    """
    print(f"[MLOps Worker] Initiating automated retraining sequence for house: {house_id}")
    try:
        # 1. Fetch the last 14 days of sensor vectors from the correct Firestore subcollection
        raw_training_data = fetch_finetuning_data(house_id)
        
        # 2. Fetch house mask
        house_mask = house_mask_store.get_mask(house_id)

        # 3. Download the CURRENT custom model from Firebase (if it exists)
        current_model = download_model_from_firebase(house_id)

        # 4. Delegate to your advanced Continual Learning function
        updated_model = fine_tune_house_model(
            house_id=house_id,
            raw_training_data=raw_training_data,
            house_sensor_mask=house_mask,
            current_model=current_model  # Pass the downloaded model in RAM
        )

        if updated_model is None:
            print(f"[MLOps Worker] Fine-tuning aborted or failed for {house_id}.")
            return

        # 5. Serialize the returned updated PyTorch model
        buffer = io.BytesIO()
        pickle.dump(updated_model, buffer)
        buffer.seek(0)

        # 6. Push the real model payload back to Firebase Storage
        bucket = storage.bucket()
        blob = bucket.blob(f"models/{house_id}/anomaly_detector.pkl")
        blob.upload_from_string(buffer.getvalue(), content_type="application/octet-stream")

        # Fetch current count (defaults to 0 if it's the first time)
        current_metadata = db.collection('houses').document(house_id).get().to_dict().get('model_metadata', {})
        current_count = current_metadata.get('fine_tune_count', 0)

        # 7. Update metadata in Firestore with the incremented counter
        db.collection('houses').document(house_id).update({
            'model_metadata.last_retrained': datetime.utcnow(),
            'model_metadata.status': 'fully_trained',
            'model_metadata.fine_tune_count': current_count + 1  # <--- מקדם את המונה!
        })
        print(f"[MLOps Worker] Cloud sync successful! {house_id} updated (Generation: {current_count + 1}).")

    except Exception as e:
        print(f"[MLOps Worker] Critical execution failure on house thread {house_id}: {str(e)}")

def run_weekly_mlops_pipeline_scalable():
    """
    Orchestrates the entire system's fine-tuning routine. Uses a bounded
    ThreadPoolExecutor to distribute workload concurrently across threads safely.
    Filters houses to ensure fine-tuning only occurs every 14 days per house.
    """
    current_time = datetime.now(timezone.utc)
    print(f"[MLOps Engine] Executing global pipeline sequence at: {current_time}")
    
    # Query all currently active houses within the infrastructure
    active_houses = db.collection('houses').where('is_active', '==', True).stream()
    
    house_ids_to_train = []
    
    for house in active_houses:
        house_data = house.to_dict() or {}
        model_metadata = house_data.get('model_metadata', {})
        last_retrained = model_metadata.get('last_retrained')
        
        # 14-Day Frequency Guard
        if last_retrained:
            # Safely handle timezone-aware datetimes from Firestore
            if last_retrained.tzinfo is None:
                last_retrained = last_retrained.replace(tzinfo=timezone.utc)
                
            days_since_last_train = (current_time - last_retrained).days
            
            if days_since_last_train < 14:
                print(f"[MLOps Engine] House {house.id} was trained {days_since_last_train} days ago. Skipping (needs 14 days).")
                continue # Skip this house and move to the next one
                
        # If it hasn't been trained yet, or 14+ days have passed, queue it for training
        house_ids_to_train.append(house.id)

    if not house_ids_to_train:
        print("[MLOps Engine] Execution halted: Zero houses require retraining this week.")
        return

    print(f"[MLOps Engine] Discovered {len(house_ids_to_train)} houses requiring updates. Dispatching jobs to Worker Pool...")

    # Execute the retraining concurrently
    with ThreadPoolExecutor(max_workers=MAX_CONCURRENT_WORKERS) as executor:
        executor.map(auto_train_house_model, house_ids_to_train)

    # Cache Invalidation step to force online endpoints to reload fresh weights on upcoming requests
    HOUSES_MODELS_CACHE.clear()
    print("[MLOps Engine] Global pipeline completed cleanly. RAM Cache cleared and sync ready.")