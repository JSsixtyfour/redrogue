"""AI speed lever 1 (2026-11-20): AIGetCritThreshold's one-entry base-Speed cache.

engine/battle/ai/ai_crit.asm. The header load inside CalcCritRate is ~3.6k of a
~4.9k cycle lookup and yields only the attacker's base Speed, which depends on
the species and MON_CATCH_RATE's form bits alone. wAICritCache* keeps the last
(species, form) -> base Speed; a hit enters CalcCritRateWithBaseSpeed and skips
PublishFormContext + GetMonHeader. AIClearDecisionCaches empties it.

With an ordinary move on the ENEMY side the threshold is exactly base Speed / 2
(the Bridge adjustments apply to the player only), so these boards read the
cached speed straight back out of the answer.
"""

from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

MOVE_LENGTH = 6
CATCH_RATE = 7  # MON_CATCH_RATE in the battle struct
FORM_SHIFT = 5  # FORM_MASK is MON_CATCH_RATE bits 5-6
ESPEON, UMBREON = 1, 2  # JOLTEON's forms (func_forms.asm's Eevee-stone table)


class AICritCacheTest(unittest.TestCase):
    def setUp(self) -> None:
        self.species = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")
        self.moves = parse_rgbds_constants(REPO_ROOT / "constants" / "move_constants.asm")
        trainers = parse_trainer_constants(REPO_ROOT / "constants" / "trainer_constants.asm")
        self.rom = (REPO_ROOT / "pokeblue_debug.gbc").read_bytes()
        self.h = h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        mon = lambda s, m: {"species": self.species[s], "level": 50,  # noqa: E731
                            "moves": [self.moves[x] for x in m]}
        h.inject_fight2_spec([mon("PERSIAN", ["TACKLE"])], [mon("JOLTEON", ["TACKLE"])],
                             trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)
        h.boot_fight2(seed=1)
        for side in ("Player", "Enemy"):
            self.load_move(side, "TACKLE")
        h.write8("wAICritCacheSpecies", 0)  # start empty, whatever the boot's AI left

    def load_move(self, side: str, move: str) -> None:
        """The move's 6-byte record from the ROM's Moves table into w{side}Move*."""
        bank, address = self.h.symbols.get("Moves")
        start = bank * 0x4000 + address - 0x4000 + (self.moves[move] - 1) * MOVE_LENGTH
        for offset, value in enumerate(self.rom[start:start + MOVE_LENGTH]):
            self.h.write8(f"w{side}MoveNum", value, offset=offset)

    def set_form(self, struct: str, form: int) -> None:
        rate = self.h.read8(struct, CATCH_RATE) & ~(3 << FORM_SHIFT)
        self.h.write8(struct, rate | (form << FORM_SHIFT), offset=CATCH_RATE)

    def lookup(self, side: int = 1) -> tuple[int, bool, int | None]:
        """(threshold, whether the header was loaded, the header's base Speed when it was)."""
        h = self.h
        bank, address = h.symbols.get("AIGetCritThreshold")
        seen = {"header": 0}

        def inject(_ctx) -> None:
            h.pyboy.register_file.A = side  # call_routine enters through Bankswitch, which clobbers a

        def header(_ctx) -> None:
            seen["header"] += 1

        def answer(_ctx) -> None:
            seen["b"] = h.pyboy.register_file.B
            seen["speed"] = h.read8("wMonHBaseSpeed")

        h.pyboy.hook_register(bank, address, inject, None)
        h.register_hook("GetMonHeader", header)
        h.register_hook("AIGetCritThreshold.gotRate", answer)
        try:
            h.call_routine("AIGetCritThreshold", limit=4000)
        finally:
            h.pyboy.hook_deregister(bank, address)
            h.unregister_hook("GetMonHeader", header)
            h.unregister_hook("AIGetCritThreshold.gotRate", answer)
        loaded = seen["header"] > 0
        return seen["b"], loaded, seen["speed"] if loaded else None

    def cache(self) -> list[int]:
        return list(self.h.read_bytes("wAICritCacheSpecies", 3))

    def test_a_repeat_lookup_skips_the_header_and_gives_the_same_answer(self) -> None:
        first, loaded, speed = self.lookup()
        self.assertTrue(loaded, "an empty cache must take the full lookup")
        self.assertEqual(first, speed // 2, "an ordinary enemy move: base Speed / 2")
        self.assertEqual(self.cache(), [self.species["JOLTEON"], 0, speed])
        again, loaded, _ = self.lookup()
        self.assertFalse(loaded, "the same species and form must hit")
        self.assertEqual(again, first)

    def test_the_form_bits_are_part_of_the_key(self) -> None:
        # Jolteon 130, Espeon 110, Umbreon 65: a key without the form would answer
        # every form with whichever row it saw first.
        plain, _, plain_speed = self.lookup()
        answers = {0: plain}
        for form in (ESPEON, UMBREON, 0):
            self.set_form("wEnemyMon", form)
            got, loaded, speed = self.lookup()
            self.assertTrue(loaded, f"form {form} after another form must miss")
            self.assertEqual(got, speed // 2, form)
            answers.setdefault(form, got)
            self.assertEqual(got, answers[form], form)
        self.assertEqual(len(set(answers.values())), 3, answers)
        self.assertEqual(answers[0], plain_speed // 2)

    def test_another_species_or_side_misses(self) -> None:
        jolteon, _, _ = self.lookup()
        # A staged reserve: the same struct, a different species.
        self.h.write8("wEnemyMon", self.species["PERSIAN"])
        persian, loaded, speed = self.lookup()
        self.assertTrue(loaded)
        self.assertEqual(persian, speed // 2)
        self.assertNotEqual(persian, jolteon)
        # The player's side reads wBattleMon (Persian) through the same one entry,
        # which the enemy's Jolteon holds again: a miss.
        self.h.write8("wEnemyMon", self.species["JOLTEON"])
        self.lookup()
        _, loaded, _ = self.lookup(side=0)
        self.assertTrue(loaded, "the player's Persian after the enemy's Jolteon must miss")

    def test_each_decision_starts_with_an_empty_cache(self) -> None:
        self.lookup()
        self.assertNotEqual(self.cache()[0], 0)
        self.h.call_routine("AIClearDecisionCaches", limit=4000)
        self.assertEqual(self.cache()[0], 0)
        _, loaded, _ = self.lookup()
        self.assertTrue(loaded, "after a clear the first lookup must be the full one")


if __name__ == "__main__":
    unittest.main()
