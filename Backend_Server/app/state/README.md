# app/state

In-process (RAM) caches shared across request handlers and the scheduler. Both are safe as plain module-level globals because gunicorn runs a single worker — the whole app lives in one process/address space. Neither survives a restart/deploy; each is designed to cheaply rebuild itself from Firestore when that happens.

## Files

- **[data_buffer.py](data_buffer.py)** — `SensorDataBuffer` / the global `sensor_buffer` instance: a per-house rolling 6-hour (360-reading) window of raw sensor vectors, backing the LSTM's fixed-length input requirement (see [app/ai](../ai/README.md)). One `deque(maxlen=360)` per house_id.
  - `add_reading()` / `has_enough_data()` / `get_all_readings()` / `get_last_reading()` / `clear_house()` — buffer read/write, used by [app/api/analyze_routes.py](../api/README.md).
  - `pause_house()` / `resume_house()` — used by vacation mode ([app/api/config_routes.py](../api/README.md), [app/scheduling](../scheduling/README.md)) to stop buffering while a house is away; `clear_house()` is called alongside pausing so stale pre-vacation readings don't linger.
  - On a cold process start the buffer is empty for every house; `analyze_routes._ensure_buffer_warm()` replays recent Firestore history back into it so an established house doesn't have to wait a full 6 hours to refill.
- **[house_mask_store.py](house_mask_store.py)** — `HouseMaskStore` / the global `house_mask_store` instance: caches each house's 7-element installed-sensor mask (which of the 7 zones actually have a physical sensor) after a lazy first load from Firestore (`database.get_sensor_mask`). `set_mask()` writes through to Firestore and updates the cache in the same call. Used by [app/ai/model_paths.py](../ai/README.md)'s `masked_sensor_config` and by [app/api/house_routes.py](../api/README.md).
