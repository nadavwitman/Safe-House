"""
Tests for the Weekly AI Insights feature.

Covers:
  - weekly_aggregator.py — all 5 feature categories (unit tests, no DB)
  - insights_generator.py — prompt formatting and data-guard logic (no Gemini)
  - database integration — saves a mock weekly report to Firestore and reads it back

Run from the Backend_Server directory:
    python tests/test_weekly_insights.py
"""

import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from datetime import datetime, timezone

import pandas as pd

from app.core.weekly_aggregator import (
    _compute_sleep_metrics,
    _compute_sleep_quality_score,
    _compute_sleep_consistency,
    _compute_mobility_metrics,
    _compute_activity_score,
    _compute_meal_metrics,
    _compute_door_exits,
    _compute_visitor_events,
    _compute_night_door_events,
    _compute_morning_sequence,
    _compute_medication_adherence,
    aggregate_weekly_metrics,
)
from app.core.insights_generator import format_compact_prompt, run_insights_pipeline

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _ts(date_str, hour, minute=0):
    return pd.Timestamp(f"{date_str}T{hour:02d}:{minute:02d}:00", tz='UTC')


def _make_day_df(readings):
    records = []
    for r in readings:
        sv = r.get('sensor_vector', [0] * 7)
        records.append({
            'time': r['time'],
            'current_location': r['current_location'],
            'sensor_vector': sv,
            'sensor_0': sv[0] if len(sv) > 0 else 0,
            'sensor_4': sv[4] if len(sv) > 4 else 0,
            'hour': r['time'].hour + r['time'].minute / 60.0,
        })
    return pd.DataFrame(records).sort_values('time').reset_index(drop=True)


def _make_raw_docs(day_readings_by_date):
    docs = []
    for date_str, readings in day_readings_by_date.items():
        for (hour, minute, loc, sv) in readings:
            docs.append({
                'sensor_vector': sv,
                'time': _ts(date_str, hour, minute),
                'current_location': loc,
            })
    return docs


def _build_typical_week():
    dates = [
        "2026-03-31", "2026-04-01", "2026-04-02",
        "2026-04-03", "2026-04-04", "2026-04-05", "2026-04-06",
    ]
    sv_door = [1, 0, 0, 0, 0, 0, 0]
    sv_med  = [0, 0, 0, 0, 1, 0, 0]
    sv_none = [0, 0, 0, 0, 0, 0, 0]

    day_readings = {}
    for date in dates:
        day_readings[date] = [
            (22, 30, 5, sv_none),   # Go to bed
            (23, 0,  5, sv_none),   # Still in bed
            (7,  0,  2, sv_none),   # Wake → Bathroom
            (7,  15, 1, sv_none),   # Breakfast → Kitchen
            (7,  45, 6, sv_none),   # Living room
            (9,  0,  4, sv_med),    # Medications
            (12, 0,  1, sv_none),   # Lunch
            (13, 0,  6, sv_none),   # Living room
            (14, 0,  0, sv_door),   # Door exit
            (18, 0,  1, sv_none),   # Dinner
            (19, 0,  6, sv_none),   # Living room
        ]
    return _make_raw_docs(day_readings)


# ============================================================================
# Category 1 — Sleep
# ============================================================================

def test_sleep_bedtime_and_wake_detection():
    # Bedtime at 01:30 (hour < 3, person is in bed in the early hours of this date)
    # Wake at 07:15 (first transition away from bedroom in morning window)
    # Sleep = 07:15 - 01:30 = 5.75h
    date = "2026-04-01"
    readings = [
        {'time': _ts(date,  1, 30), 'current_location': 5, 'sensor_vector': [0]*7},
        {'time': _ts(date,  2,  0), 'current_location': 5, 'sensor_vector': [0]*7},
        {'time': _ts(date,  7, 15), 'current_location': 2, 'sensor_vector': [0]*7},
    ]
    result = _compute_sleep_metrics(_make_day_df(readings))
    assert result['bedtime'] is not None, "Bedtime should be detected"
    assert result['wake_time'] is not None, "Wake time should be detected"
    assert result['sleep_hours'] is not None, "Sleep hours should be computed"
    # Last bedtime row = 02:00; wake = 07:15 → 5.25h
    assert 5.0 <= result['sleep_hours'] <= 5.5, f"Expected ~5.25h, got {result['sleep_hours']}"
    assert result['nocturnal_visits'] == 0


