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
typedef struct
{
    uint8_t sensor_idx;
} esp_now_msg_t;

// ─── State ────────────────────────────────────────────────────────────────────
static uint8_t masterMac[] = MASTER_MAC;
static esp_now_peer_info_t peerInfo = {};
static int activeChannel = 0;
bool lastPIRState = LOW; // Replaced the interrupt flag

// Set by the send callback (WiFi task) and polled by sendTrigger() (Arduino task).
static volatile bool ackPending = false;
static volatile bool ackOk = false;

// ─── ESP-NOW send callback ────────────────────────────────────────────────────
// esp_now_send() only reports that the frame was *queued*; this callback is the
// only place delivery is actually confirmed. Kept free of Serial — it runs in the
// WiFi task and sendTrigger() does the reporting.
// ESP32 Arduino core 3.x: esp_now_send_cb_t uses wifi_tx_info_t (not uint8_t* MAC).
#if ESP_ARDUINO_VERSION >= ESP_ARDUINO_VERSION_VAL(3, 0, 0)
void onDataSent(const wifi_tx_info_t *info, esp_now_send_status_t status)
{
    (void)info;
#else
void onDataSent(const uint8_t *mac, esp_now_send_status_t status)
{
    (void)mac;
#endif
    ackOk = (status == ESP_NOW_SEND_SUCCESS);
    ackPending = false;
}

// ─── Channel sync ─────────────────────────────────────────────────────────────
// ESP-NOW only works when both boards sit on the same channel, so this board has to
// follow whatever channel the master's router is on. Returns the channel in use.
static int syncToMasterChannel()
{
    int found = 0;
    for (int attempt = 1; attempt <= CHANNEL_SCAN_ATTEMPTS && found == 0; attempt++)
    {
        Serial.printf("[WiFi] Scanning for %s (attempt %d/%d)...\n",
                      ROUTER_SSID, attempt, CHANNEL_SCAN_ATTEMPTS);
        int16_t n = WiFi.scanNetworks(false, false, false, 300, 0, ROUTER_SSID);
        if (n > 0)
            found = WiFi.channel(0);
        WiFi.scanDelete();
        if (found == 0)
            delay(1000);
    }

    // The radio is 2.4 GHz only, so anything outside 1–13 is unusable and
    // esp_wifi_set_channel() would reject it, leaving the board deaf.
    if (found >= 1 && found <= 13)
    {
        Serial.printf("[WiFi] Found %s on channel %d\n", ROUTER_SSID, found);
    }
    else
    {
        found = WIFI_CHANNEL;
        Serial.printf("[WiFi] %s not found — falling back to channel %d\n",
                      ROUTER_SSID, found);
    }

    esp_err_t err = esp_wifi_set_channel(found, WIFI_SECOND_CHAN_NONE);
    if (err != ESP_OK)
    {
        Serial.printf("[WiFi] esp_wifi_set_channel(%d) failed: %s — "
                      "WIFI_CHANNEL must be a 2.4 GHz channel (1-13).\n",
                      found, esp_err_to_name(err));
    }

    activeChannel = found;
    return found;
}

// ─── Trigger delivery ─────────────────────────────────────────────────────────
// Retries until the master acknowledges. A dropped packet is a lost room change:
// the master's current_location is sticky, so it would keep reporting the previous
// room as if the resident never moved.
static bool sendTrigger()
{
    esp_now_msg_t msg = {.sensor_idx = SENSOR_INDEX};

    for (int attempt = 1; attempt <= SEND_MAX_ATTEMPTS; attempt++)
    {
        ackPending = true;
        ackOk = false;

        if (esp_now_send(masterMac, (uint8_t *)&msg, sizeof(msg)) == ESP_OK)
        {
            unsigned long start = millis();
            while (ackPending && millis() - start < SEND_ACK_TIMEOUT_MS)
                delay(5);
            if (ackOk)
            {
                Serial.printf("[Trigger] Sensor %d fired — delivered (attempt %d)\n",
                              SENSOR_INDEX, attempt);
                return true;
            }
        }
        delay(SEND_RETRY_DELAY_MS);
    }

    // Every attempt failed. The most common cause is the router having moved to a
    // different channel, which leaves this board permanently deaf until it resyncs.
    Serial.printf("[Trigger] Sensor %d fired — DELIVERY FAILED after %d attempts; "
                  "resyncing channel (was %d)\n",
                  SENSOR_INDEX, SEND_MAX_ATTEMPTS, activeChannel);
    int channel = syncToMasterChannel();
    esp_now_del_peer(masterMac);
    peerInfo.channel = channel;
    if (esp_now_add_peer(&peerInfo) != ESP_OK)
        Serial.println("[ESP-NOW] Failed to re-add master peer after resync.");
    return false;
}

// ─── Setup ────────────────────────────────────────────────────────────────────
void setup()
{
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
    int targetChannel = syncToMasterChannel();

    // ESP-NOW init
    if (esp_now_init() != ESP_OK)
    {
        Serial.println("[ESP-NOW] Init failed — halting.");
        while (true)
            delay(1000);
    }
    esp_now_register_send_cb(onDataSent);

    // Register master as peer
    memcpy(peerInfo.peer_addr, masterMac, 6);
    peerInfo.channel = targetChannel; // Use the dynamically found channel
    peerInfo.encrypt = false;
    peerInfo.ifidx = WIFI_IF_STA; // 2. NETWORK FIX: Explicitly set the Wi-Fi interface

    if (esp_now_add_peer(&peerInfo) != ESP_OK)
    {
        Serial.println("[ESP-NOW] Failed to add master peer — halting.");
        while (true)
            delay(1000);
    }

    // 3. WARM-UP: a PIR module outputs garbage for its first 30–60 s on power-up.
    // Without this, every reboot (including a brownout loop) emits a phantom trigger
    // for this board's index, which the master reads as real movement in this room.
    Serial.printf("[Init] PIR warm-up — ignoring the sensor for %lu s...\n",
                  (unsigned long)(PIR_WARMUP_MS / 1000UL));
    unsigned long warmStart = millis();
    while (millis() - warmStart < PIR_WARMUP_MS)
        delay(200);

    // Seed from the real pin so a sensor that is still HIGH here has to drop LOW
    // and rise again before it counts as a trigger.
    lastPIRState = digitalRead(SENSOR_PIN);

    Serial.println("[Init] Ready — waiting for PIR triggers.");
}

// ─── Loop ─────────────────────────────────────────────────────────────────────
void loop()
{
    // Read exactly what the sensor is outputting right now
    bool currentState = digitalRead(SENSOR_PIN);

    // We only trigger if the sensor JUST flipped from LOW to HIGH
    if (currentState == HIGH && lastPIRState == LOW)
    {

        // 1. Blast the Wi-Fi immediately, retrying until the master confirms
        sendTrigger();

        // 2. Wait out the initial Wi-Fi power spike noise
        delay(2000);

        // 3. THE BULLETPROOF TRAP
        // If the physical knob on the sensor is keeping the pin HIGH for 90 seconds,
        // this while-loop will just freeze the ESP32 right here.
        // It cannot trigger again until the sensor physically drops back to LOW.
        while (digitalRead(SENSOR_PIN) == HIGH)
        {
            delay(100);
        }

        // At this point, we guarantee the sensor is completely quiet, so record LOW
        // rather than the stale HIGH read at the top of this iteration.
        currentState = LOW;
    }

    // Save the state for the next loop
    lastPIRState = currentState;

    // Polling this hard starves the idle task; a PIR holds its output HIGH for
    // seconds, so there is nothing to gain from a tighter interval.
    delay(PIR_POLL_MS);
}
