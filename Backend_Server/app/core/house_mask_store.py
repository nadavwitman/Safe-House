import database.database as database


class HouseMaskStore:
    def __init__(self):
        self._store = {}  # house_id -> [0/1 x7]

    def get_mask(self, house_id):
        """ Returns mask from RAM; lazy-loads from DB on first access per house """
        if house_id not in self._store:
            self._store[house_id] = database.get_sensor_mask(house_id)
        return self._store[house_id]

    def set_mask(self, house_id, mask):
        """ Persists mask to Firestore and updates RAM """
        database.set_sensor_mask(house_id, mask)
        self._store[house_id] = mask

    def clear(self, house_id=None):
        """ Clears one house or all entries (useful for testing / resets) """
        if house_id:
            self._store.pop(house_id, None)
        else:
            self._store.clear()


# Global instance — import this in routes
house_mask_store = HouseMaskStore()
