/*
 * Safe-House ESP32 — SERVANT Firmware (Bulletproof State Machine Edition)
 *
 * Monitors one PIR sensor. When it fires, sends this board's sensor index
 * to the master ESP32 via ESP-NOW (no WiFi router needed).
 *
 * Setup per board:
 * 1. Open config_servant.h
 * 2. Set SENSOR_INDEX to this board's sensor (0–6, see comments there)
 * 3. Set SENSOR_PIN to the GPIO the PIR signal wire is connected to
 * 4. Set MASTER_MAC to the MAC printed by the master on first boot
 * 5. Set ROUTER_SSID to the master's WiFi network (e.g., "Yael")
 * 6. Flash and done — no other changes needed
 */

 #include <WiFi.h>
 #include <esp_wifi.h>
 #include <esp_now.h>
 #include "config_servant.h"
 
 // ─── ESP-NOW message structure (must match master) ────────────────────────────
 typedef struct {
     uint8_t sensor_idx;
 } esp_now_msg_t;
 
 // ─── State ────────────────────────────────────────────────────────────────────
 static uint8_t          masterMac[] = MASTER_MAC;
 static esp_now_peer_info_t peerInfo = {};
 bool                    lastPIRState = LOW; // Replaced the interrupt flag
 
 // ─── ESP-NOW send callback (optional debug) ───────────────────────────────────
 // ESP32 Arduino core 3.x: esp_now_send_cb_t uses wifi_tx_info_t (not uint8_t* MAC).
 #if ESP_ARDUINO_VERSION >= ESP_ARDUINO_VERSION_VAL(3, 0, 0)
 void onDataSent(const wifi_tx_info_t *info, esp_now_send_status_t status) {
     (void)info;
 #else
 void onDataSent(const uint8_t *mac, esp_now_send_status_t status) {
     (void)mac;
 #endif
     Serial.printf("[ESP-NOW] Send to master: %s\n",
                   status == ESP_NOW_SEND_SUCCESS ? "OK" : "FAIL");
 }
 
 // ─── Setup ────────────────────────────────────────────────────────────────────
 void setup() {
     Serial.begin(115200);
     delay(500);
     Serial.printf("\n=== Safe-House Servant — Sensor %d on GPIO%d ===\n",
                   SENSOR_INDEX, SENSOR_PIN);
 
     // 1. HARDWARE FIX: Use INPUT_PULLDOWN to prevent floating pin noise.
     // ISR/Interrupts are entirely removed to prevent memory-queued ghost triggers.
     pinMode(SENSOR_PIN, INPUT_PULLDOWN);
 
     // WiFi in STA mode (required for ESP-NOW) — does NOT connect to a router
     WiFi.mode(WIFI_STA);
     WiFi.disconnect();
 
     // Auto-scan for the master's router channel
     Serial.printf("[WiFi] Scanning for %s to determine channel...\n", ROUTER_SSID);
     int16_t n = WiFi.scanNetworks(false, false, false, 300, 0, ROUTER_SSID);
 
     int targetChannel = WIFI_CHANNEL; // Default fallback from config
     if (n > 0) {
         targetChannel = WiFi.channel(0);
         Serial.printf("[WiFi] Found %s on channel %d\n", ROUTER_SSID, targetChannel);
     } else {
         Serial.println("[WiFi] Network not found, using default channel from config.");
     }
     WiFi.scanDelete();
 
     // Set the ESP to the matched channel
     esp_wifi_set_channel(targetChannel, WIFI_SECOND_CHAN_NONE);
 
     // ESP-NOW init
     if (esp_now_init() != ESP_OK) {
         Serial.println("[ESP-NOW] Init failed — halting.");
         while (true) delay(1000);
     }
     esp_now_register_send_cb(onDataSent);
 
     // Register master as peer
     memcpy(peerInfo.peer_addr, masterMac, 6);
     peerInfo.channel = targetChannel; // Use the dynamically found channel
     peerInfo.encrypt = false;
     peerInfo.ifidx   = WIFI_IF_STA;   // 2. NETWORK FIX: Explicitly set the Wi-Fi interface
 
     if (esp_now_add_peer(&peerInfo) != ESP_OK) {
         Serial.println("[ESP-NOW] Failed to add master peer — halting.");
         while (true) delay(1000);
     }
 
     Serial.println("[Init] Ready — waiting for PIR triggers.");
 }
 
 // ─── Loop ─────────────────────────────────────────────────────────────────────
 void loop() {
     // Read exactly what the sensor is outputting right now
     bool currentState = digitalRead(SENSOR_PIN);
 
     // We only trigger if the sensor JUST flipped from LOW to HIGH
     if (currentState == HIGH && lastPIRState == LOW) {
         
         // 1. Blast the Wi-Fi immediately
         esp_now_msg_t msg = { .sensor_idx = SENSOR_INDEX };
         esp_err_t result = esp_now_send(masterMac, (uint8_t *)&msg, sizeof(msg));
 
         Serial.printf("[Trigger] Sensor %d fired — send %s\n",
                       SENSOR_INDEX,
                       result == ESP_OK ? "queued" : "error");
 
         // 2. Wait out the initial Wi-Fi power spike noise
         delay(2000); 
 
         // 3. THE BULLETPROOF TRAP
         // If the physical knob on the sensor is keeping the pin HIGH for 90 seconds,
         // this while-loop will just freeze the ESP32 right here. 
         // It cannot trigger again until the sensor physically drops back to LOW.
         while (digitalRead(SENSOR_PIN) == HIGH) {
             delay(100); 
         }
         
         // At this point, we guarantee the sensor is completely quiet.
     }
 
     // Save the state for the next loop
     lastPIRState = currentState;
 }