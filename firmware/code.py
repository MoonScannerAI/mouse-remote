# code.py -- MouseRemote dongle firmware (CircuitPython 10.x, nRF52840 MDK USB Dongle).
#
# Bridges the MouseRemote iPhone app (BLE central) to the PC (USB HID keyboard,
# mouse with horizontal pan, consumer control). Implements docs/PROTOCOL.md v1.
#
# BUTTON NOTE: the dongle's button is the chip's hardware RESET pin under
# CircuitPython (see boot.py), so it cannot be read as a GPIO and press
# duration cannot be measured. Button actions are therefore detected from the
# reset reason at start-up -- see handle_button_presses() below.

import os
import time

import _bleio
import board
import digitalio
import microcontroller
import supervisor

from adafruit_ble import BLERadio
from adafruit_ble.advertising.standard import ProvideServicesAdvertisement
from adafruit_ble.attributes import Attribute
from adafruit_ble.characteristics import Characteristic, ComplexCharacteristic
from adafruit_ble.services import Service
from adafruit_ble.uuid import VendorUUID
from adafruit_hid.consumer_control import ConsumerControl
from adafruit_hid.keyboard import Keyboard
from adafruit_hid.keycode import Keycode
from adafruit_hid.mouse import Mouse
import usb_hid

import protocol as P

DEVICE_NAME = "MouseRemote"
SERVICE_UUID = VendorUUID("A7E10001-3C2B-4F6E-9D41-7B8C2E5F1A00")
RX_UUID = VendorUUID("A7E10002-3C2B-4F6E-9D41-7B8C2E5F1A00")
TX_UUID = VendorUUID("A7E10003-3C2B-4F6E-9D41-7B8C2E5F1A00")

RX_MAX = 244            # max bytes per BLE write we accept (ATT MTU 247 - 3)
RX_QUEUE = 32           # number of queued writes held by the PacketBuffer

IDLE_RELEASE_MS = 1000  # PROTOCOL: release all after 1.0 s without any packet
DENY_DISCONNECT_MS = 200  # PROTOCOL: disconnect ~200 ms after DENIED
PAIRING_WINDOW_MS = 60000  # PROTOCOL: short press -> 60 s of pairing mode
# Not in PROTOCOL.md (dongle-internal policy): drop a connection that never
# authenticates, so a stranger can't hold the only connection slot forever.
# Generous enough for the iOS "Pair" system dialog on first use.
AUTH_TIMEOUT_MS = 30000

# Button presses (= resets) that follow each other within this time after
# code.py starts are counted together. 3 presses = "long press" (erase).
PRESS_WINDOW_MS = 10000
ERASE_PRESS_COUNT = 3

# ---------------------------------------------------------------- ticks
_TICKS_PERIOD = 1 << 29
_TICKS_MASK = _TICKS_PERIOD - 1
_TICKS_HALF = _TICKS_PERIOD // 2
ticks_ms = supervisor.ticks_ms  # wraps every ~6 days; never loses precision


def ticks_diff(a, b):
    """a - b in ms, correct across wrap-around (like adafruit_ticks)."""
    d = (a - b) & _TICKS_MASK
    if d >= _TICKS_HALF:
        d -= _TICKS_PERIOD
    return d


def ticks_add(t, ms):
    return (t + ms) & _TICKS_MASK


# ---------------------------------------------------------------- NVM storage
# microcontroller.nvm layout:
#   [0]  magic 0x4D ('M')   [1] version 0x01   [2..17] token   [18] check byte
#   [32] press magic 0xB7   [33] press count
_NVM = microcontroller.nvm
_TOK_MAGIC = 0x4D
_TOK_VERSION = 0x01
_TOK_REC_LEN = 2 + P.TOKEN_LEN + 1
_PRESS_OFF = 32
_PRESS_MAGIC = 0xB7


def _check_byte(token):
    c = 0x5A
    for b in token:
        c = (((c << 1) | (c >> 7)) & 0xFF) ^ b
    return c


