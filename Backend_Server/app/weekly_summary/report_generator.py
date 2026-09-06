import json
import os
import time
from datetime import date as _date
from datetime import datetime, timedelta, timezone

from firebase_admin import firestore
from google import genai
from google.genai import types

import database.database as database
from app.state.house_mask_store import house_mask_store
from app.weekly_summary.aggregator import aggregate_weekly_metrics
from app.weekly_summary.baseline import (
    compute_weekly_averages_for_baseline,
    build_new_baseline,
    compute_deltas,
)

GEMINI_MODEL = "gemini-2.5-flash"

PROMPT_TEMPLATE = """You are a compassionate health assistant helping family members and \
caregivers understand the weekly wellness of an elderly person living independently in a smart home.

Below is structured sensor activity data from the past 7 days covering sleep, mobility, \
nutrition, hygiene, food preparation, medication, and outdoor activity.

--- DATA ---
{compact_prompt}
--- END DATA ---

Respond ONLY with valid JSON matching this exact structure:
{{
  "summary": "<2-3 sentence overall impression of the week>",
  "insights": {{
    "sleep":      "<1-2 sentences on sleep duration and interruptions>",
    "mobility":   "<1-2 sentences on daily location transitions>",
    "nutrition":  "<1-2 sentences on kitchen sensor activity>",
    "cognitive":  "<1-2 sentences on bath duration, toilet duration, and food prep time>",
    "meds":       "<1-2 sentences on medication session count and timing patterns>",
    "social":     "<1-2 sentences on time spent outside>"
  }},
  "recommendations": [
    "<actionable recommendation 1>",
    "<actionable recommendation 2>",
    "<actionable recommendation 3 if warranted>"
  ]
}}

Tone: warm, accessible, non-alarming. \
If baseline deltas are provided, compare to the individual's personal norm. \
If no baseline exists, provide a neutral summary of observed activity without judgement. \
Any day marked "insufficient sensor data" had a device outage — ignore it and never treat \
missing data as inactivity, poor sleep, or a skipped meal. A "?" means not measured, not zero."""


# ---------------------------------------------------------------------------
# Prompt formatting
# ---------------------------------------------------------------------------

def format_compact_prompt(weekly_metrics, house_id):
    days    = weekly_metrics['days']
    wa      = weekly_metrics['weekly_averages']
    deltas  = weekly_metrics.get('deltas')

    def _fmt(val, suffix='', default='?'):
        return f"{val}{suffix}" if val is not None else default

    lines = [
        f"WEEKLY WELLNESS DATA — House: {house_id}",
        f"Period: {days[0]['date'] if days else '?'} → {days[-1]['date'] if days else '?'}",
        "",
        "DAILY LOG:",
    ]

    for d in days:
        weekday = _date.fromisoformat(d['date']).strftime('%a')
        if d.get('low_data'):
            # Device outage that day — metrics are excluded, not zero. Flag it explicitly
            # so the model doesn't read the missing values as a lack of activity.
            lines.append(f"{weekday} {d['date']}: (insufficient sensor data — device outage, excluded from analysis)")
            continue
        meds_str = f"Meds:{d['meds_count']}x@{d['meds_hours']}" if d['meds_count'] else "Meds:0"
        lines.append(
            f"{weekday} {d['date']}: "
            f"Sleep:{_fmt(d['sleep_hours'], 'h')}(int:{_fmt(d['interruptions'])}) | "
            f"Trans:{d['transitions']} | "
            f"Kitchen:{_fmt(d['kitchen_triggers'])} | "
            f"Bath:{_fmt(d['bath_duration'], 'min')} Toilet:{_fmt(d['toilet_duration'], 'min')} FoodPrep:{_fmt(d['food_prep_duration'], 'min')} | "
            f"{meds_str} | "
            f"Outside:{_fmt(d['outside_duration'], 'min')}"
        )

    lines += [
        "",
        "WEEKLY AVERAGES:",
        f"Sleep:{_fmt(wa.get('avg_sleep_hours'), 'h')} Interruptions:{_fmt(wa.get('avg_interruptions'))}/night",
        f"Transitions:{_fmt(wa.get('avg_transitions'))}/day",
        f"Kitchen triggers:{_fmt(wa.get('avg_kitchen_triggers'))}/day",
        f"Bath:{_fmt(wa.get('avg_bath_duration'), 'min/day')} Toilet:{_fmt(wa.get('avg_toilet_duration'), 'min/day')} FoodPrep:{_fmt(wa.get('avg_food_prep_duration'), 'min/day')}",
        f"Meds:{_fmt(wa.get('avg_meds_count'))}/day",
        f"Outside:{_fmt(wa.get('avg_outside_duration'), 'min/day')}",
    ]

    if deltas is None:
        lines += ["", "NOTE: First recorded week — no personal baseline available for comparison."]
    else:
        def _d(val, suffix=''):
            return f"{val:+.1f}{suffix}" if val is not None else "N/A"

        lines += [
            "",
            "CHANGE VS PERSONAL BASELINE:",
            f"Sleep:{_d(deltas.get('sleep_hours'), 'h')} "
            f"Interruptions:{_d(deltas.get('interruptions'))} "
            f"Transitions:{_d(deltas.get('transitions'))}/day",
            f"Kitchen:{_d(deltas.get('kitchen_triggers'))}/day "
            f"Bath:{_d(deltas.get('bath_duration'), 'min')} "
            f"Toilet:{_d(deltas.get('toilet_duration'), 'min')} "
            f"FoodPrep:{_d(deltas.get('food_prep_duration'), 'min')}",
            f"Outside:{_d(deltas.get('outside_duration'), 'min')}",
        ]

        meds_deltas = deltas.get('meds') or {}
        if meds_deltas:
            lines.append("Meds deltas by day:")
            for day_key, md in meds_deltas.items():
                slot_str = ', '.join(
                    f"slot{i}:{_d(h)}h" for i, h in enumerate(md.get('delta_hours', []))
                )
                lines.append(f"  Day {day_key}: count{_d(md.get('delta_count'))} | {slot_str}")

    return '\n'.join(lines)