def test_sleep_nocturnal_visits_counted():
    date = "2026-04-01"
    readings = [
        {'time': _ts(date, 22,  0), 'current_location': 5, 'sensor_vector': [0]*7},
        {'time': _ts(date,  2, 15), 'current_location': 3, 'sensor_vector': [0]*7},  # Toilet 02:15
        {'time': _ts(date,  4, 45), 'current_location': 2, 'sensor_vector': [0]*7},  # Bathroom 04:45
        {'time': _ts(date,  7, 30), 'current_location': 6, 'sensor_vector': [0]*7},
    ]
    result = _compute_sleep_metrics(_make_day_df(readings))
    assert result['nocturnal_visits'] == 2, f"Expected 2, got {result['nocturnal_visits']}"


def test_sleep_quality_score_good_sleep():
    assert _compute_sleep_quality_score({'sleep_hours': 7.5, 'nocturnal_visits': 0}) == 100


def test_sleep_quality_score_short_sleep():
    assert _compute_sleep_quality_score({'sleep_hours': 4.5, 'nocturnal_visits': 0}) == 70


def test_sleep_quality_score_missing_data():
    assert _compute_sleep_quality_score({'sleep_hours': None, 'nocturnal_visits': 0}) == 70


def test_sleep_quality_score_nocturnal_penalty():
    assert _compute_sleep_quality_score({'sleep_hours': 7.5, 'nocturnal_visits': 3}) == 76


def test_sleep_consistency_consistent_schedule():
    dates = ["2026-04-01", "2026-04-02", "2026-04-03", "2026-04-04",
             "2026-04-05", "2026-04-06", "2026-04-07"]
    all_sleep = [
        {'bedtime': _ts(d, 1, 30), 'wake_time': _ts(d, 7, 0),
         'sleep_hours': 5.5, 'nocturnal_visits': 0}
        for d in dates
    ]
    result = _compute_sleep_consistency(all_sleep)
    assert result['sleep_consistency_score'] is not None
    assert result['sleep_consistency_score'] >= 90, f"Got {result['sleep_consistency_score']}"


def test_sleep_consistency_insufficient_data():
    all_sleep = [{'bedtime': None, 'wake_time': None, 'sleep_hours': None, 'nocturnal_visits': 0}] * 3
    result = _compute_sleep_consistency(all_sleep)
    assert result['sleep_consistency_score'] is None


# ============================================================================
# Category 2 — Mobility & Vitality
# ============================================================================

def test_zone_transitions_counted():
    readings = [
        {'time': _ts("2026-04-01",  8), 'current_location': 5, 'sensor_vector': [0]*7},
        {'time': _ts("2026-04-01",  9), 'current_location': 2, 'sensor_vector': [0]*7},
        {'time': _ts("2026-04-01", 10), 'current_location': 1, 'sensor_vector': [0]*7},
        {'time': _ts("2026-04-01", 11), 'current_location': 6, 'sensor_vector': [0]*7},
    ]
    result = _compute_mobility_metrics(_make_day_df(readings))
    assert result['zone_transitions'] == 3, f"Expected 3, got {result['zone_transitions']}"


def test_zone_distribution_sums_to_100():
    readings = [
        {'time': _ts("2026-04-01", h), 'current_location': loc, 'sensor_vector': [0]*7}
        for h, loc in [(8, 5), (9, 1), (10, 6), (11, 1), (12, 6)]
    ]
    result = _compute_mobility_metrics(_make_day_df(readings))
    total = sum(result['zone_distribution'].values())
    assert abs(total - 100.0) < 0.5, f"Distribution should sum to 100, got {total}"


def test_activity_score_high_activity():
    score = _compute_activity_score(30, {'kitchen_visits': 10}, 3)
    assert score == 100


def test_activity_score_sedentary():
    score = _compute_activity_score(0, {'kitchen_visits': 0}, 0)
    assert score == 0