class TokenStore:
    def __init__(self):
        self.token = self._load()

    @staticmethod
    def _load():
        rec = bytes(_NVM[0:_TOK_REC_LEN])
        if rec[0] != _TOK_MAGIC or rec[1] != _TOK_VERSION:
            return None
        tok = rec[2:2 + P.TOKEN_LEN]
        if rec[-1] != _check_byte(tok):
            return None
        return tok

    def save(self, token):
        _NVM[0:_TOK_REC_LEN] = bytes((_TOK_MAGIC, _TOK_VERSION)) + token + bytes((_check_byte(token),))
        self.token = bytes(token)

    def erase(self):
        _NVM[0:2] = b"\x00\x00"
        self.token = None


def new_token():
    while True:
        tok = os.urandom(P.TOKEN_LEN)  # nRF52840 hardware RNG
        if any(tok):  # all-zero means "no token" on the phone side
            return tok


def read_press_count():
    if _NVM[_PRESS_OFF] == _PRESS_MAGIC:
        return _NVM[_PRESS_OFF + 1]
    return 0


def write_press_count(n):
    _NVM[_PRESS_OFF:_PRESS_OFF + 2] = bytes((_PRESS_MAGIC if n else 0x00, min(n, 255)))


def handle_button_presses():
    """Return the number of consecutive button presses that led to this boot.

    The button is the RESET pin, so each press reboots the dongle with reset
    reason RESET_PIN. Presses are chained through NVM: a press made while the
    previous boot's PRESS_WINDOW_MS is still running adds one to the count.
    Only counted on a fresh start (not on a soft reload of code.py).
    """
    if supervisor.runtime.run_reason != supervisor.RunReason.STARTUP:
        return 0
    if microcontroller.cpu.reset_reason != microcontroller.ResetReason.RESET_PIN:
        if read_press_count():
            write_press_count(0)
        return 0
    n = read_press_count() + 1
    write_press_count(n)
    return n


# ---------------------------------------------------------------- LED
class Led:
    """RGB LED on P0.23/P0.22/P0.24, active-low. Blue shows connection state."""

    OFF, SLOW, FAST, SOLID = 0, 1, 2, 3

    def __init__(self):
        self._pins = []
        for name in ("LED_RED", "LED_GREEN", "LED_BLUE"):
            try:
                p = digitalio.DigitalInOut(getattr(board, name))
                p.switch_to_output(value=True)  # high = off
            except Exception:  # LED unavailable: run without it
                p = None
            self._pins.append(p)
        self._state = None

    def _write(self, rgb):
        if rgb == self._state:
            return
        self._state = rgb
        for p, on in zip(self._pins, rgb):
            if p is not None:
                p.value = not on

    def update(self, mode, now):
        if mode == Led.SOLID:
            on = True
        elif mode == Led.FAST:
            on = (now % 250) < 125
        elif mode == Led.SLOW:
            on = (now % 1000) < 150
        else:
            on = False
        self._write((False, False, on))

    def flash_red(self, times):
        for _ in range(times):
            self._write((True, False, False))
            time.sleep(0.15)
            self._write((False, False, False))
            time.sleep(0.15)


# ---------------------------------------------------------------- USB HID
class PanMouse(Mouse):
    """adafruit_hid Mouse on the 5-byte report from boot.py (adds AC Pan)."""

    def __init__(self, devices):
        super().__init__(devices)
        self.report = bytearray(5)  # buttons, x, y, wheel, pan

    def _send_no_move(self):
        r = self.report
        r[1] = r[2] = r[3] = r[4] = 0
        self._mouse_device.send_report(r)

    def set_buttons(self, mask):
        self.report[0] = mask
        self._send_no_move()

    def scroll(self, wheel, pan):
        r = self.report
        r[1] = r[2] = 0
        r[3] = max(-127, wheel) & 0xFF
        r[4] = max(-127, pan) & 0xFF
        self._mouse_device.send_report(r)
        r[3] = r[4] = 0  # Mouse.move() never touches r[4]; keep it zero


# PROTOCOL modifier bits 0x01..0x80, in bit order.
_MOD_KEYCODES = (
    Keycode.LEFT_CONTROL, Keycode.LEFT_SHIFT, Keycode.LEFT_ALT, Keycode.LEFT_GUI,
    Keycode.RIGHT_CONTROL, Keycode.RIGHT_SHIFT, Keycode.RIGHT_ALT, Keycode.RIGHT_GUI,
)


