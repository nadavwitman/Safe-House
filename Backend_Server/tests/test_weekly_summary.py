"""
Tests for Backend_Server/app/weekly_summary/

Covers every module with unit tests + DB integration + one real LLM call.

Run from Backend_Server/:
    pytest tests/test_weekly_summary.py -v
    pytest tests/test_weekly_summary.py -v -k "DB"          # DB tests only
    pytest tests/test_weekly_summary.py -v -k "not DB"      # skip DB tests
"""
import os
import pytest
import pandas as pd
from datetime import datetime, timezone, timedelta
from unittest.mock import patch

import database.database as db_module

from app.weekly_summary.metrics.sleep         import _compute_sleep_metrics
from app.weekly_summary.metrics.mobility      import _compute_mobility_metrics
from app.weekly_summary.metrics.nutrition     import _compute_nutrition_metrics
from app.weekly_summary.metrics.cognitive     import (
    _compute_bath_duration, _compute_toilet_duration, _compute_food_prep_duration,
)
from app.weekly_summary.metrics.meds          import _compute_meds
from app.weekly_summary.metrics.socialization import _compute_outside_duration
from app.weekly_summary.aggregator            import aggregate_weekly_metrics
from app.weekly_summary.baseline              import (
    apply_ema, compute_weekly_averages_for_baseline,
    build_new_baseline, compute_deltas,
)
from app.weekly_summary.report_generator      import format_compact_prompt, run_insights_pipeline


# ─────────────────────────────────────────────────────────────────────────────
# Shared constants & helpers
# ─────────────────────────────────────────────────────────────────────────────

ALL_ACTIVE  = [1, 1, 1, 1, 1, 1, 1]
ZERO_SV     = [0, 0, 0, 0, 0, 0, 0]


def _ts(date_str, hour, minute=0):
    return pd.Timestamp(f"{date_str} {hour:02d}:{minute:02d}:00", tz='UTC')


def _make_df(rows):
    """
    rows: list of (timestamp, current_location_int, [s0..s6])
    Returns a DataFrame as individual metric functions expect.
    """
    records = []
    for t, loc, sensors in rows:
        entry = {'time': t, 'current_location': loc}
        for i, v in enumerate(sensors):
            entry[f'sensor_{i}'] = v
        records.append(entry)
    return pd.DataFrame(records)


def _loc_vec(zone):
    v = [0] * 7
    v[zone] = 1
    return v


def _raw_doc(dt, zone, sv=None):
    return {
        'time':             dt,
        'current_location': _loc_vec(zone),
        'sensor_vector':    sv or ZERO_SV[:],
    }


def _make_week_docs():
    """
    6 days (Jan 1–6 2024) of hourly raw docs.

    Daily routine:
      00–06  Bedroom   (zone 5)
      07     Kitchen   (zone 1, sensor_1=1  → 1 nutrition trigger/day)
      08     Meds zone (zone 4, sensor_4=1  → 1 meds session/day)
      09     Bathroom  (zone 2)
      10     Toilet    (zone 3)
      11–18  Living Room (zone 6)
      19–23  Bedroom   (zone 5)
    """
    docs = []
    for day in range(1, 7):
        date_str = f"2024-01-{day:02d}"
        for hour in range(24):
            if hour <= 6 or hour >= 19:
                zone, sv = 5, ZERO_SV[:]
            elif hour == 7:
                zone, sv = 1, [0, 1, 0, 0, 0, 0, 0]
            elif hour == 8:
                zone, sv = 4, [0, 0, 0, 0, 1, 0, 0]
            elif hour == 9:
                zone, sv = 2, ZERO_SV[:]
            elif hour == 10:
                zone, sv = 3, ZERO_SV[:]
            else:
                zone, sv = 6, ZERO_SV[:]
            docs.append(_raw_doc(
                pd.Timestamp(f"{date_str} {hour:02d}:00:00", tz='UTC'),
                zone, sv,
            ))
    return docs


# ─────────────────────────────────────────────────────────────────────────────
# 1. Sleep
# ─────────────────────────────────────────────────────────────────────────────