# ============================================================================
# Category 3 — Nutrition & Self-Care
# ============================================================================

def test_meal_detection_all_meals():
    readings = [
        {'time': _ts("2026-04-01",  7), 'current_location': 6, 'sensor_vector': [0]*7},
        {'time': _ts("2026-04-01",  7, 30), 'current_location': 1, 'sensor_vector': [0]*7},  # breakfast
        {'time': _ts("2026-04-01",  8), 'current_location': 6, 'sensor_vector': [0]*7},
        {'time': _ts("2026-04-01", 12), 'current_location': 1, 'sensor_vector': [0]*7},  # lunch
        {'time': _ts("2026-04-01", 13), 'current_location': 6, 'sensor_vector': [0]*7},
        {'time': _ts("2026-04-01", 18), 'current_location': 1, 'sensor_vector': [0]*7},  # dinner
    ]
    result = _compute_meal_metrics(_make_day_df(readings))
    assert result['kitchen_visits'] == 3
    assert result['breakfast'] and result['lunch'] and result['dinner']


def test_meal_detection_no_meals():
    readings = [
        {'time': _ts("2026-04-01", h), 'current_location': 6, 'sensor_vector': [0]*7}
        for h in range(8, 22)
    ]
    result = _compute_meal_metrics(_make_day_df(readings))
    assert result['kitchen_visits'] == 0
    assert not result['breakfast'] and not result['lunch'] and not result['dinner']


# ============================================================================
# Category 4 — Socialization & Outdoor Activity
# ============================================================================

def test_door_exits_counted():
    sv_d = [1, 0, 0, 0, 0, 0, 0]
    sv_n = [0]*7
    readings = [
        {'time': _ts("2026-04-01",  9), 'current_location': 0, 'sensor_vector': sv_d},
        {'time': _ts("2026-04-01", 12), 'current_location': 0, 'sensor_vector': sv_d},
        {'time': _ts("2026-04-01", 16), 'current_location': 6, 'sensor_vector': sv_n},
        {'time': _ts("2026-04-01", 17), 'current_location': 0, 'sensor_vector': sv_d},
    ]
    assert _compute_door_exits(_make_day_df(readings)) == 3


def test_visitor_detection_visitor_present():
    """Door opens but person stays at door for 5+ readings → visitor."""
    sv_d = [1, 0, 0, 0, 0, 0, 0]
    sv_n = [0]*7
    # Door activation at index 1; next 5 readings (indices 2-6) must all stay at location 0
    readings = [
        {'time': _ts("2026-04-01", 14,  0), 'current_location': 6, 'sensor_vector': sv_n},
        {'time': _ts("2026-04-01", 14,  1), 'current_location': 0, 'sensor_vector': sv_d},
        {'time': _ts("2026-04-01", 14,  2), 'current_location': 0, 'sensor_vector': sv_n},
        {'time': _ts("2026-04-01", 14,  3), 'current_location': 0, 'sensor_vector': sv_n},
        {'time': _ts("2026-04-01", 14,  4), 'current_location': 0, 'sensor_vector': sv_n},
        {'time': _ts("2026-04-01", 14,  5), 'current_location': 0, 'sensor_vector': sv_n},
        {'time': _ts("2026-04-01", 14,  6), 'current_location': 0, 'sensor_vector': sv_n},
        {'time': _ts("2026-04-01", 14, 10), 'current_location': 6, 'sensor_vector': sv_n},
    ]
    assert _compute_visitor_events(_make_day_df(readings)) == 1


def test_visitor_detection_resident_exits():
    """Door opens and person immediately moves inside → exit, not visitor."""
    sv_d = [1, 0, 0, 0, 0, 0, 0]
    sv_n = [0]*7
    readings = [
        {'time': _ts("2026-04-01", 10, 0), 'current_location': 6, 'sensor_vector': sv_n},
        {'time': _ts("2026-04-01", 10, 1), 'current_location': 0, 'sensor_vector': sv_d},
        {'time': _ts("2026-04-01", 10, 2), 'current_location': 6, 'sensor_vector': sv_n},
    ]
    assert _compute_visitor_events(_make_day_df(readings)) == 0


