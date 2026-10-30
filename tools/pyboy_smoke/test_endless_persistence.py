"""Endless mode checkpoint F: persistence and endurance
(ENDLESS_MODE_IMPLEMENTATION_PLAN.md section 11F, acceptance rows in section 12).

Accepting Endless does not save (ENDLESS_MODE_CHECKPOINT_A.md, B2 design
change): a reset before the player's next save reloads the pre-Champion save,
where wEndlessDepth was never incremented, so nothing can apply twice. What
needs proving is the other side: a save made DURING an Endless run comes back
exactly, still reaches the overworld, and keeps scaling; a blackout ends
Endless; many circuits in a row keep the gym rotation and route pick coherent;
and the debug eligibility override can never ride along in a save.

The save test drives the real EndlessContinue twice, saves with SaveGameData,
boots a fresh emulator on nothing but that cartridge RAM (save_reload.Reboot)
and compares every saved region byte for byte at TryLoadSaveFile.done, before
any map script runs, then CONTINUEs into the overworld.
"""
import unittest

import save_reload
from routine_session import isolated_routine_calls
from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_smoke import HarnessTestCase, REPO_ROOT

NUM_BADGES = 8
KANTO = ["BROCK", "MISTY", "LT_SURGE", "ERIKA", "KOGA", "SABRINA", "BLAINE", "GIOVANNI"]
JOHTO = ["FALKNER", "BUGSY", "WHITNEY", "MORTY", "CHUCK", "JASMINE", "PRYCE", "CLAIR"]
GROUPS = parse_rgbds_constants(REPO_ROOT / "constants" / "rogue_species_groups.asm")
EVENTS = parse_rgbds_constants(REPO_ROOT / "constants" / "event_constants.asm")
RAM = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")


class EndlessFixture(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.harness.boot_to_lobby()
        self.classes = parse_trainer_class_indexes(REPO_ROOT / "constants" / "trainer_constants.asm")
        self.by_id = {v: k for k, v in self.classes.items()}

    def set_groups(self, *, johto: bool) -> None:
        h = self.harness
        enabled = 1 << GROUPS["BIT_GROUP_KANTO"]
        if johto:
            h.set_event(EVENTS["EVENT_JOHTO_ACTIVATED"])
            enabled |= 1 << GROUPS["BIT_GROUP_JOHTO"]
        h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [enabled], bank=1)

    def lineup(self) -> list[str]:
        """This circuit's eight gyms, Janine folded into Koga's Fuchsia slot."""
        names = [self.by_id[self.harness.read8("wRunGymLineup", offset=i)] for i in range(NUM_BADGES)]
        return ["KOGA" if n == "JANINE" else n for n in names]

    def set_lineup(self, names) -> None:
        for i, name in enumerate(names):
            self.harness.write8("wRunGymLineup", self.classes[name], offset=i)


class EndlessSaveReloadTest(EndlessFixture):
    def test_mid_endless_save_reloads_exactly_and_continues(self) -> None:
        h = self.harness
        with isolated_routine_calls(h):
            self.set_groups(johto=True)
            self.set_lineup(KANTO)
            h.write8("wEndlessDepth", 0)
            h.write8("wGymsUsedMask", 0)
            h.write8("wGymsUsedMask", 0, offset=1)
            h.call_routine("EndlessContinue")
            h.call_routine("EndlessContinue")         # two circuits deep
            self.assertEqual(h.read8("wEndlessDepth"), 2)
            depth_lineup = self.lineup()
            saved = save_reload.save_now(h)
            sram = save_reload.sram_image(h)
        boot = save_reload.Reboot(sram)
        try:
            boot.load()
            self.assertEqual(boot.status, 2, "the Endless save did not load")
            diffs = [d for d in save_reload.differences(h, saved, boot.loaded)
                     if not d["label"].startswith("wRunTimer")]  # the run clock ticks during the load
            self.assertEqual(diffs, [], "saved Endless state came back different")
            self.assertTrue(boot.overworld, "the reloaded Endless save never reached the overworld")
            b = boot.h
            self.assertEqual(b.read8("wEndlessDepth"), 2, "depth changed on reload")
            got = [self.by_id[b.read8("wRunGymLineup", offset=i)] for i in range(NUM_BADGES)]
            self.assertEqual(["KOGA" if n == "JANINE" else n for n in got], depth_lineup)
            b.call_routine("GetRunProgress")
            self.assertEqual(b.last_call_registers["A"],
                             min(255, b.read8("wBattleCount") + 2 * 72), "scaling after reload")
        finally:
            boot.close()


    def test_retained_daycare_deposit_survives_save_reload(self) -> None:
        h = self.harness
        with isolated_routine_calls(h):
            self.set_groups(johto=False)
            h.write8("wEndlessDepth", 0)
            h.write8("wDayCareInUse", 1)
            h.write8("wDayCareDepositBattleCount", 1)
            for _ in range(3):
                h.write8("wBattleCount", 73)
                h.call_routine("EndlessContinue")
            snapshot = h.read8("wDayCareDepositBattleCount")
            elapsed = (h.read8("wBattleCount") - snapshot) & 0xFF
            self.assertEqual(elapsed, 183)
            saved = save_reload.save_now(h)
            sram = save_reload.sram_image(h)
        boot = save_reload.Reboot(sram)
        try:
            boot.load()
            self.assertEqual(boot.status, 2, "the Endless save did not load")
            b = boot.h
            self.assertEqual(b.read8("wDayCareDepositBattleCount"), snapshot)
            self.assertEqual((b.read8("wBattleCount") - b.read8("wDayCareDepositBattleCount")) & 0xFF,
                             elapsed, "daycare elapsed changed across save and reload")
        finally:
            boot.close()


