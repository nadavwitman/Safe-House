"""
One-time backfill for the per-sensor `last_sensor_activity` map.

New readings maintain this map automatically (see database.log_vector_reading),
but houses that already have history predate the field. This script scans each
house's existing sensor_vectors — newest first — and records, per sensor index,
the most recent minute it fired (==1). After running it once, the dashboard
shows each sensor's true last-activity time even if it was weeks ago.

Efficiency:
  * Fetches only the two fields it needs (sensor_vector, time).
  * Stops scanning a house the moment every sensor's last hit is found — so a
    healthy house finishes almost instantly. A house where some sensor never
    fired is scanned in full: that is the only way to prove it has no history.

Run from the Backend_Server directory:
    python backfill_last_activity.py            # all houses
    python backfill_last_activity.py <house_id> # one or more specific houses
"""
import sys
import time

from firebase_admin import firestore

import database.database as database

db = database.db
NUM_SENSORS = 7
PROGRESS_EVERY = 5000  # heartbeat line every N scanned docs (for long full scans)


def backfill_house(house_id):
    remaining = set(range(NUM_SENSORS))
    activity = {}  # str(sensor_index) -> Firestore timestamp
    scanned = 0
    started = time.time()

    # Newest first, fetching only the fields we need. Docs missing 'time' are
    # skipped by order_by; legacy string timestamps still work downstream.
    query = (
        db.collection('houses').document(house_id)
        .collection('sensor_vectors')
        .order_by('time', direction=firestore.Query.DESCENDING)
        .select(['sensor_vector', 'time'])
    )

    for doc in query.stream():
        if not remaining:
            break
        scanned += 1
        if scanned % PROGRESS_EVERY == 0:
            print(f"    ...{house_id}: scanned {scanned} docs, "
                  f"still looking for sensors {sorted(remaining)}")
        d = doc.to_dict() or {}
        vec = d.get('sensor_vector') or []
        t = d.get('time')
        if t is None:
            continue
        for i in list(remaining):
            if i < len(vec) and (vec[i] == 1 or vec[i] is True):
                activity[str(i)] = t
                remaining.discard(i)

    if activity:
        db.collection('houses').document(house_id).set(
            {'last_sensor_activity': activity}, merge=True
        )

    elapsed = time.time() - started
    print(f"  {house_id}: recorded sensors "
          f"{sorted(int(k) for k in activity)} "
          f"({scanned} docs scanned in {elapsed:.1f}s)")


def main():
    if len(sys.argv) > 1:
        house_ids = sys.argv[1:]
    else:
        house_ids = [h.id for h in db.collection('houses').stream()]

    print(f"Backfilling last_sensor_activity for {len(house_ids)} house(s)...")
    for house_id in house_ids:
        try:
            backfill_house(house_id)
        except Exception as e:
            print(f"  {house_id}: FAILED — {e}")
    print("Done.")


if __name__ == '__main__':
    main()
