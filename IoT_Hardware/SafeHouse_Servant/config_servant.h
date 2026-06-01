#pragma once

// ─── Which sensor is this board? ─────────────────────────────────────────────
// Set SENSOR_INDEX to one of:
//   0 = Door        2 = Bathroom    3 = Toilet
//   4 = Medication  5 = Bedroom     6 = Living Room
//
// Change this one line and reflash for each board.
#define SENSOR_INDEX    2       // <-- change per board

// ─── GPIO pin the PIR signal wire is connected to ────────────────────────────
#define SENSOR_PIN      14      // PIR signal wire on GPIO 14

// ─── Master ESP32 MAC addres
// s ────────────────────────────────────────────────
// Flash the master first, read the Serial Monitor line:
//   [ESP-NOW] Master MAC: AA:BB:CC:DD:EE:FF
// then fill in the 6 bytes below.
#define MASTER_MAC      { 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF }  // <-- replace

// ─── WiFi channel ────────────────────────────────────────────────────────────
// Must match the channel your WiFi router uses (usually 1, 6, or 11).
// Check by running the master and looking for the connected channel in Serial,
// or check your router's admin page.
#define WIFI_CHANNEL    1
