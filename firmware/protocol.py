# MouseRemote BLE protocol v1 -- packet decoder.
#
# Pure Python: no CircuitPython imports, so it runs (and is unit-tested) on a
# desktop as well as on the dongle. See docs/PROTOCOL.md for the contract.

import struct

OP_MOVE = 0x01
OP_BUTTONS = 0x02
OP_SCROLL = 0x03
OP_KEY_TAP = 0x04
OP_KEY_SET = 0x05
OP_CONSUMER = 0x06
OP_RELEASE_ALL = 0x07
OP_PING = 0x08
OP_AUTH = 0x09

TOKEN_LEN = 16

# TX reply codes (dongle -> phone).
REPLY_DENIED = 0x00
REPLY_OK = 0x01
REPLY_NEW_TOKEN = 0x02

# opcode -> (payload length, struct format or None).
# All multi-byte integers are little-endian.
_LAYOUT = {
    OP_MOVE: (4, "<hh"),        # dx i16, dy i16
    OP_BUTTONS: (1, "<B"),      # mask u8
    OP_SCROLL: (2, "<bb"),      # v i8, h i8
    OP_KEY_TAP: (2, "<BB"),     # mod u8, key u8
    OP_KEY_SET: (3, "<BBB"),    # mod u8, key u8, down u8
    OP_CONSUMER: (2, "<H"),     # usage u16
    OP_RELEASE_ALL: (0, None),
    OP_PING: (0, None),
    OP_AUTH: (TOKEN_LEN, None),  # token [16] -> (bytes,)
}


def payload_len(op):
    """Payload length for a known opcode, or None if the opcode is unknown."""
    entry = _LAYOUT.get(op)
    return None if entry is None else entry[0]


def decode(buf, length=None):
    """Decode one BLE write into a list of (op, fields) tuples.

    ``buf`` is any bytes-like object; only the first ``length`` bytes are used
    (default: all of it). ``fields`` is a tuple:
      MOVE (dx, dy), BUTTONS (mask,), SCROLL (v, h), KEY_TAP (mod, key),
      KEY_SET (mod, key, down), CONSUMER (usage,), RELEASE_ALL (), PING (),
      AUTH (token_bytes,)

    Decoding stops (discarding the rest of the write) at an unknown opcode or
    at a packet whose payload is truncated. Packets decoded before that point
    are still returned. Never raises on malformed input.
    """
    if length is None:
        length = len(buf)
    else:
        length = max(0, min(length, len(buf)))
    out = []
    i = 0
    while i < length:
        op = buf[i]
        entry = _LAYOUT.get(op)
        if entry is None:
            break  # unknown opcode: discard rest of this write
        n, fmt = entry
        start = i + 1
        end = start + n
        if end > length:
            break  # truncated packet: discard it
        if op == OP_AUTH:
            fields = (bytes(buf[start:end]),)
        elif fmt is None:
            fields = ()
        else:
            fields = struct.unpack_from(fmt, buf, start)
        out.append((op, fields))
        i = end
    return out


def ct_equal(a, b):
    """Constant-time comparison of two byte strings (time depends only on length)."""
    if len(a) != len(b):
        return False
    diff = 0
    for x, y in zip(a, b):
        diff |= x ^ y
    return diff == 0
