"""RollSpreadClass (home/rarity_class.asm) against the balance model.

Every random rarity-class roll goes through this one HOME routine: the Wild
Area wild and boss rolls (PCRollMonClass), the reward-mon roll
(Random_Pokemon_Selection) and the item roll (Random_Item_Selection). It
replaced "add the bonus to the roll and saturate", which gave every point of
bonus to the TOP class and left the middle classes their base width.

The routine is pure (a, b, hl in; c out), so it is driven directly: map the
table's bank, set the registers, jump in, and read the class at `.done`. Each
table is checked for EVERY roll at a spread of bonuses, against
tools/balance/model.py's spread_class, plus the two properties the design
rests on: zero bonus reproduces the old odds, the bonus is split evenly, and
what is left once pokeball is empty drains greatball next (the cascade).
"""

from __future__ import annotations

import io
from pathlib import Path
import sys
import unittest

from harness import RedRogueHarness

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
sys.path.insert(0, str(REPO_ROOT / "tools" / "balance"))
from model import spread_class  # noqa: E402
from source_constants import parse_rgbds_constants  # noqa: E402

CONSTANTS = {
    **parse_rgbds_constants(REPO_ROOT / "constants" / "rogue_species_groups.asm"),
    **parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm"),
}

# 0 = the pre-spread odds; 52 empties the item pokeball band exactly and is a
# partial drain elsewhere; 166 (the round-9 boss bonus) cascades into greatball
# for items and rewards; 255 cascades for every table. Every probe reloads a
# state (~8 ms), so the list is kept short.
BONUSES = (0, 52, 166, 255)


