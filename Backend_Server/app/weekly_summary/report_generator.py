import json
import os
import time
from datetime import date as _date

from google import genai
from google.genai import types

import database.database as database
from app.core.house_mask_store import house_mask_store
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
If no baseline exists, provide a neutral summary of observed activity without judgement."""


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

def run_insights_pipeline(house_id, raw_docs):
    """
    Full pipeline: load mask → load baseline → aggregate → compute deltas
    → save baseline → format prompt → call Gemini.

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

    metrics         = aggregate_weekly_metrics(raw_docs, house_mask)
    current_avgs    = compute_weekly_averages_for_baseline(metrics['days'])
    deltas          = compute_deltas(current_avgs, baseline)
    new_baseline    = build_new_baseline(current_avgs, baseline)

    metrics['deltas'] = deltas

    # Persist baseline before Gemini call so it's saved even if AI fails
    database.save_baseline(house_id, new_baseline)

    compact_prompt = format_compact_prompt(metrics, house_id)
    ai_output      = generate_weekly_report(compact_prompt)
    database.save_weekly_report(house_id, ai_output)

    return metrics, ai_output
