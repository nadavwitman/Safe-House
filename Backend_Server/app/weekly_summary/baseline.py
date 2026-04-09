ALPHA = 0.05


# ---------------------------------------------------------------------------
# EMA core
# ---------------------------------------------------------------------------

def apply_ema(current, previous):
    """Applies EMA: current * 0.05 + previous * 0.95.
    Returns previous unchanged if current is None (masked week).
    Returns current directly if previous is None (first data point for this metric).
    """
    if current is None:
        return previous
    if previous is None:
        return current
    return round(current * ALPHA + previous * (1 - ALPHA), 4)


# ---------------------------------------------------------------------------
# Medication EMA helpers (nested structure)
# ---------------------------------------------------------------------------

def _update_meds_baseline(current_meds_by_day, existing_meds):
    """Updates meds.count_by_day and meds.hour_by_slot using EMA.

    current_meds_by_day: dict keyed by str(weekday_index) → {"count": int, "hours": list[float]}
    existing_meds: existing baseline["meds"] dict or None
    """
    existing = existing_meds or {"count_by_day": {}, "hour_by_slot": {}}

    # Update count_by_day — one EMA value per weekday
    new_count_by_day = dict(existing.get("count_by_day", {}))
    for day_key, day_data in current_meds_by_day.items():
        if day_data is None:
            continue
        new_count_by_day[day_key] = apply_ema(day_data["count"], new_count_by_day.get(day_key))

    # Update hour_by_slot — EMA per ordered usage position
    new_hour_by_slot = dict(existing.get("hour_by_slot", {}))
    # Collect all hours across all days this week, sorted per slot position
    all_hours_by_slot = {}
    for day_data in current_meds_by_day.values():
        if day_data is None or not day_data.get("hours"):
            continue
        for i, h in enumerate(sorted(day_data["hours"])):
            all_hours_by_slot.setdefault(str(i), []).append(h)

    # Average same-slot hours across days, then apply EMA to baseline slot
    for slot_key, hours in all_hours_by_slot.items():
        week_avg = sum(hours) / len(hours)
        new_hour_by_slot[slot_key] = apply_ema(week_avg, new_hour_by_slot.get(slot_key))

    return {"count_by_day": new_count_by_day, "hour_by_slot": new_hour_by_slot}


# ---------------------------------------------------------------------------
# Weekly averages extraction (what feeds into the baseline)
# ---------------------------------------------------------------------------

def compute_weekly_averages_for_baseline(daily_metrics):
    """Extracts per-metric weekly averages from the daily metrics list.
    Returns a dict ready to be passed to build_new_baseline.
    """
    def avg(values):
        clean = [v for v in values if v is not None]
        return round(sum(clean) / len(clean), 4) if clean else None

    # Meds: aggregate per weekday
    meds_by_day = {}
    for d in daily_metrics:
        if d.get('meds_count') is None:
            continue
        weekday_key = str(_date_to_weekday(d['date']))
        meds_by_day[weekday_key] = {
            'count': d['meds_count'],
            'hours': d.get('meds_hours') or [],
        }

    return {
        'sleep_hours':       avg([d.get('sleep_hours')       for d in daily_metrics]),
        'interruptions':     avg([d.get('interruptions')     for d in daily_metrics]),
        'transitions':       avg([d.get('transitions')       for d in daily_metrics]),
        'kitchen_triggers':  avg([d.get('kitchen_triggers')  for d in daily_metrics]),
        'bath_duration':      avg([d.get('bath_duration')      for d in daily_metrics]),
        'toilet_duration':    avg([d.get('toilet_duration')    for d in daily_metrics]),
        'food_prep_duration': avg([d.get('food_prep_duration') for d in daily_metrics]),
        'outside_duration':  avg([d.get('outside_duration')  for d in daily_metrics]),
        'meds_by_day':       meds_by_day or None,
    }


def _date_to_weekday(date_str):
    """Converts a 'YYYY-MM-DD' string to weekday index (0=Mon … 6=Sun)."""
    from datetime import date
    y, m, d = map(int, date_str.split('-'))
    return date(y, m, d).weekday()


# ---------------------------------------------------------------------------
# Baseline build / update
# ---------------------------------------------------------------------------

def build_new_baseline(current_avgs, existing_baseline):
    """Seeds a new baseline (first run) or applies EMA to update it.

    existing_baseline: None on first run, existing dict otherwise.
    Returns the new baseline dict (does not mutate inputs).
    """
    if existing_baseline is None:
        # First run: seed directly from current week averages
        new = {k: v for k, v in current_avgs.items() if k != 'meds_by_day'}
        if current_avgs.get('meds_by_day'):
            new['meds'] = _update_meds_baseline(current_avgs['meds_by_day'], None)
        return new

    new = dict(existing_baseline)
    scalar_keys = ['sleep_hours', 'interruptions', 'transitions', 'kitchen_triggers',
                   'bath_duration', 'toilet_duration', 'food_prep_duration', 'outside_duration']
    for key in scalar_keys:
        new[key] = apply_ema(current_avgs.get(key), existing_baseline.get(key))

    if current_avgs.get('meds_by_day'):
        new['meds'] = _update_meds_baseline(current_avgs['meds_by_day'], existing_baseline.get('meds'))

    return new


# ---------------------------------------------------------------------------
# Delta computation
# ---------------------------------------------------------------------------

def compute_deltas(current_avgs, baseline):
    """Returns signed deltas (current - baseline) for each metric.
    Returns None if no baseline exists yet (first run).
    """
    if baseline is None:
        return None

    def delta(current, base):
        if current is None or base is None:
            return None
        return round(current - base, 4)

    deltas = {
        'sleep_hours':        delta(current_avgs.get('sleep_hours'),        baseline.get('sleep_hours')),
        'interruptions':      delta(current_avgs.get('interruptions'),      baseline.get('interruptions')),
        'transitions':        delta(current_avgs.get('transitions'),        baseline.get('transitions')),
        'kitchen_triggers':   delta(current_avgs.get('kitchen_triggers'),   baseline.get('kitchen_triggers')),
        'bath_duration':       delta(current_avgs.get('bath_duration'),       baseline.get('bath_duration')),
        'toilet_duration':     delta(current_avgs.get('toilet_duration'),     baseline.get('toilet_duration')),
        'food_prep_duration':  delta(current_avgs.get('food_prep_duration'),  baseline.get('food_prep_duration')),
        'outside_duration':   delta(current_avgs.get('outside_duration'),   baseline.get('outside_duration')),
    }

    # Meds deltas: count per weekday + per slot hour
    meds_baseline = baseline.get('meds', {})
    meds_by_day = current_avgs.get('meds_by_day') or {}
    meds_deltas = {}
    for day_key, day_data in meds_by_day.items():
        if day_data is None:
            continue
        base_count = meds_baseline.get('count_by_day', {}).get(day_key)
        slot_deltas = []
        base_slots = meds_baseline.get('hour_by_slot', {})
        for i, h in enumerate(sorted(day_data.get('hours') or [])):
            base_h = base_slots.get(str(i))
            slot_deltas.append(delta(h, base_h))
        # Pad with None for skipped slots
        for i in range(len(slot_deltas), len(base_slots)):
            slot_deltas.append(None)
        meds_deltas[day_key] = {
            'delta_count': delta(day_data['count'], base_count),
            'delta_hours': slot_deltas,
        }
    deltas['meds'] = meds_deltas or None

    return deltas