class EndlessEnduranceTest(EndlessFixture):
    def setUp(self) -> None:
        super().setUp()
        self.session = isolated_routine_calls(self.harness)
        self.session.__enter__()

    def tearDown(self) -> None:
        try:
            self.session.__exit__(None, None, None)
        finally:
            self.harness.close()

    def circuit(self) -> list[str]:
        h = self.harness
        depth = h.read8("wEndlessDepth")
        h.call_routine("EndlessContinue")
        self.assertEqual(h.read8("wEndlessDepth"), min(255, depth + 1))
        self.assertEqual(h.read8("wBattleCount"), 1)
        self.assertNotEqual(h.read8("wRogueMap"), 0, "no first route picked")
        self.assertLess(h.read8("wRogueDoorSelection"), 4)
        lineup = self.lineup()
        self.assertEqual(len(set(lineup)), NUM_BADGES, lineup)
        return lineup

    def test_johto_sixteen_gym_rotation_holds_for_many_circuits(self) -> None:
        h = self.harness
        self.set_groups(johto=True)
        self.set_lineup(KANTO)
        h.write8("wEndlessDepth", 0)
        h.write8("wGymsUsedMask", 0)
        h.write8("wGymsUsedMask", 0, offset=1)
        lineups = [self.circuit() for _ in range(9)]
        self.assertCountEqual(lineups[0], JOHTO, "circuit 1 is the other eight")
        # From then on every pair of circuits is one full sixteen-gym rotation.
        for first, second in zip(lineups[1::2], lineups[2::2]):
            self.assertFalse(set(first) & set(second), (first, second))
            self.assertCountEqual(first + second, KANTO + JOHTO)

    def test_kanto_only_never_draws_johto_over_many_circuits(self) -> None:
        h = self.harness
        self.set_groups(johto=False)
        self.set_lineup(KANTO)
        h.write8("wEndlessDepth", 0)
        for _ in range(8):
            self.assertCountEqual(self.circuit(), KANTO)

    def test_saturated_depth_keeps_continuing(self) -> None:
        h = self.harness
        self.set_groups(johto=False)
        h.write8("wEndlessDepth", 0xFE)
        for _ in range(3):
            self.circuit()
        self.assertEqual(h.read8("wEndlessDepth"), 0xFF)
        h.call_routine("GetRunProgress")
        self.assertEqual(h.last_call_registers["A"], 0xFF)
        h.write8("wCurEnemyLevel", 50)
        h.call_routine("EndlessLevelBonus")              # indexes the last row, not past it
        self.assertGreaterEqual(h.read8("wCurEnemyLevel"), 50)

    def test_blackout_ends_endless(self) -> None:
        h = self.harness
        self.set_groups(johto=False)
        h.write8("wEndlessDepth", 3)
        h.write8("wEndlessFlags", 0)
        h.call_routine("RogueOnBlackout")
        self.assertEqual(h.read8("wEndlessDepth"), 0)
        self.assertEqual(h.read8("wEndlessFlags"), 0)
        h.write8("wBattleCount", 30)
        h.call_routine("GetRunProgress")
        self.assertEqual(h.last_call_registers["A"], 30, "a new run scales from its own count")


class EndlessDebugOverrideTest(HarnessTestCase):
    def test_debug_override_is_outside_every_saved_region(self) -> None:
        h = self.harness
        override = h.address("wEndlessDebugOverride")
        for name, first, length in save_reload.region_spans(h):
            self.assertFalse(first <= override < first + length, f"override saved with {name}")
        self.assertNotIn("sEndlessDebugOverride", h.symbols._symbols)
        h.close()


if __name__ == "__main__":
    unittest.main()
