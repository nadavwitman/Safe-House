"""
Standalone scheduler process — runs on Machine 2 (t3.micro).

Handles:
  - Weekly wellness insights  (every Sunday at 06:00 UTC)
  - Model fine-tuning         (1st and 15th of every month at 03:00 UTC)

Machine 1 (API) sets ENABLE_SCHEDULER=false so only this process owns scheduling.
"""
import atexit
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from dotenv import load_dotenv
load_dotenv()

# Validate required env vars before going any further
_required = ['JWT_SECRET_KEY', 'FIREBASE_CREDENTIALS_PATH', 'GEMINI_API_KEY']
_missing = [v for v in _required if not os.environ.get(v)]
if _missing:
    print(f"[ERROR] Missing required environment variables: {', '.join(_missing)}")
    sys.exit(1)

from apscheduler.schedulers.blocking import BlockingScheduler
from apscheduler.triggers.cron import CronTrigger

import database.database as database
import database.user_db as user_db
from app.weekly_summary.report_generator import run_insights_pipeline
from app.weekly_summary.model_manager import run_weekly_mlops_pipeline_scalable
from firebase_admin import firestore as _firestore


def run_weekly_insights():
    print("[Scheduler] Starting weekly insights pipeline...")
    try:
        run_weekly_mlops_pipeline_scalable()

        house_ids = user_db.get_all_active_house_ids()
        if not house_ids:
            print("[Scheduler] No active houses — skipping.")
            return

        for house_id in house_ids:
            try:
                raw_docs = database.get_weekly_sensor_data(house_id)
                metrics, ai_output = run_insights_pipeline(house_id, raw_docs)

                if metrics is None:
                    print(f"[Scheduler] {house_id}: insufficient data, skipping.")
                    continue

                period_start = min(d['date'] for d in metrics['days'])
                period_end   = max(d['date'] for d in metrics['days'])
                database.save_weekly_report(house_id, {
                    'period':       {'start': period_start, 'end': period_end},
                    'generated_at': _firestore.SERVER_TIMESTAMP,
                    'metrics':      metrics,
                    'ai_output':    ai_output,
                })
                print(f"[Scheduler] {house_id}: report saved.")
            except Exception as e:
                print(f"[Scheduler] {house_id}: error — {e}")
    except Exception as e:
        print(f"[Scheduler] Fatal error in weekly insights: {e}")


def run_fine_tuning():
    print("[Scheduler] Starting fine-tuning pipeline...")
    try:
        run_weekly_mlops_pipeline_scalable()
        print("[Scheduler] Fine-tuning complete.")
    except Exception as e:
        print(f"[Scheduler] Fine-tuning error: {e}")


if __name__ == '__main__':
    scheduler = BlockingScheduler(timezone='UTC')

    scheduler.add_job(
        run_weekly_insights,
        trigger=CronTrigger(day_of_week='sun', hour=6, minute=0),
        id='weekly_insights',
        misfire_grace_time=3600,
    )
    scheduler.add_job(
        run_fine_tuning,
        trigger=CronTrigger(day='1,15', hour=3, minute=0),
        id='fine_tuning',
        misfire_grace_time=3600,
    )

    atexit.register(lambda: scheduler.shutdown(wait=False))

    print("[Scheduler] Started. Jobs: weekly insights (Sun 06:00), fine-tuning (1st+15th 03:00).")
    scheduler.start()
