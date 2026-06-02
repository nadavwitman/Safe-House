#pragma once

// ─── WiFi ────────────────────────────────────────────────────────────────────
#define WIFI_SSID       "Yael"
#define WIFI_PASSWORD   "0544219013"

// ─── Server ──────────────────────────────────────────────────────────────────
// Use your EC2 Elastic IP or domain, e.g. "http://13.48.x.x:5000/api/analyze"
#define SERVER_URL      "http://16.164.45.100:5000/api/analyze"
#define DEVICE_TOKEN    "c88129178b182d11afb452dd5c8af58d938dab252515f438b4f0e7645115f4af" // From admin dashboard
#define HOUSE_ID        "412ede6a-7810-496d-a223-49a6b8514011" // From admin dashboard

// ─── Timezone ────────────────────────────────────────────────────────────────
// POSIX TZ string — the model relies on local hour/day, so this must be correct.
// Israel Standard Time: "IST-2" | US Eastern: "EST5EDT,M3.2.0,M11.1.0" | UTC: "UTC0"
#define TIMEZONE        "UTC0"
#define NTP_SERVER_1    "pool.ntp.org"
#define NTP_SERVER_2    "time.nist.gov"

// ─── GPIO Pin Mapping ────────────────────────────────────────────────────────
// Sensor indices (must stay in this order — matches the model's feature vector):
//   0 = Door        1 = Kitchen    2 = Bathroom    3 = Toilet
//   4 = Medication  5 = Bedroom    6 = Living Room
//
// PIR sensors    → wire signal pin to GPIO, GND to GND, VCC to 3.3 V or 5 V
// Reed switches  → wire between GPIO and GND; INPUT_PULLUP will read LOW when closed
//
#define PIN_DOOR        4     // Reed switch: front door
#define PIN_KITCHEN     5     // PIR: kitchen
#define PIN_BATH        18    // PIR: bathroom
#define PIN_TOILET      19    // PIR: toilet
#define PIN_MEDS        21    // Reed switch: medication cabinet
#define PIN_BEDROOM     22    // PIR: bedroom
#define PIN_LIVING      23    // PIR: living room

// GPIO2 is the built-in LED on most ESP32 DevKit boards.
#define PIN_STATUS_LED  2

// ─── Sensor Types ────────────────────────────────────────────────────────────
// PIR:  fires HIGH on motion  → interrupt on RISING edge
// Reed: closes to GND         → interrupt on FALLING edge (INPUT_PULLUP)
//
// Set to true for PIR, false for reed switch (affects interrupt edge + pull mode)
#define SENSOR_IS_PIR   { true, true, true, true, true, true, true }
//                         Door  Kit  Bath Toilet Meds  Bed  Living

// ─── Timing ──────────────────────────────────────────────────────────────────
#define SEND_INTERVAL_MS    60000UL   // 1 minute between POSTs (match server buffer cadence)
#define WIFI_TIMEOUT_MS     15000UL   // Max wait for WiFi association
#define HTTP_TIMEOUT_MS     10000     // HTTP request timeout (ms)
