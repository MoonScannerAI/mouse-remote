# MouseRemote dongle firmware

CircuitPython firmware for the **makerdiary nRF52840 MDK USB Dongle**. The dongle
receives commands from the MouseRemote iPhone app over Bluetooth and acts as a USB
keyboard, mouse and media-key device on your Windows PC. The protocol is described in
`../docs/PROTOCOL.md`.

Built for **CircuitPython 10.3.1** (latest stable on 2026-10-06), with libraries from
Adafruit CircuitPython Bundle **10.x, release 20261003** (adafruit_ble 10.1.5,
adafruit_hid 6.1.10).

## Files

| File | Goes on the dongle? | What it does |
|---|---|---|
| `boot.py` | yes | Sets up USB (keyboard, mouse with sideways scroll, media keys). Hides the CIRCUITPY drive and serial console. |
| `code.py` | yes | The main program: Bluetooth, authentication, and sending keys and mouse input. |
| `protocol.py` | yes | Decodes the packets the phone sends. |
| `settings.toml` | yes | Turns off CircuitPython's built-in Bluetooth file editor. This one matters for security. |
| `lib/` | yes | The Adafruit libraries `adafruit_ble` and `adafruit_hid` (.mpy files for CircuitPython 10). |
| `tests/` | no | Desktop tests for `protocol.py`. |

## The button: read this first

When CircuitPython is installed, the dongle's only button becomes a **reset button**.
CircuitPython sets this up itself and it can't be changed from code. So the firmware
can't tell a short press from a long one, and it can't see the button being held.
Each press restarts the dongle, and the firmware counts the restarts:

| What you do | What happens |
|---|---|
| Press once | The dongle restarts and stays in **pairing mode for 60 s** (fast blue blink). |
| Press 3 times, waiting for the fast blue blink before each next press | The dongle **forgets the paired phone and all Bluetooth bonds**: 3 red flashes, then pairing mode. |
| Press twice quickly (within half a second) | Opens the **UF2 bootloader**, used to update CircuitPython. |
| Press once, then again while the LED **blinks yellow** | Starts **safe mode**, the escape hatch (see below). |

In PROTOCOL.md, "short press" means a single press here, and "long press (≥3 s)" means
the triple press.

LED: slow blue blink means waiting for a phone. Fast blue blink means pairing mode.
Solid blue means a phone is connected and authenticated.

## Step 1: Enter the UF2 bootloader

- **Dongle new, or CircuitPython not installed yet:** hold the button while you plug the
  dongle into the PC, then let go. The LED turns green and a drive called `UF2BOOT`
  appears in File Explorer. Older bootloaders may use a different drive name.
- **CircuitPython already installed:** press the button **twice quickly**.

Open `INFO_UF2.TXT` on the drive. It should show a bootloader version and
`SoftDevice: S140 6.1.1`. CircuitPython needs that SoftDevice.

### If it shows a different SoftDevice (e.g. `S132 5.1.0`)

CircuitPython will copy over but never start: no CIRCUITPY drive appears and Windows
doesn't see the dongle at all. This happened on a real dongle with bootloader 0.7.1.
The fix is to load makerdiary's bootloader package, which includes S140 6.1.1:

1. `pip install adafruit-nrfutil` and download
   `uf2_bootloader-nrf52840_mdk_usb_dongle-0.7.1-s140_6.1.1.zip` from
   <https://github.com/makerdiary/nrf52840-mdk-usb-dongle/tree/main/firmware/uf2_bootloader/0.7.1>.
2. Enter the UF2 bootloader (hold the button while plugging in). Find its COM port
   under "Ports (COM & LPT)" in Device Manager.
3. Run `python -m nordicsemi dfu serial --package uf2_bootloader-nrf52840_mdk_usb_dongle-0.7.1-s140_6.1.1.zip -p COM4 -b 115200 --singlebank`
   (replace COM4 with your port).
4. The `UF2BOOT` drive comes back, and `INFO_UF2.TXT` now shows `S140 6.1.1`. Continue with Step 2.

### If no UF2 drive appears: older "Open Bootloader"

Dongles sold before mid-2020 came with Nordic's **Open Bootloader**. You can tell
because holding the button while plugging in makes the LED **pulse red**, and no drive
appears. Change it to the UF2 bootloader once, following makerdiary's older guide
("Upgrade to UF2 Bootloader from Open Bootloader"):
<https://github.com/makerdiary/nrf52840-mdk-usb-dongle/blob/v1.0.0/docs/programming.md>

1. Install **Python 3.10 or older**, then run `pip install nrfutil==6.1.7`. This
   is Nordic's legacy tool, and it doesn't install on newer Python versions.
