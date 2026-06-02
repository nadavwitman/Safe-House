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
 #define IDX_DOOR    0
 #define IDX_KITCHEN 1
 #define IDX_BATH    2
 #define IDX_TOILET  3
 #define IDX_MEDS    4
 #define IDX_BEDROOM 5
 #define IDX_LIVING  6
 
 // ─── ESP-NOW message structure (must match servant) ───────────────────────────
 typedef struct {
     uint8_t sensor_idx;
 } esp_now_msg_t;
 
 // ─── Shared state ─────────────────────────────────────────────────────────────
 volatile bool sensorFired[7] = {};
 volatile int  lastActiveIdx  = IDX_LIVING;
 int           currentLocation[7] = {1, 0, 0, 0, 0, 0, };  
 unsigned long lastSendMs = 0;
 
 // ─── ESP-NOW receive callback ─────────────────────────────────────────────────
 void onDataRecv(const esp_now_recv_info *recv_info, const uint8_t *data, int len) {
     if (len != sizeof(esp_now_msg_t)) return;
     esp_now_msg_t msg;
     memcpy(&msg, data, sizeof(msg));
     
     if (msg.sensor_idx < 7) {
         sensorFired[msg.sensor_idx] = true;
         lastActiveIdx = msg.sensor_idx;
     }
 }
 
 // ─── WiFi ─────────────────────────────────────────────────────────────────────
 static void connectWiFi() {
     if (WiFi.status() == WL_CONNECTED) return;
     Serial.printf("[WiFi] Connecting to \"%s\"", WIFI_SSID);
     WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
     unsigned long start = millis();
     while (WiFi.status() != WL_CONNECTED && millis() - start < WIFI_TIMEOUT_MS) {
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
 
 // ─── Snapshot ─────────────────────────────────────────────────────────────────
 static void snapshotAndClear(int outVector[7], int &outLastIdx) {
     noInterrupts();
     for (int i = 0; i < 7; i++) {
         outVector[i]   = sensorFired[i] ? 1 : 0;
         sensorFired[i] = false;
     }
     outLastIdx = lastActiveIdx;
     interrupts();
 }
 
 // ─── Location tracking ────────────────────────────────────────────────────────
 static void updateLocation(int idx) {
     if (idx == IDX_MEDS) return; 
     for (int i = 0; i < 7; i++) currentLocation[i] = 0;
     currentLocation[idx] = 1;
 }
 
 // ─── LED feedback ─────────────────────────────────────────────────────────────
 static void blinkLed(int times, int periodMs) {
     for (int i = 0; i < times; i++) {
         digitalWrite(PIN_STATUS_LED, HIGH); delay(periodMs);
         digitalWrite(PIN_STATUS_LED, LOW);  delay(periodMs);
     }
 }
 
 // ─── HTTP POST ────────────────────────────────────────────────────────────────
 static void sendReading(const int sensorVec[7], const int location[7]) {
     if (WiFi.status() != WL_CONNECTED) {
         Serial.println("[HTTP] Skipping — WiFi not connected.");
         return;
     }
     char timestamp[32] = "1970-01-01T00:00:00Z";
     struct tm t;
     if (getLocalTime(&t)) strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", &t);
 
     StaticJsonDocument<512> doc;
     doc["house_id"] = HOUSE_ID;
     doc["time"]     = timestamp;
     JsonArray sv = doc.createNestedArray("sensor_vector");
     JsonArray lv = doc.createNestedArray("current_location");
     for (int i = 0; i < 7; i++) { sv.add(sensorVec[i]); lv.add(location[i]); }
 
     char body[512];
     serializeJson(doc, body, sizeof(body));
     Serial.printf("[HTTP] POST %s\n", body);
 
     HTTPClient http;
     http.begin(SERVER_URL);
     http.addHeader("Content-Type",   "application/json");
     http.addHeader("X-Device-Token", DEVICE_TOKEN);
     http.setTimeout(HTTP_TIMEOUT_MS);
 
     int code = http.POST(body);
     if (code > 0) {
         String resp = http.getString();
         Serial.printf("[HTTP] %d → %s\n", code, resp.c_str());
         bool isAlert = resp.indexOf("Warning") >= 0 || resp.indexOf("Emergency") >= 0;
         blinkLed(isAlert ? 3 : 1, isAlert ? 120 : 400);
     } else {
         Serial.printf("[HTTP] Error: %s\n", http.errorToString(code).c_str());
         blinkLed(5, 80);
     }
     http.end();
 }
 
 // ─── Setup ────────────────────────────────────────────────────────────────────
 void setup() {
     Serial.begin(115200);
     delay(500);
     Serial.println("\n=== Safe-House Master (Dedicated Gateway) ===");
 
     pinMode(PIN_STATUS_LED, OUTPUT);
     digitalWrite(PIN_STATUS_LED, LOW);
 
     // WiFi (STA mode required before ESP-NOW init)
     WiFi.mode(WIFI_STA);
     connectWiFi();
     syncTime();
 
     // Print MAC so you can copy it into config_servant.h
     Serial.printf("[ESP-NOW] Master MAC: %s\n", WiFi.macAddress().c_str());
 
     // ESP-NOW
     if (esp_now_init() != ESP_OK) {
         Serial.println("[ESP-NOW] Init failed — servant data will not be received.");
     } else {
         esp_now_register_recv_cb(onDataRecv);
         Serial.println("[ESP-NOW] Listening for servant packets.");
     }
 
     lastSendMs = millis();
     blinkLed(2, 200);
     Serial.println("[Init] Ready — posting every 60 s.");
 }
 
 // ─── Loop ─────────────────────────────────────────────────────────────────────
 void loop() {
     unsigned long now = millis();
     if (now - lastSendMs < SEND_INTERVAL_MS) return;
     lastSendMs = now;
 
     if (WiFi.status() != WL_CONNECTED) {
         connectWiFi();
         if (WiFi.status() == WL_CONNECTED) syncTime();
     }
 
     int sensorVec[7];
     int latestIdx;
     snapshotAndClear(sensorVec, latestIdx);
 
     bool anyFired = false;
     for (int i = 0; i < 7; i++) if (sensorVec[i]) { anyFired = true; break; }
     
     // Naturally stick to last location if nothing fired
     if (anyFired) {
         updateLocation(latestIdx);
     }
 
     Serial.print("[Data] sensors=[");
     for (int i = 0; i < 7; i++) Serial.printf("%d%s", sensorVec[i], i < 6 ? "," : "");
     Serial.print("]  location=[");
     for (int i = 0; i < 7; i++) Serial.printf("%d%s", currentLocation[i], i < 6 ? "," : "");
     Serial.println("]");
 
     sendReading(sensorVec, currentLocation);
 }