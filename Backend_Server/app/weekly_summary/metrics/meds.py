MEDS_SESSION_GAP_MINUTES = 10


def _compute_meds(day_df, house_mask):
    """Returns medication usage for the day.
    - count: number of distinct medication sessions (rising edges grouped within 10 min)
    - hours: sorted list of hour-of-day (float) for the first trigger of each session

    Returns None if sensor_4 is masked.
    """
    if house_mask[4] == 0:
        return None

    s4 = day_df['sensor_4']
    rising_edges = (s4 == 1) & (s4.shift(1, fill_value=0) == 0)
    events = day_df[rising_edges].sort_values('time')

    if events.empty:
        return {'count': 0, 'hours': []}

    # Group rising edges within 10 minutes into a single session
    sessions = []
    last_time = None
    for _, row in events.iterrows():
        if last_time is None or (row['time'] - last_time).total_seconds() / 60 > MEDS_SESSION_GAP_MINUTES:
            sessions.append(row['time'])
        last_time = row['time']

    hours = sorted(round(t.hour + t.minute / 60.0, 4) for t in sessions)
    return {'count': len(hours), 'hours': hours}
