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

    def test_cemetery_uber_boss_keeps_ghost_move_and_flag(self) -> None:
        """A forced Uber through the real PCemRollBoss: species, ghost move and
        form bits land in SRAM, and PCemApplyGhostBoss flags it like any boss."""
        h = self.harness
        moves = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        types = parse_rgbds_constants(REPO_ROOT / "constants/type_constants.asm")
        self.groups(johto=True)
        self.own(party=["RATTATA"])
        self.at_round(1, 16)
        forced = iter((4, 2))                         # Master, then Uber

        def at_done(*_args) -> None:
            value = next(forced, None)
            if value is not None:
                h.pyboy.register_file.C = value

        h.register_hook("RollSpreadClass.done", at_done)
        try:
            h.call_routine("PCemRollBoss")
        finally:
            h.unregister_hook("RollSpreadClass.done", at_done)
        species, move = h.read_sram_bytes("sProcCemeteryBossSpecies", 2, bank=0)
        ready = h.read_sram_bytes("sProcCemeteryReady", 1, bank=0)[0]
        self.assertIn(species, self.ids("MEW", "MEWTWO", "LUGIA", "HO_OH", "CELEBI"))
        self.assertIn(move, {moves["LICK"], moves["NIGHT_SHADE"], moves["CONFUSE_RAY"]})
        self.assertEqual(ready >> 4 & 3, 0, "Uber form 0 in the form bits")

        enemy = h.address("wEnemyMon")
        h.pyboy.memory[enemy] = species
        catch_rate = h.address("wEnemyMonCatchRate")
        h.pyboy.memory[catch_rate] = 0
        h.pyboy.register_file.D = enemy >> 8
        h.pyboy.register_file.E = enemy & 0xFF
        h.call_routine("PCemApplyGhostBoss")
        self.assertEqual(h.pyboy.memory[catch_rate] & 1, 1, "ghost flag set")
        self.assertEqual(h.read8("wEnemyMonType2"), types["GHOST"])

    # -- roster ace (step 4) -------------------------------------------

    def rand_mon(self, *, group: int, left: int, counts, final: bool, slot: int = 5,
                 force=()) -> tuple[int, int]:
        """One GetRandMon as GetRandRosterLoop calls it: b = class group (4 Poke
        .. 1 Master), d = mons left in it, hl -> its count byte, followed by the
        later groups' counts. Returns (species, RollSpreadClass calls)."""
        h = self.harness
        table = h.address("wBuffer")
        for i, value in enumerate(counts):
            h.pyboy.memory[table + i] = value
        flags = h.read8("wRogueFlagsBitfield")
        h.write8("wRogueFlagsBitfield", flags | 2 if final else flags & ~2)
        h.write8("wEnemyPartyCount", slot)
        calls = [0]
        forced = iter(force)

        def at_done(*_args) -> None:
            calls[0] += 1
            value = next(forced, None)
            if value is not None:
                h.pyboy.register_file.C = value

        here = table + 4 - group                      # the group's own count byte

        def at_entry(*_args) -> None:
            # call_routine enters through the bank trampoline, which owns b and
            # hl, so the roster loop's registers are set at the callee's entry.
            r = h.pyboy.register_file
            r.B = group
            r.D = left
            r.HL = here

        h.register_hook("GetRandMon", at_entry)
        h.register_hook("RollSpreadClass.done", at_done)
        try:
            h.call_routine("GetRandMon")
        finally:
            h.unregister_hook("RollSpreadClass.done", at_done)
            h.unregister_hook("GetRandMon", at_entry)
        return h.read8("wCurPartySpecies"), calls[0]

    UBERS = ("MEW", "MEWTWO", "LUGIA", "HO_OH", "CELEBI")

    def test_final_trainer_master_ace_can_be_uber(self) -> None:
        self.groups(johto=True)
        self.own(party=["MEW", "MEWTWO"])            # owned does not matter for opponents
        self.at_round(1, 16)
        seen = set()
        for _ in range(20):
            species, calls = self.rand_mon(group=1, left=1, counts=(0, 0, 0, 2), final=True, force=(2,))
            self.assertEqual(calls, 1)
            seen.add(species)
        self.assertTrue(seen <= self.ids(*self.UBERS), seen)
        self.assertTrue(seen & self.ids("MEW", "MEWTWO"), "ownership must not filter opponents")

    def test_ace_step_can_leave_master(self) -> None:
        self.groups(johto=True)
        self.at_round(1, 16)
        species, calls = self.rand_mon(group=1, left=1, counts=(0, 0, 0, 2), final=True, force=(1,))
        self.assertEqual(calls, 1)
        self.assertNotIn(species, self.ids(*self.UBERS))

    def test_only_the_final_trainers_last_master_slot_rolls(self) -> None:
        self.groups(johto=True)
        cases = [
            (16, dict(group=1, left=1, counts=(0, 0, 0, 2), final=False)),   # not a final trainer
            (16, dict(group=1, left=2, counts=(0, 0, 0, 2), final=True)),    # not the last Master
            (16, dict(group=2, left=1, counts=(0, 0, 1, 1), final=True)),    # a Master still follows
            # last slot but Ultra: round 9 floors flex slot 0 at Ultra with no coin flip
            (9, dict(group=4, left=1, counts=(1, 0, 0, 0), final=True, slot=0)),
        ]
        for round_, case in cases:
            self.at_round(1, round_)
            for _ in range(5):
                species, calls = self.rand_mon(**case, force=(2,))
                self.assertEqual(calls, 0, case)
                self.assertNotIn(species, self.ids(*self.UBERS), case)

    def test_last_slot_floored_to_master_is_the_ace(self) -> None:
        # an Ultra group ending the team, raised to Master by D's slot floor
        self.groups(johto=True)
        self.at_round(1, 16)
        species, calls = self.rand_mon(group=2, left=1, counts=(0, 0, 1, 0), final=True, slot=5, force=(2,))
        self.assertEqual(calls, 1)
        self.assertIn(species, self.ids(*self.UBERS))

    def test_roster_ace_untouched_at_depth_0(self) -> None:
        self.groups(johto=True)
        self.harness.write8("wEndlessDepth", 0)
        self.harness.write8("wBattleCount", 60)
        for _ in range(5):
            species, calls = self.rand_mon(group=1, left=1, counts=(0, 0, 0, 2), final=True, force=(2,))
            self.assertEqual(calls, 0)
            self.assertNotIn(species, self.ids(*self.UBERS))

    # -- spec ace (step 5) ----------------------------------------------

    def forced_step(self, uber: bool):
        """Context hooks: force only EndlessUberStep's own roll (armed at its
        entry), so other rarity rolls in a party build are untouched. Returns
        the list that counts how many times the step ran."""
        h = self.harness
        state = {"armed": False}
        steps: list[int] = []

        def at_step(*_args) -> None:
            state["armed"] = True
            steps.append(1)

        def at_done(*_args) -> None:
            if state["armed"]:
                h.pyboy.register_file.C = 2 if uber else 1
                state["armed"] = False

        h.register_hook("EndlessUberStep", at_step)
        h.register_hook("RollSpreadClass.done", at_done)

        def release() -> None:
            h.unregister_hook("EndlessUberStep", at_step)
            h.unregister_hook("RollSpreadClass.done", at_done)

        return steps, release

    def classes(self) -> dict:
        from source_constants import parse_trainer_class_indexes
        return parse_trainer_class_indexes(REPO_ROOT / "constants/trainer_constants.asm")

    def set_run(self, lineup=("BROCK", "MISTY", "LT_SURGE", "ERIKA", "KOGA", "SABRINA", "BLAINE", "GIOVANNI"),
                elite4=("LORELEI", "BRUNO", "AGATHA", "LANCE"), champion="RIVAL3") -> None:
        h, cls = self.harness, self.classes()
        for i, name in enumerate(lineup):
            h.write8("wRunGymLineup", cls[name], offset=i)
        for i, name in enumerate(elite4):
            h.write8("wRunElite4", cls[name], offset=i)
        h.write8("wRunChampion", cls[champion])

    def spec_ace(self, trainer: str, *, ace="RATTATA", party=(), uber=True) -> tuple[bool, int, int]:
        """One EndlessSpecAceUber: (carry, wCurPartySpecies after, steps run)."""
        h = self.harness
        h.write8("wTrainerClass", self.classes()[trainer])
        h.write8("wCurPartySpecies", self.species[ace])
        self.set_species("wEnemyPartyCount", "wEnemyPartySpecies", party)
        steps, release = self.forced_step(uber)
        try:
            h.call_routine("EndlessSpecAceUber")
        finally:
            release()
        return self.carry(), h.read8("wCurPartySpecies"), len(steps)

    def test_spec_ace_eligible_classes(self) -> None:
        self.groups(johto=True)
        self.set_run()
        self.at_round(1, 16)
        for trainer in ("BROCK", "GIOVANNI", "LORELEI", "LANCE", "RIVAL3",
                        "RIVAL_MINIBOSS", "GIOVANNI_MINIBOSS", "KARATE_MINIBOSS"):
            carry, species, steps = self.spec_ace(trainer)
            self.assertEqual((carry, steps), (True, 1), trainer)
            self.assertIn(species, self.ids(*self.UBERS), trainer)

    def test_spec_ace_ineligible_or_never_two(self) -> None:
        self.groups(johto=True)
        self.set_run()
        self.at_round(1, 16)
        cases = [
            dict(trainer="FALKNER"),                          # a leader, but not this circuit's
            dict(trainer="YOUNGSTER"),
            dict(trainer="BROCK", party=["ONIX", "MEW"]),     # already fields an Uber
            dict(trainer="BROCK", ace="MEWTWO"),              # the drawn ace is one
        ]
        for case in cases:
            carry, _, steps = self.spec_ace(**case)
            self.assertEqual((carry, steps), (False, 0), case)

    def test_spec_ace_master_result_keeps_the_ace(self) -> None:
        self.groups(johto=True)
        self.set_run()
        self.at_round(1, 16)
        carry, species, steps = self.spec_ace("BROCK", uber=False)
        self.assertEqual((carry, steps), (False, 1))
        self.assertEqual(species, self.species["RATTATA"])

    def test_spec_ace_untouched_at_depth_0(self) -> None:
        self.groups(johto=True)
        self.set_run()
        self.harness.write8("wEndlessDepth", 0)
        self.harness.write8("wBattleCount", 60)
        carry, _, steps = self.spec_ace("BROCK")
        self.assertEqual((carry, steps), (False, 0))

    def test_real_leader_team_gets_one_uber_ace(self) -> None:
        """ReadTrainer end to end: the last slot is the Uber, nothing else is,
        and its slot source carries the legendary-boss moveset marker."""
        h = self.harness
        cls = self.classes()
        ram = parse_rgbds_constants(REPO_ROOT / "constants/party_spec_constants.asm")
        self.groups(johto=True)
        self.set_run()
        self.at_round(1, 16)
        steps, release = self.forced_step(True)
        try:
            h.write8("wTrainerClass", cls["BROCK"])
            h.write8("wTrainerNo", 22)               # Endless leaders read round 8's teams
            h.call_routine("ReadTrainer", limit=4000)
        finally:
            release()
        count = h.read8("wEnemyPartyCount")
        party = h.read_bytes("wEnemyPartySpecies", count)
        ubers = self.ids(*self.UBERS)
        self.assertEqual(len(steps), 1, "one step per team")
        self.assertIn(party[-1], ubers, party)
        self.assertEqual(sum(s in ubers for s in party), 1, party)
        marker = h.read8("wPartyGenSlotSource", offset=count - 1)
        self.assertTrue(marker & 1 << ram["MSRC_LEGENDARY_BOSS_BIT"], hex(marker))

    def test_everything_owned_returns_no_carry(self) -> None:
        self.groups(johto=False)
        self.own(party=["MEW"], box=["MEWTWO"])
        self.assertIsNone(self.draw(True))
        self.assertIn(self.draw(False), self.ids("MEW", "MEWTWO"), "trainers ignore ownership")


if __name__ == "__main__":
    unittest.main()
