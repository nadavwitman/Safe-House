"""
Device & sensor health monitoring.

Two independent safety checks, both driven by the production scheduler
(see app.__init__._setup_scheduler). Historically these lived in run.py, which is
NOT copied into the Docker image — so they never actually ran in production. They
live here now, inside the `app` package that the container ships.

  check_device_connectivity  — the ESP32 master gateway stopped reporting entirely
                               (power / Wi-Fi / crash). Alerts after 30 min of total
                               silence, once per outage.

  check_sensor_health        — an individual PIR servant hasn't fired in a long time
                               while the master keeps reporting. Flags a *suspected
                               faulty sensor*, per sensor (24h; 72h for the entrance
                               door, which naturally stays quiet for long stretches).

DESIGN PRINCIPLE — fail loud, not silent:
Neither check ever SUPPRESSES an anomaly alert. A house that has gone completely
silent is indistinguishable from a resident who collapsed and stopped moving (e.g.
a fall *outside* the home, where the door fired hours ago and everything is quiet
since). We therefore keep the anomaly safety net fully active and only ADD context —
the analyze route annotates its Warning/Emergency notifications with any currently
suspected-faulty sensors (via FAULTY_SENSORS_CACHE) so the family can judge for
themselves. The only legitimate way to silence alerts is the explicit, user-controlled
vacation mode.
"""
from datetime import datetime, timezone, timedelta

import database.database as database
import database.user_db as user_db
from app.alerts import notifications

# Sensor index → human-readable name (0=Door 1=Kitchen 2=Bath 3=Toilet 4=Meds 5=Bed 6=Living)
SENSOR_NAMES = {
    0: 'Front Door',
    1: 'Kitchen',
    2: 'Bathroom',
    3: 'Toilet',
    4: 'Medication',
    5: 'Bedroom',
    6: 'Living Room',
}

DOOR_INDEX = 0
SENSOR_FAULT_HOURS = 24          # a normally-used room silent this long → suspected fault
DOOR_FAULT_HOURS = 72            # the entrance door fires only on exits — give it longer
OFFLINE_THRESHOLD_MINUTES = 30   # master gateway silent this long → device offline

# house_id -> set[int] of sensor indices currently suspected faulty. Maintained by
# check_sensor_health and read by the analyze route to enrich anomaly alerts. Safe as
# a plain module global because gunicorn runs a single worker, so the scheduler and the
# request handlers share one process and one address space.
FAULTY_SENSORS_CACHE: dict = {}


def _sensor_name(i):
    return SENSOR_NAMES.get(i, f'Sensor {i}')


def _as_utc(dt):
    """Normalizes a (possibly naive) datetime to tz-aware UTC."""
    if dt is None:
        return None
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


# ---------------------------------------------------------------------------
# Per-sensor "suspected faulty sensor" detection
# ---------------------------------------------------------------------------

def check_sensor_health():
    """Scheduled hourly. Flags individual sensors that have gone quiet for too long."""
    try:
        house_ids = user_db.get_all_active_house_ids()
    except Exception as e:
        print(f'[SensorHealth] Could not list active houses: {e}')
        return

    now = datetime.now(timezone.utc)
    for house_id in house_ids:
        try:
            _check_house_sensor_health(house_id, now)
        except Exception as e:
            print(f'[SensorHealth] Error for house {house_id}: {e}')


