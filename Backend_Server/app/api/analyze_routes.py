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
from app.ai.model_manager import HOUSES_MODELS_CACHE, download_model_from_firebase

analyze_bp = Blueprint('analyze', __name__)

# Sensor index mapping: 0=Door  1=Kitchen  2=Bath  3=Toilet  4=Meds  5=Bed  6=Living Room
DEFAULT_LOCATION = [0, 0, 0, 0, 0, 0, 1]

# In-memory cache for validated device tokens: {house_id: token}
_device_token_cache = {}

# Tracks the last alert signature per house so a push notification only fires on a
# transition INTO a *different* alert, not on every repeated reading of the same one.
# Keyed by house_id, holding the value of _alert_key() from the previous cycle.
_last_alert_key: dict = {}


def _alert_key(decision, ai_meta):
    """Identity of the alert currently in effect, as a stable string.

    Severity alone is too coarse: a house that moves from a Missing-Usage Warning
    to a High-Frequency Warning stays 'Warning', so keying on severity would leave
    the dashboard showing the stale first message with its original timestamp.
    The anomaly type and zone are exactly what compose_alert_message renders, so
    including them means the key changes precisely when the displayed alert does.

    Normal collapses to a single key — an unremarkable house has no anomaly type
    or zone to distinguish, and every Normal reading is the same non-event.
    """
    if decision == 'Normal':
        return 'Normal'
    return f"{decision}|{ai_meta.get('activity_type')}|{ai_meta.get('room_index')}"


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

        # ONE house-document read per request. Everything below that needs house
        # state (activation, fine-tune count, vacation flag, last known location)
        # reads it off this dict — each of those used to issue its own Firestore
        # get() of the very same document, tripling the read cost of the
        # per-minute sensor feed.
        house = user_db.get_house(house_id)
        fine_tune_count = 0
        is_vacation = False

        if house:
            if not house.get('is_active', False):
                user_db.activate_house(house_id)
                print(f"[Activation] House {house_id} activated by first IoT reading.")

            # Extract the fine-tune count for dynamic threshold decay in the AI handler
            fine_tune_count = house.get('model_metadata', {}).get('fine_tune_count', 0)
            is_vacation = house.get('is_vacation', False)

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
                # Read off the house dict fetched above rather than issuing a
                # third get() for the same document.
                current_location = house.get('last_current_location') if house else None

        # Inject resolved value into data before buffering
        data['current_location'] = current_location if current_location is not None else DEFAULT_LOCATION
        ai_sensor = "System_Vector"
        ai_decision = "Normal"
        ai_meta = {'severity': 'Normal', 'activity_type': None, 'room_index': None}

        # Add to buffer and persist (now with resolved current_location)
        sensor_buffer.add_reading(data)
        database.log_vector_reading(data, house_id, is_vacation=is_vacation)

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


        # A push notification only fires when the house transitions INTO a different
        # alert — not on every repeated reading of the same one (e.g. the same
        # Emergency re-detected each minute stays silent).
        #
        # "Different" is judged on the full alert signature, not just the severity:
        # a Missing-Usage Warning followed by a High-Frequency Warning is a new
        # anomaly with a new message, and must refresh the alert the dashboard shows
        # along with its timestamp. Keying on severity alone left the house sitting
        # on the first Warning's text until it happened to recover to Normal.
        #
        # _last_alert_key lives in process memory and is wiped by every restart/deploy.
        # On a cold start we recover the previous key from the house doc already
        # fetched above (no extra read). Without this, the first reading after a
        # restart always looks like a transition, which re-pushed a duplicate alert
        # for a situation that was already reported.
        current_key = _alert_key(final_decision, ai_meta)
        previous_key = _last_alert_key.get(house_id)
        legacy_status = None
        if previous_key is None and house:
            previous_key = house.get('current_alert_key')
            if previous_key is None:
                # House doc predates current_alert_key. Compare on the coarse status
                # it does carry, so the migration doesn't re-push every live alert.
                legacy_status = house.get('current_status')

        status_changed = (legacy_status != final_decision) if legacy_status is not None \
            else (previous_key != current_key)
        _last_alert_key[house_id] = current_key

        title = None
        body = None
        if final_decision in ["Warning", "Emergency"]:
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

        # Only a genuine state CHANGE is recorded. log_ai_decision writes the
        # ai_decisions event AND updates current_status on the house doc, so the
        # dashboard still reads a live status in a single document read — without
        # this collection accumulating 1,440 "Normal" heartbeats per house per day.
        if status_changed:
            database.log_ai_decision(house_id, ai_sensor, final_decision,
                                     note=body, title=title, alert_key=current_key)

        fcm_status = "Not Sent"
        if final_decision in ["Warning", "Emergency"] and status_changed:
            notifications.send_alert_push(house_id, title, body)
            fcm_status = "Sent"

        return jsonify({
            "status": "success",
            "decision": final_decision,
            "fcm_status": fcm_status,
        }), 200
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500