/*
 * Safe-House ESP32 — SERVANT Firmware
 *
 * Monitors one PIR sensor. When it fires, sends this board's sensor index
 * to the master ESP32 via ESP-NOW (no WiFi router needed).
 *
 * Setup per board:
 *   1. Open config_servant.h
 *   2. Set SENSOR_INDEX to this board's sensor (0–6, see comments there)
 *   3. Set SENSOR_PIN to the GPIO the PIR signal wire is connected to
 *   4. Set MASTER_MAC to the MAC printed by the master on first boot
 *   5. Flash and done — no other changes needed
 *
 * Required libraries: none beyond the ESP32 Arduino core (esp_now is built in).
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
volatile bool           pirFired    = false;

// ─── ISR ──────────────────────────────────────────────────────────────────────
void IRAM_ATTR isrPir() {
    pirFired = true;
}

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

    // PIR input
    pinMode(SENSOR_PIN, INPUT);
    attachInterrupt(digitalPinToInterrupt(SENSOR_PIN), isrPir, RISING);

    // WiFi in STA mode (required for ESP-NOW) — does NOT connect to a router
    WiFi.mode(WIFI_STA);
    WiFi.disconnect();
    esp_wifi_set_channel(WIFI_CHANNEL, WIFI_SECOND_CHAN_NONE);

    // ESP-NOW init
    if (esp_now_init() != ESP_OK) {
        Serial.println("[ESP-NOW] Init failed — halting.");
        while (true) delay(1000);
    }
    esp_now_register_send_cb(onDataSent);

    // Register master as peer
    memcpy(peerInfo.peer_addr, masterMac, 6);
    peerInfo.channel = WIFI_CHANNEL;
    peerInfo.encrypt = false;
    if (esp_now_add_peer(&peerInfo) != ESP_OK) {
        Serial.println("[ESP-NOW] Failed to add master peer — halting.");
        while (true) delay(1000);
    }

    Serial.println("[Init] Ready — waiting for PIR triggers.");
}

// ─── Loop ─────────────────────────────────────────────────────────────────────
void loop() {
    if (!pirFired) return;
    pirFired = false;

    esp_now_msg_t msg = { .sensor_idx = SENSOR_INDEX };
    esp_err_t result = esp_now_send(masterMac, (uint8_t *)&msg, sizeof(msg));

    Serial.printf("[Trigger] Sensor %d fired — send %s\n",
                  SENSOR_INDEX,
                  result == ESP_OK ? "queued" : "error");

    // Debounce: ignore retriggering for 2 seconds
    delay(2000);
}
