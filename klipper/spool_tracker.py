# spool_tracker.py — Klipper extra for multi-channel load cell spool tracking
#
# Deploy to: ~/klipper/klippy/extras/spool_tracker.py
#
# printer.cfg:
#   [spool_tracker]
#   serial: /dev/ttyUSB0
#   baud: 115200
#   channels: 4
#
# Serial protocol (MCU → Klipper):
#   W 123.4 567.8 890.1\n    → weight per channel in grams
#
# Serial protocol (Klipper → MCU):
#   TARE 0\n                  → tare channel 0
#   TARE ALL\n                → tare all channels

import serial
import threading
import logging

class SpoolTracker:
    def __init__(self, config):
        self.printer   = config.get_printer()
        self.channels  = config.getint('channels', 1, minval=1, maxval=16)
        serial_port    = config.get('serial', '/dev/ttyUSB0')
        baud           = config.getint('baud', 115200)

        self._weights  = [0.0] * self.channels
        self._lock     = threading.Lock()
        self._serial   = None
        self._running  = False

        # Register gcode commands
        gcode = self.printer.lookup_object('gcode')
        gcode.register_command(
            'SPOOL_TARE', self.cmd_SPOOL_TARE,
            desc='Tare a load cell channel. Usage: SPOOL_TARE CHANNEL=0')
        gcode.register_command(
            'SPOOL_TARE_ALL', self.cmd_SPOOL_TARE_ALL,
            desc='Tare all load cell channels')

        # Connect to MCU serial
        try:
            self._serial = serial.Serial(serial_port, baud, timeout=1)
            self._running = True
            t = threading.Thread(target=self._read_loop, daemon=True)
            t.start()
            logging.info("SpoolTracker: connected %s @ %d", serial_port, baud)
        except Exception as e:
            logging.error("SpoolTracker: serial open failed: %s", e)

        self.printer.register_event_handler('klippy:ready', self._handle_ready)
        self.printer.register_event_handler('klippy:disconnect', self._handle_disconnect)

    def _handle_ready(self):
        self.printer.add_object('spool_tracker', self)

    def _handle_disconnect(self):
        self._running = False

    # ── Serial read loop ──────────────────────────────────────────────────────

    def _read_loop(self):
        buf = b''
        while self._running:
            try:
                if self._serial and self._serial.in_waiting:
                    buf += self._serial.read(self._serial.in_waiting)
                    while b'\n' in buf:
                        line, buf = buf.split(b'\n', 1)
                        self._parse(line.decode('ascii', errors='ignore').strip())
                else:
                    import time; time.sleep(0.01)
            except Exception as e:
                logging.warning("SpoolTracker read error: %s", e)

    def _parse(self, line: str):
        # Expected: "W 123.4 567.8 ..."
        parts = line.split()
        if len(parts) >= 2 and parts[0] == 'W':
            try:
                values = [float(p) for p in parts[1:]]
                with self._lock:
                    for i, v in enumerate(values[:self.channels]):
                        self._weights[i] = v
            except ValueError:
                pass

    def _send(self, cmd: str):
        if self._serial:
            try:
                self._serial.write((cmd + '\n').encode())
            except Exception as e:
                logging.warning("SpoolTracker write error: %s", e)

    # ── Gcode commands ────────────────────────────────────────────────────────

    def cmd_SPOOL_TARE(self, gcmd):
        ch = gcmd.get_int('CHANNEL', 0, minval=0, maxval=self.channels - 1)
        self._send(f'TARE {ch}')
        gcmd.respond_info(f'Tared spool channel {ch}')

    def cmd_SPOOL_TARE_ALL(self, gcmd):
        self._send('TARE ALL')
        gcmd.respond_info('Tared all spool channels')

    # ── Moonraker status object ───────────────────────────────────────────────

    def get_status(self, eventtime):
        with self._lock:
            return {
                'weights':  list(self._weights),
                'channels': self.channels,
            }

def load_config(config):
    return SpoolTracker(config)
