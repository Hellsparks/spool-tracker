# spool-tracker

Multi-channel filament spool weight tracker for Klipper + Mainsail.

## Architecture

```
HX711 load cells
      │
[Arduino/ESP32] ──USB serial──▶ [Klipper spool_tracker.py] ──▶ [Moonraker] ──▶ [Mainsail panel]
```

## Files

| File | Deploy to |
|---|---|
| `klipper/spool_tracker.py` | `~/klipper/klippy/extras/spool_tracker.py` |
| `mainsail/SpoolTrackerPanel.vue` | `~/mainsail/src/components/panels/SpoolTrackerPanel.vue` |
| `mcu/spool_tracker_mcu.ino` | Flash to your Arduino/ESP32 |

---

## 1. MCU (Arduino/ESP32)

### Hardware
- 1× HX711 module + load cell per spool channel
- Edit `NUM_CHANNELS`, `DATA_PINS`, `CLK_PINS` in the sketch to match your wiring

### Calibration
1. Flash with a known calibration weight on the scale
2. Open Serial Monitor, note the raw value
3. Set `CAL_FACTOR[i] = raw_value / weight_in_grams`
4. Repeat per channel

### Serial protocol
- MCU sends `W 123.4 567.8\n` (one float per channel) every second
- MCU receives `TARE 0\n` or `TARE ALL\n` from Klipper

---

## 2. Klipper

Copy `spool_tracker.py` to `~/klipper/klippy/extras/`, then add to `printer.cfg`:

```ini
[spool_tracker]
serial: /dev/ttyUSB0   # adjust to your port
baud: 115200
channels: 2            # must match NUM_CHANNELS in sketch
```

Restart Klipper. New gcode commands available:
- `SPOOL_TARE CHANNEL=0` — tare one channel
- `SPOOL_TARE_ALL` — tare all channels

---

## 3. Mainsail

Copy `SpoolTrackerPanel.vue` to `src/components/panels/`, then register it in your dashboard view (`src/views/Dashboard.vue` or wherever your layout is):

```ts
import SpoolTrackerPanel from '@/components/panels/SpoolTrackerPanel.vue'
```

```html
<spool-tracker-panel />
```

Rebuild Mainsail:
```bash
npm install && npm run build
```

---

## Panel UI

| Column | Description |
|---|---|
| Name | Editable spool label |
| Spool (g) | Empty spool tare weight — set once per spool |
| Measured (g) | Live reading from load cell |
| Filament (g) | `Measured − Spool` = filament remaining. Turns yellow < 150 g, red < 0 g |
| Tare button | Zeros the load cell for that channel |

Spool configs are persisted to the Moonraker database (survive reboots).