class TestSleep:

    def test_masked_returns_none(self):
        mask = list(ALL_ACTIVE); mask[5] = 0
        result = _compute_sleep_metrics(pd.DataFrame(), mask)
        assert result == {'sleep_hours': None, 'interruptions': None}

    def test_empty_df_returns_zeros(self):
        result = _compute_sleep_metrics(pd.DataFrame(), ALL_ACTIVE)
        assert result == {'sleep_hours': 0.0, 'interruptions': 0}

    def test_sleep_hours_calculation(self):
        # 6 rows in bedroom, 5 gaps × 60 min = 300 min = 5.0 h
        rows = [(_ts("2024-01-01", h), 5, ZERO_SV) for h in range(6)]
        df = _make_df(rows)
        assert _compute_sleep_metrics(df, ALL_ACTIVE)['sleep_hours'] == 5.0

    def test_short_interruption_not_counted(self):
        # 5-minute gap outside bedroom: below 10-min threshold
        rows = [
            (_ts("2024-01-01", 22, 0),  5, ZERO_SV),
            (_ts("2024-01-01", 22, 5),  3, ZERO_SV),
            (_ts("2024-01-01", 22, 10), 5, ZERO_SV),
        ]
        assert _compute_sleep_metrics(_make_df(rows), ALL_ACTIVE)['interruptions'] == 0

    def test_long_interruption_counted(self):
        # 12 consecutive minutes outside bedroom: above 10-min threshold
        rows = (
            [(_ts("2024-01-01", 22, 0),  5, ZERO_SV)] +
            [(_ts("2024-01-01", 22, i),  3, ZERO_SV) for i in range(1, 13)] +
            [(_ts("2024-01-01", 22, 13), 5, ZERO_SV)]
        )
        assert _compute_sleep_metrics(_make_df(rows), ALL_ACTIVE)['interruptions'] == 1

    def test_two_interruptions_counted(self):
        # Two separate 12-min gaps outside bedroom
        def _gap(base_min):
            return (
                [(_ts("2024-01-01", 22, base_min),     5, ZERO_SV)] +
                [(_ts("2024-01-01", 22, base_min + i), 3, ZERO_SV) for i in range(1, 13)] +
                [(_ts("2024-01-01", 22, base_min + 13), 5, ZERO_SV)]
            )
        rows = _gap(0) + _gap(20)
        assert _compute_sleep_metrics(_make_df(rows), ALL_ACTIVE)['interruptions'] == 2


# ─────────────────────────────────────────────────────────────────────────────
# 2. Mobility
# ─────────────────────────────────────────────────────────────────────────────

class TestMobility:

    def test_no_transitions(self):
        rows = [(_ts("2024-01-01", h), 6, ZERO_SV) for h in range(5)]
        assert _compute_mobility_metrics(_make_df(rows), ALL_ACTIVE)['transitions'] == 0

    def test_transitions_counted(self):
        # 5 → 1 → 2 → 6 = 3 transitions
        rows = [
            (_ts("2024-01-01", 8),  5, ZERO_SV),
            (_ts("2024-01-01", 9),  1, ZERO_SV),
            (_ts("2024-01-01", 10), 2, ZERO_SV),
            (_ts("2024-01-01", 11), 6, ZERO_SV),
        ]
        assert _compute_mobility_metrics(_make_df(rows), ALL_ACTIVE)['transitions'] == 3


# ─────────────────────────────────────────────────────────────────────────────
# 3. Nutrition
# ─────────────────────────────────────────────────────────────────────────────

class TestNutrition:

    def test_masked_returns_none(self):
        mask = list(ALL_ACTIVE); mask[1] = 0
        rows = [(_ts("2024-01-01", 8), 1, [0,1,0,0,0,0,0])]
        assert _compute_nutrition_metrics(_make_df(rows), mask)['kitchen_triggers'] is None

    def test_consecutive_ones_count_as_one(self):
        rows = [
            (_ts("2024-01-01", 8, 0), 1, [0,1,0,0,0,0,0]),
            (_ts("2024-01-01", 8, 1), 1, [0,1,0,0,0,0,0]),
            (_ts("2024-01-01", 8, 2), 1, [0,0,0,0,0,0,0]),
        ]
        assert _compute_nutrition_metrics(_make_df(rows), ALL_ACTIVE)['kitchen_triggers'] == 1

    def test_multiple_triggers(self):
        rows = [
            (_ts("2024-01-01",  8, 0), 1, [0,1,0,0,0,0,0]),
            (_ts("2024-01-01",  8, 1), 1, [0,0,0,0,0,0,0]),
            (_ts("2024-01-01", 12, 0), 1, [0,1,0,0,0,0,0]),
            (_ts("2024-01-01", 12, 1), 1, [0,0,0,0,0,0,0]),
        ]
        assert _compute_nutrition_metrics(_make_df(rows), ALL_ACTIVE)['kitchen_triggers'] == 2


