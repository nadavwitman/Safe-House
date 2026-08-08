import os
import sys
import atexit

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

# Let __init__.py start the weekly-insights + vacation-checker scheduler.
os.environ.setdefault('ENABLE_SCHEDULER', 'true')

from app import create_app
import database.database as database

application = create_app()

# Fine-tuning scheduler — runs on the 1st and 15th of every month at 03:00.
# Kept here (not in __init__.py) so it only runs in the production process,
# not during tests or local flask dev server usage.
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger


def _fine_tuning_job():
    # Delegate to the MLOps pipeline, which fine-tunes AND persists each updated model to
    # Firebase Storage (bumping the fine-tune counter and invalidating the RAM cache). The
    # previous inline loop trained models and discarded the return value, so personalization
    # never actually took effect.
    try:
        from app.weekly_summary.model_manager import run_weekly_mlops_pipeline_scalable
        run_weekly_mlops_pipeline_scalable()
        print("[Scheduler] Fine-tuning completed for all houses.")
    except Exception as e:
        print(f"[Scheduler] Fine-tuning error: {e}")


_ft_scheduler = BackgroundScheduler(daemon=True)
_ft_scheduler.add_job(_fine_tuning_job, CronTrigger(day='1,15', hour=3, minute=0))
_ft_scheduler.start()
atexit.register(lambda: _ft_scheduler.shutdown(wait=False))
