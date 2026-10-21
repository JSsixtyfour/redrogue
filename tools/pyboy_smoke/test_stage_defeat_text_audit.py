"""Regression controls for the bank-aware stage defeat-text audit."""

import unittest

from audit_stage_defeat_text import defeat_pointer_ok, offset


class StageDefeatPointerTests(unittest.TestCase):
    def test_same_bank_requires_direct_dispatcher(self):
        self.assertTrue(defeat_pointer_ok(b"", 0x11, 0x6000, 0x11, 0x6000))
        self.assertFalse(defeat_pointer_ok(b"", 0x11, 0x5000, 0x11, 0x6000))

    def test_cross_bank_requires_exact_local_wrapper(self):
        rom = bytearray(0x48000)
        off = offset(0x11, 0x5000)
        wrapper = bytes([0x17, 0xF9, 0x6D, 0x14, 0x50])
        rom[off:off + 5] = wrapper
        self.assertTrue(defeat_pointer_ok(rom, 0x11, 0x5000, 0x14, 0x6DF9))
        # Reject a raw cross-bank address, even if its numeric value matches.
        self.assertFalse(defeat_pointer_ok(rom, 0x11, 0x6DF9, 0x14, 0x6DF9))
        # Opcode, target address, target bank, and terminator all matter.
        for index in range(5):
            with self.subTest(index=index):
                rom[off:off + 5] = wrapper
                rom[off + index] ^= 1
                self.assertFalse(
                    defeat_pointer_ok(rom, 0x11, 0x5000, 0x14, 0x6DF9))


if __name__ == "__main__":
    unittest.main()
