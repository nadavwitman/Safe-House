import pandas as pd
from datetime import timedelta

from app.weekly_summary.metrics.sleep        import _compute_sleep_metrics
from app.weekly_summary.metrics.mobility     import _compute_mobility_metrics
from app.weekly_summary.metrics.nutrition    import _compute_nutrition_metrics
from app.weekly_summary.metrics.cognitive    import _compute_bath_duration, _compute_toilet_duration, _compute_food_prep_duration
from app.weekly_summary.metrics.meds        import _compute_meds
from app.weekly_summary.metrics.socialization import _compute_outside_duration


def aggregate_weekly_metrics(raw_docs, house_mask):
    """
    Aggregates a week of sensor readings into structured daily metrics.

    Parameters
    ----------
    raw_docs   : list[dict] — each with 'sensor_vector' (7-bit list), 'time' (datetime UTC),
                 'current_location' (7-bit one-hot list)
    house_mask : list[int] — 7-bit mask; 0 = sensor absent

    Returns
    -------
    dict with 'days' (list of per-day dicts) and 'weekly_averages' (dict)
    """
    df = pd.DataFrame(raw_docs)
    df['time'] = pd.to_datetime(df['time'], utc=True)

    # Decode current_location vector → int index (default 6 = Living Room)
    df['current_location'] = df['current_location'].apply(
        lambda v: int(v.index(1)) if isinstance(v, list) and 1 in v else 6
    )

    # Extract individual sensor columns needed by metric functions
    df['sensor_0'] = df['sensor_vector'].apply(lambda v: v[0] if isinstance(v, list) and len(v) > 0 else 0)
    df['sensor_1'] = df['sensor_vector'].apply(lambda v: v[1] if isinstance(v, list) and len(v) > 1 else 0)
    df['sensor_4'] = df['sensor_vector'].apply(lambda v: v[4] if isinstance(v, list) and len(v) > 4 else 0)

    df['date'] = df['time'].dt.date
    df = df.sort_values('time').reset_index(drop=True)

    unique_dates = sorted(df['date'].unique())
    daily_metrics = []

    for date in unique_dates:
        # Standard calendar day slice for non-sleep metrics
        day_df = df[df['date'] == date].copy()

        # 14-hour sleep window: 20:00 prior day → 10:00 current day
        window_start = pd.Timestamp(date, tz='UTC') - timedelta(hours=4)   # 20:00 prior = midnight - 4h
        window_end   = pd.Timestamp(date, tz='UTC') + timedelta(hours=10)  # 10:00 current
        sleep_window_df = df[(df['time'] >= window_start) & (df['time'] < window_end)].copy()

        sleep_m    = _compute_sleep_metrics(sleep_window_df, house_mask)
        mobility_m = _compute_mobility_metrics(day_df, house_mask)
        nutrition_m = _compute_nutrition_metrics(day_df, house_mask)
        bath       = _compute_bath_duration(day_df, house_mask)
        toilet     = _compute_toilet_duration(day_df, house_mask)
        food_prep  = _compute_food_prep_duration(day_df, house_mask)
        meds_m     = _compute_meds(day_df, house_mask)
        outside    = _compute_outside_duration(day_df, house_mask)

        daily_metrics.append({
            'date':              str(date),
            'sleep_hours':       sleep_m['sleep_hours'],
            'interruptions':     sleep_m['interruptions'],
            'transitions':       mobility_m['transitions'],
            'kitchen_triggers':  nutrition_m['kitchen_triggers'],
            'bath_duration':      bath,
            'toilet_duration':    toilet,
            'food_prep_duration': food_prep,
            'meds_count':        meds_m['count']  if meds_m is not None else None,
            'meds_hours':        meds_m['hours']  if meds_m is not None else None,
            'outside_duration':  outside,
        })

    return {'days': daily_metrics, 'weekly_averages': _compute_weekly_averages(daily_metrics)}


def _compute_weekly_averages(daily_metrics):
    def avg(values):
        clean = [v for v in values if v is not None]
        return round(sum(clean) / len(clean), 2) if clean else None

    return {
        'avg_sleep_hours':        avg([d['sleep_hours']        for d in daily_metrics]),
        'avg_interruptions':      avg([d['interruptions']      for d in daily_metrics]),
        'avg_transitions':        avg([d['transitions']        for d in daily_metrics]),
        'avg_kitchen_triggers':   avg([d['kitchen_triggers']   for d in daily_metrics]),
        'avg_bath_duration':       avg([d['bath_duration']       for d in daily_metrics]),
        'avg_toilet_duration':     avg([d['toilet_duration']     for d in daily_metrics]),
        'avg_food_prep_duration':  avg([d['food_prep_duration']  for d in daily_metrics]),
        'avg_outside_duration':   avg([d['outside_duration']   for d in daily_metrics]),
        'avg_meds_count':         avg([d['meds_count']         for d in daily_metrics]),
    }
