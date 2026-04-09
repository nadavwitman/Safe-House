MAX_GAP_MINUTES = 60
INTERRUPTION_THRESHOLD_MINUTES = 10


def _compute_sleep_metrics(window_df, house_mask):
    """Computes sleep hours and interruptions from a 14-hour overnight window
    (20:00 prior day → 10:00 current day).

    sleep_hours:   total time spent in Bedroom (zone 5), clipped to [0, 16]
    interruptions: count of gaps where person left bedroom for > 10 consecutive minutes

    Returns None for both if Bedroom sensor (mask[5]) is masked.
    """
    if house_mask[5] == 0:
        return {'sleep_hours': None, 'interruptions': None}

    if window_df.empty:
        return {'sleep_hours': 0.0, 'interruptions': 0}

    df = window_df.sort_values('time').reset_index(drop=True)
    df['next_time'] = df['time'].shift(-1)
    df['gap_min'] = (df['next_time'] - df['time']).dt.total_seconds() / 60
    df['gap_min'] = df['gap_min'].clip(upper=MAX_GAP_MINUTES).fillna(0)

    # Total bedroom time
    bedroom_minutes = float(df.loc[df['current_location'] == 5, 'gap_min'].sum())
    sleep_hours = round(min(max(bedroom_minutes / 60, 0.0), 16.0), 2)

    # Interruptions: contiguous out-of-bedroom gaps > 5 minutes within the window
    interruptions = 0
    in_bedroom = df['current_location'] == 5

    # Find contiguous blocks outside the bedroom
    out_block_minutes = 0.0
    for _, row in df.iterrows():
        if row['current_location'] != 5:
            out_block_minutes += row['gap_min']
        else:
            if out_block_minutes > INTERRUPTION_THRESHOLD_MINUTES:
                interruptions += 1
            out_block_minutes = 0.0
    # Check final block
    if out_block_minutes > INTERRUPTION_THRESHOLD_MINUTES:
        interruptions += 1

    return {'sleep_hours': sleep_hours, 'interruptions': interruptions}
