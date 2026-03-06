/**
 * spool_tracker_mcu.ino
 *
 * Arduino/ESP32 firmware for multi-channel HX711 load cell spool tracker.
 * Communicates with the Klipper spool_tracker.py extra over USB serial.
 *
 * Serial protocol:
 *   MCU  → Host : "W <ch0> <ch1> ... <chN>\n"   (weights in grams, 1 Hz)
 *   Host → MCU  : "TARE <n>\n"                   (tare channel n)
 *                 "TARE ALL\n"                    (tare all channels)
 *
 * Wiring (per channel):
 *   HX711 DOUT → DATA_PINS[i]
 *   HX711 SCK  → CLK_PINS[i]
 *   HX711 VCC  → 3.3V or 5V (check your module)
 *   HX711 GND  → GND
 *
 * Library: HX711 by bogde  (install via Arduino Library Manager)
 */

#include <HX711.h>

// ── Configuration ─────────────────────────────────────────────────────────────

// Number of load cell channels. Add/remove pins to match.
static const int NUM_CHANNELS = 2;

// HX711 data / clock pin pairs per channel
static const int DATA_PINS[NUM_CHANNELS] = { 4, 6 };
static const int CLK_PINS[NUM_CHANNELS]  = { 5, 7 };

// Calibration factor: raw units per gram.
// Run the calibration sketch once with a known weight, then paste values here.
static float CAL_FACTOR[NUM_CHANNELS] = { 420.0f, 420.0f };

// How often to broadcast weights (milliseconds)
static const unsigned long REPORT_INTERVAL_MS = 1000;

// Averaging: number of HX711 readings to average per report
static const int AVG_SAMPLES = 4;

// Serial baud — must match spool_tracker.py config
static const long BAUD = 115200;

// ── Globals ───────────────────────────────────────────────────────────────────

HX711 scales[NUM_CHANNELS];
float weights[NUM_CHANNELS];
unsigned long lastReport = 0;

// ── Setup ─────────────────────────────────────────────────────────────────────

void setup() {
    Serial.begin(BAUD);
    while (!Serial) {}  // wait for USB on Leonardo/32u4

    for (int i = 0; i < NUM_CHANNELS; i++) {
        scales[i].begin(DATA_PINS[i], CLK_PINS[i]);
        scales[i].set_scale(CAL_FACTOR[i]);
        scales[i].tare();  // zero on boot
        weights[i] = 0.0f;
    }

    Serial.println("READY");
}

// ── Loop ──────────────────────────────────────────────────────────────────────

void loop() {
    handleCommands();
    reportWeights();
}

// ── Read & report ─────────────────────────────────────────────────────────────

void reportWeights() {
    if (millis() - lastReport < REPORT_INTERVAL_MS) return;
    lastReport = millis();

    for (int i = 0; i < NUM_CHANNELS; i++) {
        if (scales[i].is_ready()) {
            weights[i] = scales[i].get_units(AVG_SAMPLES);
        }
    }

    // "W 123.4 567.8\n"
    Serial.print("W");
    for (int i = 0; i < NUM_CHANNELS; i++) {
        Serial.print(' ');
        Serial.print(weights[i], 1);
    }
    Serial.println();
}

// ── Command parser ────────────────────────────────────────────────────────────

void handleCommands() {
    if (!Serial.available()) return;

    String line = Serial.readStringUntil('\n');
    line.trim();

    if (line.startsWith("TARE ")) {
        String arg = line.substring(5);
        arg.trim();

        if (arg.equalsIgnoreCase("ALL")) {
            for (int i = 0; i < NUM_CHANNELS; i++) {
                scales[i].tare();
                weights[i] = 0.0f;
            }
            Serial.println("TARED ALL");
        } else {
            int ch = arg.toInt();
            if (ch >= 0 && ch < NUM_CHANNELS) {
                scales[ch].tare();
                weights[ch] = 0.0f;
                Serial.print("TARED ");
                Serial.println(ch);
            } else {
                Serial.print("ERR invalid channel: ");
                Serial.println(ch);
            }
        }
    }
}
