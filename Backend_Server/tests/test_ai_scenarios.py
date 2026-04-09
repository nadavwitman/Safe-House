"""
Weekly AI Insights — Gemini API Scenario Tests

3 end-to-end scenarios that call the real Gemini API and print results to terminal.
No database access. Limited API calls (one per scenario).

  Scenario 1: Healthy week — good sleep, all meals, daily walk, meds taken every day
  Scenario 2: Concerning week — poor sleep, missed meds, night door event, skipped meals
  Scenario 3: Improvement trend — current healthy week compared against previous anomaly week

Run from the Backend_Server directory:
    GEMINI_API_KEY=your_key python tests/test_ai_scenarios.py
"""

import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import time
import traceback

import pandas as pd

from app.core.weekly_aggregator import aggregate_weekly_metrics
from app.core.insights_generator import format_compact_prompt, generate_weekly_report


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _ts(date_str, hour, minute=0):
    return pd.Timestamp(f"{date_str}T{hour:02d}:{minute:02d}:00", tz='UTC')


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


# Sensor vector shortcuts
SV_NONE = [0, 0, 0, 0, 0, 0, 0]
SV_DOOR = [1, 0, 0, 0, 0, 0, 0]
SV_MED  = [0, 0, 0, 0, 1, 0, 0]

WEEK_DATES = [
    "2026-04-01", "2026-04-02", "2026-04-03",
    "2026-04-04", "2026-04-05", "2026-04-06", "2026-04-07",
]


def _print_result(scenario_name, metrics, ai_output):
    """Pretty-prints metrics summary and full AI output."""
    wa = metrics['weekly_averages']
    md = wa.get('meal_days', {})

    print(f"\n{'='*70}")
    print(f"SCENARIO: {scenario_name}")
    print(f"{'='*70}")
    print("Key Metrics (weekly averages):")
    print(f"  Sleep:           {wa.get('avg_sleep_hours', '?')}h avg  |  score: {wa.get('avg_sleep_quality_score', '?')}  |  consistency: {wa.get('sleep_consistency_score', '?')}")
    print(f"  Nocturnal visits:{wa.get('avg_nocturnal_visits', '?')}/night")
    print(f"  Activity score:  {wa.get('avg_activity_score', '?')}")
    print(f"  Meals (B/L/D):   {md.get('breakfast','?')}/7  {md.get('lunch','?')}/7  {md.get('dinner','?')}/7")
    print(f"  Medications:     {wa.get('medication_adherence_days', '?')}/7 days")
    print(f"  Morning sequence:{wa.get('morning_sequence_correct_days', '?')}/7 days")
    print(f"  Night door events: {wa.get('total_night_door_events', '?')}/week")
    print()
    print("AI Summary:")
    print(f"  {ai_output.get('summary', '(none)')}")
    print()
    print("AI Insights:")
    for cat, text in ai_output.get('insights', {}).items():
        print(f"  [{cat.upper():14s}] {text}")
    print()
    print("AI Recommendations:")
    for i, rec in enumerate(ai_output.get('recommendations', []), 1):
        print(f"  {i}. {rec}")
    print(f"{'='*70}")


# ---------------------------------------------------------------------------
# Scenario builders
# ---------------------------------------------------------------------------

def _build_healthy_week():
    """
    Ideal elderly routine — one sleep block per day (00:30 = still sleeping, wake 07:30),
    all 3 meals, daily outdoor walk, medications, complete morning sequence.

    Sleep detection note: The bedtime proxy used here is 00:30 (hour<3, bedroom).
    This represents the person already asleep from the previous night.
    Wake transition is detected at 07:30 (first move away from bedroom in the 05:00–11:00 window).
    Sleep hours = 07:30 − 00:30 = 7.0h.
    """
    day_readings = {}
    for date in WEEK_DATES:
        day_readings[date] = [
            ( 0, 30, 5, SV_NONE),   # Still sleeping (bedtime proxy, hour<3)
            ( 7, 30, 2, SV_NONE),   # Wake → Bathroom  (morning sequence: step 1)
            ( 7, 45, 1, SV_NONE),   # Breakfast → Kitchen (morning sequence: step 2+3)
            ( 8,  0, 6, SV_NONE),   # Living room
            ( 9,  0, 4, SV_MED),    # Medications
            (10,  0, 6, SV_NONE),   # Living room
            (12,  0, 1, SV_NONE),   # Lunch
            (13,  0, 6, SV_NONE),   # Living room
            (14,  0, 0, SV_DOOR),   # Door exit (daily walk)
            (15,  0, 6, SV_NONE),   # Return, living room
            (16,  0, 5, SV_NONE),   # Short rest in bedroom
            (17,  0, 6, SV_NONE),   # Living room
            (18, 30, 1, SV_NONE),   # Dinner
            (19,  0, 6, SV_NONE),   # Evening, living room
        ]
    return _make_raw_docs(day_readings)