# ─────────────────────────────────────────────────────────────────────────────
# 4. Cognitive
# ─────────────────────────────────────────────────────────────────────────────

class TestCognitive:

    def test_bath_masked_returns_none(self):
        mask = list(ALL_ACTIVE); mask[2] = 0
        assert _compute_bath_duration(_make_df([(_ts("2024-01-01", 9), 2, ZERO_SV)]), mask) is None

    def test_toilet_masked_returns_none(self):
        mask = list(ALL_ACTIVE); mask[3] = 0
        assert _compute_toilet_duration(_make_df([(_ts("2024-01-01", 9), 3, ZERO_SV)]), mask) is None

    def test_kitchen_masked_returns_none(self):
        mask = list(ALL_ACTIVE); mask[1] = 0
        assert _compute_food_prep_duration(_make_df([(_ts("2024-01-01", 7), 1, ZERO_SV)]), mask) is None

    def test_bath_duration_calculation(self):
        # zone 2: 30-min gap + 30-min gap = 60 min total
        rows = [
            (_ts("2024-01-01", 9, 0),  2, ZERO_SV),
            (_ts("2024-01-01", 9, 30), 2, ZERO_SV),
            (_ts("2024-01-01", 10, 0), 6, ZERO_SV),
        ]
        assert _compute_bath_duration(_make_df(rows), ALL_ACTIVE) == 60.0

    def test_toilet_duration_calculation(self):
        rows = [
            (_ts("2024-01-01", 10, 0),  3, ZERO_SV),
            (_ts("2024-01-01", 10, 15), 3, ZERO_SV),
            (_ts("2024-01-01", 10, 30), 6, ZERO_SV),
        ]
        assert _compute_toilet_duration(_make_df(rows), ALL_ACTIVE) == 30.0

    def test_food_prep_duration_calculation(self):
        rows = [
            (_ts("2024-01-01", 7, 0),  1, ZERO_SV),
            (_ts("2024-01-01", 7, 30), 1, ZERO_SV),
            (_ts("2024-01-01", 8, 0),  6, ZERO_SV),
        ]
        assert _compute_food_prep_duration(_make_df(rows), ALL_ACTIVE) == 60.0


# ─────────────────────────────────────────────────────────────────────────────
# 5. Meds
# ─────────────────────────────────────────────────────────────────────────────

