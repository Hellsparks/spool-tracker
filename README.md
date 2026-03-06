# spool-tracker

Multi-channel filament spool weight tracker for Klipper + Mainsail.
Track remaining filament on up to N spools using HX711 load cells and an Arduino/ESP32.

```
HX711 load cells
      │
[Arduino/ESP32] ──USB serial──▶ [Klipper plugin] ──▶ [Moonraker] ──▶ [Mainsail panel]
```

---

## One-line install (Raspberry Pi)

```bash
curl -fsSL https://raw.githubusercontent.com/Hellsparks/spool-tracker/master/install.sh | bash
```

The installer will:
- Clone this repo to `~/spool-tracker`
- Symlink the Klipper extra into `~/klipper/klippy/extras/`
- Add a `[update_manager spool-tracker]` entry to `moonraker.conf` — the panel appears in Mainsail's update manager alongside Klipper, Moonraker, Crowsnest, etc.
- Clone Mainsail source, patch it to include the Spool Tracker panel, build it, and deploy to your web root automatically
- Restart Klipper

> **Updating later:** updates appear in **Mainsail → Settings → Update Manager**. Clicking update re-runs the installer, which re-patches and rebuilds Mainsail automatically.

---

## Manual install

If you prefer not to pipe to bash:

```bash
git clone https://github.com/Hellsparks/spool-tracker.git ~/spool-tracker
cd ~/spool-tracker
bash install.sh
```

---

## 1. printer.cfg

After running the installer, add this block to your `printer.cfg`:

```ini
[spool_tracker]
serial: /dev/ttyUSB0   # adjust to your MCU's port (check: ls /dev/ttyUSB*)
baud: 115200
channels: 2            # must match NUM_CHANNELS in the Arduino sketch
```

Find your MCU port with:
```bash
ls /dev/ttyUSB* /dev/ttyACM*
```

Then restart Klipper (Mainsail → Power → Restart Klipper, or `sudo systemctl restart klipper`).

---

## 2. MCU (Arduino / ESP32)

### Hardware per channel
- 1× HX711 load cell amplifier module
- 1× compatible load cell (5 kg platform cell recommended for spool weights)

### Wiring

| HX711 pin | Arduino pin |
|-----------|-------------|
| VCC       | 5V (or 3.3V — check your module) |
| GND       | GND |
| DOUT      | `DATA_PINS[i]` (default: 4, 6, …) |
| SCK       | `CLK_PINS[i]`  (default: 5, 7, …) |

### Flash

1. Install the **HX711** library by bogde via Arduino Library Manager
2. Open `mcu/spool_tracker_mcu.ino`
3. Edit the config section at the top:
   ```cpp
   static const int NUM_CHANNELS = 2;          // one per spool
   static const int DATA_PINS[] = { 4, 6 };    // HX711 DOUT pins
   static const int CLK_PINS[]  = { 5, 7 };    // HX711 SCK pins
   ```
4. Flash to your board

### Calibration

1. Leave the scale empty, open Serial Monitor at 115200 baud
2. Note the raw value printed — this is your zero offset (handled by `tare()` on boot)
3. Place a known weight (e.g. 500 g) on the scale
4. Raw value ÷ known weight in grams = your calibration factor
5. Set `CAL_FACTOR[i]` in the sketch and re-flash

```cpp
static float CAL_FACTOR[NUM_CHANNELS] = { 420.0f, 418.5f };
```

Repeat per channel since each HX711 + load cell pair will differ slightly.

---

## 3. Mainsail panel

**The installer handles this automatically.** It clones Mainsail source, patches two files (`src/pages/Dashboard.vue` and `src/store/gui/index.ts`), builds, and deploys.

After install, enable the panel in **Mainsail → Settings → Dashboard** — it will appear as "Spool Tracker" in the panel list.

### What the installer patches

| File | Change |
|---|---|
| `src/pages/Dashboard.vue` | Adds import + registers `SpoolTrackerPanel` component |
| `src/store/gui/index.ts` | Adds `{ name: 'spool-tracker', visible: true }` to all layout arrays |

### Manual build (if needed)

```bash
cd ~/mainsail-src
git pull
cp ~/spool-tracker/mainsail/SpoolTrackerPanel.vue src/components/panels/
python3 ~/spool-tracker/install.sh   # re-runs patching
npm run build
sudo cp -r dist/* /var/www/mainsail/
```

---

## Panel UI

| Column | Description |
|---|---|
| **Name** | Editable spool label |
| **Spool (g)** | Empty spool tare weight — set once per spool type |
| **Measured (g)** | Live reading from load cell |
| **Filament (g)** | `Measured − Spool` = filament remaining |
| **Tare button** | Zeros the load cell for that channel (sends `SPOOL_TARE CHANNEL=n` to Klipper) |

Filament column colour coding:
- Normal — more than 150 g remaining
- **Yellow** — less than 150 g (running low)
- **Red** — negative (spool weight heavier than measured — needs recalibration or tare)

Spool configs (names + tare weights) are saved to the Moonraker database and survive reboots.

---

## Gcode commands

| Command | Description |
|---|---|
| `SPOOL_TARE CHANNEL=0` | Tare a single channel |
| `SPOOL_TARE_ALL` | Tare all channels |

---

## Moonraker update_manager

The installer adds this block to `moonraker.conf` automatically.
If you need to add it manually:

```ini
[update_manager spool-tracker]
type: git_repo
path: ~/spool-tracker
origin: https://github.com/Hellsparks/spool-tracker.git
primary_branch: master
install_script: install.sh
managed_services: klipper
```

Once added, spool-tracker appears in **Mainsail → Settings → Update Manager** and can be updated with one click, just like Klipper, Moonraker, or Crowsnest.
