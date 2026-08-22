"""
Runs all 4 user-story tests together and prints a clean pass/fail summary,
for a screenshot. Run from Backend_Server/:

    python tests/user_stories/run_user_story_tests.py
"""
import os
import sys
import pytest

STORIES = {
    "test_story1_emergency_alert.py": "US1 - Emergency Alert",
    "test_story3_live_status.py":     "US3 - Live Status",
    "test_story6_sensor_silence.py":  "US6 - Sensor Silence Alert",
    "test_story9_vacation_mode.py":   "US9 - Vacation Mode",
}


class SummaryPlugin:
    def __init__(self):
        self.results = {}

    def pytest_runtest_logreport(self, report):
        if report.when == 'call':
            self.results[report.nodeid] = report.outcome


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, here)
    plugin = SummaryPlugin()
    exit_code = pytest.main(["-q", here], plugins=[plugin])

    print("\n" + "=" * 50)
    print("SAFE HOUSE - USER STORY TEST RESULTS")
    print("=" * 50)
    for filename, label in STORIES.items():
        outcome = next((v for k, v in plugin.results.items() if filename in k), "not run")
        mark = "PASS" if outcome == "passed" else "FAIL"
        print(f"  [{mark}] {label}")
    print("=" * 50)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
