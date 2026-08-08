from flask import Blueprint, request, jsonify
from app.state.data_buffer import sensor_buffer
from app.state.house_mask_store import house_mask_store
import database.database as database
import database.user_db as user_db
from app.alerts import notifications
from app.ai.inference import evaluate_buffer_with_AI
import app.monitoring.device_health as device_health
from app.alerts import alert_messages

# Import the global cache dictionary and download helper from your manager
from app.weekly_summary.model_manager import HOUSES_MODELS_CACHE, download_model_from_firebase

analyze_bp = Blueprint('analyze', __name__)

# Sensor index mapping: 0=Door  1=Kitchen  2=Bath  3=Toilet  4=Meds  5=Bed  6=Living Room
DEFAULT_LOCATION = [0, 0, 0, 0, 0, 0, 1]

# In-memory cache for validated device tokens: {house_id: token}
_device_token_cache = {}

# Alert cooldown: {house_id: last_alert_datetime} — prevents duplicate alerts within 30 min
from datetime import datetime, timedelta
_last_alert_time: dict = {}
_ALERT_COOLDOWN = timedelta(minutes=30)


def _validate_device_token(house_id, token):
    if not token:
        return False
    if _device_token_cache.get(house_id) == token:
        return True
    if user_db.validate_device_token(house_id, token):
        _device_token_cache[house_id] = token
        return True
    return False


# Tracks houses whose in-memory buffer was already reconstructed from Firestore after a
# cold start, so we only pay the historical read once per house per process.
_warmed_houses: set = set()


def _ensure_buffer_warm(house_id):
    """Replays recent Firestore history into the in-memory buffer on cold start.

    The buffer lives in process memory and is wiped on every restart/deploy. Without
    this, an established house would take a full 6 hours to refill before the model
    could run again. We replay at most one full window (360 readings) in chronological
    order, once per house per process.
    """
    if house_id in _warmed_houses:
        return
    _warmed_houses.add(house_id)

    # Nothing to warm if this process already accumulated readings for the house.
    if sensor_buffer.get_all_readings(house_id):
        return

    try:
        recent = database.get_recent_sensor_events(house_id, limit=sensor_buffer.threshold)
    except Exception as e:
        print(f"[Buffer] Warm-start read failed for {house_id}: {e}")
        return

    # get_recent_sensor_events returns newest-first; replay oldest-first so the deque
    # preserves chronological order for the LSTM.
    for r in reversed(recent):
        sensor_buffer.add_reading({
            'house_id': house_id,
            'sensor_vector': r.get('sensor_vector'),
            'current_location': r.get('current_location'),
            'time': r.get('time'),
        })
    if recent:
        print(f"[Buffer] Warm-started {house_id} with {len(recent)} readings from Firestore.")