def test_night_door_events_at_3am():
    sv_d = [1, 0, 0, 0, 0, 0, 0]
    readings = [
        {'time': _ts("2026-04-01",  3), 'current_location': 0, 'sensor_vector': sv_d},
        {'time': _ts("2026-04-01", 10), 'current_location': 1, 'sensor_vector': [0]*7},
    ]
    assert _compute_night_door_events(_make_day_df(readings)) == 1


def test_night_door_events_daytime_only():
    sv_d = [1, 0, 0, 0, 0, 0, 0]
    readings = [
        {'time': _ts("2026-04-01",  9), 'current_location': 0, 'sensor_vector': sv_d},
        {'time': _ts("2026-04-01", 14), 'current_location': 0, 'sensor_vector': sv_d},
    ]
    assert _compute_night_door_events(_make_day_df(readings)) == 0


# ============================================================================
# Category 5 — Cognitive Routine Stability
# ============================================================================

def test_morning_sequence_correct_order():
    readings = [
        {'time': _ts("2026-04-01", 6), 'current_location': 5, 'sensor_vector': [0]*7},
        {'time': _ts("2026-04-01", 7), 'current_location': 2, 'sensor_vector': [0]*7},
        {'time': _ts("2026-04-01", 7, 30), 'current_location': 1, 'sensor_vector': [0]*7},
    ]
    assert _compute_morning_sequence(_make_day_df(readings)) is True


def test_morning_sequence_wrong_order():
    readings = [
        {'time': _ts("2026-04-01", 6), 'current_location': 1, 'sensor_vector': [0]*7},
        {'time': _ts("2026-04-01", 7), 'current_location': 2, 'sensor_vector': [0]*7},
        {'time': _ts("2026-04-01", 8), 'current_location': 5, 'sensor_vector': [0]*7},
    ]
    assert _compute_morning_sequence(_make_day_df(readings)) is False


def test_morning_sequence_outside_window():
    readings = [
        {'time': _ts("2026-04-01", 13), 'current_location': 5, 'sensor_vector': [0]*7},
        {'time': _ts("2026-04-01", 14), 'current_location': 2, 'sensor_vector': [0]*7},
        {'time': _ts("2026-04-01", 15), 'current_location': 1, 'sensor_vector': [0]*7},
    ]
    assert _compute_morning_sequence(_make_day_df(readings)) is False


def test_medication_adherence_taken():
    sv_m = [0, 0, 0, 0, 1, 0, 0]
    readings = [
        {'time': _ts("2026-04-01", 9), 'current_location': 4, 'sensor_vector': sv_m},
    ]
    assert _compute_medication_adherence(_make_day_df(readings)) is True


def test_medication_adherence_not_taken():
    readings = [
        {'time': _ts("2026-04-01", 9), 'current_location': 6, 'sensor_vector': [0]*7},
    ]
    assert _compute_medication_adherence(_make_day_df(readings)) is False


# ============================================================================
# Full aggregation
# ============================================================================

def test_aggregate_weekly_structure():
    raw_docs = _build_typical_week()
    result = aggregate_weekly_metrics(raw_docs)

    assert len(result['days']) == 7, f"Expected 7 days, got {len(result['days'])}"

    required_day_keys = [
        'date', 'weekday', 'sleep_hours', 'sleep_quality_score', 'nocturnal_visits',
        'activity_score', 'zone_transitions', 'zone_distribution',
        'kitchen_visits', 'breakfast', 'lunch', 'dinner',
        'door_exits', 'visitor_events', 'night_door_events',
        'morning_sequence_ok', 'medication_taken',
    ]
    for key in required_day_keys:
        assert key in result['days'][0], f"Missing daily key: {key}"

    required_avg_keys = [
        'avg_sleep_hours', 'avg_sleep_quality_score', 'sleep_consistency_score',
        'avg_activity_score', 'avg_zone_transitions_per_day', 'avg_zone_distribution',
        'avg_kitchen_visits', 'meal_days', 'avg_door_exits',
        'total_visitor_events', 'total_night_door_events',
        'morning_sequence_correct_days', 'medication_adherence_days',
    ]
    for key in required_avg_keys:
        assert key in result['weekly_averages'], f"Missing weekly_averages key: {key}"


