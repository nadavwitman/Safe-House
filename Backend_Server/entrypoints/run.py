import os
import sys
import atexit
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

# Prevent __init__.py from starting its own scheduler — run.py manages scheduling here.
os.environ.setdefault('ENABLE_SCHEDULER', 'false')

from app import create_app

import database.database as database
# Single source of truth — the health checks live in the app package so they ship in
# the Docker image (this file does not). Imported here only for the local dev server.
from app.monitoring.device_health import check_device_connectivity, check_sensor_health
from app.weekly_summary.report_generator import run_insights_pipeline

app = create_app()

def scheduled_weekly_insights():
    """Generates weekly wellness reports for every active house."""
    try:
        import database.user_db as user_db
        house_ids = user_db.get_all_active_house_ids()
        if not house_ids:
            print("[Scheduler] No active houses found — skipping weekly insights.")
            return

        from firebase_admin import firestore as _firestore

        for house_id in house_ids:
            try:
                print(f"[Scheduler] Generating weekly insights for house: {house_id}")
                raw_docs = database.get_weekly_sensor_data(house_id)
                metrics, ai_output = run_insights_pipeline(house_id, raw_docs)

                if metrics is None:
                    print(f"[Scheduler] Skipping {house_id} — insufficient data.")
                    continue

                period_start = min(d['date'] for d in metrics['days'])
                period_end = max(d['date'] for d in metrics['days'])

                report_dict = {
                    'period': {'start': period_start, 'end': period_end},
                    'generated_at': _firestore.SERVER_TIMESTAMP,
                    'metrics': metrics,
                    'ai_output': ai_output,
                }
                database.save_weekly_report(house_id, report_dict)
                print(f"[Scheduler] Report saved for house: {house_id}")

            except Exception as e:
                print(f"[Scheduler] Error generating report for house {house_id}: {e}")

    except Exception as e:
        print(f"[Scheduler] Fatal error in scheduled_weekly_insights: {e}")


def scheduled_fine_tuning_job():
    """Checks nightly and fine-tunes any house that's 14+ days overdue, persisting the
    updated model to Firebase Storage (download current model → fine-tune → upload →
    bump the fine-tune counter → refresh the RAM cache entry for that house)."""
    print("[03:00 AM] Starting automatic Weight Interpolation fine-tuning...")
    try:
        from app.ai.model_manager import run_weekly_mlops_pipeline_scalable
        run_weekly_mlops_pipeline_scalable()
        print("Nightly fine-tuning check completed.")
    except Exception as e:
        print(f"Error during scheduled fine-tuning: {e}")


def check_vacation_schedules():
    """Auto-activates/deactivates vacation mode based on stored schedules."""
    from datetime import datetime
    import database.user_db as user_db
    from app.state.data_buffer import sensor_buffer
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


scheduler = BackgroundScheduler()
scheduler.add_job(
    func=scheduled_weekly_insights,
    trigger=CronTrigger(day_of_week='sun', hour=6, minute=0),
    id='weekly_insights',
    replace_existing=True,
    misfire_grace_time=3600,
)
scheduler.add_job(
    func=scheduled_fine_tuning_job,
    trigger=CronTrigger(hour=3, minute=0),
    id='nightly_fine_tuning',
    replace_existing=True,
    misfire_grace_time=3600,
)
scheduler.add_job(
    func=check_vacation_schedules,
    trigger='interval',
    minutes=5,
    id='vacation_schedule_checker',
    replace_existing=True,
)
scheduler.add_job(
    func=check_device_connectivity,
    trigger='interval',
    minutes=10,
    id='device_connectivity_checker',
    replace_existing=True,
)
scheduler.add_job(
    func=check_sensor_health,
    trigger='interval',
    minutes=60,
    id='sensor_health_checker',
    replace_existing=True,
)

if os.environ.get('WERKZEUG_RUN_MAIN') != 'true':
    scheduler.start()
    atexit.register(lambda: scheduler.shutdown())
    print("[Scheduler] Weekly insights, fine-tuning, vacation schedule checker, device connectivity checker, and sensor health checker started.")

if __name__ == '__main__':
    # Run server: accessible externally, on port 5000, with debug mode on
    app.run(host='0.0.0.0', port=5000, debug=True, use_reloader=False)
