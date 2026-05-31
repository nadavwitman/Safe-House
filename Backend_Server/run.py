import os
import atexit
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger

# Prevent __init__.py from starting its own scheduler — run.py manages scheduling here.
os.environ.setdefault('ENABLE_SCHEDULER', 'false')

from app import create_app

import database.database as database
from app.core.ai_handler import fine_tune_house_model

app = create_app()

def scheduled_fine_tuning_job():
    """Fine tune the .pth file every 2 weeks at 3 AM."""
    print("[03:00 AM] Starting automatic Weight Interpolation fine-tuning...")
    try:
        import database.user_db as user_db
        house_ids = user_db.get_all_active_house_ids()
        for house_id in house_ids:
            print(f"Processing house number: {house_id}")
            mask = database.get_sensor_mask(house_id)
            new_training_data = database.fetch_finetuning_data(house_id)
            fine_tune_house_model(house_id, new_training_data, mask)
        print("Nightly fine-tuning completed successfully for all houses.")
    except Exception as e:
        print(f"Error during scheduled fine-tuning: {e}")


def check_vacation_schedules():
    """Auto-activates/deactivates vacation mode based on stored schedules."""
    from datetime import datetime
    import database.user_db as user_db
    from app.core.data_buffer import sensor_buffer
    try:
        house_ids = user_db.get_all_active_house_ids()
        now = datetime.now()
        for house_id in house_ids:
            try:
                schedule = database.get_vacation_schedule(house_id)
                if not schedule:
                    continue
                start = datetime.fromisoformat(
                    f"{schedule['startDate']}T{schedule['startTime']}")
                end = datetime.fromisoformat(
                    f"{schedule['endDate']}T{schedule['endTime']}")
                is_vacation = database.get_vacation_mode(house_id)
                if start <= now <= end and not is_vacation:
                    database.set_vacation_mode(house_id, True)
                    sensor_buffer.pause_house(house_id)
                    sensor_buffer.clear_house(house_id)
                    print(f"[Scheduler] Vacation started for house {house_id}")
                elif now > end and is_vacation:
                    database.set_vacation_mode(house_id, False)
                    database.clear_vacation_schedule(house_id)
                    sensor_buffer.resume_house(house_id)
                    print(f"[Scheduler] Vacation ended for house {house_id}, schedule cleared")
            except Exception as e:
                print(f"[Scheduler] Error checking vacation for house {house_id}: {e}")
    except Exception as e:
        print(f"[Scheduler] Fatal error in check_vacation_schedules: {e}")


OFFLINE_THRESHOLD_MINUTES = 30


def check_device_connectivity():
    """Alerts family members once when an ESP32 has been silent for 30+ minutes.
    Uses Firestore to persist alert state — survives server restarts."""
    from datetime import datetime, timezone, timedelta
    import database.user_db as user_db
    from app.core import notifications

    try:
        house_ids = user_db.get_all_active_house_ids()
        now = datetime.now(timezone.utc)
        threshold = timedelta(minutes=OFFLINE_THRESHOLD_MINUTES)

        for house_id in house_ids:
            try:
                if database.get_vacation_mode(house_id):
                    continue

                readings = database.get_recent_sensor_events(house_id, limit=1)
                if not readings:
                    continue

                last_time_str = readings[0].get('time')
                if not last_time_str:
                    continue

                last_time = datetime.fromisoformat(last_time_str)
                if last_time.tzinfo is None:
                    last_time = last_time.replace(tzinfo=timezone.utc)

                silent_for = now - last_time

                if silent_for < threshold:
                    # Device is back — clear the Firestore flag so next outage alerts again
                    database.clear_offline_alert_sent_at(house_id)
                    continue

                # Check Firestore: was an alert already sent for this outage?
                alert_sent_at = database.get_offline_alert_sent_at(house_id)
                if alert_sent_at is not None:
                    continue

                house = user_db.get_house(house_id)
                resident_name = house.get('resident_name', 'your resident') if house else 'your resident'
                minutes_silent = int(silent_for.total_seconds() // 60)
                notifications.trigger_device_offline_alert(house_id, resident_name, minutes_silent)
                database.log_device_offline_alert(house_id, minutes_silent)
                database.set_offline_alert_sent_at(house_id, now)
                print(f'[Scheduler] Offline alert sent for house {house_id} ({minutes_silent} min silent).')

            except Exception as e:
                print(f'[Scheduler] Error checking connectivity for house {house_id}: {e}')
    except Exception as e:
        print(f'[Scheduler] Fatal error in check_device_connectivity: {e}')


scheduler = BackgroundScheduler()
scheduler.add_job(
    func=scheduled_fine_tuning_job,
    trigger=CronTrigger(day='1,15', hour=3, minute=0),
)
scheduler.add_job(
    func=check_vacation_schedules,
    trigger='interval',
    minutes=5,
    id='vacation_schedule_checker',
)
scheduler.add_job(
    func=check_device_connectivity,
    trigger='interval',
    minutes=10,
    id='device_connectivity_checker',
)

if os.environ.get('WERKZEUG_RUN_MAIN') != 'true':
    scheduler.start()
    atexit.register(lambda: scheduler.shutdown())
    print("[Scheduler] Fine-tuning, vacation schedule checker, and device connectivity checker started.")

if __name__ == '__main__':
    # Run server: accessible externally, on port 5000, with debug mode on
    app.run(host='0.0.0.0', port=5000, debug=True, use_reloader=False)
