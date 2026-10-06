"""Desktop unit tests for firmware/protocol.py.

Run from the project root (NOT from inside firmware/, where code.py would
shadow Python's standard "code" module that pytest imports):
    python -m pytest firmware/tests
or without pytest:
    python firmware/tests/test_protocol.py
"""

import importlib.util
import os
import unittest

# Load ../protocol.py by path so the firmware folder never lands on sys.path.
_spec = importlib.util.spec_from_file_location(
    "mouseremote_protocol",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "protocol.py"),
)
P = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(P)


def h(s):
    return bytes.fromhex(s.replace(" ", ""))


class DecodeSingle(unittest.TestCase):
    def test_move_little_endian_signed(self):
        self.assertEqual(P.decode(h("01 0a00 f6ff")), [(P.OP_MOVE, (10, -10))])
        self.assertEqual(P.decode(h("01 ff7f 0080")), [(P.OP_MOVE, (32767, -32768))])

    def test_buttons(self):
        self.assertEqual(P.decode(h("02 05")), [(P.OP_BUTTONS, (5,))])

    def test_scroll_signed(self):
        self.assertEqual(P.decode(h("03 01 ff")), [(P.OP_SCROLL, (1, -1))])
        self.assertEqual(P.decode(h("03 80 7f")), [(P.OP_SCROLL, (-128, 127))])

    def test_key_tap(self):
        self.assertEqual(P.decode(h("04 02 04")), [(P.OP_KEY_TAP, (2, 4))])
        self.assertEqual(P.decode(h("04 08 00")), [(P.OP_KEY_TAP, (8, 0))])

    def test_key_set(self):
        self.assertEqual(P.decode(h("05 04 2b 01")), [(P.OP_KEY_SET, (4, 0x2B, 1))])

    def test_consumer(self):
        self.assertEqual(P.decode(h("06 e900")), [(P.OP_CONSUMER, (0x00E9,))])
        self.assertEqual(P.decode(h("06 cd00")), [(P.OP_CONSUMER, (0x00CD,))])

    def test_zero_payload_ops(self):
        self.assertEqual(P.decode(h("07")), [(P.OP_RELEASE_ALL, ())])
        self.assertEqual(P.decode(h("08")), [(P.OP_PING, ())])

    def test_auth(self):
        tok = bytes(range(16))
        self.assertEqual(P.decode(b"\x09" + tok), [(P.OP_AUTH, (tok,))])
        self.assertEqual(P.decode(b"\x09" + bytes(16)), [(P.OP_AUTH, (bytes(16),))])

    def test_auth_token_is_bytes_copy(self):
        buf = bytearray(b"\x09" + bytes(range(16)))
        (op, (tok,)), = P.decode(buf)
        buf[1] = 0xEE
        self.assertIsInstance(tok, bytes)
        self.assertEqual(tok[0], 0)


class DecodeFraming(unittest.TestCase):
    def test_concatenated(self):
        data = h("09" + "00" * 16 + "01 0100 0200" + "02 01" + "08" + "02 00" + "06 e200")
        self.assertEqual(P.decode(data), [
            (P.OP_AUTH, (bytes(16),)),
            (P.OP_MOVE, (1, 2)),
            (P.OP_BUTTONS, (1,)),
            (P.OP_PING, ()),
            (P.OP_BUTTONS, (0,)),
            (P.OP_CONSUMER, (0xE2,)),
        ])

    def test_empty(self):
        self.assertEqual(P.decode(b""), [])

    def test_unknown_opcode_discards_rest(self):
        self.assertEqual(P.decode(h("08 ff 02 01 08")), [(P.OP_PING, ())])
        self.assertEqual(P.decode(h("00 08")), [])
        self.assertEqual(P.decode(h("0a 08")), [])

    def test_truncated_tail_dropped(self):
        self.assertEqual(P.decode(h("02 01 01 0100")), [(P.OP_BUTTONS, (1,))])
        self.assertEqual(P.decode(h("05 01 04")), [])
        self.assertEqual(P.decode(b"\x09" + bytes(15)), [])
        self.assertEqual(P.decode(h("01")), [])

    def test_length_argument(self):
        buf = bytearray(64)
        buf[0:6] = h("02 01 08 03 01 00")
        self.assertEqual(P.decode(buf, 3), [(P.OP_BUTTONS, (1,)), (P.OP_PING, ())])
        self.assertEqual(P.decode(buf, 6),
                         [(P.OP_BUTTONS, (1,)), (P.OP_PING, ()), (P.OP_SCROLL, (1, 0))])
        # bytes past `length` are ignored even if they would complete a packet
        self.assertEqual(P.decode(buf, 5), [(P.OP_BUTTONS, (1,)), (P.OP_PING, ())])

    def test_length_out_of_range_is_clamped(self):
        self.assertEqual(P.decode(h("08"), 100), [(P.OP_PING, ())])
        self.assertEqual(P.decode(h("08"), -5), [])
        self.assertEqual(P.decode(h("08"), 0), [])

    def test_memoryview_input(self):
        self.assertEqual(P.decode(memoryview(h("01 0500 fbff"))), [(P.OP_MOVE, (5, -5))])

    def test_fuzz_never_raises(self):
        import random
        rng = random.Random(1234)
        for _ in range(5000):
            data = bytes(rng.randrange(256) for _ in range(rng.randrange(40)))
            out = P.decode(data)
            consumed = sum(1 + P.payload_len(op) for op, _ in out)
            self.assertLessEqual(consumed, len(data))

    def test_payload_len(self):
        self.assertEqual([P.payload_len(op) for op in range(1, 10)], [4, 1, 2, 2, 3, 2, 0, 0, 16])
        self.assertIsNone(P.payload_len(0))
        self.assertIsNone(P.payload_len(0x0A))


class CtEqual(unittest.TestCase):
    def test_equal_and_not(self):
        a = bytes(range(16))
        self.assertTrue(P.ct_equal(a, bytes(range(16))))
        self.assertFalse(P.ct_equal(a, bytes(16)))
        self.assertFalse(P.ct_equal(a, a[:15]))
        self.assertFalse(P.ct_equal(a, a[:15] + b"\xff"))


class ReadmeExamples(unittest.TestCase):
    """The hex strings given in README.md must decode as documented."""

    def test_examples(self):
        self.assertEqual(P.decode(h("09" + "00" * 16)), [(P.OP_AUTH, (bytes(16),))])
        self.assertEqual(P.decode(h("0164003200")), [(P.OP_MOVE, (100, 50))])
        self.assertEqual(P.decode(h("040004")), [(P.OP_KEY_TAP, (0, 4))])
        self.assertEqual(P.decode(h("06E900")), [(P.OP_CONSUMER, (0xE9,))])


if __name__ == "__main__":
    unittest.main(verbosity=2)
