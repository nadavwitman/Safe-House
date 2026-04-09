def _compute_mobility_metrics(day_df, house_mask):
    transitions = int(day_df['current_location'].diff().fillna(0).ne(0).sum())
    return {'transitions': transitions}