def _check_house_sensor_health(house_id, now):
    state = database.get_house_health_doc(house_id)   # single Firestore read
    if state is None:
        return

    # Whole-home silence is expected on vacation — never flag sensors then.
    if state.get('is_vacation'):
        FAULTY_SENSORS_CACHE[house_id] = set()
        return

    # If the master itself isn't currently reporting, this is a connectivity outage
    # (handled by check_device_connectivity), not a per-sensor fault. Skip so we don't
    # fire a "faulty" alert for every sensor when the whole gateway is down.
    last_reading_at = _as_utc(state.get('last_reading_at'))
    if last_reading_at is None or (now - last_reading_at) > timedelta(minutes=OFFLINE_THRESHOLD_MINUTES):
        FAULTY_SENSORS_CACHE[house_id] = set()
        return

    mask = state.get('sensor_mask') or [1] * 7
    last_activity = state.get('last_sensor_activity') or {}
    already_sent = state.get('faulty_sensor_alert_sent') or {}

    # A sensor that has never fired is measured from house activation, so a fresh
    # install isn't flagged immediately. Lazily backfill activated_at for legacy
    # houses (giving them a full grace window from now rather than a burst of alerts).
    activated_at = _as_utc(state.get('activated_at'))
    if activated_at is None:
        activated_at = now
        database.set_activated_at(house_id, now)

    faulty = set()
    to_set = []      # indices to mark alert-sent
    to_clear = []    # indices to clear alert-sent (recovered)

    for i in range(7):
        if i >= len(mask) or mask[i] != 1:
            continue   # sensor not installed / not part of this house

        threshold = timedelta(hours=DOOR_FAULT_HOURS if i == DOOR_INDEX else SENSOR_FAULT_HOURS)
        ref = _as_utc(last_activity.get(i)) or activated_at
        silent_for = now - ref

        if silent_for >= threshold:
            faulty.add(i)
            if not already_sent.get(i):
                hours = int(silent_for.total_seconds() // 3600)
                notifications.trigger_sensor_fault_alert(house_id, _sensor_name(i), hours)
                database.log_sensor_fault_alert(house_id, i, _sensor_name(i), hours)
                to_set.append(i)
                print(f'[SensorHealth] {house_id}: {_sensor_name(i)} silent {hours}h — fault alert sent.')
        elif already_sent.get(i):
            # Sensor recovered — clear the flag so a future failure alerts again.
            to_clear.append(i)

    FAULTY_SENSORS_CACHE[house_id] = faulty
    if to_set or to_clear:
        database.update_faulty_sensor_flags(house_id, to_set, to_clear)


# ---------------------------------------------------------------------------
# Master-gateway offline detection (moved out of run.py so it runs in prod)
# ---------------------------------------------------------------------------

def check_device_connectivity():
    """Scheduled every 10 min. Alerts once when the ESP32 master has gone silent for
    30+ minutes. Offline state is persisted in Firestore so it survives restarts.

    Costs ONE Firestore read per house. This used to issue three separate get()s of
    the same house document (vacation flag, offline-alert flag, resident name) plus
    a sensor_vectors query for the newest reading — the latter being redundant, since
    log_vector_reading already denormalizes that timestamp onto the house doc as
    last_reading_at precisely so this check doesn't have to scan the subcollection.
    """
    try:
        house_ids = user_db.get_all_active_house_ids()
    except Exception as e:
        print(f'[Connectivity] Could not list active houses: {e}')
        return

    now = datetime.now(timezone.utc)
    threshold = timedelta(minutes=OFFLINE_THRESHOLD_MINUTES)

    for house_id in house_ids:
        try:
            state = database.get_house_health_doc(house_id)   # single Firestore read
            if state is None or state.get('is_vacation'):
                continue

            # last_reading_at is refreshed on EVERY post (even an all-zeros vector),
            # so it is the authoritative "master last spoke" timestamp. None means the
            # house has never reported — nothing to call an outage yet.
            last_time = _as_utc(state.get('last_reading_at'))
            if last_time is None:
                continue

            silent_for = now - last_time

            # clear_offline_alert_sent_at writes None rather than deleting the field,
            # so an explicit type check keeps "cleared" and "never set" equivalent.
            raw_sent_at = state.get('offline_alert_sent_at')
            already_alerted = isinstance(raw_sent_at, datetime)

            if silent_for < threshold:
                # Device is reporting — clear the flag so the next outage alerts again,
                # but only if it is actually set (saves a pointless write every run).
                if already_alerted:
                    database.clear_offline_alert_sent_at(house_id)
                continue

            if already_alerted:
                continue   # already alerted for this outage

            resident_name = state.get('resident_name') or 'your resident'
            minutes_silent = int(silent_for.total_seconds() // 60)
            notifications.trigger_device_offline_alert(house_id, resident_name, minutes_silent)
            database.log_device_offline_alert(house_id, minutes_silent)
            database.set_offline_alert_sent_at(house_id, now)
            print(f'[Connectivity] {house_id}: offline {minutes_silent} min — alert sent.')

        except Exception as e:
            print(f'[Connectivity] Error for house {house_id}: {e}')