class RollSpreadClassTest(unittest.TestCase):
    harness: RedRogueHarness

    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        cls.harness.tick(240)
        cls.harness.park_before_hijack()
        cls.baseline = io.BytesIO()
        cls.harness.save_state(cls.baseline)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.harness.close()

    def table(self, label: str) -> tuple[int, int, list[int]]:
        """(bank, address, cumulative widths) of a RollSpreadClass table."""
        bank, address = self.harness.symbols.get(label)
        self.harness.pyboy.memory[0x2000] = bank
        raw = [self.harness.pyboy.memory[address + i] for i in range(6)]
        widths = raw[1:raw.index(0, 1)]
        self.assertEqual(raw[0], len(widths), f"{label}: share count != classes above pokeball")
        return bank, address, widths

    def roll(self, bank: int, address: int, roll: int, bonus: int) -> int:
        h = self.harness
        self.baseline.seek(0)
        h.load_state(self.baseline)
        done_bank, done_address = h.symbols.get("RollSpreadClass.done")
        _, entry = h.symbols.get("RollSpreadClass")
        result: dict[str, int] = {}

        def capture(_context) -> None:
            result["class"] = h.pyboy.register_file.C

        h.pyboy.hook_register(done_bank, done_address, capture, None)
        try:
            sp = (h.pyboy.register_file.SP - 2) & 0xFFFF
            h.pyboy.memory[sp] = 0xFF  # return sentinel $3FFF, never reached
            h.pyboy.memory[sp + 1] = 0x3F
            h.pyboy.register_file.SP = sp
            h.pyboy.memory[0x2000] = bank
            h.write8("hLoadedROMBank", bank)
            h.pyboy.register_file.A = roll
            h.pyboy.register_file.B = bonus
            h.pyboy.register_file.HL = address
            h.pyboy.register_file.PC = entry
            h.wait_until(lambda: "class" in result, "RollSpreadClass.done", limit=60)
        finally:
            h.pyboy.hook_deregister(done_bank, done_address)
        return result["class"]

    def check_table(self, label: str, expected_widths: list[int]) -> None:
        bank, address, widths = self.table(label)
        self.assertEqual(widths, expected_widths, label)
        for bonus in BONUSES:
            counts = [0] * (len(widths) + 1)
            for roll in range(256):
                got = self.roll(bank, address, roll, bonus)
                want = spread_class(roll, bonus, widths)
                if got != want:
                    self.fail(f"{label} roll={roll} bonus={bonus}: ROM class {got}, model {want}")
                counts[got - 1] += 1
            base = [widths[0]] + [b - a for a, b in zip(widths, widths[1:])] + [256 - widths[-1]]
            freed = min(bonus, widths[0])
            with self.subTest(table=label, bonus=bonus):
                self.assertEqual(counts[0], widths[0] - freed, "pokeball band shrinks by the bonus")
                self.assertGreaterEqual(counts[-1], base[-1], "the top class never shrinks")
                if bonus <= widths[0]:
                    gains = [c - b for c, b in zip(counts[1:], base[1:])]
                    self.assertEqual(sum(gains), freed, "every freed roll lands in a higher class")
                    self.assertLessEqual(max(gains) - min(gains), len(gains) - 1,
                                         f"freed width split evenly, got gains {gains}")
                else:
                    # past an empty pokeball band the rest drains greatball
                    great = counts[1] - base[1] - freed // (len(base) - 1)
                    self.assertEqual(-great, min(bonus - freed, base[1] + freed // (len(base) - 1)),
                                     "leftover bonus drains the greatball band next")

    def test_wild_area_table(self) -> None:
        self.check_table("PCWildClassWidths", [205, 243, 253])

    def test_reward_table(self) -> None:
        self.check_table("RewardClassWidths", [128, 230])

    def test_item_table(self) -> None:
        self.check_table("ItemClassWidths", [52, 129, 205])

    def test_stage_reward_table(self) -> None:
        self.check_table("StageRewardClassWidths", [128, 230, 255])

    def test_reward_down_table(self) -> None:
        # challenge 4's reverse cascade: the reward bands listed top class first
        self.check_table("RewardClassWidthsDown", [26, 128])

    def ladder(self, class_arg: int, prize: bool, challenge: bool = False) -> dict[str, object]:
        """Enter Random_Pokemon_Selection with c = class_arg and run to
        RogueSelectFromTier: the table and bonus RollSpreadClass was handed,
        the class it returned, and the tier id that reached the species pick."""
        h = self.harness
        self.baseline.seek(0)
        h.load_state(self.baseline)
        bank, entry = h.symbols.get("Random_Pokemon_Selection")
        spread_bank, spread = h.symbols.get("RollSpreadClass")
        done_bank, done = h.symbols.get("RollSpreadClass.done")
        tier_bank, tier_entry = h.symbols.get("RogueSelectFromTier")
        tables = {h.symbols.get(name)[1]: name for name in
                  ("RewardClassWidths", "StageRewardClassWidths", "RewardClassWidthsDown")}
        result: dict[str, object] = {}
        regs = h.pyboy.register_file

        def at_spread(_context) -> None:
            result.setdefault("table", tables.get(regs.HL, hex(regs.HL)))
            result.setdefault("bonus", regs.B)

        def at_done(_context) -> None:
            result.setdefault("class", regs.C)

        def at_tier(_context) -> None:
            result.setdefault("tier", regs.B)

        prizes = h.read8("wWitchPrizesEarned")
        bit = 1 << (CONSTANTS["PRIZE_RARITY_POKEMON"] - 1)
        h.write8("wWitchPrizesEarned", (prizes | bit) if prize else (prizes & ~bit & 0xFF))
        flags = h.read8("wRogueFlagsBitfield")
        accepted = 1 << CONSTANTS["BIT_WITCH_ACCEPTED"]
        h.write8("wRogueFlagsBitfield", (flags | accepted) if challenge else (flags & ~accepted & 0xFF))
        h.write8("wWitchChallenge", CONSTANTS["CHALLENGE_REDUCED_RARITY"] if challenge else 0)
        hooks = ((spread_bank, spread, at_spread), (done_bank, done, at_done),
                 (tier_bank, tier_entry, at_tier))
        for hook_bank, address, callback in hooks:
            h.pyboy.hook_register(hook_bank, address, callback, None)
        try:
            sp = (regs.SP - 2) & 0xFFFF
            h.pyboy.memory[sp] = 0xFF
            h.pyboy.memory[sp + 1] = 0x3F
            regs.SP = sp
            h.pyboy.memory[0x2000] = bank
            h.write8("hLoadedROMBank", bank)
            regs.C = class_arg
            regs.PC = entry
            h.wait_until(lambda: "tier" in result, "RogueSelectFromTier entry", limit=120)
        finally:
            for hook_bank, address, _ in hooks:
                h.pyboy.hook_deregister(hook_bank, address)
        # the tier id must follow from the class: mirrored on the reverse ladder
        if result["table"] == "RewardClassWidthsDown":
            self.assertEqual(result["tier"], 3 - result["class"], f"reverse ladder tier {result}")
        else:
            self.assertEqual(result["tier"], result["class"] - 1, f"tier {result}")
        return result

    def test_stage_reward_ladder_gate(self) -> None:
        """Masterball opens only for the stage-reward class AND a live bonus."""
        stage = CONSTANTS["REWARD_CLASS_STAGE"]
        got = self.ladder(stage, prize=True)
        self.assertGreater(got["bonus"], 0)
        self.assertEqual(got["table"], "StageRewardClassWidths", "stage reward with a bonus")
        got = self.ladder(0, prize=True)
        self.assertEqual(got["table"], "RewardClassWidths", "class 0 (bridge gift) never opens masterball")
        got = self.ladder(stage, prize=False)
        want = "StageRewardClassWidths" if got["bonus"] else "RewardClassWidths"
        self.assertEqual(got["table"], want, f"stage reward {got}: zero bonus keeps the 3-class table")

    def test_reduced_rarity_challenge_is_a_luck_penalty(self) -> None:
        """Challenge 4 subtracts its penalty from the stacked bonus; a shortfall
        rolls the reverse cascade, and with the +51 prize it nets to base odds."""
        stage = CONSTANTS["REWARD_CLASS_STAGE"]
        penalty = CONSTANTS["CHALLENGE_REDUCED_RARITY_PENALTY"]
        self.assertEqual(penalty, 51, "mirrors PRIZE_RARITY_POKEMON's +51")
        base = self.ladder(stage, prize=False)["bonus"]
        got = self.ladder(stage, prize=False, challenge=True)
        if base < penalty:
            self.assertEqual(got["table"], "RewardClassWidthsDown", got)
            self.assertEqual(got["bonus"], penalty - base, got)
        with_prize = self.ladder(stage, prize=True)["bonus"]
        got = self.ladder(stage, prize=True, challenge=True)
        net = with_prize - penalty
        self.assertEqual(got["table"], "StageRewardClassWidths" if net > 0 else "RewardClassWidths", got)
        if net > 0:
            self.assertEqual(got["bonus"], net, got)


if __name__ == "__main__":
    unittest.main()