def test_aggregate_healthy_week_values():
    result = aggregate_weekly_metrics(_build_typical_week())
    wa = result['weekly_averages']
    assert wa['medication_adherence_days'] == 7
    assert wa['total_night_door_events'] == 0
    assert wa['meal_days']['breakfast'] == 7
    assert wa['meal_days']['lunch'] == 7
    assert wa['meal_days']['dinner'] == 7


# ============================================================================
# Insights generator — guard logic and prompt formatting
# ============================================================================

def test_insufficient_data_returns_none():
    dates = ["2026-04-05", "2026-04-06"]
    raw_docs = _make_raw_docs({d: [(10, 0, 6, [0]*7), (14, 0, 1, [0]*7)] for d in dates})
    metrics, ai_output = run_insights_pipeline("test_house", raw_docs)
    assert metrics is None and ai_output is None


def test_empty_raw_docs_returns_none():
    metrics, ai_output = run_insights_pipeline("test_house", [])
    assert metrics is None and ai_output is None


def test_format_compact_prompt_no_previous_week():
    metrics = aggregate_weekly_metrics(_build_typical_week())
    prompt = format_compact_prompt(metrics, None, "test_house")
    assert "PREVIOUS WEEK" not in prompt
    assert "WEEKLY WELLNESS DATA" in prompt
    assert "DAILY LOG" in prompt
    assert "WEEKLY AVERAGES" in prompt


def test_format_compact_prompt_with_previous_week():
    metrics = aggregate_weekly_metrics(_build_typical_week())
    prompt = format_compact_prompt(metrics, metrics, "test_house")
    assert "PREVIOUS WEEK FOR COMPARISON" in prompt


def test_format_compact_prompt_covers_all_categories():
    metrics = aggregate_weekly_metrics(_build_typical_week())
    prompt = format_compact_prompt(metrics, None, "test_house")
    for token in ["Sleep", "Activity", "Kitchen", "Door", "Meds", "Seq"]:
        assert token in prompt, f"Prompt missing: {token}"


# ============================================================================
# DB integration — writes a mock report to Firestore and reads it back
# ============================================================================

TEST_HOUSE_ID = "test_weekly_insights_cleanup"

def test_db_save_and_read_weekly_report():
    """
    Generates a mock weekly report from synthetic data and saves it to Firestore.
    Reads it back and verifies the structure.
    The test document is written to house '{TEST_HOUSE_ID}' — visible in Firebase console.
    """
    from firebase_admin import firestore as _firestore
    from database.database import db, save_weekly_report, get_previous_report_metrics

    raw_docs = _build_typical_week()
    metrics = aggregate_weekly_metrics(raw_docs)

    mock_ai_output = {
        "summary": "TEST REPORT — This is a synthetic weekly report generated by the test suite.",
        "insights": {
            "sleep": "Sleep quality was excellent throughout the week.",
            "mobility": "Activity levels were high with consistent zone transitions.",
            "nutrition": "All meals were detected on every day of the week.",
            "socialization": "One door exit per day with no nighttime anomalies.",
            "cognitive": "Morning sequence was correctly completed every day.",
        },
        "recommendations": [
            "All patterns look healthy — no action required.",
            "Continue current routine consistency.",
        ],
    }

    period_start = min(d['date'] for d in metrics['days'])
    period_end   = max(d['date'] for d in metrics['days'])

    report_dict = {
        'period':       {'start': period_start, 'end': period_end},
        'generated_at': _firestore.SERVER_TIMESTAMP,
        'metrics':      metrics,
        'ai_output':    mock_ai_output,
    }

    # Save to Firestore
    save_weekly_report(TEST_HOUSE_ID, report_dict)

    # Read back and verify
    doc = db.collection('houses').document(TEST_HOUSE_ID).get()
    assert doc.exists, "House document should exist after save"

    data = doc.to_dict()
    assert 'weekly_report' in data, "weekly_report field should be present"

    wr = data['weekly_report']
    assert wr['period']['start'] == period_start
    assert wr['period']['end'] == period_end
    assert 'metrics' in wr
    assert 'ai_output' in wr
    assert len(wr['metrics']['days']) == 7
    assert wr['ai_output']['summary'].startswith("TEST REPORT")

    # Verify previous-report rotation: call save again → previous should appear
    save_weekly_report(TEST_HOUSE_ID, report_dict)
    doc2 = db.collection('houses').document(TEST_HOUSE_ID).get().to_dict()
    assert 'weekly_report_previous' in doc2, \
        "weekly_report_previous should appear after second save"
    prev = doc2['weekly_report_previous']
    assert 'metrics' in prev, "Previous report should have metrics"
    assert 'ai_output' not in prev, "Previous report must NOT contain ai_output (saves space)"

    print(f"  → Firestore document 'houses/{TEST_HOUSE_ID}' written — check Firebase console.")


