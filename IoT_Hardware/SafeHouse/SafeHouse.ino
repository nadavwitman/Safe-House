/*
 * Safe-House ESP32 Firmware
 *
 * Reads 7 sensors every 60 seconds and POSTs a JSON payload to the Flask API.
 * The sensor_vector captures which sensors fired during the last minute.
 * The current_location one-hot vector tracks which room the resident is in.
 *
 * Required libraries (install via Arduino Library Manager):
 *   - ArduinoJson  by Benoit Blanchon  (v6.x — NOT v7, API differs)
 *   - Built-in: WiFi, HTTPClient (both included in the ESP32 Arduino core)
 *
 * Board: "ESP32 Dev Module" (or your specific board) via the ESP32 Arduino core.
 * Upload speed: 115200 baud.
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <time.h>
#include "config.h"

// ─── Sensor index labels (for readability only) ───────────────────────────────
#define IDX_DOOR    0
#define IDX_KITCHEN 1
#define IDX_BATH    2
#define IDX_TOILET  3
#define IDX_MEDS    4
#define IDX_BEDROOM 5
#define IDX_LIVING  6

// ─── Static sensor configuration ─────────────────────────────────────────────
static const int  SENSOR_PINS[7] = {
    PIN_DOOR, PIN_KITCHEN, PIN_BATH, PIN_TOILET, PIN_MEDS, PIN_BEDROOM, PIN_LIVING
};
static const bool SENSOR_PIR[7] = SENSOR_IS_PIR;

// ─── Shared state written by ISRs ─────────────────────────────────────────────
// sensorFired[i] — did sensor i activate at any point during the last minute?
// lastActiveIdx  — index of the most recently triggered sensor this minute.
volatile bool sensorFired[7]  = {};
volatile int  lastActiveIdx   = IDX_LIVING;   // default: living room

// ─── Persisted between cycles ─────────────────────────────────────────────────
// One-hot vector: currentLocation[i] = 1 means the resident is at sensor i.
// Stays unchanged until a room sensor fires.
int  currentLocation[7] = {0, 0, 0, 0, 0, 0, 1};   // start in living room
unsigned long lastSendMs = 0;

// ─── ISR handlers ─────────────────────────────────────────────────────────────
// Each sensor gets its own ISR (ESP32 does not support parameterised ISRs).
// IRAM_ATTR places them in fast internal RAM so they run even during flash ops.
void IRAM_ATTR isr0() { sensorFired[0] = true; lastActiveIdx = 0; }
void IRAM_ATTR isr1() { sensorFired[1] = true; lastActiveIdx = 1; }
void IRAM_ATTR isr2() { sensorFired[2] = true; lastActiveIdx = 2; }
void IRAM_ATTR isr3() { sensorFired[3] = true; lastActiveIdx = 3; }
void IRAM_ATTR isr4() { sensorFired[4] = true; lastActiveIdx = 4; }
void IRAM_ATTR isr5() { sensorFired[5] = true; lastActiveIdx = 5; }
void IRAM_ATTR isr6() { sensorFired[6] = true; lastActiveIdx = 6; }

static void (*const ISR_TABLE[7])() = {
    isr0, isr1, isr2, isr3, isr4, isr5, isr6
};

// ─── WiFi ─────────────────────────────────────────────────────────────────────
static void connectWiFi() {
    if (WiFi.status() == WL_CONNECTED) return;

    Serial.printf("[WiFi] Connecting to \"%s\"", WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < WIFI_TIMEOUT_MS) {
        delay(500);
        Serial.print('.');
    }
    Serial.println();

    if (WiFi.status() == WL_CONNECTED) {
        Serial.printf("[WiFi] Connected. IP: %s\n", WiFi.localIP().toString().c_str());
    } else {
        Serial.println("[WiFi] Connection failed — will retry next cycle.");
    }
}

// ─── NTP ──────────────────────────────────────────────────────────────────────
// Syncs wall-clock time so timestamps in the JSON are local time.
// The backend uses hour and day-of-week for circular time features, so local
// time must be correct — set TIMEZONE in config.h.
static void syncTime() {
    configTzTime(TIMEZONE, NTP_SERVER_1, NTP_SERVER_2);
    Serial.print("[NTP] Syncing");

    struct tm t;
    unsigned long start = millis();
    while (!getLocalTime(&t) && millis() - start < 10000) {
        delay(500);
        Serial.print('.');
    }
    Serial.println();

    char buf[32];
    if (getLocalTime(&t)) {
        strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%S", &t);
        Serial.printf("[NTP] Time: %s (%s)\n", buf, TIMEZONE);
    } else {
        Serial.println("[NTP] Sync failed — timestamps will be inaccurate.");
    }
}

// ─── Sensor snapshot ──────────────────────────────────────────────────────────
// Atomically reads the ISR flags into outVector and clears them for the next
// cycle. Also captures the index of the last sensor to fire.
static void snapshotAndClear(int outVector[7], int &outLastIdx) {
    noInterrupts();
    for (int i = 0; i < 7; i++) {
        outVector[i]  = sensorFired[i] ? 1 : 0;
        sensorFired[i] = false;
    }
    outLastIdx = lastActiveIdx;
    interrupts();
}

// ─── Location tracking ────────────────────────────────────────────────────────
// Updates the one-hot currentLocation vector based on the last sensor that fired.
// Door (0) and medication cabinet (4) are point events, not rooms — they don't
// change which room the resident is considered to be in.
static void updateLocation(int idx) {
    if (idx == IDX_DOOR || idx == IDX_MEDS) return;
    for (int i = 0; i < 7; i++) currentLocation[i] = 0;
    currentLocation[idx] = 1;
}

// ─── LED feedback ─────────────────────────────────────────────────────────────
static void blinkLed(int times, int periodMs) {
    for (int i = 0; i < times; i++) {
        digitalWrite(PIN_STATUS_LED, HIGH);
        delay(periodMs);
        digitalWrite(PIN_STATUS_LED, LOW);
        delay(periodMs);
    }
}

// ─── HTTP POST ────────────────────────────────────────────────────────────────
static void sendReading(const int sensorVec[7], const int location[7]) {
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("[HTTP] Skipping — WiFi not connected.");
        return;
    }

    // Build ISO 8601 local timestamp
    char timestamp[32] = "1970-01-01T00:00:00";
    struct tm t;
    if (getLocalTime(&t)) {
        strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%S", &t);
    }

    // Build JSON payload:
    // {
    //   "house_id": "...",
    //   "time": "2026-05-20T14:30:00",
    //   "sensor_vector": [0,1,0,0,0,0,1],
    //   "current_location": [0,0,0,0,0,0,1]
    // }
    StaticJsonDocument<512> doc;
    doc["house_id"] = HOUSE_ID;
    doc["time"]     = timestamp;

    JsonArray sv = doc.createNestedArray("sensor_vector");
    JsonArray lv = doc.createNestedArray("current_location");
    for (int i = 0; i < 7; i++) {
        sv.add(sensorVec[i]);
        lv.add(location[i]);
    }

    char body[512];
    serializeJson(doc, body, sizeof(body));
    Serial.printf("[HTTP] POST %s\n", body);

    HTTPClient http;
    http.begin(SERVER_URL);
    http.addHeader("Content-Type",  "application/json");
    http.addHeader("X-Device-Token", DEVICE_TOKEN);
    http.setTimeout(HTTP_TIMEOUT_MS);

    int code = http.POST(body);

    if (code > 0) {
        String resp = http.getString();
        Serial.printf("[HTTP] %d → %s\n", code, resp.c_str());

        // Visual feedback: 3 fast blinks = Warning/Emergency, 1 slow = Normal
        bool isAlert = resp.indexOf("Warning") >= 0 || resp.indexOf("Emergency") >= 0;
        blinkLed(isAlert ? 3 : 1, isAlert ? 120 : 400);
    } else {
        Serial.printf("[HTTP] Error: %s\n", http.errorToString(code).c_str());
        blinkLed(5, 80);    // rapid 5-blink = network failure
    }

    http.end();
}

// ─── Arduino setup ────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);
    delay(500);
    Serial.println("\n=== Safe-House ESP32 v1.0 ===");

    pinMode(PIN_STATUS_LED, OUTPUT);
    digitalWrite(PIN_STATUS_LED, LOW);

    // Configure each sensor pin and attach its interrupt
    for (int i = 0; i < 7; i++) {
        if (SENSOR_PIR[i]) {
            // PIR: output goes HIGH on motion — pull down so idle reads LOW
            pinMode(SENSOR_PINS[i], INPUT_PULLDOWN);
            attachInterrupt(digitalPinToInterrupt(SENSOR_PINS[i]), ISR_TABLE[i], RISING);
        } else {
            // Reed switch wired to GND: closing the circuit pulls pin LOW
            pinMode(SENSOR_PINS[i], INPUT_PULLUP);
            attachInterrupt(digitalPinToInterrupt(SENSOR_PINS[i]), ISR_TABLE[i], FALLING);
        }
        Serial.printf("[Init] Sensor %d (%s) on GPIO%d\n",
                      i, SENSOR_PIR[i] ? "PIR" : "Reed", SENSOR_PINS[i]);
    }

    connectWiFi();
    syncTime();

    // Start the first send interval from now
    lastSendMs = millis();
    blinkLed(2, 200);
    Serial.println("[Init] Ready — posting every 60 s.");
}

// ─── Arduino loop ─────────────────────────────────────────────────────────────
void loop() {
    unsigned long now = millis();
    if (now - lastSendMs < SEND_INTERVAL_MS) return;
    lastSendMs = now;

    // Reconnect and re-sync time if WiFi dropped
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("[Loop] WiFi lost — reconnecting...");
        connectWiFi();
        if (WiFi.status() == WL_CONNECTED) syncTime();
    }

    // Atomically grab what fired this minute and reset for the next cycle
    int sensorVec[7];
    int latestIdx;
    snapshotAndClear(sensorVec, latestIdx);

    // Update the current-room estimate if anything moved
    bool anyFired = false;
    for (int i = 0; i < 7; i++) if (sensorVec[i]) { anyFired = true; break; }
    if (anyFired) updateLocation(latestIdx);

    // Debug print
    Serial.print("[Data] sensors=[");
    for (int i = 0; i < 7; i++) Serial.printf("%d%s", sensorVec[i], i < 6 ? "," : "");
    Serial.print("]  location=[");
    for (int i = 0; i < 7; i++) Serial.printf("%d%s", currentLocation[i], i < 6 ? "," : "");
    Serial.println("]");

    sendReading(sensorVec, currentLocation);
}
