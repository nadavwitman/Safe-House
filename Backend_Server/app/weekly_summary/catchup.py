"""Lazy regeneration for houses whose weekly report never arrived.

The Sunday scheduler is the normal path. When it fails outright — Gemini erroring
through all its retries, or the box being down past the misfire window — nothing
downstream notices, and the family sits on last week's report for another full
week with no way to ask for a new one.

This closes that hole using traffic the app already produces. Every dashboard
poll reads the stored report's age off the house document, so a house whose
report is overdue gets regenerated the next time somebody opens the app. Houses
nobody looks at cost nothing, which is why this is lazy rather than a nightly
sweep across every house on the system.

Two properties keep it off the hot path:

  * The staleness test runs on fields the poll already read. A house with a
    current report does no extra work at all — the poll stays at one document
    read, which is the whole basis of the dashboard's cost model.
  * The claim is transactional, so several family members polling at once
    produce one regeneration rather than one each.

Deliberately, a catch-up never advances the EMA baseline. Only the weekly job
does, because the baseline assumes exactly one update per week and a catch-up
runs at an arbitrary moment. The cost is that a rescued week's numbers never
enter the long-run average; the alternative — double-counting a week, or
counting one twice because two workers raced — distorts every delta the report
shows for the next several months.
"""

import threading
from datetime import datetime, timedelta, timezone

from firebase_admin import firestore

from app.weekly_summary.report_generator import generate_and_store
from database.repositories.client import db

# A week plus a day of slack: the Sunday 06:00 job has an hour of misfire grace,
# so anything past 8 days means that run genuinely did not produce a report.
STALE_AFTER = timedelta(days=8)

# A house that fails to generate — not enough data yet, Gemini still down —
# must not be retried on every poll. One attempt a day.
RETRY_AFTER = timedelta(hours=24)


def maybe_catch_up(house_id, weekly_report_at, catchup_attempted_at, is_vacation=False):
    """Starts a background regeneration if this house is overdue for one.

    Both timestamps come from the caller's existing read of the house document;
    nothing here touches Firestore unless the cheap test below already says the
    house is overdue and not recently attempted. Returns immediately either way —
    generation takes a Gemini call and must never block a dashboard poll.

    A null weekly_report_at counts as overdue. That covers a house whose very
    first report failed to land, and as a side effect gives a newly installed
    house its first summary as soon as it has five days of activity rather than
    at the next Sunday.

    is_vacation also comes from the caller's existing read (house_routes.py's
    dashboard poll already fetches it). A house currently away has its vacation
    readings filtered out of get_weekly_sensor_data anyway (see
    database/repositories/sensor_readings.py), so regenerating now would just
    burn a Gemini call on a thin or empty week — and would stamp
    catchup_attempted_at, backing off the real regeneration by RETRY_AFTER once
    the resident is back. Skip here and let the next poll after vacation ends
    (still overdue, no attempt recorded) trigger it instead.
    """
    if is_vacation:
        return
    try:
        now = datetime.now(timezone.utc)
        if not _is_due(weekly_report_at, catchup_attempted_at, now):
            return
        house_ref = db.collection('houses').document(house_id)
        if not _claim(db.transaction(), house_ref, now):
            return
        threading.Thread(target=_regenerate, args=(house_id,), daemon=True).start()
    except Exception as e:
        # A catch-up is best-effort. It must never turn a working dashboard poll
        # into a failed request.
        print(f"[Catchup] Could not start catch-up for house {house_id}: {e}")


def _is_due(weekly_report_at, catchup_attempted_at, now):
    """Staleness test on values already in hand — no reads, no writes."""
    if catchup_attempted_at is not None:
        attempted = _as_datetime(catchup_attempted_at)
        if attempted is not None and now - attempted < RETRY_AFTER:
            return False
    if weekly_report_at is None:
        return True
    generated = _as_datetime(weekly_report_at)
    if generated is None:
        return False
    return now - generated >= STALE_AFTER


def _as_datetime(value):
    """Accepts either a Firestore timestamp or the ISO string the meta read
    returns, since callers hand over whichever they happen to hold."""
    if hasattr(value, 'tzinfo'):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    try:
        parsed = datetime.fromisoformat(str(value))
    except (TypeError, ValueError):
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


@firestore.transactional
def _claim(transaction, house_ref, now):
    """Marks this house as being caught up, if nobody else already has.

    Re-checks inside the transaction rather than trusting the caller's read: with
    several family members polling every 30 seconds, two requests can both see a
    stale report before either has written anything. The winner regenerates; the
    losers return False and do nothing.
    """
    snap = house_ref.get(
        transaction=transaction,
        field_paths=['weekly_report.generated_at', 'catchup_attempted_at'],
    )
    if not snap.exists:
        return False
    data = snap.to_dict() or {}
    generated_at = (data.get('weekly_report') or {}).get('generated_at')
    if not _is_due(generated_at, data.get('catchup_attempted_at'), now):
        return False
    # Written before the work starts, not after, so a crash mid-generation still
    # backs off for a day instead of retrying on the very next poll.
    transaction.update(house_ref, {'catchup_attempted_at': now})
    return True


def _regenerate(house_id):
    """Runs on a background thread. Nothing waits on the result — the app finds
    the new report through the same generated_at signal it uses for everything
    else, within one poll of it being written."""
    try:
        status, _ = generate_and_store(house_id, advance_baseline=False)
        if status == 'success':
            print(f"[Catchup] Regenerated overdue report for house {house_id}")
        else:
            print(f"[Catchup] House {house_id} not regenerated ({status}); "
                  f"retrying no sooner than {RETRY_AFTER}")
    except Exception as e:
        print(f"[Catchup] Failed to regenerate report for house {house_id}: {e}")