2. Download `uf2_bootloader-0.2.13-44-gb2b4284-nosd_signed.zip` from the
   `firmware/open_bootloader` folder of the v1.0.0 tag of that repository.
3. Hold the button while plugging in (LED pulses red). In Device Manager, under
   "Ports (COM & LPT)", find the dongle's COM port, then run:
   `nrfutil dfu usb-serial -pkg uf2_bootloader-0.2.13-44-gb2b4284-nosd_signed.zip -p COM5`
   (replace COM5 with your port).
4. Update to the current bootloader, which includes the S140 6.1.1 SoftDevice.
   Run `pip install adafruit-nrfutil` and download
   `uf2_bootloader-nrf52840_mdk_usb_dongle-0.7.1-s140_6.1.1.zip` from
   <https://github.com/makerdiary/nrf52840-mdk-usb-dongle/tree/main/firmware/uf2_bootloader/0.7.1>.
   Hold the button while plugging in, then run:
   `adafruit-nrfutil --verbose dfu serial --package uf2_bootloader-nrf52840_mdk_usb_dongle-0.7.1-s140_6.1.1.zip -p COM5 -b 115200 --singlebank`

If any step fails, makerdiary's fallback is to program the bootloader `.hex` with an
external SWD debugger. See <https://wiki.makerdiary.com/nrf52840-mdk-usb-dongle/programming/uf2boot/>.

## Step 2: Install CircuitPython

Board page: <https://circuitpython.org/board/makerdiary_nrf52840_mdk_usb_dongle/>

Download the **10.3.1, English (US)** `.uf2` file:

```
https://downloads.circuitpython.org/bin/makerdiary_nrf52840_mdk_usb_dongle/en_US/adafruit-circuitpython-makerdiary_nrf52840_mdk_usb_dongle-en_US-10.3.1.uf2
```

For other versions the pattern is
`.../bin/makerdiary_nrf52840_mdk_usb_dongle/<lang>/adafruit-circuitpython-makerdiary_nrf52840_mdk_usb_dongle-<lang>-<version>.uf2`.

Drag the `.uf2` onto the `UF2BOOT` drive. The LED flashes while it copies, then the
dongle restarts and a drive called **CIRCUITPY** appears.

## Step 3: Copy the firmware

Copy these to the CIRCUITPY drive, replacing anything already there:

1. the whole `lib` folder
2. `protocol.py`, `code.py`, `settings.toml`
3. `boot.py` **last**

Wait about 5 seconds, then unplug the dongle and plug it back in. CIRCUITPY no longer
appears. Windows instead finds a keyboard and mouse, and the LED starts the slow blue
blink.

## Escape hatch: get the CIRCUITPY drive back

Press the button once. Right after that, the LED **blinks yellow** for about one second.
Press the button again during the yellow blinking, at least half a second after the
first press. The dongle starts in **safe mode**: `boot.py` doesn't run, so the CIRCUITPY
drive and the serial console come back.

Edit or delete files as needed, then press the button once to restart normally.

If safe mode doesn't work, press twice quickly to open the UF2 bootloader and copy the
CircuitPython `.uf2` again. Your files stay on the dongle.

## Testing with nRF Connect (iPhone)

1. Make sure the dongle is in pairing mode. That happens automatically the first time.
   Otherwise, press the button once and wait for the fast blue blink.
2. In **nRF Connect**, go to **Scanner**, find **MouseRemote**, and tap **Connect**.
3. Open the service `A7E10001-…`. On the TX characteristic `A7E10003-…`, tap the
   **subscribe** (down-arrows) icon. When iOS asks to pair, tap **Pair**.
4. On the RX characteristic `A7E10002-…`, tap the **write** (up-arrow) icon. Choose
   **Byte Array**, type the hex, and send.

| Test | Hex to write | What you should see |
|---|---|---|
| AUTH with no token (send first) | `0900000000000000000000000000000000` | TX shows `02` followed by 32 hex digits: your new token. LED goes solid blue. |
| MOVE: right 100, down 50 | `0164003200` | The PC's pointer moves. |
| KEY_TAP of `a` | `040004` | Types `a` (US keyboard layout). |
| CONSUMER volume up | `06E900` | The PC's volume goes up. |

On later connections, the first write must be `09` followed by your token. Otherwise
the dongle replies `00` (DENIED) and disconnects. If you made the dongle forget its
pairing (triple press), also go to iOS **Settings > Bluetooth > MouseRemote > Forget
This Device** before pairing again.

## Desktop tests

Run these from the project root, not from inside `firmware/`. Inside that folder,
`code.py` hides Python's built-in `code` module.

```
python -m pytest firmware/tests
python firmware/tests/test_protocol.py
```
