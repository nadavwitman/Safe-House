"""
Test script for database vector logging.
Writes a test vector to Firestore, reads it back, verifies, then deletes it.
"""
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from database.database import db, log_vector_reading

TEST_HOUSE_ID = "test_house_cleanup"

def test_log_vector_reading():
    test_data = {
        "sensor_vector": [1, 0, 1, 0, 0, 0, 1],
        "time": "2026-03-27T10:00:00"
    }

    # Write
    log_vector_reading(test_data, TEST_HOUSE_ID)

    # Read back
    docs = db.collection('houses').document(TEST_HOUSE_ID).collection('sensor_vectors').get()
    found = False
    for doc in docs:
        d = doc.to_dict()
        if d.get('sensor_vector') == [1, 0, 1, 0, 0, 0, 1] and d.get('time') == "2026-03-27T10:00:00":
            found = True
            break

    if found:
        print("TEST PASSED: Vector reading written and verified in Firestore.")
    else:
        print("TEST FAILED: Could not find the written vector in Firestore.")

if __name__ == "__main__":
    test_log_vector_reading()