# ---------------------------------------------------------------------------
# Gemini API call
# ---------------------------------------------------------------------------

_INITIAL_RETRY_DELAY_SECONDS = 5
_MAX_RETRIES = 3


def generate_weekly_report(compact_prompt):
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError(
            "GEMINI_API_KEY environment variable is not set. "
            "Set it before starting the server: export GEMINI_API_KEY='your_key'"
        )

    client = genai.Client(api_key=api_key)
    last_exc = None
    delay = _INITIAL_RETRY_DELAY_SECONDS

    for attempt in range(1, _MAX_RETRIES + 1):
        try:
            response = client.models.generate_content(
                model    = GEMINI_MODEL,
                contents = PROMPT_TEMPLATE.format(compact_prompt=compact_prompt),
                config   = types.GenerateContentConfig(response_mime_type="application/json"),
            )
            return json.loads(response.text)
        except Exception as exc:
            last_exc = exc
            err_str = str(exc).lower()
            retryable = any(kw in err_str for kw in (
                "429", "503", "overloaded", "resource exhausted",
                "quota", "unavailable", "too many requests",
            ))
            if not retryable or attempt == _MAX_RETRIES:
                raise
            
            print(
                f"[ReportGenerator] Gemini API error (attempt {attempt}/{_MAX_RETRIES}): {exc}. "
                f"Retrying in {delay} seconds..."
            )
            time.sleep(delay)
            delay *= 2  # Double the wait time for the next attempt

    raise last_exc


# ---------------------------------------------------------------------------
# Pipeline orchestrator
# ---------------------------------------------------------------------------

# Matches the weekly scheduler's CronTrigger(day_of_week='sun', hour=6) — both
# read the same fixed calendar week off the wall clock the container runs in
# (UTC on this deployment), so the report a house gets never depends on
# whether it came from the Sunday job or a later catch-up.
WEEK_BOUNDARY_HOUR = 6

# The first night's sleep window (aggregator.py) reaches back to 20:00 LOCAL_TZ on the
# day before `start` — up to 10h before `start` in the worst-case UTC/local offset, plus
# the fetch window boundary itself is a UTC wall-clock hour rather than local midnight.
# Without this lead-in, get_weekly_sensor_data(start, end) never pulls those readings at
# all (not a coverage gap — they're outside the query), so the first night's sleep_hours
# and interruptions are nulled even on a night with perfect sensor coverage. Widening the
# fetch by a full day is a generous margin; aggregate_weekly_metrics still buckets exactly
# 7 days off `week_start`, so the extra lead-in readings never create a stray 8th day.
SLEEP_WINDOW_FETCH_LEAD_IN = timedelta(hours=24)


