ZONE_NAMES = {
    0: "Door",
    1: "Kitchen",
    2: "Bathroom",
    3: "Toilet",
    4: "Medications",
    5: "Bedroom",
    6: "Living Room",
}

# The device posts a reading roughly once per minute — even while the resident is still
# (an all-zeros vector with a sticky location). So a gap between consecutive readings
# larger than this means the device DROPPED OUT (connectivity loss or a Firestore quota
# error that made the server 500 and skip the write), NOT continuous presence. Time
# attributed to a single reading is therefore capped here, so a multi-hour data outage
# can't be miscounted as hours of presence in the last-seen zone (which would then poison
# the durations and, through the EMA, the personal baseline).
MAX_ATTRIBUTABLE_GAP_MINUTES = 5

# The resident's local timezone — daily boundaries, the overnight sleep window, and
# medication times are all computed in local wall-clock, matching the LSTM preprocessing
# pipeline (data_preprocessing.py) which localizes to the same zone.
LOCAL_TZ = "Asia/Jerusalem"

# A day (or overnight window) must have data covering at least this fraction of its span
# — i.e., not be mostly a >cap blackout — for its metrics to be trusted. Capping gaps
# (above) stops an outage from INFLATING a duration; this stops the resulting UNDERCOUNT
# from a mostly-missing day from being fed as a low value into the averages and the EMA
# baseline. Below-threshold days are nulled, which PAUSES learning (the EMA keeps its
# previous value on None) instead of corrupting it. ~0.6 ≈ "average reading cadence
# better than ~8 min"; per-minute operation sits at ~1.0.
MIN_COVERAGE_FRACTION = 0.6
