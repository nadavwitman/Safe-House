#pragma once

// ─── WiFi ────────────────────────────────────────────────────────────────────
#define WIFI_SSID "Yael"
#define WIFI_PASSWORD "0544219013"

// ─── Server ──────────────────────────────────────────────────────────────────
#define SERVER_URL "http://16.164.45.100:5000/api/analyze"
#define DEVICE_TOKEN "a10fb638b677d5f42470cfec2350002218ee348ed1d587e58d6bf6ded49011d9"
#define HOUSE_ID "412ede6a-7810-496d-a223-49a6b8514011"

// ─── Timezone ────────────────────────────────────────────────────────────────
// Affects the serial log ONLY. The timestamp in the POST body is always true UTC
// (built with gmtime_r), because the backend converts it to Asia/Jerusalem itself
// — see data_preprocessing.format_sensor_data. Setting a local zone here used to
// shift every reading by that zone's offset, e.g. "EST5EDT,M3.2.0,M11.1.0" is
// UTC-4 in summer and made readings land 4 hours early.
// Israel: "IST-2IDT,M3.5.5/2,M10.5.0" | UTC: "UTC0"
#define TIMEZONE "IST-2IDT,M3.5.5/2,M10.5.0"
#define NTP_SERVER_1 "pool.ntp.org"
#define NTP_SERVER_2 "time.nist.gov"

// Sanity floor for the RTC: 2025-01-01T00:00:00Z. Below this the clock has not been
// set, so NTP has not synced and any timestamp we emit would be epoch garbage.
#define MIN_VALID_EPOCH 1735689600UL

// ─── Local sensor ────────────────────────────────────────────────────────────
// The master is a dedicated gateway — it has NO sensor of its own. It used to
// carry the kitchen PIR on GPIO14 via attachInterrupt(..., RISING) on a pin left
// floating (plain INPUT, no pull resistor). With nothing wired, that pin picked up
// noise and asserted index 1 continuously, pinning current_location to Kitchen.
// The kitchen is a servant board now; do not reintroduce a local sensor here.

// ─── Timing ──────────────────────────────────────────────────────────────────
#define SEND_INTERVAL_MS 60000UL
#define WIFI_TIMEOUT_MS 15000UL
#define HTTP_TIMEOUT_MS 10000

// ─── Diagnostics ─────────────────────────────────────────────────────────────
// A servant rate-limits itself to roughly one packet per 2–3 s (send + settle +
// wait-for-LOW), so continuous human occupancy tops out near 13 packets/minute and
// radio-level noise saturates near 30. Above this, the sensor is reporting more
// motion than a person can produce — warn, but never suppress: a real emergency
// must still get through.
#define STUCK_SENSOR_WARN_COUNT 20

// GPIO2 is the built-in LED on most ESP32 DevKit boards.
#define PIN_STATUS_LED 2
