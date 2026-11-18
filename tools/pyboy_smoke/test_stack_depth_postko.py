"""Stack headroom of the post-KO send-out ranker on its two real paths.

AIRankPostKOSendOut (and AIPostKOReply under it) is the deepest call chain the
battle AI has. This measures the true lowest SP each path reaches, VBlank and
every other interrupt included, and fails if it leaves fewer than
MIN_SPARE_BYTES above the stack section's low end, or if it writes into the
unused WRAM0 gap below the stack at all (an actual overflow).

V (voluntary): the T3 stalemate breaker (AIRankStalemateTarget -> VOLUNTARY
   ranking) inside the real turn plan, AIPlanEnemyTurn from MainInBattleLoop.
F (faint): the player KOs a 1-HP enemy from the battle menu, so
   AISelectSendOut -> AIRankPostKOSendOut runs from HandleEnemyMonFainted.

Method: at the path's entry hook, every free byte from the gap's low end up to
SP is filled with CANARY; at the path's end hook, the lowest byte that is no
longer CANARY is the deepest the stack went. This module runs both paths on
DMG; test_cgb_stack_depth_postko.py reruns them on CGB (CGB VBlank does more
palette work on the same stack, and run_smoke picks the mode per module).

Measured 2026-11-18: 101 B spare on the shallowest of the four.
"""
from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants
from stack_layout import MIN_SPARE_BYTES, stack_layout

ROOT = Path(__file__).resolve().parents[2]
CANARY = 0x5A


class Probe:
    def __init__(self, h: RedRogueHarness, gap_low: int):
        self.h = h
        self.gap_low = gap_low
        self.entry_sp = None
        self.lowest = None
        self.reply_calls = 0

    def fill(self, _=None):
        if self.entry_sp is not None:
            return
        sp = self.h.pyboy.register_file.SP
        self.entry_sp = sp
        for address in range(self.gap_low, sp):
            self.h.pyboy.memory[address] = CANARY

    def scan(self, _=None):
        if self.entry_sp is None or self.lowest is not None:
            return
        mem = self.h.pyboy.memory
        self.lowest = next((a for a in range(self.gap_low, self.entry_sp) if mem[a] != CANARY),
                           self.entry_sp)

    def count(self, _=None):
        self.reply_calls += 1


class StackDepthPostKOTest(unittest.TestCase):
    CGB = False

    @classmethod
    def setUpClass(cls):
        cls.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        cls.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        cls.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        cls.gap_low, cls.stack_low = stack_layout(ROOT / "pokeblue_debug.map")

    def mon(self, name, moves, level=50):
        return {"species": self.species[name], "level": level,
                "moves": [self.moves[m] for m in moves]}

    def harness(self):
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts", cgb_mode=self.CGB)
        self.addCleanup(h.close)
        return h

    def check(self, probe: Probe, name: str):
        self.assertIsNotNone(probe.entry_sp, f"{name}: path entry hook never fired")
        self.assertIsNotNone(probe.lowest, f"{name}: path end hook never fired")
        self.assertGreater(probe.reply_calls, 0, f"{name}: AIPostKOReply never ran")
        spare = probe.lowest - self.stack_low
        print(f"\n{name}: entry SP ${probe.entry_sp:04x}, lowest ${probe.lowest:04x}, "
              f"path used {probe.entry_sp - probe.lowest} B, {spare} B spare above "
              f"${self.stack_low:04x}, AIPostKOReply calls {probe.reply_calls}")
        self.assertGreaterEqual(probe.lowest, self.stack_low,
                                f"{name}: stack OVERFLOWED into the unused gap "
                                f"(${probe.lowest:04x} < ${self.stack_low:04x})")
        self.assertGreaterEqual(spare, MIN_SPARE_BYTES,
                                f"{name}: only {spare} B of stack spare, minimum {MIN_SPARE_BYTES}")

    def test_voluntary(self):
        h = self.harness()
        h.inject_fight2_spec(
            [self.mon("EKANS", ["POISON_STING", "LEER"], 10),
             self.mon("EKANS", ["POISON_STING", "LEER"], 10)],
            [self.mon("WEEZING", ["AMNESIA", "SELFDESTRUCT", "HAZE", "EXPLOSION"], 60),
             self.mon("CLEFABLE", ["BODY_SLAM", "THUNDERBOLT", "ICE_BEAM", "PSYCHIC_M"], 58),
             self.mon("SLOWBRO", ["SURF", "THUNDERBOLT", "PSYCHIC_M", "ICE_BEAM"], 58),
             self.mon("GENGAR", ["THUNDERBOLT", "PSYCHIC_M", "NIGHT_SHADE", "MEGA_DRAIN"], 58),
             self.mon("RHYDON", ["EARTHQUAKE", "ROCK_SLIDE", "BODY_SLAM", "HYPER_BEAM"], 58),
             self.mon("MAGMORTAR", ["FLAMETHROWER", "THUNDERBOLT", "BODY_SLAM", "EARTHQUAKE"], 58)],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3)
        probe = Probe(h, self.gap_low)
        h.register_hook("AIPlanEnemyTurn", probe.fill)
        h.register_hook("AIPostKOReply", probe.count)
        h.register_hook("DisplayBattleMenu", probe.scan)
        h.boot_fight2(seed=1)
        probe.scan()
        self.check(probe, f"voluntary {'CGB' if self.CGB else 'DMG'}")

    def test_faint(self):
        h = self.harness()
        h.inject_fight2_spec(
            [self.mon("STARMIE", ["SURF", "PSYCHIC_M", "THUNDERBOLT", "ICE_BEAM"], 70)],
            [self.mon("RATTATA", ["TACKLE"], 5),
             self.mon("SLOWBRO", ["SURF", "THUNDERBOLT", "PSYCHIC_M", "ICE_BEAM"]),
             self.mon("MAGMORTAR", ["FLAMETHROWER", "THUNDERBOLT", "BODY_SLAM", "EARTHQUAKE"]),
             self.mon("ELECTRODE", ["THUNDERBOLT", "SWIFT", "TAKE_DOWN", "EXPLOSION"]),
             self.mon("RHYDON", ["EARTHQUAKE", "ROCK_SLIDE", "BODY_SLAM", "HYPER_BEAM"]),
             self.mon("GENGAR", ["THUNDERBOLT", "PSYCHIC_M", "NIGHT_SHADE", "MEGA_DRAIN"])],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3)
        h.boot_fight2(seed=1)
        h.write8("wEnemyMonHP", 0)
        h.write8("wEnemyMonHP", 1, offset=1)
        h.write8("wAISeenPlayerMoveMask", 15)
        probe = Probe(h, self.gap_low)
        h.register_hook("AISelectSendOut", probe.fill)
        h.register_hook("AIPostKOReply", probe.count)
        h.register_hook("AISelectSendOut.commit", probe.scan)
        for _ in range(60):
            if probe.lowest is not None:
                break
            h.tap("a", 6)
            h.tick(20)
        self.check(probe, f"faint {'CGB' if self.CGB else 'DMG'}")


if __name__ == "__main__":
    unittest.main()
