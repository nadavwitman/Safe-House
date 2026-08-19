import os
import pickle
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor
import torch  # kept so unpickling serialized torch models resolves cleanly
from firebase_admin import firestore
from database.database import db, fetch_finetuning_data, FINETUNING_READING_TARGET
from app.state.house_mask_store import house_mask_store
from app.ai.fine_tuning import fine_tune_house_model
from app.ai.model_paths import AI_MODEL_DIR

# Local disk directory for persisted per-house models. Firebase Storage requires the
# Blaze plan (out of scope — single house, single server), so fine-tuned models are
# kept on the server's own filesystem and overwritten on every retrain.
TRAINED_MODELS_DIR = os.path.join(AI_MODEL_DIR, "trained_models")

# Global In-Memory Cache (RAM) to store loaded house models
HOUSES_MODELS_CACHE = {}

# Bounded capacity for the concurrent worker pool to throttle CPU/RAM usage
MAX_CONCURRENT_WORKERS = 1  # One house at a time — the gunicorn process only has a
# single worker (APScheduler runs in-process, see Dockerfile), so PyTorch training
# competes for the same CPU/GIL as live sensor requests. Keeping this at 1 leaves
# headroom for /api/analyze to keep responding to real sensor traffic during a run.

# Hard cap on how many houses get fine-tuned in a single pipeline run. Each house costs
# ~1 Firestore read per sensor reading in its 14-day training window (tens of thousands
# on a per-minute feed) — with no cap, a backlog of overdue houses (e.g. this pipeline's
# very first run, where every house looks overdue at once) fetches all of them in one
# shot and can exhaust the Firestore free-tier daily quota in a couple of hours. Capping
# to 1 spreads a large backlog across multiple nightly runs instead.
MAX_HOUSES_PER_RUN = 1


def _house_model_path(house_id):
    return os.path.join(TRAINED_MODELS_DIR, house_id, "anomaly_detector.pkl")


def download_model_from_firebase(house_id):
    """
    Loads a serialized house-specific model from local disk into RAM.
    (Name kept for compatibility with existing callers.)
    """
    path = _house_model_path(house_id)
    try:
        if not os.path.exists(path):
            print(f"[MLOps] No custom model found on disk for house: {house_id}")
            return None

        with open(path, "rb") as f:
            model_instance = pickle.load(f)
        print(f"[MLOps] Successfully loaded model for house: {house_id}")
        return model_instance

    except Exception as e:
        print(f"[MLOps] Exception raised during model retrieval for house {house_id}: {str(e)}")
        return None