class TestMeds:

    def test_masked_returns_none(self):
        mask = list(ALL_ACTIVE); mask[4] = 0
        rows = [(_ts("2024-01-01", 8), 4, [0,0,0,0,1,0,0])]
        assert _compute_meds(_make_df(rows), mask) is None

    def test_within_10min_counts_as_one_session(self):
        # Two rising edges 8 minutes apart → same session
        rows = [
            (_ts("2024-01-01", 8, 0), 4, [0,0,0,0,1,0,0]),
            (_ts("2024-01-01", 8, 1), 4, [0,0,0,0,0,0,0]),
            (_ts("2024-01-01", 8, 8), 4, [0,0,0,0,1,0,0]),
            (_ts("2024-01-01", 8, 9), 4, [0,0,0,0,0,0,0]),
        ]
        assert _compute_meds(_make_df(rows), ALL_ACTIVE)['count'] == 1

    def test_beyond_10min_counts_as_separate_sessions(self):
        # Two rising edges 15 minutes apart → different sessions
        rows = [
            (_ts("2024-01-01", 8, 0),  4, [0,0,0,0,1,0,0]),
            (_ts("2024-01-01", 8, 1),  4, [0,0,0,0,0,0,0]),
            (_ts("2024-01-01", 8, 15), 4, [0,0,0,0,1,0,0]),
            (_ts("2024-01-01", 8, 16), 4, [0,0,0,0,0,0,0]),
        ]
        assert _compute_meds(_make_df(rows), ALL_ACTIVE)['count'] == 2

    def test_session_hours_recorded(self):
        rows = [
            (_ts("2024-01-01",  8, 0), 4, [0,0,0,0,1,0,0]),
            (_ts("2024-01-01",  8, 1), 4, [0,0,0,0,0,0,0]),
            (_ts("2024-01-01", 20, 0), 4, [0,0,0,0,1,0,0]),
            (_ts("2024-01-01", 20, 1), 4, [0,0,0,0,0,0,0]),
        ]
        result = _compute_meds(_make_df(rows), ALL_ACTIVE)
        assert result['count'] == 2
        assert 8.0  in result['hours']
        assert 20.0 in result['hours']

    def test_no_triggers_returns_zero(self):
        rows = [(_ts("2024-01-01", h), 6, ZERO_SV) for h in range(5)]
        result = _compute_meds(_make_df(rows), ALL_ACTIVE)
        assert result == {'count': 0, 'hours': []}


# ─────────────────────────────────────────────────────────────────────────────
# 6. Socialization
# ─────────────────────────────────────────────────────────────────────────────

class TestSocialization:

    def test_masked_returns_none(self):
        mask = list(ALL_ACTIVE); mask[0] = 0
        rows = [(_ts("2024-01-01", 10), 0, ZERO_SV)]
        assert _compute_outside_duration(_make_df(rows), mask) is None

    def test_outside_duration_calculation(self):
        rows = [
            (_ts("2024-01-01", 10, 0),  0, ZERO_SV),
            (_ts("2024-01-01", 10, 30), 0, ZERO_SV),
            (_ts("2024-01-01", 11, 0),  6, ZERO_SV),
        ]
        assert _compute_outside_duration(_make_df(rows), ALL_ACTIVE) == 60.0

    def test_no_outside_time(self):
        rows = [(_ts("2024-01-01", h), 6, ZERO_SV) for h in range(5)]
        assert _compute_outside_duration(_make_df(rows), ALL_ACTIVE) == 0.0


# ─────────────────────────────────────────────────────────────────────────────
# 7. Baseline
# ─────────────────────────────────────────────────────────────────────────────

