import requests
import time
import json

BASE_URL = "http://127.0.0.1:5000/api"

def test_anomaly_flow(num_requests=10):

    print(f"🚀 Starting to send {num_requests} requests to simulate an ANOMALY...\n")

    for i in range(num_requests):

        if i < 7:
            payload = {
                "sensor": "living_room_detector",
                "action": "motion_detected",
                "status": "open",
                "house_id": "test_house_123",
                "time": "2026-03-17T08:30:00"
            }
            print(f"Request {i+1} [08:30 AM] - Normal routine...")

        else:
            payload = {
                "sensor": "main_door_sensor",
                "action": "door_opened",
                "status": "open",
                "house_id": "test_house_123",
                "time": "2026-03-18T03:15:00"
            }
            print(f"Request {i+1} [03:15 AM] - 🚨 ANOMALY EVENT!")

        try:
            response = requests.post(f"{BASE_URL}/analyze", json=payload)
            data = response.json()

            if data.get('decision') != "Normal" or i == num_requests - 1:
                print(f"--> AI Decision: {data.get('decision')} | FCM: {data.get('fcm_status')}")

        except Exception as e:
            print(f"Connection failed: {e}")
            break

        time.sleep(0.5)

def test_vacation_mode():

    print("\n🏖️ Testing Vacation Mode...")
    payload = {"mode": "Vacation"}
    response = requests.post(f"{BASE_URL}/config", json=payload)
    print(f"Response: {response.json()}")

if __name__ == "__main__":
    test_anomaly_flow(num_requests=10)
    test_vacation_mode()
