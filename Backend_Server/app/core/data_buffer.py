from collections import deque

class SensorDataBuffer:
    def __init__(self, hours=6):
        # 6 hours * 60 minutes = 360 data vectors received every minute for a full window
        self.threshold = hours * 60
        # Dictionary to store a separate deque for each house_id
        self.buffers = {}
        self.is_active = True

    def _get_or_create_buffer(self, house_id):
        """ Internal helper to ensure each house has its own dedicated queue """
        if house_id not in self.buffers:
            self.buffers[house_id] = deque(maxlen=self.threshold)
        return self.buffers[house_id]

    def add_reading(self, data):
        """ 
        Adds new data to the specific buffer of the house.
        Automatically drops the oldest reading when it reaches 360 items.
        """
        if self.is_active:
            house_id = data.get('house_id', 'default_house')
            house_queue = self._get_or_create_buffer(house_id)
            house_queue.append(data)

    def has_enough_data(self, house_id):
        """ Checks if a specific house has reached the 360-minute window for AI processing """
        house_queue = self.buffers.get(house_id)
        return len(house_queue) == self.threshold if house_queue else False

    def get_all_readings(self, house_id):
        """ Returns the 360-minute buffer for a specific house as a standard list """
        house_queue = self.buffers.get(house_id, deque())
        return list(house_queue)

    def get_last_reading(self, house_id):
        """ 
        Returns the most recent reading for the given house_id.
        Efficient O(1) access to the end of the queue.
        """
        house_queue = self.buffers.get(house_id)
        if house_queue and len(house_queue) > 0:
            return house_queue[-1]
        return None

    def clear_house(self, house_id):
        """ Resets the buffer for a specific house if needed """
        if house_id in self.buffers:
            self.buffers[house_id].clear()


# The global object buffer holding exactly the last 6 hours of 1-minute ESP32 logs per house
sensor_buffer = SensorDataBuffer(hours=6)