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

    # ENABLE_SCHEDULER gates the in-process APScheduler so only one process ever
    # owns the scheduled jobs. entrypoints/wsgi.py (production) opts in;
    # entrypoints/run.py (local dev) manages its own scheduler and opts out here
    # to avoid running two schedulers side by side.
    if os.environ.get("ENABLE_SCHEDULER", "true").lower() == "true":
        # With use_reloader=False (or production), WERKZEUG_RUN_MAIN is never
        # set — start the scheduler directly. With reloader enabled, start only
        # in the child process to avoid running it twice.
        reloader_active = os.environ.get("WERKZEUG_RUN_MAIN") is not None
        is_reloader_child = os.environ.get("WERKZEUG_RUN_MAIN") == "true"
        if not reloader_active or is_reloader_child:
            _setup_scheduler()

    return app


def _setup_scheduler():
    from apscheduler.schedulers.background import BackgroundScheduler
    from apscheduler.triggers.cron import CronTrigger

    import database.database as database
    from app.weekly_summary.report_generator import generate_and_store

    def scheduled_nightly_fine_tuning():
        """Checks every active house nightly and fine-tunes any that are 14+ days overdue."""
        try:
            from app.ai.model_manager import run_weekly_mlops_pipeline_scalable
            run_weekly_mlops_pipeline_scalable()
        except Exception as e:
            print(f"[Scheduler] Fatal error in scheduled_nightly_fine_tuning: {e}")

    def scheduled_weekly_insights():
        """Generates weekly wellness reports for every active house."""
        try:
            import database.user_db as user_db
            house_ids = user_db.get_all_active_house_ids()
            if not house_ids:
                print("[Scheduler] No active houses found — skipping weekly insights.")
                return

            for house_id in house_ids:
                try:
                    # A house currently on vacation (toggled on directly or via an
                    # active vacation_schedule window — both flip the same is_vacation
                    # flag, see database/repositories/vacation.py) has its vacation
                    # readings filtered out of get_weekly_sensor_data anyway, so
                    # generating now would either produce a thin, mostly-empty report
                    # or waste a Gemini call outright. Skip and let the lazy catch-up
                    # (which also checks is_vacation) generate the report once real
                    # data resumes.
                    if database.get_vacation_mode(house_id):
                        print(f"[Scheduler] House {house_id} is currently in vacation mode. Skipping weekly insights.")
                        continue

                    print(f"[Scheduler] Generating weekly insights for house: {house_id}")
                    status, _ = generate_and_store(house_id)
                    if status == 'success':
                        print(f"[Scheduler] Report saved for house: {house_id}")
                    else:
                        print(f"[Scheduler] Skipping {house_id} — {status}.")

                except Exception as e:
                    print(f"[Scheduler] Error generating report for house {house_id}: {e}")

        except Exception as e:
            print(f"[Scheduler] Fatal error in scheduled_weekly_insights: {e}")

    def check_vacation_schedules():
        """Auto-activates/deactivates vacation mode based on stored schedules."""
        import database.user_db as _user_db
        from app.state.data_buffer import sensor_buffer
        from app.scheduling.vacation_window import parse_window, now_utc

        try:
            house_ids = _user_db.get_all_active_house_ids()
            now = now_utc()
            for house_id in house_ids:
                try:
                    # One read for both the schedule and the flag — fetching them
                    # separately re-read the same house document every 5 minutes.
                    state = database.get_vacation_state(house_id)
                    schedule = state['schedule']
                    if not schedule:
                        continue
                    # Absolute instants, so a server in a different timezone from
                    # the phone that wrote the trip still starts it on time.
                    window = parse_window(schedule)
                    if window is None:
                        print(f"[Scheduler] Unparseable vacation schedule for {house_id} — skipping.")
                        continue
                    start, end = window
                    is_vacation = state['is_vacation']
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

    from app.monitoring.device_health import check_device_connectivity, check_sensor_health

    scheduler = BackgroundScheduler(daemon=True)
    scheduler.add_job(
        func=scheduled_weekly_insights,
        trigger=CronTrigger(day_of_week='sun', hour=6, minute=0),
        id='weekly_insights',
        replace_existing=True,
        misfire_grace_time=3600,  # Fire up to 1h late if server was down at 06:00
    )
    # Nightly, not weekly: checks every active house and fine-tunes any that are 14+
    # days overdue (or in vacation mode / lacking a full 14-day data span get skipped
    # inside the pipeline). Decoupled from weekly_insights so a report failure can't
    # block retraining and vice versa.
    scheduler.add_job(
        func=scheduled_nightly_fine_tuning,
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
    # Device offline (master gateway silent 30+ min) — every 10 minutes.
    scheduler.add_job(
        func=check_device_connectivity,
        trigger='interval',
        minutes=10,
        id='device_connectivity_checker',
        replace_existing=True,
    )
    # Per-sensor "suspected faulty sensor" (a servant silent 24h / door 72h) — hourly.
    scheduler.add_job(
        func=check_sensor_health,
        trigger='interval',
        minutes=60,
        id='sensor_health_checker',
        replace_existing=True,
    )
    scheduler.start()
    atexit.register(lambda: scheduler.shutdown(wait=False))

    print("[Scheduler] Weekly insights scheduler started — runs every Sunday at 06:00.")
    print("[Scheduler] Nightly fine-tuning checker started — runs every night at 03:00.")
    print("[Scheduler] Vacation schedule checker started — runs every 5 minutes.")
    print("[Scheduler] Device connectivity checker started — runs every 10 minutes.")
    print("[Scheduler] Sensor health checker started — runs every 60 minutes.")
