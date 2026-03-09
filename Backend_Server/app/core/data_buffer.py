import threading
from collections import deque

class SensorDataBuffer:
    def __init__(self, max_len=1000):
        # deque with maxlen automatically drops oldest items when full
        self.buffer = deque(maxlen=max_len)
        # Lock ensures data integrity during concurrent API requests
        self.lock = threading.Lock()

    def add_reading(self, reading):
        # Thread-safe append to the end of the buffer
        with self.lock:
            self.buffer.append(reading)

    def get_latest_window(self, window_size=10):
        # Thread-safe retrieval of the N most recent readings
        with self.lock:
            return list(self.buffer)[-window_size:]

# Global instance to be shared across the Flask application
sensor_buffer = SensorDataBuffer()