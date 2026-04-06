import os
import atexit
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger

from app import create_app

import database.database as database
from app.core.ai_handler import fine_tune_house_model

app = create_app()

def scheduled_fine_tuning_job():
    """
    Fine tune the .pth file every 2 weeks at 3 AM
    """
    print("[03:00 AM] Starting automatic Weight Interpolation fine-tuning...")

    try:
        # Go throguh all the houses in the database
        houses_ref = database.db.collection('houses').stream()

        for house_doc in houses_ref:
            house_id = house_doc.id
            print(f"Processing house number: {house_id}")

            # fetch the data from the last 14 days
            mask = database.get_sensor_mask(house_id)
            new_training_data = database.fetch_finetuning_data(house_id)

            # Acticvate the fine tuning function
            fine_tune_house_model(house_id, new_training_data, mask)

        print("Nightly fine-tuning completed successfully for all houses.")
    except Exception as e:
        print(f"Error during scheduled fine-tuning: {e}")

# Define the scheduler itself
scheduler = BackgroundScheduler()

# The scheduler will run in the first day of every month and 2 weeks afterwards
scheduler.add_job(
    func=scheduled_fine_tuning_job,
    trigger=CronTrigger(day='1,15', hour=3, minute=0)
)

# Debug
if os.environ.get('WERKZEUG_RUN_MAIN') != 'true':
    scheduler.start()
    atexit.register(lambda: scheduler.shutdown())

if __name__ == '__main__':
    # activate the backend server
    app.run(debug=True, host='0.0.0.0', port=5000)