class TestBaseline:

    def test_apply_ema_no_previous_seeds_directly(self):
        assert apply_ema(10.0, None) == 10.0

    def test_apply_ema_no_current_keeps_previous(self):
        assert apply_ema(None, 8.0) == 8.0

    def test_apply_ema_formula(self):
        # 10 × 0.05 + 8 × 0.95 = 0.5 + 7.6 = 8.1
        assert apply_ema(10.0, 8.0) == 8.1

    def test_build_baseline_first_run_seeds_directly(self):
        avgs = {
            'sleep_hours': 7.5, 'interruptions': 1.0, 'transitions': 12.0,
            'kitchen_triggers': 3.0, 'bath_duration': 20.0, 'toilet_duration': 10.0,
            'food_prep_duration': 30.0, 'outside_duration': 45.0,
            'meds_by_day': None,
        }
        baseline = build_new_baseline(avgs, None)
        assert baseline['sleep_hours']   == 7.5
        assert baseline['transitions']   == 12.0
        assert 'meds' not in baseline

    def test_build_baseline_subsequent_run_applies_ema(self):
        existing = {
            'sleep_hours': 8.0, 'interruptions': 0.0, 'transitions': 10.0,
            'kitchen_triggers': 3.0, 'bath_duration': 20.0, 'toilet_duration': 10.0,
            'food_prep_duration': 30.0, 'outside_duration': 45.0,
        }
        avgs = {**existing, 'sleep_hours': 10.0, 'meds_by_day': None}
        new = build_new_baseline(avgs, existing)
        # 10 × 0.05 + 8 × 0.95 = 8.1
        assert new['sleep_hours'] == 8.1
        assert new['transitions'] == 10.0  # unchanged (EMA of same value)

    def test_compute_deltas_no_baseline_returns_none(self):
        assert compute_deltas({'sleep_hours': 7.0}, None) is None

    def test_compute_deltas_correct_values(self):
        avgs = {
            'sleep_hours': 7.0, 'interruptions': 2.0, 'transitions': 10.0,
            'kitchen_triggers': 3.0, 'bath_duration': 20.0, 'toilet_duration': 10.0,
            'food_prep_duration': 30.0, 'outside_duration': 45.0, 'meds_by_day': None,
        }
        baseline = {
            'sleep_hours': 8.0, 'interruptions': 1.0, 'transitions': 12.0,
            'kitchen_triggers': 3.0, 'bath_duration': 20.0, 'toilet_duration': 10.0,
            'food_prep_duration': 30.0, 'outside_duration': 45.0,
        }
        deltas = compute_deltas(avgs, baseline)
        assert deltas['sleep_hours']   == -1.0
        assert deltas['interruptions'] ==  1.0
        assert deltas['transitions']   == -2.0

    def test_compute_deltas_masked_metric_is_none(self):
        avgs = {
            'sleep_hours': None, 'interruptions': 1.0, 'transitions': 10.0,
            'kitchen_triggers': None, 'bath_duration': None, 'toilet_duration': None,
            'food_prep_duration': None, 'outside_duration': None, 'meds_by_day': None,
        }
        baseline = {
            'sleep_hours': 8.0, 'interruptions': 1.0, 'transitions': 10.0,
            'kitchen_triggers': 3.0, 'bath_duration': 20.0, 'toilet_duration': 10.0,
            'food_prep_duration': 30.0, 'outside_duration': 45.0,
        }
        deltas = compute_deltas(avgs, baseline)
        assert deltas['sleep_hours']      is None
        assert deltas['kitchen_triggers'] is None


# ─────────────────────────────────────────────────────────────────────────────
# 8. Aggregator
# ─────────────────────────────────────────────────────────────────────────────

class TestAggregator:

    def test_returns_expected_structure(self):
        result = aggregate_weekly_metrics(_make_week_docs(), ALL_ACTIVE)
        assert 'days' in result
        assert 'weekly_averages' in result

    def test_correct_number_of_days(self):
        result = aggregate_weekly_metrics(_make_week_docs(), ALL_ACTIVE)
        assert len(result['days']) == 6  # Jan 1–6

    def test_daily_keys_present(self):
        day = aggregate_weekly_metrics(_make_week_docs(), ALL_ACTIVE)['days'][0]
        for key in ['date', 'sleep_hours', 'interruptions', 'transitions',
                    'kitchen_triggers', 'bath_duration', 'toilet_duration',
                    'food_prep_duration', 'meds_count', 'meds_hours', 'outside_duration']:
            assert key in day, f"Missing key: {key}"

    def test_weekly_averages_keys_present(self):
        wa = aggregate_weekly_metrics(_make_week_docs(), ALL_ACTIVE)['weekly_averages']
        for key in ['avg_sleep_hours', 'avg_interruptions', 'avg_transitions',
                    'avg_kitchen_triggers', 'avg_bath_duration', 'avg_toilet_duration',
                    'avg_food_prep_duration', 'avg_outside_duration', 'avg_meds_count']:
            assert key in wa, f"Missing key: {key}"

    def test_one_kitchen_trigger_per_day(self):
        result = aggregate_weekly_metrics(_make_week_docs(), ALL_ACTIVE)
        for day in result['days']:
            assert day['kitchen_triggers'] == 1

    def test_one_meds_session_per_day(self):
        result = aggregate_weekly_metrics(_make_week_docs(), ALL_ACTIVE)
        for day in result['days']:
            assert day['meds_count'] == 1

    def test_masked_sensors_produce_none(self):
        mask = list(ALL_ACTIVE)
        mask[5] = 0  # bedroom → sleep None
        mask[1] = 0  # kitchen → nutrition + food_prep None
        result = aggregate_weekly_metrics(_make_week_docs(), mask)
        day = result['days'][2]
        assert day['sleep_hours']       is None
        assert day['kitchen_triggers']  is None
        assert day['food_prep_duration'] is None

    def test_weekly_averages_computed(self):
        wa = aggregate_weekly_metrics(_make_week_docs(), ALL_ACTIVE)['weekly_averages']
        assert wa['avg_kitchen_triggers'] == 1.0
        assert wa['avg_meds_count']       == 1.0