def _build_anomaly_week():
    """
    Concerning week — late nights, poor/missing sleep, nocturnal bathroom trips,
    skipped breakfast every day, medications missed Mon–Thu, night door event on Wednesday,
    no morning sequence observed, low activity.
    """
    day_readings = {}
    for i, date in enumerate(WEEK_DATES):
        readings = []

        # Sleep: late bedtime (02:00-02:30), short sleep (~5h on good days)
        # Days 3 and 6 (Wed, Sat): no transition from bedroom before 11am → sleep_hours=None
        if i in (2, 5):
            readings.append((2, 0, 5, SV_NONE))   # Bedroom at 02:00
            readings.append((12, 0, 6, SV_NONE))  # Move to living room at 12:00 (outside 5–11 window → wake=None)
        else:
            bed_m = 0 if i % 2 == 0 else 30
            readings.append((2, bed_m, 5, SV_NONE))   # Bedroom at 02:00 or 02:30
            readings.append((7, 0,    2, SV_NONE))    # Move to bathroom at 07:00 (wake transition)
            # sleep ≈ 4.5–5.0h

        # Nocturnal bathroom visits (01:00 every night)
        readings.append((1, 0, 3, SV_NONE))   # Toilet at 01:00

        # No morning sequence: bedroom → (bathroom only on non-skip days) → living room directly
        readings.append((9, 0, 6, SV_NONE))   # Living room, skipping kitchen for breakfast

        # Night door event on Wednesday (day index 2)
        if i == 2:
            readings.append((23, 0, 0, SV_DOOR))  # Door opens at 23:00

        # Medications only on Fri/Sat/Sun (last 3 days)
        if i >= 4:
            readings.append((9, 30, 4, SV_MED))

        # Skip breakfast every day (no kitchen visit 06:00–09:00)
        # Lunch on Mon/Wed/Fri only
        if i % 2 == 0:
            readings.append((13, 0, 1, SV_NONE))

        # Dinner most days
        if i != 3:
            readings.append((19, 0, 1, SV_NONE))

        # Low activity — mostly living room, few transitions
        readings.append((15, 0, 6, SV_NONE))
        readings.append((20, 0, 6, SV_NONE))

        day_readings[date] = readings

    return _make_raw_docs(day_readings)


# ---------------------------------------------------------------------------
# Scenario runners
# ---------------------------------------------------------------------------

def run_scenario_1_healthy():
    """No anomalies — AI should give a warm, positive report."""
    raw_docs = _build_healthy_week()
    metrics = aggregate_weekly_metrics(raw_docs)
    compact_prompt = format_compact_prompt(metrics, None, "house_healthy")
    ai_output = generate_weekly_report(compact_prompt)
    _print_result("HEALTHY WEEK — No Anomalies", metrics, ai_output)


def run_scenario_2_anomalies():
    """Multiple anomalies — AI should flag concerns gently."""
    raw_docs = _build_anomaly_week()
    metrics = aggregate_weekly_metrics(raw_docs)
    compact_prompt = format_compact_prompt(metrics, None, "house_anomaly")
    ai_output = generate_weekly_report(compact_prompt)
    _print_result("CONCERNING WEEK — Multiple Anomalies", metrics, ai_output)


def run_scenario_3_improvement_over_previous():
    """
    Current week (healthy) compared against previous week (anomaly).
    AI should notice the improvement and highlight positive trends.
    """
    metrics_prev = aggregate_weekly_metrics(_build_anomaly_week())
    metrics_curr = aggregate_weekly_metrics(_build_healthy_week())
    compact_prompt = format_compact_prompt(metrics_curr, metrics_prev, "house_improvement")
    ai_output = generate_weekly_report(compact_prompt)
    _print_result("IMPROVEMENT — Better Than Previous Week", metrics_curr, ai_output)


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

SCENARIOS = [
    ("Healthy week (no anomalies)",            run_scenario_1_healthy),
    ("Concerning week (multiple anomalies)",   run_scenario_2_anomalies),
    ("Improvement over previous week",         run_scenario_3_improvement_over_previous),
]

if __name__ == "__main__":
    if not os.environ.get("GEMINI_API_KEY"):
        print("ERROR: GEMINI_API_KEY environment variable is not set.")
        print("       Run: export GEMINI_API_KEY='your_key_here'")
        sys.exit(1)

    print("Weekly AI Insights — Gemini Scenario Tests")
    print(f"Running {len(SCENARIOS)} scenarios ({len(SCENARIOS)} Gemini API calls)")
    print("No database access — all output printed to terminal\n")

    passed = failed = 0
    for i, (name, fn) in enumerate(SCENARIOS):
        if i > 0:
            time.sleep(5)  # avoid rate limits between scenarios
        print(f">> Running: {name} ...")
        for attempt in range(3):
            try:
                fn()
                passed += 1
                break
            except Exception as e:
                if attempt < 2 and '503' in str(e):
                    print(f"   503 overload, retrying in 15s...")
                    time.sleep(15)
                    continue
                print(f"\nFAIL  {name}")
                traceback.print_exc()
                failed += 1
                break

    print(f"\n{'='*55}")
    print(f"Results: {passed} passed, {failed} failed out of {len(SCENARIOS)} scenarios")
    if failed:
        sys.exit(1)
