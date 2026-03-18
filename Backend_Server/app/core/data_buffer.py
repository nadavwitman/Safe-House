import threading
from collections import deque
class SensorDataBuffer:
    def __init__(self, threshold=10):

        self.buffer = []

        self.threshold = threshold
        # This flag will be set true if the system is up and running
        self.is_active = True

    def add_reading(self, data):
        """ Adds new data to the buffer only if the system is up """
        if self.is_active:
            self.buffer.append(data)

    def has_enough_data(self):
        """ Checks whether we have enough data in the buffer to send to the AI model """
        return len(self.buffer) >= self.threshold

    def get_all_readings(self):
        return self.buffer

    def clear(self):
        self.buffer = []

# The global object buffer that will be filled by the ESP32 logs
sensor_buffer = SensorDataBuffer(threshold=10)
