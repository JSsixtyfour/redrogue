"""Endless mode checkpoint E, step 2: the two Uber helpers
(ENDLESS_MODE_CHECKPOINT_E.md section 7).

EndlessUberStep ($3C) is the extra Master | Uber cascade step: never at depth
0, and the bonus it hands RollSpreadClass is ENDLESS_UBER_STEP x the Endless
rounds so far. RogueDrawUber ($38) draws uniformly over the active groups'
Uber tiers, optionally only species the player does not own. The table itself
is checked roll-by-roll against the balance model in test_rarity_spread_class.

Every ROM test boots the lobby and runs inside isolated_routine_calls, which
restores the whole machine on exit.
"""
import unittest

from routine_session import isolated_routine_calls
from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

SPAN = 72              # ENDLESS_CIRCUIT_SPAN
ROUND_BATTLES = 8
LAST_ROUND = 8
CARRY = 0x10


class EndlessUberTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        h = self.harness
        h.boot_to_lobby()
        self.session = isolated_routine_calls(h)
        self.session.__enter__()
        self.events = parse_rgbds_constants(REPO_ROOT / "constants/event_constants.asm")
        self.species = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
        self.rounds = parse_rgbds_constants(REPO_ROOT / "constants/round_constants.asm")

    def tearDown(self) -> None:
        try:
            self.session.__exit__(None, None, None)
        finally:
            self.harness.close()

    # -- helpers ------------------------------------------------------

    def carry(self) -> bool:
        return bool(self.harness.last_call_registers["F"] & CARRY)

    def at_round(self, depth: int, round_: int) -> None:
        """wEndlessDepth/wBattleCount so GetRunProgress lands in round_."""
        count = round_ * ROUND_BATTLES + 1 - depth * SPAN
        self.assertGreaterEqual(count, 1)
        self.harness.write8("wEndlessDepth", depth)
        self.harness.write8("wBattleCount", count)

    def set_species(self, label_count: str, label_list: str, names) -> None:
        h = self.harness
        ids = [self.species[n] for n in names]
        h.write8(label_count, len(ids))
        base = h.address(label_list)
        for i, v in enumerate(ids + [0xFF]):
            h.pyboy.memory[base + i] = v

    def own(self, party=(), box=()) -> None:
        self.set_species("wPartyCount", "wPartySpecies", list(party) or ["RATTATA"])
        self.set_species("wBoxCount", "wBoxSpecies", box)

    def groups(self, johto: bool) -> None:
        h = self.harness
        if johto:
            h.set_event(self.events["EVENT_JOHTO_ACTIVATED"])
        h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [0b011 if johto else 0b001], bank=1)

    def step(self) -> tuple[bool, int | None, int | None]:
        """One EndlessUberStep: (carry, bonus handed to RollSpreadClass, class)."""
        h = self.harness
        seen: dict[str, int] = {}

        def at_spread(*_args) -> None:
            seen["bonus"] = h.pyboy.register_file.B

        def at_done(*_args) -> None:
            seen["class"] = h.pyboy.register_file.C

        h.register_hook("RollSpreadClass", at_spread)
        h.register_hook("RollSpreadClass.done", at_done)
        try:
            h.call_routine("EndlessUberStep")
        finally:
            h.unregister_hook("RollSpreadClass", at_spread)
            h.unregister_hook("RollSpreadClass.done", at_done)
        return self.carry(), seen.get("bonus"), seen.get("class")

    def draw(self, unowned_only: bool) -> int | None:
        h = self.harness
        h.pyboy.register_file.E = 1 if unowned_only else 0
        h.call_routine("RogueDrawUber")
        if not self.carry():
            return None
        self.assertEqual(h.last_call_registers["E"], 0, "Uber entries are form 0")
        return h.last_call_registers["D"]

    def ids(self, *names) -> set[int]:
        return {self.species[n] for n in names}

    # -- EndlessUberStep ----------------------------------------------

    def test_constants_are_the_approved_rate(self) -> None:
        self.assertEqual(self.rounds["ENDLESS_UBER_BASE"], 1)
        self.assertEqual(self.rounds["ENDLESS_UBER_STEP"], 4)   # user answer Q1

    def test_depth_0_never_rolls(self) -> None:
        for round_ in (0, 4, 8):
            self.at_round(0, round_)
            for _ in range(5):
                carry, bonus, _ = self.step()
                self.assertFalse(carry, round_)
                self.assertIsNone(bonus, "depth 0 must not reach RollSpreadClass")

    def test_bonus_is_step_times_endless_rounds(self) -> None:
        step = self.rounds["ENDLESS_UBER_STEP"]
        for depth, round_ in ((1, 9), (1, 16), (2, 20), (3, 31)):
            self.at_round(depth, round_)
            carry, bonus, cls = self.step()
            self.assertEqual(bonus, min(255, step * (round_ - LAST_ROUND)), (depth, round_))
            self.assertIn(cls, (1, 2))
            self.assertEqual(carry, cls == 2, "carry means Uber")

    def test_saturated_progress_still_rolls(self) -> None:
        h = self.harness
        h.write8("wEndlessDepth", 0xFF)              # progress saturates at 255
        h.write8("wBattleCount", 1)
        _, bonus, _ = self.step()
        self.assertEqual(bonus, self.rounds["ENDLESS_UBER_STEP"] * (255 // ROUND_BATTLES - LAST_ROUND))

    # -- RogueDrawUber ------------------------------------------------

    def test_kanto_only_draws_mew_and_mewtwo(self) -> None:
        self.groups(johto=False)
        self.own(party=["RATTATA"])
        seen = {self.draw(False) for _ in range(30)}
        self.assertEqual(seen, self.ids("MEW", "MEWTWO"))

    def test_johto_adds_its_three(self) -> None:
        self.groups(johto=True)
        self.own(party=["RATTATA"])
        seen = {self.draw(False) for _ in range(60)}
        self.assertEqual(seen, self.ids("MEW", "MEWTWO", "LUGIA", "HO_OH", "CELEBI"))

    def test_unowned_filter_skips_party_and_box(self) -> None:
        self.groups(johto=True)
        self.own(party=["MEW", "PIKACHU"], box=["LUGIA"])
        seen = {self.draw(True) for _ in range(50)}
        self.assertEqual(seen, self.ids("MEWTWO", "HO_OH", "CELEBI"))

    # -- bosses (step 3) -----------------------------------------------

    def boss_class(self, force=()) -> tuple[int, list[int]]:
        """One PCRollBossClass: (class in c, bonus seen at each RollSpreadClass).
        force[i], when given, overrides the class the i-th RollSpreadClass returns."""
        h = self.harness
        bonuses: list[int] = []
        done = [0]

        def at_spread(*_args) -> None:
            bonuses.append(h.pyboy.register_file.B)

        def at_done(*_args) -> None:
            i = done[0]
            done[0] += 1
            if i < len(force):
                h.pyboy.register_file.C = force[i]

        h.register_hook("RollSpreadClass", at_spread)
        h.register_hook("RollSpreadClass.done", at_done)
        try:
            h.call_routine("PCRollBossClass")
        finally:
            h.unregister_hook("RollSpreadClass", at_spread)
            h.unregister_hook("RollSpreadClass.done", at_done)
        return h.last_call_registers["C"], bonuses

    def test_boss_roll_at_depth_0_is_the_old_roll(self) -> None:
        bump = parse_rgbds_constants(REPO_ROOT / "constants/balance_constants.asm")["WILD_BOSS_RARITY_BUMP"]
        h = self.harness
        h.write8("wEndlessDepth", 0)
        for count in (1, 40, 76, 120):               # 120: past the authored rows, still clamped
            h.write8("wBattleCount", count)
            cls, bonuses = self.boss_class(force=(4,))
            self.assertEqual(bonuses, [min(255, min(count // 8, LAST_ROUND) * 8 + bump)], count)
            self.assertEqual(cls, 4, "depth 0 never takes the Uber step")

    def test_endless_boss_bonus_is_unclamped(self) -> None:
        bump = parse_rgbds_constants(REPO_ROOT / "constants/balance_constants.asm")["WILD_BOSS_RARITY_BUMP"]
        for round_ in (9, 12, 20):
            self.at_round(1, round_)
            _, bonuses = self.boss_class(force=(1,))
            self.assertEqual(bonuses, [min(255, round_ * 8 + bump)], round_)

    def test_only_master_takes_the_uber_step(self) -> None:
        self.at_round(1, 16)
        for cls in (1, 2, 3):
            got, bonuses = self.boss_class(force=(cls,))
            self.assertEqual((got, len(bonuses)), (cls, 1), cls)
        self.assertEqual(self.boss_class(force=(4, 1))[0], 4, "Master stays Master")
        got, bonuses = self.boss_class(force=(4, 2))
        self.assertEqual(len(bonuses), 2)
        self.assertEqual(got, self.rounds_species_groups()["BOSS_CLASS_UBER"])

    def rounds_species_groups(self) -> dict:
        return parse_rgbds_constants(REPO_ROOT / "constants/rogue_species_groups.asm")

    def boss_species(self, cls: int) -> tuple[int, int]:
        h = self.harness
        h.write8("wCurEnemyLevel", 50)
        h.pyboy.register_file.E = cls
        h.call_routine("Random_Boss_Selection_Far")
        return h.last_call_registers["D"], h.last_call_registers["E"]

    def tier_of(self, species: int) -> int:
        h = self.harness
        h.pyboy.register_file.E = species
        h.call_routine("RogueGetSpeciesTierFar")
        return h.last_call_registers["E"]

    def test_uber_boss_is_unowned(self) -> None:
        uber = self.rounds_species_groups()["BOSS_CLASS_UBER"]
        self.groups(johto=True)
        self.own(party=["MEWTWO"], box=["LUGIA", "CELEBI"])
        seen = {self.boss_species(uber) for _ in range(30)}
        self.assertEqual(seen, {(s, 0) for s in self.ids("MEW", "HO_OH")})

    def test_uber_boss_falls_back_to_master_when_all_owned(self) -> None:
        g = self.rounds_species_groups()
        self.groups(johto=False)
        self.own(party=["MEW"], box=["MEWTWO"])
        for _ in range(10):
            species, _ = self.boss_species(g["BOSS_CLASS_UBER"])
            self.assertNotIn(species, self.ids("MEW", "MEWTWO"))
            self.assertEqual(self.tier_of(species), g["RARITY_TIER_MASTERBALL"], hex(species))

    def test_everything_owned_returns_no_carry(self) -> None:
        self.groups(johto=False)
        self.own(party=["MEW"], box=["MEWTWO"])
        self.assertIsNone(self.draw(True))
        self.assertIn(self.draw(False), self.ids("MEW", "MEWTWO"), "trainers ignore ownership")


if __name__ == "__main__":
    unittest.main()
