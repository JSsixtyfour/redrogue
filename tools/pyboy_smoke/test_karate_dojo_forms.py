"""Karate Dojo special forms (KARATE_MINIBOSS_PLAN.md steps 1, 3, 4).

NO GUARD MACHOP keeps its caps through evolution, LIMBER HITMONLEE blocks only
paralysis, and MYSTIC HITMONCHAN's stored Attack and Special come out of the
real recalc path swapped. Each test boots fresh: call_routine is only good for
about ten invocations per boot (project_call_routine_harness_limits).
"""

from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

MON_TYPE2 = 6
MON_CATCH_RATE = 7
MON_LEVEL = 0x21
MON_ATK = 0x24
MON_SPC = 0x2A
BIT_TYPE_VARIANT = 1 << 2
BIT_SPECIAL_FORM = 1 << 3
BIT_SHINY = 1 << 4
BRIDGE_CALC_SWAP = 1 << 0
SF_NEVER_MISS = 1 << 3
SF_ALWAYS_HIT = 1 << 4
BRIDGE_STATUS_CHECK_OTHER = 1
BRIDGE_STATUS_CHECK_PARALYSIS = 2


class KarateDojoFormsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.species = parse_rgbds_constants(
            REPO_ROOT / "constants" / "pokemon_constants.asm"
        )
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.harness.boot_to_lobby()
        start = self.harness.address("wBridgeSelectedEffects")
        self.harness.pyboy.memory[start : start + 4] = [0, 0, 0, 0]

    def tearDown(self) -> None:
        self.harness.close()

    def word(self, address: int) -> int:
        memory = self.harness.pyboy.memory
        return (memory[address] << 8) | memory[address + 1]

    def recalc_party_mon1(self, species: str, catch_rate: int) -> tuple[int, int]:
        h = self.harness
        base = h.address("wPartyMon1")
        h.pyboy.memory[base] = self.species[species]
        h.pyboy.memory[base + MON_CATCH_RATE] = catch_rate
        h.pyboy.memory[base + MON_LEVEL] = 50
        h.pyboy.register_file.D = base >> 8
        h.pyboy.register_file.E = base & 0xFF
        h.call_routine("BridgeRecalcStatsFar")
        return self.word(base + MON_ATK), self.word(base + MON_SPC)

    def test_mystic_hitmonchan_swaps_attack_and_special(self) -> None:
        plain = self.recalc_party_mon1("HITMONCHAN", 0)
        mystic = self.recalc_party_mon1("HITMONCHAN", BIT_SPECIAL_FORM)
        self.assertNotEqual(plain[0], plain[1])  # base 105 ATK vs 35 SPC
        self.assertEqual(mystic, (plain[1], plain[0]))
        # The flag byte is transient: a later plain recalc is unswapped again.
        self.assertEqual(self.recalc_party_mon1("HITMONCHAN", 0), plain)

    def test_mystic_bit_does_nothing_for_other_species(self) -> None:
        plain = self.recalc_party_mon1("HITMONLEE", 0)
        self.assertEqual(self.recalc_party_mon1("HITMONLEE", BIT_SPECIAL_FORM), plain)

    def paralysis_block(
        self, species: str, catch_rate: int, kind: int, defender: str = "player"
    ) -> str:
        h = self.harness
        # The defending mon is the one Limber protects: the enemy attacks the
        # player on hWhoseTurn 1, the player attacks the enemy on 0.
        target = "wBattleMon" if defender == "player" else "wEnemyMon"
        battle_mon = h.address(target)
        h.pyboy.memory[battle_mon] = self.species[species]
        h.pyboy.memory[battle_mon + MON_CATCH_RATE] = catch_rate
        h.write8("wPlayerMonNumber", 0)
        h.write8("hWhoseTurn", 1 if defender == "player" else 0)
        h.write8("wLinkState", 0)
        h.pyboy.register_file.E = kind
        captured: list[str] = []
        hooks: list[tuple[int, int]] = []
        for outcome in ("blocked", "allowed"):
            bank, address = h.symbols.get(f"BridgePlayerTargetBlocksStatus.{outcome}")
            hooks.append((bank, address))

            def capture(_context, value=outcome) -> None:
                captured.append(value)

            h.pyboy.hook_register(bank, address, capture, None)
        try:
            h.call_routine("BridgePlayerTargetBlocksStatus", limit=200)
        finally:
            for bank, address in hooks:
                h.pyboy.hook_deregister(bank, address)
        self.assertTrue(captured)
        return captured[0]

    def test_limber_hitmonlee_blocks_only_paralysis(self) -> None:
        paralysis = BRIDGE_STATUS_CHECK_PARALYSIS
        self.assertEqual(
            self.paralysis_block("HITMONLEE", BIT_SPECIAL_FORM, paralysis), "blocked"
        )
        self.assertEqual(self.paralysis_block("HITMONLEE", 0, paralysis), "allowed")
        self.assertEqual(
            self.paralysis_block(
                "HITMONLEE", BIT_SPECIAL_FORM, BRIDGE_STATUS_CHECK_OTHER
            ),
            "allowed",
        )
        self.assertEqual(
            self.paralysis_block("HITMONCHAN", BIT_SPECIAL_FORM, paralysis), "allowed"
        )

    def test_limber_protects_an_enemy_hitmonlee(self) -> None:
        # A stolen special form fights for the enemy, so Limber works there too.
        paralysis = BRIDGE_STATUS_CHECK_PARALYSIS
        self.assertEqual(
            self.paralysis_block("HITMONLEE", BIT_SPECIAL_FORM, paralysis, "enemy"),
            "blocked",
        )
        self.assertEqual(
            self.paralysis_block("HITMONLEE", 0, paralysis, "enemy"), "allowed"
        )
        self.assertEqual(
            self.paralysis_block(
                "HITMONLEE", BIT_SPECIAL_FORM, BRIDGE_STATUS_CHECK_OTHER, "enemy"
            ),
            "allowed",
        )

    def enemy_catch_rate_byte(self) -> int:
        h = self.harness
        captured: list[int] = []
        bank, address = h.symbols.get("GetEnemyCatchRateByte.done")

        def capture(_context) -> None:
            captured.append(h.pyboy.register_file.E)

        h.pyboy.hook_register(bank, address, capture, None)
        try:
            h.call_routine("GetEnemyCatchRateByte", limit=200)
        finally:
            h.pyboy.hook_deregister(bank, address)
        self.assertEqual(len(captured), 1)
        return captured[0]

    def test_trainer_mon_keeps_its_whole_catch_rate_byte(self) -> None:
        h = self.harness
        types = parse_rgbds_constants(REPO_ROOT / "constants" / "type_constants.asm")
        slot = h.address("wEnemyMon1")
        h.write8("hIsInBattle", 2)
        h.write8("hWhichPokemon", 0)
        # special form + shiny + form index 2: carried verbatim, types untouched
        h.write8("wEnemyMonType2", types["FIGHTING"])
        h.pyboy.memory[slot + MON_CATCH_RATE] = BIT_SPECIAL_FORM | BIT_SHINY | 0x40
        self.assertEqual(
            self.enemy_catch_rate_byte(), BIT_SPECIAL_FORM | BIT_SHINY | 0x40
        )
        self.assertEqual(h.read8("wEnemyMonType2"), types["FIGHTING"])
        # a type variant's own stored type 2 replaces the header's
        h.pyboy.memory[slot + MON_TYPE2] = types["WATER"]
        h.pyboy.memory[slot + MON_CATCH_RATE] = BIT_TYPE_VARIANT
        self.assertEqual(self.enemy_catch_rate_byte(), BIT_TYPE_VARIANT)
        self.assertEqual(h.read8("wEnemyMonType2"), types["WATER"])
        # a wild mon has no struct: the form alone, from wSpawnForm
        h.write8("hIsInBattle", 1)
        h.write8("wSpawnForm", 2)
        self.assertEqual(self.enemy_catch_rate_byte(), 0x40)

    def test_enemy_mystic_hitmonchan_arms_the_stat_swap(self) -> None:
        h = self.harness
        slot = h.address("wEnemyMon1")
        h.write8("hIsInBattle", 2)
        h.write8("hWhichPokemon", 0)
        h.write8("wEnemyMonSpecies2", self.species["HITMONCHAN"])
        h.pyboy.memory[slot] = self.species["HITMONCHAN"]
        for catch_rate, expected in ((0, 0), (BIT_SPECIAL_FORM, BRIDGE_CALC_SWAP)):
            h.write8("wBridgeCalcEffectFlags", 0)
            h.pyboy.memory[slot + MON_CATCH_RATE] = catch_rate
            h.call_routine("PublishEnemyFormAndStatContext", limit=400)
            self.assertEqual(h.read8("wBridgeCalcEffectFlags"), expected)
        h.write8("wBridgeCalcEffectFlags", 0)

    def test_no_guard_survives_evolution(self) -> None:
        h = self.harness
        base = h.address("wPartyMon1")
        caps: list[int] = []
        bank, address = h.symbols.get("SpecialFormCapsLookup.found")

        def capture(_context) -> None:
            caps.append(h.pyboy.register_file.A)

        h.pyboy.hook_register(bank, address, capture, None)
        try:
            for species in ("MACHOP", "MACHOKE", "MACHAMP"):
                h.pyboy.memory[base] = self.species[species]
                h.pyboy.memory[base + MON_CATCH_RATE] = BIT_SPECIAL_FORM
                h.pyboy.register_file.D = base >> 8
                h.pyboy.register_file.E = base & 0xFF
                h.call_routine("GetSpecialFormCaps", limit=200)
        finally:
            h.pyboy.hook_deregister(bank, address)
        self.assertEqual(caps, [SF_NEVER_MISS | SF_ALWAYS_HIT] * 3)


if __name__ == "__main__":
    unittest.main()
