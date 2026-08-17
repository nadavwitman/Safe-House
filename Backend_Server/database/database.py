"""
Facade over database/repositories/* — kept as the single import surface
(`import database.database as database`) so callers don't need to know
which repository module actually owns a given function.
"""
from database.repositories.client import db

from database.repositories.sensor_readings import (
    get_sensor_mask,
    set_sensor_mask,
    log_vector_reading,
    get_recent_sensor_events,
    get_weekly_sensor_data,
    fetch_finetuning_data,
    FINETUNING_READING_TARGET,
)

from database.repositories.device_health import (
    get_house_health_doc,
    set_activated_at,
    update_faulty_sensor_flags,
    log_sensor_fault_alert,
    set_offline_alert_sent_at,
    clear_offline_alert_sent_at,
    log_device_offline_alert,
)

from database.repositories.vacation import (
    get_vacation_mode,
    set_vacation_mode,
    set_vacation_schedule,
    get_vacation_schedule,
    get_vacation_state,
    clear_vacation_schedule,
)

from database.repositories.alerts import (
    get_house_activity_meta,
    log_ai_decision,
    get_alert_history,
)

from database.repositories.model_state import (
    get_baseline,
    save_baseline,
    save_weekly_report,
    get_weekly_report,
)
