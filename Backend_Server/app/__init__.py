import atexit
import os

from flask import Flask


def create_app():
    app = Flask(__name__)

    # Import blueprints locally to avoid circular dependencies
    from app.api.analyze_routes import analyze_bp
    from app.api.config_routes import config_bp
    from app.api.house_routes import house_bp
    from app.api.insights_routes import insights_bp

    app.register_blueprint(analyze_bp)
    app.register_blueprint(config_bp)
    app.register_blueprint(house_bp)
    app.register_blueprint(insights_bp)

    # Start the weekly insights scheduler only in the main process.
    # In Flask debug mode, Werkzeug spawns a reloader child process and sets
    # WERKZEUG_RUN_MAIN="true" there. We start the scheduler only in that child
    # (or when not in debug mode at all) to avoid double-scheduling.
    if os.environ.get("WERKZEUG_RUN_MAIN") == "true" or not app.debug:
        _setup_scheduler()

    return app


def _setup_scheduler():
    from apscheduler.schedulers.background import BackgroundScheduler
    from apscheduler.triggers.cron import CronTrigger

    import database.database as database
    from app.weekly_summary.report_generator import run_insights_pipeline

    def scheduled_weekly_insights():
        """Generates weekly wellness reports for every registered house."""
        try:
            house_docs = database.db.collection('houses').stream()
            house_ids = [doc.id for doc in house_docs]
            if not house_ids:
                print("[Scheduler] No houses found — skipping weekly insights.")
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

    scheduler = BackgroundScheduler(daemon=True)
    scheduler.add_job(
        func=scheduled_weekly_insights,
        trigger=CronTrigger(day_of_week='sun', hour=6, minute=0),
        id='weekly_insights',
        replace_existing=True,
        misfire_grace_time=3600,  # Fire up to 1h late if server was down at 06:00
    )
    scheduler.start()
    atexit.register(lambda: scheduler.shutdown(wait=False))

    print("[Scheduler] Weekly insights scheduler started — runs every Sunday at 06:00.")