# ============================================================================
# Runner
# ============================================================================

TESTS = [
    # Sleep
    ("Sleep bedtime/wake detection",       test_sleep_bedtime_and_wake_detection),
    ("Sleep nocturnal visits counted",     test_sleep_nocturnal_visits_counted),
    ("Sleep quality score — good sleep",   test_sleep_quality_score_good_sleep),
    ("Sleep quality score — short sleep",  test_sleep_quality_score_short_sleep),
    ("Sleep quality score — missing data", test_sleep_quality_score_missing_data),
    ("Sleep quality score — nocturnal",    test_sleep_quality_score_nocturnal_penalty),
    ("Sleep consistency — consistent",     test_sleep_consistency_consistent_schedule),
    ("Sleep consistency — no data",        test_sleep_consistency_insufficient_data),
    # Mobility
    ("Zone transitions counted",           test_zone_transitions_counted),
    ("Zone distribution sums to 100",      test_zone_distribution_sums_to_100),
    ("Activity score — high activity",     test_activity_score_high_activity),
    ("Activity score — sedentary",         test_activity_score_sedentary),
    # Nutrition
    ("Meal detection — all meals",         test_meal_detection_all_meals),
    ("Meal detection — no meals",          test_meal_detection_no_meals),
    # Socialization
    ("Door exits counted",                 test_door_exits_counted),
    ("Visitor detection — visitor",        test_visitor_detection_visitor_present),
    ("Visitor detection — resident exit",  test_visitor_detection_resident_exits),
    ("Night door event at 3am",            test_night_door_events_at_3am),
    ("Night door events — daytime only",   test_night_door_events_daytime_only),
    # Cognitive
    ("Morning sequence — correct order",   test_morning_sequence_correct_order),
    ("Morning sequence — wrong order",     test_morning_sequence_wrong_order),
    ("Morning sequence — outside window",  test_morning_sequence_outside_window),
    ("Medication adherence — taken",       test_medication_adherence_taken),
    ("Medication adherence — not taken",   test_medication_adherence_not_taken),
    # Full aggregation
    ("Aggregate weekly structure",         test_aggregate_weekly_structure),
    ("Aggregate healthy week values",      test_aggregate_healthy_week_values),
    # Insights generator
    ("Insufficient data guard",            test_insufficient_data_returns_none),
    ("Empty raw_docs guard",               test_empty_raw_docs_returns_none),
    ("Prompt — no previous week",          test_format_compact_prompt_no_previous_week),
    ("Prompt — with previous week",        test_format_compact_prompt_with_previous_week),
    ("Prompt — all 5 categories present",  test_format_compact_prompt_covers_all_categories),
    # DB integration
    ("DB save & read weekly report",       test_db_save_and_read_weekly_report),
]


if __name__ == "__main__":
    passed, failed = 0, 0
    for name, fn in TESTS:
        try:
            fn()
            print(f"PASS  {name}")
            passed += 1
        except Exception as e:
            print(f"FAIL  {name} — {e}")
            failed += 1

    print(f"\n{'='*55}")
    print(f"Results: {passed} passed, {failed} failed out of {len(TESTS)} tests")
    if failed:
        sys.exit(1)