def mod_keycodes(mod):
    """HID modifier bitmask -> list of Keycode modifier keycodes."""
    return [kc for i, kc in enumerate(_MOD_KEYCODES) if mod & (1 << i)]


class Hid:
    def __init__(self):
        devices = usb_hid.devices
        self.kbd = Keyboard(devices)
        self.mouse = PanMouse(devices)
        self.cc = ConsumerControl(devices)
        self.held = set()     # keycodes held via KEY_SET
        self.active = False   # something may be pressed

    def dispatch(self, op, f):
        if op == P.OP_MOVE:
            self.mouse.move(f[0], f[1])  # adafruit_hid splits into +-127 reports
        elif op == P.OP_BUTTONS:
            self.mouse.set_buttons(f[0] & 0x07)
            if f[0] & 0x07:
                self.active = True
        elif op == P.OP_SCROLL:
            self.mouse.scroll(f[0], f[1])
        elif op == P.OP_KEY_TAP:
            codes = mod_keycodes(f[0])
            if f[1]:
                codes.append(f[1])
            if codes:
                self.active = True
                self.kbd.press(*codes)
                rel = [c for c in codes if c not in self.held]
                if rel:
                    self.kbd.release(*rel)
        elif op == P.OP_KEY_SET:
            codes = mod_keycodes(f[0])
            if f[1]:
                codes.append(f[1])
            if codes:
                if f[2]:
                    self.active = True
                    self.kbd.press(*codes)
                    self.held.update(codes)
                else:
                    self.kbd.release(*codes)
                    for c in codes:
                        self.held.discard(c)
        elif op == P.OP_CONSUMER:
            if f[0]:
                self.cc.send(f[0])
        elif op == P.OP_RELEASE_ALL:
            self.release_all(force=True)
        # OP_PING: nothing to do (activity timestamp is updated by the caller)

    def release_all(self, force=False):
        if not (self.active or force):
            return
        self.held.clear()
        self.active = False
        for fn in (self.kbd.release_all, self.mouse.release_all, self.cc.release):
            try:
                fn()
            except Exception:
                pass


# ---------------------------------------------------------------- BLE
class RxPackets(ComplexCharacteristic):
    """RX characteristic bound to a _bleio.PacketBuffer, which queues every
    write separately (keeps write boundaries; nothing lost between polls)."""

    def __init__(self):
        super().__init__(
            uuid=RX_UUID,
            properties=Characteristic.WRITE | Characteristic.WRITE_NO_RESPONSE,
            read_perm=Attribute.ENCRYPT_NO_MITM,
            write_perm=Attribute.ENCRYPT_NO_MITM,
            max_length=RX_MAX,
        )

    def bind(self, service):
        bound = super().bind(service)
        return _bleio.PacketBuffer(bound, buffer_size=RX_QUEUE, max_packet_size=RX_MAX)


class MouseRemoteService(Service):
    uuid = SERVICE_UUID
    rx = RxPackets()
    # On nRF, the CCCD's write permission follows the characteristic's
    # read_perm, so read_perm=ENCRYPT_NO_MITM makes subscribing require
    # encryption. That ATT error is what makes iOS start system pairing.
    tx = Characteristic(
        uuid=TX_UUID,
        properties=Characteristic.NOTIFY,
        read_perm=Attribute.ENCRYPT_NO_MITM,
        write_perm=Attribute.NO_ACCESS,
        max_length=1 + P.TOKEN_LEN,
    )


