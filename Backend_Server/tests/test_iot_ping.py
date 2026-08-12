import requests
import time

url = "http://127.0.0.1:5000/api/analyze"  # תחליף לפורט שלך אם הוא שונה
headers = {
    "X-Device-Token": "YOUR_TEST_TOKEN",  # תכניס טוקן חוקי שיעבור ולידציה
    "Content-Type": "application/json"
}

payload = {
    "house_id": "test_house_123",
    "current_location": [0, 0, 0, 0, 0, 0, 1]
    # תוסיף לכאן עוד שדות אם הראוט שלכם דורש אותם (כמו timestamps וכו')
}

print("🚀 Sending Ping 1 (Testing Cache Miss...)")
response1 = requests.post(url, json=payload, headers=headers)
print(f"Response 1: {response1.json()}\n")

time.sleep(2) # נותנים לשרת לנשום

print("🚀 Sending Ping 2 (Testing Cache Hit...)")
response2 = requests.post(url, json=payload, headers=headers)
print(f"Response 2: {response2.json()}")