def auto_train_house_model(house_id):
    """
    Background worker that fetches data, delegates fine-tuning to the AI handler,
    and persists the newly blended model to local disk.

    Returns True on a successful persisted retrain, False otherwise (including
    "correctly skipped" cases), so the caller can report real success/failure counts.
    """
    print(f"[MLOps Worker] Initiating automated retraining sequence for house: {house_id}")
    try:
        # 1. Fetch the last ~14 real (non-vacation) days of sensor vectors
        raw_training_data = fetch_finetuning_data(house_id)

        # Guard against training on a thin, mostly-vacation slice: fetch_finetuning_data
        # asks Firestore for FINETUNING_READING_TARGET non-vacation readings directly, so
        # coming up short here means the house genuinely doesn't have 14 real days yet.
        if len(raw_training_data) < FINETUNING_READING_TARGET:
            print(f"[MLOps Worker] Skipping {house_id}: only {len(raw_training_data)} non-vacation "
                  f"readings (< {FINETUNING_READING_TARGET} required).")
            return False

        # 2. Fetch house mask
        house_mask = house_mask_store.get_mask(house_id)

        # 3. Load the CURRENT custom model from local disk (if it exists)
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
            return False

        # 5. Serialize and persist the updated model to local disk, overwriting
        # whatever was there from the previous fine-tune.
        path = _house_model_path(house_id)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            pickle.dump(updated_model, f)

        # Fetch current count (defaults to 0 if it's the first time)
        current_metadata = db.collection('houses').document(house_id).get().to_dict().get('model_metadata', {})
        current_count = current_metadata.get('fine_tune_count', 0)

        # 7. Update metadata in Firestore with the incremented counter. Also zero out
        # vacation_days_total — it tracks vacation time accrued since the LAST
        # fine-tune (see database/repositories/vacation.py), so a fresh retrain resets
        # the clock on it.
        db.collection('houses').document(house_id).update({
            'model_metadata.last_retrained': datetime.utcnow(),
            'model_metadata.status': 'fully_trained',
            'model_metadata.fine_tune_count': current_count + 1,  # <--- מקדם את המונה!
            'model_metadata.last_error': firestore.DELETE_FIELD,
            'vacation_days_total': 0,
        })

        # 8. Make the freshly trained model immediately available to inference on this
        # process, instead of waiting for a blanket cache clear + disk re-load.
        HOUSES_MODELS_CACHE[house_id] = updated_model

        print(f"[MLOps Worker] Retrain successful! {house_id} updated (Generation: {current_count + 1}).")
        return True

    except Exception as e:
        print(f"[MLOps Worker] Critical execution failure on house thread {house_id}: {str(e)}")
        try:
            db.collection('houses').document(house_id).update({
                'model_metadata.status': 'failed',
                'model_metadata.last_error': str(e),
                'model_metadata.last_error_at': datetime.utcnow(),
            })
        except Exception as meta_err:
            print(f"[MLOps Worker] Also failed to record failure metadata for {house_id}: {meta_err}")
        return False

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

        # Never fine-tune a house that's currently on vacation — its recent buffer is
        # paused/cleared and not representative of the resident's real routine.
        if house_data.get('is_vacation', False):
            print(f"[MLOps Engine] House {house.id} is currently in vacation mode. Skipping.")
            continue

        model_metadata = house_data.get('model_metadata', {})
        last_retrained = model_metadata.get('last_retrained')
        vacation_days = house_data.get('vacation_days_total', 0)

        # 14-Day Frequency Guard. vacation_days_total (accrued since the last successful
        # fine-tune, reset to 0 there — see auto_train_house_model / vacation.py) is
        # already sitting on house_data for free, so this whole check costs zero extra
        # Firestore reads — it only queues houses that plausibly HAVE 14 real days,
        # instead of finding out after paying for the full raw-data fetch.
        if last_retrained:
            # Safely handle timezone-aware datetimes from Firestore
            if last_retrained.tzinfo is None:
                last_retrained = last_retrained.replace(tzinfo=timezone.utc)

            calendar_days_since_train = (current_time - last_retrained).days
            effective_days_since_train = calendar_days_since_train - vacation_days

            if effective_days_since_train < 14:
                print(f"[MLOps Engine] House {house.id}: {calendar_days_since_train} calendar days "
                      f"since last train, {vacation_days:.1f} of them vacation "
                      f"({effective_days_since_train:.1f} real days). Skipping (needs 14).")
                continue # Skip this house and move to the next one
        else:
            # Never trained. A brand-new house can't have 14 days of sensor data yet, so
            # querying sensor_vectors every night until it does is a wasted DB read. Track
            # eligibility purely off metadata (training_start_date) until 14 effective days
            # have passed, and only then let the house through to the real data fetch.
            training_start_date = model_metadata.get('training_start_date')

            if not training_start_date:
                db.collection('houses').document(house.id).update({
                    'model_metadata.training_start_date': current_time,
                })
                print(f"[MLOps Engine] House {house.id}: first time seen, stamped "
                      f"training_start_date. Skipping until 14 real days accrue.")
                continue

            if training_start_date.tzinfo is None:
                training_start_date = training_start_date.replace(tzinfo=timezone.utc)

            calendar_days_since_start = (current_time - training_start_date).days
            effective_days_since_start = calendar_days_since_start - vacation_days

            if effective_days_since_start < 14:
                print(f"[MLOps Engine] House {house.id}: {calendar_days_since_start} calendar days "
                      f"since training_start_date, {vacation_days:.1f} of them vacation "
                      f"({effective_days_since_start:.1f} real days). Skipping (needs 14).")
                continue

        # Either last_retrained or training_start_date shows 14+ effective days have
        # passed — queue it for its first/next fine-tune.
        house_ids_to_train.append(house.id)

    if not house_ids_to_train:
        print("[MLOps Engine] Execution halted: Zero houses require retraining this week.")
        return

    # Cap to MAX_HOUSES_PER_RUN — see its definition for why. A larger backlog just
    # rolls over to the next run instead of trying to do it all in one shot.
    if len(house_ids_to_train) > MAX_HOUSES_PER_RUN:
        print(f"[MLOps Engine] {len(house_ids_to_train)} houses need updates — processing "
              f"{MAX_HOUSES_PER_RUN} this run, rest roll over to the next.")
        house_ids_to_train = house_ids_to_train[:MAX_HOUSES_PER_RUN]

    print(f"[MLOps Engine] Discovered {len(house_ids_to_train)} houses requiring updates. Dispatching jobs to Worker Pool...")

    # Execute the retraining concurrently. Each worker returns True/False so the engine
    # can report real success/failure counts instead of always claiming a clean run —
    # auto_train_house_model catches its own exceptions to keep one bad house from
    # aborting the others, so this is the only place that sees the outcome.
    with ThreadPoolExecutor(max_workers=MAX_CONCURRENT_WORKERS) as executor:
        results = list(executor.map(auto_train_house_model, house_ids_to_train))

    succeeded = sum(1 for r in results if r)
    failed = len(results) - succeeded
    print(f"[MLOps Engine] Global pipeline finished: {succeeded} succeeded, {failed} failed/skipped "
          f"out of {len(house_ids_to_train)} candidate houses.")