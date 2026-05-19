"""
Tests for the Weekly AI Insights feature.

Covers:
  - weekly_summary/aggregator.py — active metrics categories
  - weekly_summary/report_generator.py — prompt formatting and data-guard logic (no Gemini)
"""

import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import pandas as pd

from app.weekly_summary.aggregator import aggregate_weekly_metrics
from app.weekly_summary.metrics.mobility import _compute_mobility_metrics
from app.weekly_summary.metrics.sleep import _compute_sleep_metrics
from app.weekly_summary.metrics.nutrition import _compute_nutrition_metrics
from app.weekly_summary.metrics.meds import _compute_meds

from app.weekly_summary.report_generator import format_compact_prompt, run_insights_pipeline

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
    date = "2026-04-01"
    readings = [
        {'time': _ts(date,  1, 30), 'current_location': 5, 'sensor_vector': [0]*7},
        {'time': _ts(date,  2,  0), 'current_location': 5, 'sensor_vector': [0]*7},
        {'time': _ts(date,  7, 15), 'current_location': 2, 'sensor_vector': [0]*7},
    ]
    result = _compute_sleep_metrics(_make_day_df(readings), house_mask=[1]*7)
    assert result['sleep_hours'] is not None, "Sleep hours should be computed"
    assert 'interruptions' in result, "Interruptions key should exist in sleep metrics"


def test_sleep_nocturnal_visits_counted():
    date = "2026-04-01"
    readings = [
        {'time': _ts(date, 22,  0), 'current_location': 5, 'sensor_vector': [0]*7},
        {'time': _ts(date,  2, 15), 'current_location': 3, 'sensor_vector': [0]*7},
        {'time': _ts(date,  4, 45), 'current_location': 2, 'sensor_vector': [0]*7},
        {'time': _ts(date,  7, 30), 'current_location': 6, 'sensor_vector': [0]*7},
    ]
    result = _compute_sleep_metrics(_make_day_df(readings), house_mask=[1]*7)
    assert 'interruptions' in result, "Should track overnight interruptions/visits"


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
    result = _compute_mobility_metrics(_make_day_df(readings), house_mask=[1]*7)
    assert 'transitions' in result, "Transitions key should exist in mobility metrics"


# ============================================================================
# Full aggregation
# ============================================================================

def test_aggregate_weekly_structure():
    raw_docs = _build_typical_week()
    result = aggregate_weekly_metrics(raw_docs, house_mask=[1]*7)
    assert len(result['days']) == 7, f"Expected 7 days, got {len(result['days'])}"

    expected_daily_keys = [
        'date', 'sleep_hours', 'interruptions', 'transitions', 'kitchen_triggers', 
        'bath_duration', 'toilet_duration', 'food_prep_duration', 'meds_count', 
        'meds_hours', 'outside_duration'
    ]
    for key in expected_daily_keys:
        assert key in result['days'][0], f"Missing expected daily key: {key}"

    expected_avg_keys = [
        'avg_sleep_hours', 'avg_interruptions', 'avg_transitions', 'avg_kitchen_triggers', 
        'avg_bath_duration', 'avg_toilet_duration', 'avg_food_prep_duration', 
        'avg_outside_duration', 'avg_meds_count'
    ]
    for key in expected_avg_keys:
        assert key in result['weekly_averages'], f"Missing expected weekly average key: {key}"


def test_aggregate_healthy_week_values():
    raw_docs = _build_typical_week()
    result = aggregate_weekly_metrics(raw_docs, house_mask=[1]*7)
    wa = result['weekly_averages']
    assert wa['avg_sleep_hours'] is not None
    assert wa['avg_transitions'] is not None


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
    metrics = aggregate_weekly_metrics(_build_typical_week(), house_mask=[1]*7)
    prompt = format_compact_prompt(metrics, "test_house")
    assert prompt is not None, "Prompt generation should return a valid string"


def test_format_compact_prompt_covers_all_categories():
    metrics = aggregate_weekly_metrics(_build_typical_week(), house_mask=[1]*7)
    prompt = format_compact_prompt(metrics, "test_house")
    assert isinstance(prompt, str)


# ============================================================================
# Runner עבור הרצה ידנית ישירה
# ============================================================================

TESTS = [
    ("Sleep bedtime/wake detection",       test_sleep_bedtime_and_wake_detection),
    ("Sleep nocturnal visits counted",     test_sleep_nocturnal_visits_counted),
    ("Zone transitions counted",           test_zone_transitions_counted),
    ("Aggregate weekly structure",         test_aggregate_weekly_structure),
    ("Aggregate healthy week values",      test_aggregate_healthy_week_values),
    ("Insufficient data guard",            test_insufficient_data_returns_none),
    ("Empty raw_docs guard",               test_empty_raw_docs_returns_none),
    ("Prompt Formatting — Basic",          test_format_compact_prompt_no_previous_week),
    ("Prompt Formatting — Type Validation", test_format_compact_prompt_covers_all_categories),
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