def get_last_complete_week(now=None):
    """Returns (start, end) — the most recently completed Sunday 06:00 to
    Sunday 06:00 window as of `now`. `end` is exclusive.

    Deterministic in `now`, so the Sunday job and a catch-up firing mid-week
    always agree on which week they're generating for.
    """
    now = now or datetime.now(timezone.utc)
    days_since_sunday = (now.weekday() + 1) % 7  # Python: Monday=0 ... Sunday=6
    end = (now - timedelta(days=days_since_sunday)).replace(
        hour=WEEK_BOUNDARY_HOUR, minute=0, second=0, microsecond=0)
    if end > now:
        end -= timedelta(days=7)
    return end - timedelta(days=7), end


def run_insights_pipeline(house_id, raw_docs, advance_baseline=True, week_start=None):
    """
    Full pipeline: load mask → load baseline → aggregate → compute deltas
    → format prompt → call Gemini.

    advance_baseline decides whether this run moves the EMA baseline forward. The
    baseline is the reference every week-over-week delta is measured against, and
    each update pulls it 5% toward the week just measured. generate_and_store
    always advances it — its callers only ever target a distinct, not-yet-reported
    calendar week (see get_last_complete_week) — but re-running this directly on
    the same week's data must pass False, or repeating it would drag the baseline
    toward that week twice and quietly flatten the very deltas being reported.

    Saving the report is the caller's job: it owns the period and generated_at
    that wrap this output into the stored document.

    Returns (metrics_dict, ai_output_dict), or (None, None) if fewer than 5 distinct days.
    """
    if not raw_docs:
        return None, None

    distinct_days = len({
        r['time'].date() if hasattr(r['time'], 'date') else str(r['time'])[:10]
        for r in raw_docs
    })
    if distinct_days < 5:
        return None, None

    house_mask = house_mask_store.get_mask(house_id)
    baseline   = database.get_baseline(house_id)

    metrics         = aggregate_weekly_metrics(raw_docs, house_mask, week_start=week_start)
    current_avgs    = compute_weekly_averages_for_baseline(metrics['days'])
    deltas          = compute_deltas(current_avgs, baseline)
    new_baseline    = build_new_baseline(current_avgs, baseline)

    metrics['deltas'] = deltas

    # Persist baseline before Gemini call so it's saved even if AI fails
    if advance_baseline:
        database.save_baseline(house_id, new_baseline)

    compact_prompt = format_compact_prompt(metrics, house_id)
    ai_output      = generate_weekly_report(compact_prompt)

    return metrics, ai_output


def generate_and_store(house_id):
    """Runs the pipeline for one house and persists the result.

    Returns (status, report) where status is 'success', 'no_data' or
    'insufficient_data', and report is the stored document (None unless
    successful).

    Every producer goes through here — the weekly scheduler, the lazy catch-up
    and the ops endpoint — so the shape of a stored report, and the fact that
    period and generated_at wrap the pipeline's output, is defined once.

    Both the Sunday job and a catch-up always target the same fixed calendar
    week (get_last_complete_week), so a catch-up genuinely fills in the week
    that was missed rather than an arbitrary trailing window — safe to always
    advance the baseline, unlike an on-demand re-run of the same week.
    """
    start, end = get_last_complete_week()
    raw_docs = database.get_weekly_sensor_data(house_id, start - SLEEP_WINDOW_FETCH_LEAD_IN, end)
    if not raw_docs:
        return 'no_data', None

    metrics, ai_output = run_insights_pipeline(house_id, raw_docs, week_start=start)
    if metrics is None:
        return 'insufficient_data', None

    report = {
        'period': {
            'start': min(d['date'] for d in metrics['days']),
            'end':   max(d['date'] for d in metrics['days']),
        },
        'generated_at': firestore.SERVER_TIMESTAMP,
        'metrics': metrics,
        'ai_output': ai_output,
    }
    database.save_weekly_report(house_id, report)
    return 'success', report
