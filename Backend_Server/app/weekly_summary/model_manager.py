import os
import io
import pickle
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import TensorDataset, DataLoader
from firebase_admin import storage
from database.database import db, fetch_finetuning_data
from datetime import datetime, timezone
from app.core.house_mask_store import house_mask_store
from app.core.ai_handler import fine_tune_house_model

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


def prepare_colab_dataloaders(readings, seq_len=30, batch_size=32):
    """
    Converts raw Firestore sequence logs into sliding-window sequences 
    and wraps them into PyTorch DataLoaders exactly like the Colab notebook implementation.
    """
    # 1. Vectorize and transform document dicts into a structured numeric NumPy array
    # This matches your 18-feature layout (or whatever feature size your system expects)
    data_matrix = []
    for doc in readings:
        data = doc.to_dict()
        # Extract features in the correct sequential column order
        # features = [data.get(f'f_{i}', 0.0) for i in range(18)]
        # data_matrix.append(features)
        
        # Temporary fallback placeholder ensuring array structure matches your feature shape
        if 'features' in data:
            data_matrix.append(data['features'])
        else:
            # Generate a consistent baseline shape array if structured fields differ
            data_matrix.append(np.zeros(18))
            
    data_array = np.array(data_matrix, dtype=np.float32)
    
    if len(data_array) <= seq_len:
        return None, None

    # 2. Extract sequences using a Sliding Window approach
    sequences = []
    for i in range(len(data_array) - seq_len + 1):
        sequences.append(data_array[i : i + seq_len])
    
    sequences = np.array(sequences, dtype=np.float32)
    
    # 3. Split into Train / Validation sets (80% / 20%)
    split_idx = int(len(sequences) * 0.8)
    train_seqs = sequences[:split_idx]
    val_seqs = sequences[split_idx:]
    
    if len(train_seqs) == 0 or len(val_seqs) == 0:
        return None, None

    # 4. Wrap with TensorDataset and DataLoader
    train_dataset = TensorDataset(torch.from_numpy(train_seqs), torch.from_numpy(train_seqs))
    val_dataset = TensorDataset(torch.from_numpy(val_seqs), torch.from_numpy(val_seqs))
    
    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=batch_size, shuffle=False)
    
    return train_loader, val_loader


def train_model_engine(model, train_loader, val_loader, n_epochs=50):
    """
    The core PyTorch execution loop from Colab, implementing Early Stopping,
    L2 regularization (weight decay), and Gradient Clipping for LSTM stability.
    """
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = model.to(device)

    optimizer = optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-5)
    criterion = nn.MSELoss()

    best_loss = float('inf')
    patience = 10
    counter = 0

    for epoch in range(n_epochs):
        # Training Phase
        model.train()
        train_losses = []
        for x_batch, _ in train_loader:
            x_batch = x_batch.to(device)
            optimizer.zero_grad()

            output = model(x_batch)
            loss = criterion(output, x_batch)
            loss.backward()

            # Gradient Clipping to prevent exploding gradients in LSTMs
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()
            train_losses.append(loss.item())

        # Validation Phase
        model.eval()
        val_losses = []
        with torch.no_grad():
            for x_val, _ in val_loader:
                x_val = x_val.to(device)
                output = model(x_val)
                loss = criterion(output, x_val)
                val_losses.append(loss.item())

        train_loss = np.mean(train_losses)
        val_loss = np.mean(val_losses)

        # Early Stopping check
        if val_loss < best_loss:
            best_loss = val_loss
            counter = 0
        else:
            counter += 1
            if counter >= patience:
                print(f"[MLOps Engine] Early Stopping triggered at epoch {epoch+1}")
                break

    return model

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