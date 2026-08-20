# User Story Tests

**US1 — Emergency Alert.** LSTM returns an "Emergency" decision -> asserts a push notification is actually sent to the house.

**US3 — Live Status.** `GET /api/house/<id>/status` -> asserts the dashboard's live-poll endpoint returns the correct status in one call.

**US6 — Sensor Silence Alert.** A sensor silent past its fault threshold (24h) -> asserts a "may need attention" fault alert fires.

**US9 — Vacation Mode.** House flagged `is_vacation=True` -> asserts LSTM inference and alerts are skipped, while per-sensor last-activity tracking keeps running (so intrusions can still be noticed).

Run all four together:

```
python tests/user_stories/run_user_story_tests.py
```
