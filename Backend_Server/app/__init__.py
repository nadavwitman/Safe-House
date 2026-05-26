import atexit
import os
from datetime import timedelta

from flask import Flask
from flask_jwt_extended import JWTManager
from flask_cors import CORS
from dotenv import load_dotenv

load_dotenv()


def create_app():
    app = Flask(__name__)

    app.config['JWT_SECRET_KEY'] = os.environ['JWT_SECRET_KEY']
    app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(minutes=30)
    app.config['JWT_REFRESH_TOKEN_EXPIRES'] = timedelta(days=30)

    JWTManager(app)
    CORS(app)

    # Import blueprints locally to avoid circular dependencies
    from app.api.analyze_routes import analyze_bp
    from app.api.config_routes import config_bp
    from app.api.house_routes import house_bp
    from app.api.insights_routes import insights_bp
    from app.api.auth_routes import auth_bp
    from app.api.user_routes import user_bp
    from app.api.admin_routes import admin_bp

    app.register_blueprint(analyze_bp)
    app.register_blueprint(config_bp)
    app.register_blueprint(house_bp)
    app.register_blueprint(insights_bp)
    app.register_blueprint(auth_bp)
    app.register_blueprint(user_bp)
    app.register_blueprint(admin_bp)

    # ENABLE_SCHEDULER=false on the API machine (Machine 1) — the dedicated
    # scheduler machine (Machine 2) runs its own APScheduler process via
    # scheduler_main.py, which avoids double-scheduling when scaling the API.
    if os.environ.get("ENABLE_SCHEDULER", "true").lower() == "true":
        if os.environ.get("WERKZEUG_RUN_MAIN") == "true" or not app.debug:
            _setup_scheduler()

    return app


def _setup_scheduler():
    from apscheduler.schedulers.background import BackgroundScheduler
    from apscheduler.triggers.cron import CronTrigger

    import database.database as database
    from app.weekly_summary.report_generator import run_insights_pipeline

    def scheduled_weekly_insights():
        """Generates weekly wellness reports for every active house."""
        try:
            from app.weekly_summary.model_manager import run_weekly_mlops_pipeline_scalable
            run_weekly_mlops_pipeline_scalable()
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

    def check_vacation_schedules():
        """Auto-activates/deactivates vacation mode based on stored schedules."""
        from datetime import datetime
        import database.user_db as _user_db
        from app.core.data_buffer import sensor_buffer

        try:
            house_ids = _user_db.get_all_active_house_ids()
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
                        sensor_buffer.is_active = False
                        sensor_buffer.clear_house(house_id)
                        print(f"[Scheduler] Vacation started for house {house_id}")
                    elif now > end and is_vacation:
                        database.set_vacation_mode(house_id, False)
                        database.clear_vacation_schedule(house_id)
                        sensor_buffer.is_active = True
                        print(f"[Scheduler] Vacation ended for house {house_id}, schedule cleared")
                except Exception as e:
                    print(f"[Scheduler] Error checking vacation for house {house_id}: {e}")
        except Exception as e:
            print(f"[Scheduler] Fatal error in check_vacation_schedules: {e}")

    scheduler = BackgroundScheduler(daemon=True)
    scheduler.add_job(
        func=scheduled_weekly_insights,
        trigger=CronTrigger(day_of_week='sun', hour=6, minute=0),
        id='weekly_insights',
        replace_existing=True,
        misfire_grace_time=3600,  # Fire up to 1h late if server was down at 06:00
    )
    scheduler.add_job(
        func=check_vacation_schedules,
        trigger='interval',
        minutes=5,
        id='vacation_schedule_checker',
        replace_existing=True,
    )
    scheduler.start()
    atexit.register(lambda: scheduler.shutdown(wait=False))

    print("[Scheduler] Weekly insights scheduler started — runs every Sunday at 06:00.")
    print("[Scheduler] Vacation schedule checker started — runs every 5 minutes.")
