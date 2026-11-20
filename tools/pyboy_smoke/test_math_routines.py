"""Multiply and Divide (home/math.asm) against Python, contract included (2026-11-19).

Both are hot: the AI decision profile spends ~28% of its cycles in them, and every
real damage roll uses them. Any speedup must be bit-exact, so this pins the
results AND the register contract callers were written against (home/math.asm
header): Multiply preserves bc/de/hl, returns a = hLoadedROMBank, exits Z set /
C clear and leaves hMultiplier alone; Divide preserves bc/de/hl, returns a =
hLoadedROMBank with the CALLER's flags, takes a b-byte left-aligned dividend,
destroys the divisor through the hRemainder alias, and is a no-op on divisor 0.

Registers are set by a hook at the routine's entry and read by a hook on its
final `ret` (the byte before the next routine, asserted to be $C9), so the
trampoline call_routine enters through cannot hide a contract break.
"""
from __future__ import annotations

import io
from pathlib import Path
import random
import unittest

from harness import RedRogueHarness

ROOT = Path(__file__).resolve().parents[2]
RET = 0xC9
H_MULTIPLICAND, H_MULTIPLIER, H_PRODUCT = 0xFF96, 0xFF99, 0xFF95
H_DIVIDEND, H_DIVISOR = 0xFF95, 0xFF99
FLAG_Z, FLAG_C = 0x80, 0x10


class MathRoutinesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        cls.h.boot_to_lobby()
        cls.baseline = io.BytesIO()
        cls.h.save_state(cls.baseline)
        sym = cls.h.symbols
        for label, addr in (("hMultiplicand", H_MULTIPLICAND), ("hMultiplier", H_MULTIPLIER),
                            ("hProduct", H_PRODUCT), ("hDividend", H_DIVIDEND), ("hDivisor", H_DIVISOR)):
            assert sym.get(label)[1] == addr, f"{label} moved: update this test"
        cls.mul_ret = (0, sym.get("Divide")[1] - 1)  # Multiply's final ret: the byte before Divide
        div_addr = sym.get("Divide")[1]
        nxt = min(a for b, a in (sym.get(n) for n in sym._symbols if "." not in n)
                  if b == 0 and div_addr < a < 0x4000)  # the next GLOBAL ROM0 label
        cls.div_ret = (0, nxt - 1)
        mem = cls.h.pyboy.memory
        assert mem[cls.mul_ret[1]] == RET, f"Multiply's last byte is {mem[cls.mul_ret[1]]:#04x}, not ret"
        assert mem[cls.div_ret[1]] == RET, f"Divide's last byte is {mem[cls.div_ret[1]]:#04x}, not ret"
        cls.entry, cls.exit = {}, {}
        rf = cls.h.pyboy.register_file

        def at_entry(_c, key):
            want = cls.entry.get("want")
            # Armed for exactly ONE call: the parked game's own Multiply/Divide calls (the frame that
            # runs out after each call, and the lobby right after a reload) must be left alone.
            if want is None or not cls.entry.get("armed") or key != cls.entry.get("routine"):
                return
            cls.entry["armed"] = False
            b, c, d, e, hi, lo = want["regs"]
            rf.B, rf.C, rf.D, rf.E, rf.HL = b, c, d, e, hi << 8 | lo
            rf.F = want["F"]
            cls.entry["seen"] = True

        def at_exit(_c, key):
            if cls.entry.get("seen") and key == cls.entry.get("routine") and not cls.exit:
                cls.exit.update(regs=(rf.B, rf.C, rf.D, rf.E, rf.HL >> 8, rf.HL & 0xFF), A=rf.A, F=rf.F,
                                bank=cls.h.read8("hLoadedROMBank"),
                                hram=[cls.h.pyboy.memory[H_PRODUCT + i] for i in range(5)])
                cls.entry["seen"] = False
        cls.h.register_hook("Multiply", lambda c: at_entry(c, "mul"))
        cls.h.register_hook("Divide", lambda c: at_entry(c, "div"))
        cls.h._register_at(cls.mul_ret, lambda c: at_exit(c, "mul"))
        cls.h._register_at(cls.div_ret, lambda c: at_exit(c, "div"))
        cls.calls = 0

    @classmethod
    def tearDownClass(cls) -> None:
        cls.h.close()

    def _call(self, routine, label, rng):
        h = self.h
        regs = tuple(rng.randrange(256) for _ in range(6))
        flags = rng.choice((0x00, 0x10, 0x80, 0x90, 0x60, 0xF0))
        self.entry.update(want={"regs": regs, "F": flags}, routine=routine, seen=False, armed=True)
        self.exit.clear()
        h.call_routine(label, limit=20000)
        self.assertTrue(self.exit, f"{label} never reached its final ret")
        self.assertEqual(self.exit["regs"], regs, f"{label} must preserve bc/de/hl")
        self.assertEqual(self.exit["A"], self.exit["bank"], f"{label} must return a = hLoadedROMBank")
        return flags

    def _maybe_reload(self):
        # Every 40 calls, re-park on a clean baseline. BEFORE writing inputs: load_state restores HRAM.
        h = self.h
        if self.calls % 40 == 0:
            self.baseline.seek(0)
            h.load_state(self.baseline)
            h.park_before_hijack()
            self.entry["armed"] = False
            h.call_routine("Multiply", limit=20000)  # unarmed warm-up after a fresh park
        type(self).calls += 1

    def multiply(self, mc, mp, rng):
        self._maybe_reload()
        mem = self.h.pyboy.memory
        guard = rng.randrange(256)
        for i in range(3):
            mem[H_MULTIPLICAND + i] = (mc >> (16 - 8 * i)) & 0xFF
        mem[H_MULTIPLIER] = mp
        mem[H_PRODUCT] = guard  # hProduct's first byte (not an input) must be overwritten
        self._call("mul", "Multiply", rng)
        out = self.exit["hram"]  # read AT the ret: the parked frame that follows reuses this HRAM
        got = int.from_bytes(bytes(out[:4]), "big")
        self.assertEqual(got, mc * mp, f"{mc:#08x} * {mp:#04x}")
        self.assertEqual(out[4], mp, "hMultiplier must be left alone")
        self.assertEqual(self.exit["F"] & (FLAG_Z | FLAG_C), FLAG_Z, "Multiply exits Z set, C clear")

    def divide(self, value, b, d, rng):
        mem = self.h.pyboy.memory
        raw = value.to_bytes(b, "big") + bytes(rng.randrange(256) for _ in range(4 - b))  # junk tail
        for i in range(4):
            mem[H_DIVIDEND + i] = raw[i]
        mem[H_DIVISOR] = d
        before = bytes(raw)
        flags = self._call_div(b, rng)  # b is an input register: the entry hook sets it
        out = self.exit["hram"]
        quotient = int.from_bytes(bytes(out[:4]), "big")
        if d == 0:
            self.assertEqual(bytes(out[:4]), before, "divisor 0 is a no-op")
        else:
            self.assertEqual(quotient, value // d, f"{value:#x} (b={b}) / {d}")
            self.assertEqual(out[4], value % d, "remainder lands in hRemainder (= hDivisor)")
        self.assertEqual(self.exit["F"] & 0xF0, flags & 0xF0, "Divide returns the caller's flags")

    def _call_div(self, b, rng):
        h = self.h
        if self.calls % 40 == 0:
            mem = h.pyboy.memory
            saved = [mem[H_DIVIDEND + i] for i in range(5)]
            self.baseline.seek(0)
            h.load_state(self.baseline)
            h.park_before_hijack()
            self.entry["armed"] = False
            h.call_routine("Multiply", limit=20000)  # unarmed warm-up, as in _call
            for i in range(5):
                mem[H_DIVIDEND + i] = saved[i]
        type(self).calls += 1
        regs = (b,) + tuple(rng.randrange(256) for _ in range(5))
        flags = rng.choice((0x00, 0x10, 0x80, 0x90, 0x60, 0xF0))
        self.entry.update(want={"regs": regs, "F": flags}, routine="div", seen=False, armed=True)
        self.exit.clear()
        h.call_routine("Divide", limit=20000)
        self.assertTrue(self.exit, "Divide never reached its final ret")
        self.assertEqual(self.exit["regs"], regs, "Divide must preserve bc/de/hl")
        self.assertEqual(self.exit["A"], self.exit["bank"], "Divide must return a = hLoadedROMBank")
        return flags

    def test_multiply_boundaries(self) -> None:
        rng = random.Random(1)
        for mc in (0, 1, 2, 0x7F, 0x80, 0xFF, 0x100, 0x1FF, 0x7FFF, 0xFFFF, 0x10000, 0x123456, 0xFFFFFF):
            for mp in (0, 1, 2, 3, 0x7F, 0x80, 0xAA, 0xFF):
                with self.subTest(mc=mc, mp=mp):
                    self.multiply(mc, mp, rng)

    def test_multiply_random(self) -> None:
        rng = random.Random(2)
        for _ in range(400):
            size = rng.choices((1, 2, 3), weights=(6, 3, 1))[0]
            mc, mp = rng.randrange(1 << (8 * size)), rng.randrange(256)
            with self.subTest(mc=mc, mp=mp):
                self.multiply(mc, mp, rng)

    def test_divide_boundaries(self) -> None:
        rng = random.Random(3)
        for b in (1, 2, 3, 4):
            top = (1 << (8 * b)) - 1
            for value in sorted(v for v in {0, 1, 2, 0xFF, 0x100, top, top // 2, top - 1} if v <= top):
                for d in (0, 1, 2, 5, 50, 0x7F, 0x80, 0xFF):
                    with self.subTest(value=value, b=b, d=d):
                        self.divide(value, b, d, rng)

    def test_divide_random(self) -> None:
        rng = random.Random(4)
        for _ in range(400):
            b = rng.choices((1, 2, 3, 4), weights=(1, 1, 1, 6))[0]
            sig = rng.randint(0, b)
            value = rng.randrange(1 << (8 * sig)) if sig else 0
            d = rng.randrange(1, 256)
            with self.subTest(value=value, b=b, d=d):
                self.divide(value, b, d, rng)


if __name__ == "__main__":
    unittest.main()
