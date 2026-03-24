from collections import deque

class SensorDataBuffer:
    def __init__(self, hours=12):
        # 12 hours * 60 minutes = 720 data vectors which recieved every minute needed for a full window
        self.threshold = hours * 60
        # deque automatically drops the oldest item when maxlen is reached
        self.buffer = deque(maxlen=self.threshold)
        self.is_active = True

    def add_reading(self, data):
        """
        Adds new data to the right side of the buffer.
        If the buffer is full (720 items), the oldest reading on the left drops off automatically.
        """
        if self.is_active:
            self.buffer.append(data)

    def has_enough_data(self):
        """ Checks if we have a full 12-hour window ready for the AI model """
        return len(self.buffer) == self.threshold

    def get_all_readings(self):
        """ Returns the buffer as a standard Python list for Pandas to process """
        return list(self.buffer)

    def clear(self):
        """ Clears the buffer (useful if the system reboots or resets) """
        self.buffer.clear()

# The global object buffer holding exactly the last 12 hours of 1-minute ESP32 logs
sensor_buffer = SensorDataBuffer(hours=12)
