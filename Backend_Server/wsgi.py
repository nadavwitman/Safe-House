import os
import atexit

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
    try:
        import database.user_db as user_db
        from app.core.ai_handler import fine_tune_house_model

        house_ids = user_db.get_all_active_house_ids()
        for house_id in house_ids:
            mask = database.get_sensor_mask(house_id)
            data = database.fetch_finetuning_data(house_id)
            fine_tune_house_model(house_id, data, mask)
        print("[Scheduler] Fine-tuning completed for all houses.")
    except Exception as e:
        print(f"[Scheduler] Fine-tuning error: {e}")


_ft_scheduler = BackgroundScheduler(daemon=True)
_ft_scheduler.add_job(_fine_tuning_job, CronTrigger(day='1,15', hour=3, minute=0))
_ft_scheduler.start()
atexit.register(lambda: _ft_scheduler.shutdown(wait=False))
