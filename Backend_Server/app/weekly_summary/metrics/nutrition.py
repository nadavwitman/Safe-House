def _compute_nutrition_metrics(day_df, house_mask):
    """Counts distinct kitchen sensor (sensor_1) trigger events.
    Consecutive 1s are clustered into a single event (rising-edge count).
    Returns None if sensor_1 is masked.
    """
    if house_mask[1] == 0:
        return {'kitchen_triggers': None}

    s1 = day_df['sensor_1']
    triggers = int(((s1 == 1) & (s1.shift(1, fill_value=0) == 0)).sum())
    return {'kitchen_triggers': triggers}
