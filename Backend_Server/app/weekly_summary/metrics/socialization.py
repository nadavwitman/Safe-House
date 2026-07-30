from app.weekly_summary.constants import MAX_ATTRIBUTABLE_GAP_MINUTES as MAX_GAP_MINUTES


def _compute_outside_duration(day_df, house_mask):
    """Total minutes where current_location == 0 (Door zone = outside).
    Returns None if door sensor is masked.
    """
    if house_mask[0] == 0:
        return None

    outside = day_df[day_df['current_location'] == 0].copy()
    if outside.empty:
        return 0.0

    # Time-delta method: attribute duration from row N to row N+1 to zone of row N
    df_sorted = day_df.sort_values('time').reset_index(drop=True)
    df_sorted['next_time'] = df_sorted['time'].shift(-1)
    df_sorted['gap_min'] = (df_sorted['next_time'] - df_sorted['time']).dt.total_seconds() / 60
    df_sorted['gap_min'] = df_sorted['gap_min'].clip(upper=MAX_GAP_MINUTES).fillna(0)

    total = float(df_sorted.loc[df_sorted['current_location'] == 0, 'gap_min'].sum())
    return round(total, 1)