# ─────────────────────────────────────────────────────────────────────────────
# 9. Report prompt formatting (no LLM)
# ─────────────────────────────────────────────────────────────────────────────

class TestPromptFormat:

    def _metrics(self, with_deltas=False):
        metrics = aggregate_weekly_metrics(_make_week_docs(), ALL_ACTIVE)
        if with_deltas:
            avgs = compute_weekly_averages_for_baseline(metrics['days'])
            baseline = {
                'sleep_hours': 7.0, 'interruptions': 1.0, 'transitions': 10.0,
                'kitchen_triggers': 2.0, 'bath_duration': 15.0, 'toilet_duration': 8.0,
                'food_prep_duration': 25.0, 'outside_duration': 40.0,
            }
            metrics['deltas'] = compute_deltas(avgs, baseline)
        else:
            metrics['deltas'] = None
        return metrics

    def test_first_week_note_when_no_baseline(self):
        prompt = format_compact_prompt(self._metrics(with_deltas=False), 'test_house')
        assert 'First recorded week' in prompt

    def test_deltas_section_present_when_baseline_exists(self):
        prompt = format_compact_prompt(self._metrics(with_deltas=True), 'test_house')
        assert 'CHANGE VS PERSONAL BASELINE' in prompt

    def test_prompt_contains_house_id(self):
        prompt = format_compact_prompt(self._metrics(), 'house_42')
        assert 'house_42' in prompt

    def test_prompt_contains_all_metric_labels(self):
        prompt = format_compact_prompt(self._metrics(), 'test_house')
        for label in ['Sleep:', 'Trans:', 'Kitchen:', 'Bath:', 'Toilet:', 'Meds:', 'Outside:']:
            assert label in prompt, f"Missing label: {label}"


# ─────────────────────────────────────────────────────────────────────────────
# 10. Integration — full pipeline (Gemini + DB mocked)
# ─────────────────────────────────────────────────────────────────────────────

class TestIntegration:

    def test_full_pipeline_end_to_end(self):
        docs = _make_week_docs()

        mock_ai = {
            'summary': 'Good week overall.',
            'insights': {
                'sleep': '...', 'mobility': '...', 'nutrition': '...',
                'cognitive': '...', 'meds': '...', 'social': '...',
            },
            'recommendations': ['Stay active.'],
        }

        with patch('app.weekly_summary.report_generator.house_mask_store') as mock_store, \
             patch('app.weekly_summary.report_generator.database')         as mock_db, \
             patch('app.weekly_summary.report_generator.generate_weekly_report',
                   return_value=mock_ai):

            mock_store.get_mask.return_value    = ALL_ACTIVE
            mock_db.get_baseline.return_value   = None

            metrics, ai_output = run_insights_pipeline('test_house', docs)

        assert metrics    is not None
        assert ai_output  is not None
        assert 'days'     in metrics
        assert 'weekly_averages' in metrics
        assert ai_output['summary'] == 'Good week overall.'
        mock_db.save_baseline.assert_called_once()

    def test_pipeline_returns_none_for_insufficient_data(self):
        # Only 3 days → below the 5-day minimum
        docs = _make_week_docs()[:72]  # 3 days × 24 hours
        with patch('app.weekly_summary.report_generator.house_mask_store') as mock_store, \
             patch('app.weekly_summary.report_generator.database')         as mock_db:
            mock_store.get_mask.return_value  = ALL_ACTIVE
            mock_db.get_baseline.return_value = None
            metrics, ai_output = run_insights_pipeline('test_house', docs)

        assert metrics   is None
        assert ai_output is None


# ─────────────────────────────────────────────────────────────────────────────
# 11. DB Integration — real Firestore reads/writes + one real LLM call
# ─────────────────────────────────────────────────────────────────────────────