@analyze_bp.route('/api/analyze', methods=['POST'])
def analyze_data():
    try:
        data = request.get_json(silent=True)
        if not data:
            return jsonify({"error": "No data provided"}), 400

        house_id = data.get('house_id', 'default_house')

        device_token = request.headers.get('X-Device-Token')
        if not _validate_device_token(house_id, device_token):
            return jsonify({"error": "Unauthorized device"}), 401

        # Fetch house data to activate on first ping and retrieve fine-tuning generation count
        house = user_db.get_house(house_id)
        fine_tune_count = 0
        
        if house:
            if not house.get('is_active', False):
                user_db.activate_house(house_id)
                print(f"[Activation] House {house_id} activated by first IoT reading.")
            
            # Extract the fine-tune count for dynamic threshold decay in the AI handler
            fine_tune_count = house.get('model_metadata', {}).get('fine_tune_count', 0)

        # Reconstruct the buffer from Firestore on cold start so a restart doesn't blind
        # the model for a full 6-hour window (must run before the buffer is read below).
        _ensure_buffer_warm(house_id)

        # Resolve current_location: payload → last buffer reading → last DB value → default
        current_location = data.get('current_location')
        if not (isinstance(current_location, list) and len(current_location) == 7 and all(b in (0, 1) for b in current_location)):
            last_reading = sensor_buffer.get_last_reading(house_id)
            last_loc = last_reading.get('current_location') if last_reading else None
            if isinstance(last_loc, list) and len(last_loc) == 7 and all(b in (0, 1) for b in last_loc):
                current_location = last_loc
            else:
                current_location = database.get_last_current_location(house_id)

        # Inject resolved value into data before buffering
        data['current_location'] = current_location if current_location is not None else DEFAULT_LOCATION
        ai_sensor = "System_Vector"
        ai_decision = "Normal"
        ai_meta = {'severity': 'Normal', 'activity_type': None, 'room_index': None}

        # Add to buffer and persist (now with resolved current_location)
        sensor_buffer.add_reading(data)
        database.log_vector_reading(data, house_id)

        # Aquire all current buffer data for processing
        buffer_data = sensor_buffer.get_all_readings(house_id)

        # Only run the model once we hold a full 6-hour window (360 minutes). The model was
        # trained on fixed 360-length sequences and the anomaly score is calibrated on that
        # window — a partial buffer yields an out-of-distribution, unreliable score. Warm-start
        # above ensures an established house reaches this threshold right after a restart; only a
        # genuinely new install (<6h of history) waits for the window to fill.
        if sensor_buffer.has_enough_data(house_id):
            house_mask = house_mask_store.get_mask(house_id)

            # --- ARTIFACT INTEGRATION: IN-MEMORY RAM CACHE LIFECYCLE ---
            # Check if the customized baseline model for this house is already loaded in RAM
            if house_id not in HOUSES_MODELS_CACHE:
                print(f"[Cache Miss] Model for house {house_id} not found in RAM. Fetching from Firebase Storage...")
                downloaded_model = download_model_from_firebase(house_id)
                
                if downloaded_model:
                    # Save the loaded model object into the RAM dict for all future requests
                    HOUSES_MODELS_CACHE[house_id] = downloaded_model
                else:
                    print(f"[Cache Warning] No custom model found in storage for {house_id}. Using default/fallback logic.")
            else:
                print(f"[Cache Hit] Model for house {house_id} found in RAM. Running fast execution.")

            # Extract the actual model instance to pass it to the evaluation engine
            current_model_instance = HOUSES_MODELS_CACHE.get(house_id)
            # -----------------------------------------------------------

            # Get the AI model decision utilizing the custom model and threshold decay count
            ai_sensor, ai_decision, ai_meta = evaluate_buffer_with_AI(
                buffer_data_list=buffer_data,
                latest_sensor_id=ai_sensor,
                house_sensor_mask=house_mask,
                model_instance=current_model_instance,
                fine_tune_count=fine_tune_count
            )
        else:
            print(f"[AI] Buffer for {house_id} holds {len(buffer_data)}/{sensor_buffer.threshold} "
                  f"readings — skipping inference until the 6-hour window fills.")

        # Act accordingly to the model's decision
        if "Hosting" in ai_decision or "Social" in ai_decision:
            final_decision = "Normal"       # Social activity is considered safe and routine
        elif "Emergency" in ai_decision:
            final_decision = "Emergency"    # Critical situation (e.g., Stuck/Fall detected)
        elif "Warning" in ai_decision:
            final_decision = "Warning"      # Non-critical anomaly (e.g., Unusual Night Routine)
        else:
            final_decision = "Normal"       # Standard baseline routine


        # Trigger push notifications only for Warning and Emergency states,
        # with a 30-minute cooldown to avoid flooding the alert history.
        if final_decision in ["Warning", "Emergency"]:
            now = datetime.now()
            last = _last_alert_time.get(house_id)
            if last and (now - last) < _ALERT_COOLDOWN:
                return jsonify({"status": "success", "decision": final_decision, "fcm_status": "Cooldown"}), 200
            _last_alert_time[house_id] = now
            # Enrich (never suppress) the alert with any sensors the health checker
            # currently suspects are faulty, so a device fault isn't mistaken for — nor
            # hides — a real emergency. Read from the shared in-process cache (no extra
            # Firestore reads; safe under gunicorn's single worker).
            faulty_idx = device_health.FAULTY_SENSORS_CACHE.get(house_id) or set()
            faulty_names = [device_health.SENSOR_NAMES.get(i, f'Sensor {i}')
                            for i in sorted(faulty_idx)]
            resident_name = house.get('resident_name') if house else None
            # Compose a focused, situation-specific message from the AI's structured
            # verdict (severity + anomaly type + zone + last location).
            title, body = alert_messages.compose_alert_message(
                severity=final_decision,
                activity_type=ai_meta.get('activity_type'),
                room_index=ai_meta.get('room_index'),
                resident_name=resident_name,
                last_location=data.get('current_location'),
                faulty_sensor_names=faulty_names,
            )
            database.log_ai_decision(house_id, ai_sensor, final_decision,
                                     note=body, title=title)
            notifications.send_alert_push(house_id, title, body)
            return jsonify({
                "status": "success", 
                "decision": final_decision, 
                "fcm_status": "Sent"
            }), 200
        
        # For Normal state (including hosting scenarios mapped above)
        return jsonify({
            "status": "success", 
            "decision": "Normal", 
            "fcm_status": "Not Sent"
        }), 200
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500