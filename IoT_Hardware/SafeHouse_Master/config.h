#pragma once

// ─── WiFi ────────────────────────────────────────────────────────────────────
#define WIFI_SSID       "Yael"
#define WIFI_PASSWORD   "0544219013"

// ─── Server ──────────────────────────────────────────────────────────────────
#define SERVER_URL      "http://16.164.45.100:5000/api/analyze"
#define DEVICE_TOKEN    "c88129178b182d11afb452dd5c8af58d938dab252515f438b4f0e7645115f4af"
#define HOUSE_ID        "412ede6a-7810-496d-a223-49a6b8514011"

// ─── Timezone ────────────────────────────────────────────────────────────────
#define TIMEZONE        "UTC0"
#define NTP_SERVER_1    "pool.ntp.org"
#define NTP_SERVER_2    "time.nist.gov"

// ─── Master local sensor (Kitchen = index 1) ─────────────────────────────────
#define MASTER_SENSOR_INDEX   1
#define MASTER_SENSOR_PIN     14   // PIR on GPIO 14

// ─── Timing ──────────────────────────────────────────────────────────────────
#define SEND_INTERVAL_MS    60000UL
#define WIFI_TIMEOUT_MS     15000UL
#define HTTP_TIMEOUT_MS     10000

// GPIO2 is the built-in LED on most ESP32 DevKit boards.
#define PIN_STATUS_LED  2
