"""Endless mode checkpoint B: what EndlessOffer / EndlessContinue keep and reset.

custom_functions/endless.asm continues a run past the Champion. The contract
(ENDLESS_MODE_CHECKPOINT_A.md sections 4-5) is "reset only circuit-local state";
a build cannot show that, and the failure modes are silent (an item charge
refilled, a witch prize lost, a gym pool that restarts every circuit).

EndlessContinue is driven directly (it is the whole state transition; the
prompt and warp around it need VBlank waits that a hijacked call cannot run).
The decline path is driven through EndlessOffer, which returns before any
screen work when ineligible.

Every test boots the lobby and runs inside isolated_routine_calls, which
restores the whole machine on exit.
"""
import unittest

from routine_session import isolated_routine_calls
from source_constants import (
    parse_map_constants,
    parse_rgbds_constants,
    parse_trainer_class_indexes,
)
from test_smoke import HarnessTestCase, REPO_ROOT

TRAINER_CONSTANTS = REPO_ROOT / "constants" / "trainer_constants.asm"
RAM_CONSTANTS = REPO_ROOT / "constants" / "ram_constants.asm"
EVENT_CONSTANTS = REPO_ROOT / "constants" / "event_constants.asm"
GROUP_CONSTANTS = REPO_ROOT / "constants" / "rogue_species_groups.asm"

NUM_BADGES = 8
KANTO = ["BROCK", "MISTY", "LT_SURGE", "ERIKA", "KOGA", "SABRINA", "BLAINE", "GIOVANNI"]
JOHTO = ["FALKNER", "BUGSY", "WHITNEY", "MORTY", "CHUCK", "JASMINE", "PRYCE", "CLAIR"]

# (label, length): fields EndlessContinue must leave alone. Each is given a
# non-trivial sentinel first, so "unchanged" is not "0 stayed 0".
KEPT_FIELDS = [
    ("wPlayerMoney", 3),
    ("wPlayerCoins", 2),
    ("wHealAllItemLevel", 1),
    ("wRestorePPItemLevel", 1),
    ("wKODefianceUsages", 1),
    ("wTurnRewindUsages", 1),
    ("wDiceCharges", 1),
    ("wEarnedStatBoosts", 1),
    ("wBridgeGlobalEffects", 3),
    ("wBridgeSelectedEffects", 4),
    ("wWitchPrizesEarned", 2),
    ("wFallenCount", 1),
    ("wFusionSecondaryForm", 1),
    ("wFusionSecondarySpecies", 1),
    ("wVisitedStagesBitfield", 4),
    ("wBridgeOfferedLo", 1),
]

# EndlessContinue's own scratch/target bytes, in addition to the ranges handled
# separately in _allowed_changes. Anything else in Main Data that differs after
# the call is a leak.
RESET_FIELDS = [
    ("wBattleCount", 1), ("wObtainedBadges", 1), ("wGymChoice", 1),
    ("wRogueFlagsBitfield", 1), ("wRoutesSinceSpecial", 1), ("wMiniBossCount", 1),
    ("wProcCemBossBattle", 1), ("wDebug2ForcedDoor1", 1), ("wDebug2ForcedDoor2", 1),
    ("wWitchChallenge", 2), ("wWitchPrize", 1), ("wWitchLevelBonus", 2),
    ("wBattleTurnCount", 1), ("wStageEvent", 1), ("wCurOpponent", 1),
    ("wWildAreaState", 1), ("wBridgeState", 1), ("wStatusFlags7", 1),
    ("wElite4Flags", 1), ("wLastBlackoutMap", 1), ("wRogueMap", 1),
    ("wRogueDoorSelection", 1), ("wEndlessDepth", 1),
    ("wDayCareDepositBattleCount", 1), ("wDayCareDepositBattleCount2", 1),
]


class EndlessContinueTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        h = self.harness
        h.boot_to_lobby()
        self.session = isolated_routine_calls(h)
        self.session.__enter__()
        self.classes = parse_trainer_class_indexes(TRAINER_CONSTANTS)
        self.by_id = {v: k for k, v in self.classes.items()}
        self.ram = parse_rgbds_constants(RAM_CONSTANTS)
        self.events = parse_rgbds_constants(EVENT_CONSTANTS)
        self.groups = parse_rgbds_constants(GROUP_CONSTANTS)

    def tearDown(self) -> None:
        try:
            self.session.__exit__(None, None, None)
        finally:
            self.harness.close()

    # -- helpers ------------------------------------------------------

    def addr(self, label: str) -> int:
        return self.harness.address(label)

    def mem(self, label: str, length: int = 1) -> list[int]:
        a = self.addr(label)
        return list(self.harness.pyboy.memory[a:a + length])

    def put(self, label: str, values) -> None:
        a = self.addr(label)
        values = list(values) if not isinstance(values, int) else [values]
        for i, v in enumerate(values):
            self.harness.pyboy.memory[a + i] = v

    def main_data(self) -> list[int]:
        start, end = self.addr("wMainDataStart"), self.addr("wMainDataEnd")
        return list(self.harness.pyboy.memory[start:end])

    def event(self, name: str) -> bool:
        return self.harness.event_is_set(self.events[name])

    def set_groups(self, *, johto: bool) -> None:
        h = self.harness
        flags = h.read8("wStatusFlags6")
        bit = 1 << self.ram["BIT_DEBUG2_MODE"]
        h.write8("wStatusFlags6", flags | bit if johto else flags & ~bit & 0xFF)
        enabled = 1 << self.groups["BIT_GROUP_KANTO"]
        if johto:
            h.set_event(self.events["EVENT_JOHTO_ACTIVATED"])
            enabled |= 1 << self.groups["BIT_GROUP_JOHTO"]
        h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [enabled], bank=1)

    def lineup(self) -> list[str]:
        return [self.by_id[v] for v in self.mem("wRunGymLineup", NUM_BADGES)]

    def set_lineup(self, names: list[str]) -> None:
        self.put("wRunGymLineup", [self.classes[n] for n in names])

    def plant_sentinels(self) -> None:
        """Dirty every field the call is meant to keep or reset."""
        h = self.harness
        for index, (label, length) in enumerate(KEPT_FIELDS):
            self.put(label, [(0x31 + index * 7 + i) & 0xFF or 1 for i in range(length)])
        # The CurScript span: dirty it all, then re-plant the three kept fields.
        start, end = self.addr("wGameProgressFlags"), self.addr("wRogueMap") + 1
        for a in range(start, end):
            h.pyboy.memory[a] = 0xA5
        for index, (label, length) in enumerate(KEPT_FIELDS):
            if start <= self.addr(label) < end:
                self.put(label, [(0x31 + index * 7 + i) & 0xFF or 1 for i in range(length)])
        for label, length in RESET_FIELDS:
            if label in ("wEndlessDepth", "wBattleCount"):
                continue
            self.put(label, [0x5A] * length)
        h.write8("wBattleCount", 40)
        # Every run event set; the persistent zone too.
        span = self.addr("wEventFlags")
        for a in range(span, span + 62):
            h.pyboy.memory[a] = 0xFF
        self.put("wHallOfFameCurScript", 2)

    def snapshot_kept(self) -> dict:
        snap = {}
        for label, length in KEPT_FIELDS:
            snap[label] = self.mem(label, length)
        snap["wBridgeState"] = self.mem("wBridgeState")[0] & ~self.ram["BRIDGE_COUNT_MASK"] & 0xFF
        snap["wWildAreaState"] = (
            self.mem("wWildAreaState")[0] & ~self.ram["WILD_AREA_COUNT_MASK"] & 0xFF
        )
        snap["party"] = self.mem("wPartyMons", 6 * 0x2C)
        snap["wPartyCount"] = self.mem("wPartyCount")
        snap["boxes"] = self.mem("wBoxMons", 0x1E * 0x21 + 2)
        snap["events"] = self.mem("wEventFlags", 40 // 8)
        return snap

    # -- tests --------------------------------------------------------

    def test_decline_or_ineligible_changes_nothing(self) -> None:
        h = self.harness
        h.write8("wEndlessDebugOverride", 0)
        flag = self.events["EVENT_AI_DEFEATED"]
        address = self.addr("wEventFlags") + flag // 8
        h.pyboy.memory[address] &= ~(1 << (flag % 8)) & 0xFF
        h.write8("wStatusFlags3", h.read8("wStatusFlags3") & ~(1 << self.ram["BIT_WARP_FROM_CUR_SCRIPT"]) & 0xFF)
        before = self.main_data()
        h.call_routine("EndlessOffer")
        warp = self.ram["BIT_WARP_FROM_CUR_SCRIPT"]
        self.assertEqual(h.read8("wStatusFlags3") >> warp & 1, 0)
        self.assertEqual(before, self.main_data(), "ineligible EndlessOffer wrote Main Data")

    def test_accept_preserves_kept_state(self) -> None:
        h = self.harness
        self.set_groups(johto=False)
        self.plant_sentinels()
        kept_events = ["EVENT_GOT_STARTER", "EVENT_ESTABLISHED_STARTER",
                       "EVENT_BATTLED_RIVAL_IN_OAKS_LAB", "EVENT_BRIDGE_INTRO"]
        before = self.snapshot_kept()
        h.call_routine("EndlessContinue")
        after = self.snapshot_kept()
        for key, value in before.items():
            self.assertEqual(value, after[key], f"{key} changed across EndlessContinue")
        for name in kept_events:
            self.assertTrue(self.event(name), f"{name} was cleared")

    def test_accept_resets_circuit_state(self) -> None:
        h = self.harness
        self.set_groups(johto=False)
        self.plant_sentinels()
        h.call_routine("EndlessContinue")
        self.assertEqual(h.read8("wBattleCount"), 1)
        for label in ("wObtainedBadges", "wGymChoice", "wRogueFlagsBitfield",
                      "wMiniBossCount", "wHallOfFameCurScript", "wRunElite4",
                      "wRunChampion", "wStageEvent", "wCurOpponent"):
            self.assertEqual(h.read8(label), 0, label)
        for label, length in (("wRunElite4", 4),):
            self.assertEqual(self.mem(label, length), [0] * length)
        self.assertEqual(self.mem("wBridgeState")[0] & self.ram["BRIDGE_COUNT_MASK"], 0)
        self.assertEqual(self.mem("wWildAreaState")[0] & self.ram["WILD_AREA_COUNT_MASK"], 0)
        keep = {self.events[n] for n in (
            "EVENT_GOT_STARTER", "EVENT_ESTABLISHED_STARTER",
            "EVENT_BATTLED_RIVAL_IN_OAKS_LAB", "EVENT_BRIDGE_INTRO")}
        for event in range(self.events["RUN_EVENTS_START"], self.events["RUN_EVENTS_END"] + 1):
            if event not in keep:
                self.assertFalse(h.event_is_set(event), f"run event {event} survived")
        # Zone 0 (persistent) untouched, EVENT_AI_DEFEATED included.
        self.assertTrue(self.event("EVENT_AI_DEFEATED"))
        lineup = self.mem("wRunGymLineup", NUM_BADGES)
        self.assertNotIn(0, lineup)
        self.assertEqual(len(set(lineup)), NUM_BADGES)

    def test_depth_increments_and_saturates(self) -> None:
        h = self.harness
        self.set_groups(johto=False)
        h.write8("wEndlessDepth", 0)
        h.call_routine("EndlessContinue")
        self.assertEqual(h.read8("wEndlessDepth"), 1)
        h.call_routine("EndlessContinue")
        self.assertEqual(h.read8("wEndlessDepth"), 2)
        h.write8("wEndlessDepth", 0xFF)
        h.call_routine("EndlessContinue")
        self.assertEqual(h.read8("wEndlessDepth"), 0xFF)

    def test_no_stray_main_data_writes(self) -> None:
        """Any Main Data byte that changes must be one the routine owns."""
        h = self.harness
        self.set_groups(johto=False)
        h.write8("wEndlessDepth", 1)
        before = self.main_data()
        h.call_routine("EndlessContinue")
        after = self.main_data()
        start = self.addr("wMainDataStart")
        allowed = set()

        def span(label, length=1):
            for a in range(self.addr(label), self.addr(label) + length):
                allowed.add(a)

        for label, length in RESET_FIELDS:
            span(label, length)
        span("wGameProgressFlags", self.addr("wRogueMap") + 1 - self.addr("wGameProgressFlags"))
        span("wRunGymLineup", self.addr("wGymsUsedMask") - self.addr("wRunGymLineup"))
        span("wGymsUsedMask", 2)
        span("wEventFlags", 62)
        span("wPartyMons", 6 * 0x2C)  # HealParty
        stray = [
            (start + i, before[i], after[i])
            for i in range(len(before))
            if before[i] != after[i] and (start + i) not in allowed
        ]
        sym = self.harness.symbols
        self.assertEqual(
            stray, [],
            "unexpected Main Data writes: "
            + ", ".join(f"${a:04x} ({sym.nearest(0, a)}) {b:02x}->{c:02x}" for a, b, c in stray),
        )

    def test_daycare_elapsed_is_preserved(self) -> None:
        h = self.harness
        self.set_groups(johto=False)
        h.write8("wDayCareInUse", 1)
        h.write8("wDayCareDepositBattleCount", 60)
        h.write8("wDayCareDepositBattleCount2", 70)
        h.write8("wBattleCount", 73)
        h.call_routine("EndlessContinue")
        self.assertEqual((h.read8("wBattleCount") - h.read8("wDayCareDepositBattleCount")) & 0xFF, 13)
        self.assertEqual((h.read8("wBattleCount") - h.read8("wDayCareDepositBattleCount2")) & 0xFF, 3)

    def test_health_is_restored(self) -> None:
        h = self.harness
        self.set_groups(johto=False)
        count = h.read8("wPartyCount")
        stride = self.addr("wPartyMon2") - self.addr("wPartyMon1")
        for slot in range(count):
            base = self.addr("wPartyMon1") + slot * stride
            mem = h.pyboy.memory
            mem[base + (self.addr("wPartyMon1HP") - self.addr("wPartyMon1"))] = 0
            mem[base + (self.addr("wPartyMon1HP") - self.addr("wPartyMon1")) + 1] = 1
            mem[base + (self.addr("wPartyMon1Status") - self.addr("wPartyMon1"))] = 0x04
            for move in range(4):
                mem[base + (self.addr("wPartyMon1PP") - self.addr("wPartyMon1")) + move] = 0
        h.call_routine("EndlessContinue")
        for slot in range(count):
            base = self.addr("wPartyMon1") + slot * stride
            mem = h.pyboy.memory
            hp_off = self.addr("wPartyMon1HP") - self.addr("wPartyMon1")
            max_off = self.addr("wPartyMon1MaxHP") - self.addr("wPartyMon1")
            self.assertEqual(
                (mem[base + hp_off], mem[base + hp_off + 1]),
                (mem[base + max_off], mem[base + max_off + 1]),
                f"party slot {slot} not at full HP",
            )
            self.assertEqual(mem[base + self.addr("wPartyMon1Status") - self.addr("wPartyMon1")], 0)
            pp_off = self.addr("wPartyMon1PP") - self.addr("wPartyMon1")
            moves_off = self.addr("wPartyMon1Moves") - self.addr("wPartyMon1")
            for move in range(4):
                if mem[base + moves_off + move]:
                    self.assertGreater(mem[base + pp_off + move] & 0x3F, 0, f"slot {slot} move {move} PP")

    def test_first_route_is_a_stage_map(self) -> None:
        h = self.harness
        self.set_groups(johto=False)
        h.call_routine("EndlessContinue")
        route = h.read8("wRogueMap")
        self.assertNotEqual(route, 0)
        self.assertLess(h.read8("wRogueDoorSelection"), 4)

    # -- gym rotation -------------------------------------------------

    def test_johto_on_first_continuation_draws_the_eight_johto_gyms(self) -> None:
        h = self.harness
        self.set_groups(johto=True)
        self.set_lineup(["BROCK", "MISTY", "LT_SURGE", "ERIKA", "JANINE", "SABRINA", "BLAINE", "GIOVANNI"])
        h.write8("wEndlessDepth", 0)
        h.write8("wGymsUsedMask", 0)
        h.write8("wGymsUsedMask", 0, offset=1)
        h.call_routine("EndlessContinue")
        self.assertCountEqual(self.lineup(), JOHTO)

    def test_johto_on_depth_one_with_full_mask_redraws_from_sixteen(self) -> None:
        h = self.harness
        self.set_groups(johto=True)
        self.set_lineup(JOHTO)
        h.write8("wEndlessDepth", 1)
        h.write8("wGymsUsedMask", 0xFF)
        h.write8("wGymsUsedMask", 0xFF, offset=1)
        h.call_routine("EndlessContinue")
        drawn = self.lineup()
        self.assertEqual(len(set(drawn)), NUM_BADGES, drawn)
        for name in drawn:
            self.assertIn(name, KANTO + JOHTO + ["JANINE"])

    def test_kanto_only_redraws_the_eight_kanto_gyms(self) -> None:
        h = self.harness
        self.set_groups(johto=False)
        self.set_lineup(["BROCK", "MISTY", "LT_SURGE", "ERIKA", "JANINE", "SABRINA", "BLAINE", "GIOVANNI"])
        h.write8("wEndlessDepth", 0)
        h.call_routine("EndlessContinue")
        drawn = [("KOGA" if n == "JANINE" else n) for n in self.lineup()]
        self.assertCountEqual(drawn, KANTO)


if __name__ == "__main__":
    unittest.main()
