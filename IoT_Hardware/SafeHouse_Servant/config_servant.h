#pragma once

// ─── Which sensor is this board? ─────────────────────────────────────────────
// Set SENSOR_INDEX to one of:
//   0 = Door        1 = Kitchen     2 = Bathroom    3 = Toilet
//   4 = Medication  5 = Bedroom     6 = Living Room
//
// Change this one line and reflash for each board. Nothing verifies it — the
// master trusts whatever index arrives, so two boards flashed with the same value
// are indistinguishable. Confirm the boot banner on each board after flashing:
//   === Safe-House Servant — Sensor <n> on GPIO<p> ===
#define SENSOR_INDEX 1 // <-- change per board

// ─── GPIO pin the PIR signal wire is connected to ────────────────────────────
#define SENSOR_PIN 14 // PIR signal wire on GPIO 14

// ─── Master ESP32 MAC address ────────────────────────────────────────────────
// Flash the master first, read the Serial Monitor line:
//   [ESP-NOW] Master MAC: AA:BB:CC:DD:EE:FF
// then fill in the 6 bytes below.
#define MASTER_MAC {0xD0, 0xCF, 0x13, 0x58, 0x40, 0x30}

// ─── WiFi channel ────────────────────────────────────────────────────────────
// Fallback used only when the scan below cannot find ROUTER_SSID. The radio is
// 2.4 GHz only, so this MUST be 1–13 (the previous value, 52, is a 5 GHz channel:
// esp_wifi_set_channel() rejected it and the board never reached the master).
// Read the real value from the master's boot line:
//   [ESP-NOW] Master WiFi channel: <n>
#define WIFI_CHANNEL 1
#define ROUTER_SSID "Yael"

// How many times to look for ROUTER_SSID before giving up and using WIFI_CHANNEL.
#define CHANNEL_SCAN_ATTEMPTS 3

// ─── PIR timing ──────────────────────────────────────────────────────────────
// PIR modules need 30–60 s after power-up before their output means anything.
#define PIR_WARMUP_MS 60000UL
#define PIR_POLL_MS 20

// ─── Trigger delivery ────────────────────────────────────────────────────────
// esp_now_send() only confirms queueing, so each attempt waits for the send
// callback before deciding whether to retry.
#define SEND_MAX_ATTEMPTS 3
#define SEND_ACK_TIMEOUT_MS 200UL
#define SEND_RETRY_DELAY_MS 50
