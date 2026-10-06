# MouseRemote BLE Protocol (v1)

Shared contract between the iOS app (BLE central) and the nRF52840 dongle firmware (BLE peripheral).

## GATT

| Item | UUID |
|---|---|
| Service | `A7E10001-3C2B-4F6E-9D41-7B8C2E5F1A00` |
| RX characteristic (phone → dongle) | `A7E10002-3C2B-4F6E-9D41-7B8C2E5F1A00` |
| TX characteristic (dongle → phone) | `A7E10003-3C2B-4F6E-9D41-7B8C2E5F1A00` |

- RX properties: `write` + `write without response`. Security: encrypted (`ENCRYPT_NO_MITM`), so iOS triggers system pairing on first write.
- TX properties: `notify`, encrypted. Used only for AUTH replies.
- Advertised name: `MouseRemote`. The service UUID is included in the advertisement so iOS can scan by service.
- The phone always uses write-without-response.

## Framing

One BLE write carries one or more packets, concatenated. Each packet is `opcode (u8)` + a fixed-length payload. Multi-byte integers are **little-endian**. An unknown opcode makes the receiver discard the rest of that write.

| Op | Name | Payload (bytes) | Meaning |
|---|---|---|---|
| `0x01` | MOVE | `dx i16, dy i16` (4) | Relative pointer move. The dongle splits it into ±127 HID reports. |
| `0x02` | BUTTONS | `mask u8` (1) | Absolute mouse button state: Left=`0x01`, Right=`0x02`, Middle=`0x04`. |
| `0x03` | SCROLL | `v i8, h i8` (2) | Wheel (positive = up) and horizontal pan (positive = right). |
| `0x04` | KEY_TAP | `mod u8, key u8` (2) | Press `mod`+`key`, then release both. `key=0` means modifier-only tap. |
| `0x05` | KEY_SET | `mod u8, key u8, down u8` (3) | Press (`down=1`) or release (`down=0`) `mod` bits and `key`. Used for holds like Alt+Tab. |
| `0x06` | CONSUMER | `usage u16` (2) | Tap a consumer-control usage (press+release). |
| `0x07` | RELEASE_ALL | — (0) | Release all keys and mouse buttons. |
| `0x08` | PING | — (0) | Keepalive. |
| `0x09` | AUTH | `token [16]` (16) | Must be the first packet of every connection. All zeros means "no token yet". |

## Authentication (who may control the PC)

BLE encryption alone doesn't stop a stranger's phone from pairing, so the dongle also requires an app-level token.

1. The phone subscribes to TX, then sends `AUTH` with its stored token, or 16 zero bytes if it has none.
2. The dongle replies with a TX notification:
   - Token matches the one stored in the dongle's NVM → `0x01` (OK). The session is authenticated.
   - Token doesn't match **and the dongle is in pairing mode** → the dongle generates a new random token, stores it (replacing any old one), and replies `0x02` + `token[16]`. The phone saves it in the Keychain. The session is authenticated.
   - Otherwise → `0x00` (DENIED), and the dongle disconnects about 200 ms later.
3. Until authenticated, the dongle ignores every other opcode.

**Pairing mode** is on when the dongle has no stored token, or for 60 s after one press of the dongle button. It ends as soon as a phone pairs.

The button on this dongle is wired to the chip's hardware RESET, so every press restarts it. The firmware tells presses apart by counting restarts:

| Action | Result |
|---|---|
| 1 press | Restart into 60 s of pairing mode (fast blue blink) |
| 3 presses, each while the fast blue blink shows | Erase the token and BLE bonds, then enter pairing mode. Afterwards, also do "Forget This Device" in iOS Settings › Bluetooth. |
| 2 quick presses | UF2 bootloader (for updating CircuitPython) |
| Press, then press again while the LED blinks yellow | CircuitPython safe mode: the CIRCUITPY drive and console are visible, for editing firmware files |

TX reply codes: `0x00` DENIED, `0x01` OK, `0x02` NEW_TOKEN (followed by 16 bytes).

### Modifier bits (`mod`), standard HID
`0x01` LCtrl, `0x02` LShift, `0x04` LAlt, `0x08` LGUI (Windows key), `0x10` RCtrl, `0x20` RShift, `0x40` RAlt, `0x80` RGUI.

### Keycodes (`key`)
These are standard USB HID Keyboard/Keypad page (0x07) usages, for example `0x04` A, `0x28` Enter, `0x29` Esc, `0x2A` Backspace, `0x2B` Tab, `0x4C` Delete, `0x4F`–`0x52` arrows (Right, Left, Down, Up), `0x3A`–`0x45` F1–F12.

The phone maps characters to `(mod, key)` using a **US layout**, and Windows must use the US layout.

### Consumer usages (common)
`0x00E9` Vol+, `0x00EA` Vol−, `0x00E2` Mute, `0x00CD` Play/Pause, `0x00B5` Next, `0x00B6` Prev, `0x006F` Brightness+, `0x0070` Brightness−.

## Safety rules (dongle)
- On disconnect, release all keys and mouse buttons.
- If nothing (including PING) has been received for **1.0 s** while connected, release all. The phone sends PING every **300 ms** while connected.
- Only an authenticated phone may send input (see Authentication).