# ---------------------------------------------------------------- main
class Dongle:
    def __init__(self):
        self.led = Led()
        self.store = TokenStore()
        self.pair_deadline = None
        self.press_window_end = None

        presses = handle_button_presses()
        start = ticks_ms()
        if presses:
            self.press_window_end = ticks_add(start, PRESS_WINDOW_MS)
        if presses >= ERASE_PRESS_COUNT:
            # "Long press": erase token + BLE bonds, enter pairing mode.
            self.store.erase()
            try:
                _bleio.adapter.erase_bonding()
            except Exception:
                pass
            write_press_count(0)
            self.press_window_end = None
            self.led.flash_red(3)
        elif presses >= 1:
            # "Short press": 60 s pairing mode.
            self.pair_deadline = ticks_add(start, PAIRING_WINDOW_MS)

        self.hid = Hid()  # waits for USB enumeration
        self.radio = BLERadio()
        self.radio.name = DEVICE_NAME
        self.service = MouseRemoteService()
        self.adv = ProvideServicesAdvertisement(self.service)
        self.rx_buf = bytearray(512)

    # -- pairing mode ------------------------------------------------------
    def pairing_mode(self, now):
        if self.store.token is None:
            return True
        if self.pair_deadline is not None:
            if ticks_diff(self.pair_deadline, now) > 0:
                return True
            self.pair_deadline = None
        return False

    def housekeeping(self, now):
        if self.press_window_end is not None and ticks_diff(now, self.press_window_end) >= 0:
            write_press_count(0)
            self.press_window_end = None

    # -- AUTH ----------------------------------------------------------------
    def handle_auth(self, conn, token, now):
        """Returns (authenticated, deny_at)."""
        stored = self.store.token
        if not conn.paired:
            # Should be unreachable: RX requires an encrypted link.
            self.service.tx = bytes((P.REPLY_DENIED,))
            return False, ticks_add(now, DENY_DISCONNECT_MS)
        if stored is not None and P.ct_equal(token, stored):
            self.service.tx = bytes((P.REPLY_OK,))
            return True, None
        if self.pairing_mode(now):
            tok = new_token()
            self.store.save(tok)
            self.pair_deadline = None  # pairing mode ends as soon as a phone pairs
            self.service.tx = bytes((P.REPLY_NEW_TOKEN,)) + tok
            return True, None
        self.service.tx = bytes((P.REPLY_DENIED,))
        return False, ticks_add(now, DENY_DISCONNECT_MS)

    def drain_rx(self):
        rx = self.service.rx
        while rx.readinto(self.rx_buf) != 0:
            pass

    # -- connection session --------------------------------------------------
    def session(self, conn):
        try:
            conn.connection_interval = 15  # ms; lowest iOS accepts. Best effort.
        except Exception:
            pass
        rx = self.service.rx
        buf = self.rx_buf
        hid = self.hid
        authed = False
        deny_at = None
        t0 = ticks_ms()
        last_rx = t0
        while conn.connected:
            now = ticks_ms()
            n = rx.readinto(buf)
            if n != 0:
                last_rx = now
            if n > 0 and deny_at is None:
                for op, f in P.decode(buf, n):
                    if op == P.OP_AUTH:
                        authed, deny_at = self.handle_auth(conn, f[0], now)
                        if deny_at is not None:
                            hid.release_all()
                            break
                    elif authed:
                        try:
                            hid.dispatch(op, f)
                        except Exception:
                            # e.g. >6 keys held, USB suspended; never crash the loop
                            pass
                    # else: not authenticated -> ignore every other opcode
            if hid.active and ticks_diff(now, last_rx) > IDLE_RELEASE_MS:
                hid.release_all()
            if deny_at is not None and ticks_diff(now, deny_at) >= 0:
                conn.disconnect()
                break
            if not authed and deny_at is None and ticks_diff(now, t0) > AUTH_TIMEOUT_MS:
                conn.disconnect()
                break
            if authed:
                self.led.update(Led.SOLID, now)
            else:
                self.led.update(Led.FAST if self.pairing_mode(now) else Led.SLOW, now)
            self.housekeeping(now)
        # Disconnected: safety release and forget anything still queued.
        hid.release_all(force=True)
        self.drain_rx()

    def run(self):
        while True:
            now = ticks_ms()
            if self.radio.connected:
                conns = self.radio.connections
                if conns:
                    self.session(conns[0])
                    continue
            if not self.radio.advertising:
                self.radio.start_advertising(self.adv)
            self.led.update(Led.FAST if self.pairing_mode(now) else Led.SLOW, now)
            self.housekeeping(now)
            time.sleep(0.01)


def main():
    dongle = None
    try:
        dongle = Dongle()
        dongle.run()
    except Exception as e:  # never leave keys stuck or the dongle dead
        try:
            if dongle is not None:
                dongle.hid.release_all(force=True)
        except Exception:
            pass
        print("fatal:", repr(e))
        time.sleep(2)
        microcontroller.reset()  # SOFTWARE reset; not counted as a button press


main()
