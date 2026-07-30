from app.weekly_summary.constants import MAX_ATTRIBUTABLE_GAP_MINUTES as MAX_GAP_MINUTES


def _time_in_zones(day_df, zones):
    """Returns total minutes spent in the given zone indices using the time-delta method."""
    df = day_df.sort_values('time').reset_index(drop=True)
    df['next_time'] = df['time'].shift(-1)
    df['gap_min'] = (df['next_time'] - df['time']).dt.total_seconds() / 60
    df['gap_min'] = df['gap_min'].clip(upper=MAX_GAP_MINUTES).fillna(0)
    return float(round(df.loc[df['current_location'].isin(zones), 'gap_min'].sum(), 1))


def _compute_bath_duration(day_df, house_mask):
    """Total minutes in Bath (zone 2). Returns None if bath sensor is masked."""
    if house_mask[2] == 0:
        return None
    return _time_in_zones(day_df, [2])


def _compute_toilet_duration(day_df, house_mask):
    """Total minutes in Toilet (zone 3). Returns None if toilet sensor is masked."""
    if house_mask[3] == 0:
        return None
    return _time_in_zones(day_df, [3])


def _compute_food_prep_duration(day_df, house_mask):
    """Total minutes in Kitchen (zone 1). Returns None if kitchen sensor is masked."""
    if house_mask[1] == 0:
        return None
    return _time_in_zones(day_df, [1])