class TestDatabaseIntegration:
    """
    Writes mock week data to Firestore under a dedicated test house,
    reads it back, and runs the full pipeline.

    One test makes a real Gemini call — skipped if GEMINI_API_KEY is not set.
    Cleans up all written data before and after each test.
    """
    TEST_HOUSE = 'test_house_pytest'

    @pytest.fixture(autouse=True)
    def cleanup(self):
        self._delete_test_house()
        yield
        self._delete_test_house()

    def _delete_test_house(self):
        for doc in (
            db_module.db
            .collection('houses')
            .document(self.TEST_HOUSE)
            .collection('sensor_vectors')
            .stream()
        ):
            doc.reference.delete()
        db_module.db.collection('houses').document(self.TEST_HOUSE).delete()

    def _write_week_data(self):
        """Writes 6 days × 6 key hours of mock data with current timestamps."""
        now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
        for days_ago in range(6, 0, -1):
            base = (now - timedelta(days=days_ago)).replace(hour=0)
            for hour in [0, 7, 8, 9, 10, 20]:
                if hour <= 6 or hour >= 19:
                    zone, sv = 5, ZERO_SV[:]
                elif hour == 7:
                    zone, sv = 1, [0, 1, 0, 0, 0, 0, 0]
                elif hour == 8:
                    zone, sv = 4, [0, 0, 0, 0, 1, 0, 0]
                elif hour == 9:
                    zone, sv = 2, ZERO_SV[:]
                else:          # hour == 10
                    zone, sv = 3, ZERO_SV[:]
                db_module.log_vector_reading({
                    'sensor_vector':    sv,
                    'time':             base.replace(hour=hour),
                    'current_location': _loc_vec(zone),
                }, self.TEST_HOUSE)

    def test_DB_sensor_data_roundtrip(self):
        """Writes docs to Firestore and verifies they come back with correct structure."""
        self._write_week_data()
        docs = db_module.get_weekly_sensor_data(self.TEST_HOUSE)

        assert len(docs) >= 30          # 5+ days × 6 readings
        for doc in docs:
            assert 'sensor_vector'    in doc
            assert 'current_location' in doc
            assert 'time'             in doc
            assert isinstance(doc['sensor_vector'],    list)
            assert isinstance(doc['current_location'], list)

    def test_DB_baseline_save_and_load(self):
        """Writes a baseline to Firestore and reads it back."""
        baseline = {
            'sleep_hours': 7.5, 'interruptions': 1.0, 'transitions': 12.0,
            'kitchen_triggers': 3.0, 'bath_duration': 20.0, 'toilet_duration': 10.0,
            'food_prep_duration': 30.0, 'outside_duration': 45.0,
        }
        db_module.save_baseline(self.TEST_HOUSE, baseline)
        loaded = db_module.get_baseline(self.TEST_HOUSE)

        assert loaded is not None
        assert loaded['sleep_hours']  == 7.5
        assert loaded['transitions']  == 12.0

    @pytest.mark.skipif(
        not os.environ.get('GEMINI_API_KEY'),
        reason='GEMINI_API_KEY not set',
    )
    def test_DB_full_pipeline_real_db_and_llm(self):
        """
        End-to-end: real Firestore data + one real Gemini call.
        Verifies AI output structure and that baseline is persisted to DB.
        """
        self._write_week_data()
        raw_docs = db_module.get_weekly_sensor_data(self.TEST_HOUSE)
        assert len(raw_docs) >= 30, "Not enough test data written to DB"

        metrics, ai_output = run_insights_pipeline(self.TEST_HOUSE, raw_docs)

        assert metrics   is not None, "Pipeline returned no metrics"
        assert ai_output is not None, "Pipeline returned no AI output"
        assert 'days'            in metrics
        assert 'weekly_averages' in metrics
        assert 'summary'         in ai_output
        assert 'insights'        in ai_output
        assert 'recommendations' in ai_output
        for key in ['sleep', 'mobility', 'nutrition', 'cognitive', 'meds', 'social']:
            assert key in ai_output['insights'], f"Missing AI insight category: {key}"

        # Verify baseline was persisted to real Firestore
        saved_baseline = db_module.get_baseline(self.TEST_HOUSE)
        assert saved_baseline is not None
        assert 'sleep_hours' in saved_baseline

