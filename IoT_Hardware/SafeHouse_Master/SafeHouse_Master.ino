/*
 * Safe-House ESP32 — MASTER Firmware (Dedicated Gateway)
 *
 * Responsibilities:
 * 1. Acts ONLY as a central hub (no local sensors attached).
 * 2. Receives ESP-NOW packets from 7 servant boards (including the new Kitchen servant).
 * 3. Every 60 s: aggregates the full 7-bit sensor_vector + current_location
 * and POSTs to the Flask backend over WiFi.
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <esp_now.h>
#include <time.h>
#include "config.h"

// ─── Sensor index labels ──────────────────────────────────────────────────────
#define IDX_DOOR 0
#define IDX_KITCHEN 1
#define IDX_BATH 2
#define IDX_TOILET 3
#define IDX_MEDS 4
#define IDX_BEDROOM 5
#define IDX_LIVING 6

static const char *SENSOR_NAMES[7] = {
    "Door", "Kitchen", "Bath", "Toilet", "Meds", "Bedroom", "Living"};

// ─── ESP-NOW message structure (must match servant) ───────────────────────────
typedef struct
{
    uint8_t sensor_idx;
} esp_now_msg_t;

// ─── Shared state ─────────────────────────────────────────────────────────────
// Written by onDataRecv (runs in the WiFi task) and read/cleared by loop() (the
// Arduino task) — two tasks, potentially on two cores. A spinlock is the correct
// guard here: noInterrupts() only masks the calling core and does nothing to stop
// the WiFi task, so packets arriving mid-snapshot used to be silently discarded.
static portMUX_TYPE stateMux = portMUX_INITIALIZER_UNLOCKED;

bool sensorFired[7] = {};
uint16_t firedCount[7] = {};   // packets received per sensor during this window
uint8_t lastSrcMac[7][6] = {}; // which board last claimed each index
int lastActiveIdx = IDX_LIVING;
int currentLocation[7] = {0};
unsigned long lastSendMs = 0;

// ─── ESP-NOW receive callback ─────────────────────────────────────────────────
void onDataRecv(const esp_now_recv_info *recv_info, const uint8_t *data, int len)
{
    if (len != sizeof(esp_now_msg_t))
        return;
    esp_now_msg_t msg;
    memcpy(&msg, data, sizeof(msg));

    if (msg.sensor_idx >= 7)
        return;

    portENTER_CRITICAL(&stateMux);
    sensorFired[msg.sensor_idx] = true;
    if (firedCount[msg.sensor_idx] < UINT16_MAX)
        firedCount[msg.sensor_idx]++;
    memcpy(lastSrcMac[msg.sensor_idx], recv_info->src_addr, 6);
    lastActiveIdx = msg.sensor_idx;
    portEXIT_CRITICAL(&stateMux);
}

// ─── WiFi ─────────────────────────────────────────────────────────────────────
static void connectWiFi()
{
    if (WiFi.status() == WL_CONNECTED)
        return;
    Serial.printf("[WiFi] Connecting to \"%s\"", WIFI_SSID);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    unsigned long start = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - start < WIFI_TIMEOUT_MS)
    {
        delay(500);
        Serial.print('.');
    }
    Serial.println();
    if (WiFi.status() == WL_CONNECTED)
        Serial.printf("[WiFi] Connected. IP: %s\n", WiFi.localIP().toString().c_str());
    else
        Serial.println("[WiFi] Failed — will retry next cycle.");
}

// ─── NTP ──────────────────────────────────────────────────────────────────────
static void syncTime()
{
    configTzTime(TIMEZONE, NTP_SERVER_1, NTP_SERVER_2);
    Serial.print("[NTP] Syncing");
    struct tm t;
    unsigned long start = millis();
    while (!getLocalTime(&t) && millis() - start < 10000)
    {
        delay(500);
        Serial.print('.');
    }
    Serial.println();
    char buf[32];
    if (getLocalTime(&t))
    {
        strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%S", &t);
        Serial.printf("[NTP] Time: %s (%s)\n", buf, TIMEZONE);
    }
    else
    {
        Serial.println("[NTP] Sync failed — timestamps will be inaccurate.");
    }
}

// ─── Snapshot ─────────────────────────────────────────────────────────────────
static void snapshotAndClear(int outVector[7], uint16_t outCounts[7],
                             uint8_t outMacs[7][6], int &outLastIdx)
{
    portENTER_CRITICAL(&stateMux);
    for (int i = 0; i < 7; i++)
    {
        outVector[i] = sensorFired[i] ? 1 : 0;
        outCounts[i] = firedCount[i];
        memcpy(outMacs[i], lastSrcMac[i], 6);
        sensorFired[i] = false;
        firedCount[i] = 0;
    }
    outLastIdx = lastActiveIdx;
    portEXIT_CRITICAL(&stateMux);
}

// ─── Location tracking ────────────────────────────────────────────────────────
static void updateLocation(int idx)
{
    if (idx == IDX_MEDS)
        return;
    for (int i = 0; i < 7; i++)
        currentLocation[i] = 0;
    currentLocation[idx] = 1;
}

// ─── LED feedback ─────────────────────────────────────────────────────────────
static void blinkLed(int times, int periodMs)
{
    for (int i = 0; i < times; i++)
    {
        digitalWrite(PIN_STATUS_LED, HIGH);
        delay(periodMs);
        digitalWrite(PIN_STATUS_LED, LOW);
        delay(periodMs);
    }
}

// ─── HTTP POST ────────────────────────────────────────────────────────────────
static void sendReading(const int sensorVec[7], const int location[7])
{
    if (WiFi.status() != WL_CONNECTED)
    {
        Serial.println("[HTTP] Skipping — WiFi not connected.");
        return;
    }
    // The backend reads this field as a literal UTC instant (to_datetime(utc=True)
    // then tz_convert to Asia/Jerusalem), so the "Z" has to be true. Build it from
    // gmtime_r rather than getLocalTime(): the latter applies TIMEZONE, which would
    // silently emit local time wearing a "Z" and shift every reading by that offset.
    // TIMEZONE now only affects the human-readable serial log.
    char timestamp[32] = "1970-01-01T00:00:00Z";
    time_t nowSec = time(nullptr);
    struct tm utc;
    if (nowSec >= MIN_VALID_EPOCH && gmtime_r(&nowSec, &utc))
        strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", &utc);
    else
        Serial.println("[HTTP] Clock not set — NTP has not synced; timestamp is a placeholder.");

    StaticJsonDocument<512> doc;
    doc["house_id"] = HOUSE_ID;
    doc["time"] = timestamp;
    JsonArray sv = doc.createNestedArray("sensor_vector");
    JsonArray lv = doc.createNestedArray("current_location");
    for (int i = 0; i < 7; i++)
    {
        sv.add(sensorVec[i]);
        lv.add(location[i]);
    }

    char body[512];
    serializeJson(doc, body, sizeof(body));
    Serial.printf("[HTTP] POST %s\n", body);

    HTTPClient http;
    http.begin(SERVER_URL);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("X-Device-Token", DEVICE_TOKEN);
    http.setTimeout(HTTP_TIMEOUT_MS);

    int code = http.POST(body);
    if (code > 0)
    {
        String resp = http.getString();
        Serial.printf("[HTTP] %d → %s\n", code, resp.c_str());
        bool isAlert = resp.indexOf("Warning") >= 0 || resp.indexOf("Emergency") >= 0;
        blinkLed(isAlert ? 3 : 1, isAlert ? 120 : 400);
    }
    else
    {
        Serial.printf("[HTTP] Error: %s\n", http.errorToString(code).c_str());
        blinkLed(5, 80);
    }
    http.end();
}

// ─── Setup ────────────────────────────────────────────────────────────────────
void setup()
{
    Serial.begin(115200);
    delay(500);
    Serial.println("\n=== Safe-House Master (Dedicated Gateway) ===");

    pinMode(PIN_STATUS_LED, OUTPUT);
    digitalWrite(PIN_STATUS_LED, LOW);

    // WiFi (STA mode required before ESP-NOW init)
    WiFi.mode(WIFI_STA);
    connectWiFi();
    syncTime();

    // This board has NO local sensor — every index must arrive over ESP-NOW.
    // If you ever see a "[Init] Local sensor: ..." line, an old build is flashed.
    Serial.println("[Init] No local sensor on this board — gateway only.");

    // Print MAC and channel so you can copy them into config_servant.h
    Serial.printf("[ESP-NOW] Master MAC: %s\n", WiFi.macAddress().c_str());
    Serial.printf("[ESP-NOW] Master WiFi channel: %d (set WIFI_CHANNEL to match)\n",
                  (int)WiFi.channel());

    // ESP-NOW
    if (esp_now_init() != ESP_OK)
    {
        Serial.println("[ESP-NOW] Init failed — servant data will not be received.");
    }
    else
    {
        esp_now_register_recv_cb(onDataRecv);
        Serial.println("[ESP-NOW] Listening for servant packets.");
    }

    lastSendMs = millis();
    blinkLed(2, 200);
    Serial.println("[Init] Ready — posting every 60 s.");
}

// ─── Loop ─────────────────────────────────────────────────────────────────────
void loop()
{
    unsigned long now = millis();
    if (now - lastSendMs < SEND_INTERVAL_MS)
        return;
    lastSendMs = now;

    if (WiFi.status() != WL_CONNECTED)
    {
        connectWiFi();
        if (WiFi.status() == WL_CONNECTED)
            syncTime();
    }

    int sensorVec[7] = {0};
    uint16_t counts[7] = {0};
    uint8_t macs[7][6] = {};
    int latestIdx;
    snapshotAndClear(sensorVec, counts, macs, latestIdx);

    bool anyFired = false;
    for (int i = 0; i < 7; i++)
        if (sensorVec[i])
        {
            anyFired = true;
            break;
        }

    // Naturally stick to last location if nothing fired
    if (anyFired)
    {
        updateLocation(latestIdx);
    }

    Serial.print("[Data] sensors=[");
    for (int i = 0; i < 7; i++)
        Serial.printf("%d%s", sensorVec[i], i < 6 ? "," : "");
    Serial.print("]  counts=[");
    for (int i = 0; i < 7; i++)
        Serial.printf("%u%s", (unsigned)counts[i], i < 6 ? "," : "");
    Serial.print("]  location=[");
    for (int i = 0; i < 7; i++)
        Serial.printf("%d%s", currentLocation[i], i < 6 ? "," : "");
    Serial.println("]");

    // Provenance per index: which board sent it, and how often. current_location is
    // "last packet wins", so a sensor firing far more often than a person could will
    // win every window and pin the location to its room. That is what a stuck or
    // false-triggering PIR looks like from here.
    for (int i = 0; i < 7; i++)
    {
        if (!sensorVec[i])
            continue;
        Serial.printf("[Src]  idx%d (%s) x%u from %02X:%02X:%02X:%02X:%02X:%02X\n",
                      i, SENSOR_NAMES[i], (unsigned)counts[i],
                      macs[i][0], macs[i][1], macs[i][2],
                      macs[i][3], macs[i][4], macs[i][5]);
        if (counts[i] >= STUCK_SENSOR_WARN_COUNT)
            Serial.printf("[Warn] idx%d (%s) fired %u times in 60 s — suspect stuck or "
                          "false-triggering sensor.\n",
                          i, SENSOR_NAMES[i], (unsigned)counts[i]);
    }

    sendReading(sensorVec, currentLocation);
}
