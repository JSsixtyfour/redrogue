"""Endless mode checkpoint C: recycled content pools start from fresh-run state.

A run never exhausts the stage-route pool or the gift-room pool; an Endless run
does, mid-circuit, and the next pick can then be a map cleared earlier in the
same circuit. RecycleStagePool / RecycleBridgePool (custom_functions/endless.asm)
reset each pool's maps when its history clears. The lists they use are
generated (tools/gen_pool_recycle.py -> data/events/pool_recycle.asm).

Recurring gyms (and so recurring Legendary Boss bargains) must never hand over
a legendary the player already owns: LegendaryPoolUnowned filters the pools.

Every test boots the lobby and runs inside isolated_routine_calls, which
restores the whole machine on exit.
"""
import re
import subprocess
import sys
import unittest

from routine_session import isolated_routine_calls
from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_smoke import HarnessTestCase, REPO_ROOT

POOL_FILE = REPO_ROOT / "data" / "events" / "pool_recycle.asm"
ENDLESS = REPO_ROOT / "custom_functions" / "endless.asm"
NUM_STAGE_MAPS = 22
NUM_BRIDGE_ROOMS = 14
STAGE_TOGGLES = [
    "TOGGLE_POKEMON_TOWER_7F_ROCKET_1", "TOGGLE_POKEMON_TOWER_7F_ROCKET_2",
    "TOGGLE_POKEMON_TOWER_7F_ROCKET_3", "TOGGLE_POKEMON_TOWER_7F_ROCKET_5",
    "TOGGLE_POKEMON_TOWER_7F_MR_FUJI", "TOGGLE_SS_ANNE_B1F_CAPTAIN",
]
KEPT_STARTER_EVENTS = ["EVENT_GOT_STARTER", "EVENT_ESTABLISHED_STARTER",
                       "EVENT_BATTLED_RIVAL_IN_OAKS_LAB", "EVENT_BRIDGE_INTRO"]


def parse_pools() -> dict:
    """{'StagePool': (events, scripts), 'BridgePool': (...)} from the generated file."""
    pools, current = {}, None
    for line in POOL_FILE.read_text().splitlines():
        m = re.match(r"^(\w+Pool)(EventMask|Scripts):", line)
        if m:
            current = pools.setdefault(m.group(1), ([], []))
            kind = m.group(2)
            continue
        m = re.match(r"^\s*pool_event (EVENT_\w+)", line)
        if m:
            current[0].append(m.group(1))
        m = re.match(r"^\s*dw (w\w+CurScript)", line)
        if m and kind == "Scripts":
            current[1].append(m.group(1))
    return pools


def legendary_pools() -> dict:
    text = ENDLESS.read_text()
    table = text[text.index("LegendaryBossTable:"):]
    table = table[:table.index("\tdb 0")]
    rows = {}
    for m in re.finditer(r"db (\w+),\s*(\d+),\s*([\w, ]+)", table):
        rows[m.group(1)] = [s.strip() for s in m.group(3).split(",")]
        assert len(rows[m.group(1)]) == int(m.group(2)), m.group(0)
    return rows


class GeneratedPoolFileTest(unittest.TestCase):
    def test_generated_file_is_current(self) -> None:
        result = subprocess.run(
            [sys.executable, str(REPO_ROOT / "tools" / "gen_pool_recycle.py"), "--check"],
            capture_output=True, text=True, cwd=REPO_ROOT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_legendary_pool_species_are_single_stage(self) -> None:
        """LegendaryPoolUnowned's exact-species scan equals AllSpeciesCheck's
        family-wide one only while no pool species evolves or is evolved into."""
        evos = (REPO_ROOT / "data/pokemon/evos_moves.asm").read_text()
        evos += (REPO_ROOT / "data/pokemon/form_evos_moves.asm").read_text()
        species = {s for row in legendary_pools().values() for s in row}
        self.assertTrue(species)
        for name in species:
            self.assertIsNone(re.search(r"db EVOLVE_\w+.*,\s*%s\s*(;|$)" % name, evos, re.M),
                              f"something evolves into {name}")
        for name in ("MEW", "MEWTWO", "CELEBI", "LUGIA", "HO_OH"):
            m = re.search(r"^%sEvosMoves:\n; Evolutions\n\s*db 0" % {
                "MEW": "Mew", "MEWTWO": "Mewtwo", "CELEBI": "Celebi",
                "LUGIA": "Lugia", "HO_OH": "HoOh"}[name], evos, re.M)
            self.assertIsNotNone(m, f"{name} has an evolution")


class EndlessRecycleTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        h = self.harness
        h.boot_to_lobby()
        self.session = isolated_routine_calls(h)
        self.session.__enter__()
        self.events = parse_rgbds_constants(REPO_ROOT / "constants/event_constants.asm")
        self.toggles = parse_rgbds_constants(REPO_ROOT / "constants/toggle_constants.asm")
        self.ram = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")
        self.species = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
        self.classes = parse_trainer_class_indexes(REPO_ROOT / "constants/trainer_constants.asm")
        self.pools = parse_pools()

    def tearDown(self) -> None:
        try:
            self.session.__exit__(None, None, None)
        finally:
            self.harness.close()

    # -- helpers ------------------------------------------------------

    def write_bytes(self, label: str, values) -> None:
        base = self.harness.address(label)
        for i, v in enumerate(values):
            self.harness.pyboy.memory[base + i] = v

    def run_events(self) -> range:
        return range(self.events["RUN_EVENTS_START"], self.events["RUN_EVENTS_END"] + 1)

    def set_all_run_events(self) -> None:
        h = self.harness
        start = h.address("wEventFlags")
        for byte in range(self.events["RUN_EVENTS_START"] // 8,
                          self.events["RUN_EVENTS_END"] // 8 + 1):
            h.pyboy.memory[start + byte] = 0xFF

    def dirty_scripts(self) -> dict:
        """Every pool's CurScripts plus two outsiders get a sentinel."""
        h = self.harness
        labels = set(self.pools["StagePool"][1]) | set(self.pools["BridgePool"][1])
        labels |= {"wPewterGymCurScript", "wHallOfFameCurScript"}
        for label in labels:
            h.write8(label, 0x03)
        return {label: 0x03 for label in labels}

    def hide_toggles(self, names) -> None:
        h = self.harness
        base = h.address("wToggleableObjectFlags")
        for name in names:
            index = self.toggles[name]
            h.pyboy.memory[base + index // 8] |= 1 << index % 8

    def toggle_hidden(self, name: str) -> bool:
        index = self.toggles[name]
        return bool(self.harness.read8("wToggleableObjectFlags", offset=index // 8) & 1 << index % 8)

    def assert_only_pool_reset(self, pool: str) -> None:
        h = self.harness
        cleared = {self.events[n] for n in self.pools[pool][0]}
        self.assertTrue(cleared)
        for event in self.run_events():
            if event in cleared:
                self.assertFalse(h.event_is_set(event), f"{pool} event {event} survived")
            else:
                self.assertTrue(h.event_is_set(event), f"non-{pool} run event {event} was cleared")

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

    def arm_legendary_bargain(self) -> None:
        h = self.harness
        h.write8("wRogueFlagsBitfield",
                 h.read8("wRogueFlagsBitfield") | 1 << self.ram["BIT_WITCH_ACCEPTED"])
        h.write8("wWitchChallenge", self.ram["CHALLENGE_LEGENDARY_BOSS"])

    # -- stage pool ---------------------------------------------------

    def test_stage_exhaustion_recycles_only_stage_state(self) -> None:
        h = self.harness
        self.write_bytes("wVisitedStagesBitfield", [0xFF, 0xFF, 0x3F, 0x00])  # all 22
        self.set_all_run_events()
        scripts = self.dirty_scripts()
        self.hide_toggles(STAGE_TOGGLES + ["TOGGLE_OAKS_LAB_RIVAL"])
        h.call_routine("_PickRandomUnvisitedStage")
        self.assertEqual(h.read_bytes("wVisitedStagesBitfield", 4), [0, 0, 0, 0])
        self.assert_only_pool_reset("StagePool")
        for label, sentinel in scripts.items():
            expect = 0 if label in self.pools["StagePool"][1] else sentinel
            self.assertEqual(h.read8(label), expect, label)
        for name in STAGE_TOGGLES:
            self.assertFalse(self.toggle_hidden(name), f"{name} still hidden")
        self.assertTrue(self.toggle_hidden("TOGGLE_OAKS_LAB_RIVAL"),
                        "the stage recycle re-showed a non-stage object")

    def test_stage_pick_with_stages_left_touches_nothing(self) -> None:
        h = self.harness
        self.write_bytes("wVisitedStagesBitfield", [0xFF, 0xFF, 0x1F, 0x00])  # one left
        self.set_all_run_events()
        scripts = self.dirty_scripts()
        flags_before = h.read_bytes("wEventFlags", 64)
        h.call_routine("_PickRandomUnvisitedStage")
        self.assertEqual(h.read_bytes("wEventFlags", 64), flags_before)
        for label, sentinel in scripts.items():
            self.assertEqual(h.read8(label), sentinel, label)
        self.assertEqual(h.read_bytes("wVisitedStagesBitfield", 4), [0xFF, 0xFF, 0x1F, 0x00])

    def test_stage_pool_covers_every_stage_map(self) -> None:
        """Each of the 22 stages has its trainers and its script byte in the pool."""
        events, scripts = self.pools["StagePool"]
        trainer_maps = {re.sub(r"_TRAINER_\d$", "", e) for e in events if "_TRAINER_" in e}
        # 22 stages; SS Anne's rooms carry its trainers and Route 24 adds a rocket.
        self.assertGreaterEqual(len(trainer_maps), NUM_STAGE_MAPS - 1, sorted(trainer_maps))
        self.assertGreaterEqual(len(scripts), NUM_STAGE_MAPS)
        for name in KEPT_STARTER_EVENTS + ["EVENT_ENTER_ROOM", "EVENT_GOT_ROGUE_POKEMON",
                                          "EVENT_MET_BILL_2"]:
            self.assertNotIn(name, events)

    # -- bridge pool --------------------------------------------------

    def test_bridge_exhaustion_recycles_only_bridge_state(self) -> None:
        h = self.harness
        h.write8("wBridgeOfferedLo", 0xFF)
        h.write8("wBridgeState", h.read8("wBridgeState") | 0x3F)  # all 14 offered
        self.set_all_run_events()
        scripts = self.dirty_scripts()
        h.call_routine("BridgePickTwoRooms")
        self.assert_only_pool_reset("BridgePool")
        for name in KEPT_STARTER_EVENTS:
            self.assertTrue(h.event_is_set(self.events[name]), f"{name} was cleared")
        for label, sentinel in scripts.items():
            expect = 0 if label in self.pools["BridgePool"][1] else sentinel
            self.assertEqual(h.read8(label), expect, label)
        door1, door2 = h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap")
        self.assertNotEqual(door1, door2)

    def test_bridge_pick_with_rooms_left_touches_nothing(self) -> None:
        h = self.harness
        h.write8("wBridgeOfferedLo", 0xFF)
        h.write8("wBridgeState", (h.read8("wBridgeState") & 0xC0) | 0x0F)  # 2 left
        self.set_all_run_events()
        flags_before = h.read_bytes("wEventFlags", 64)
        h.call_routine("BridgePickTwoRooms")
        self.assertEqual(h.read_bytes("wEventFlags", 64), flags_before)

    def test_bill_events_are_bridge_state(self) -> None:
        events = self.pools["BridgePool"][0]
        for name in ("EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING", "EVENT_MET_BILL_2",
                     "EVENT_MET_BILL"):
            self.assertIn(name, events)
        for name in KEPT_STARTER_EVENTS + ["EVENT_BRIDGE_RECEIVE_GIFT", "EVENT_ENTER_ROOM"]:
            self.assertNotIn(name, events)

    # -- legendary ownership ------------------------------------------

    def roll_ace(self, trainer: str) -> int | None:
        """One RollLegendaryBossAce; the species it swapped in, else None."""
        h = self.harness
        h.write8("wTrainerClass", self.classes[trainer])
        h.write8("wLegendaryBossSpecies", 0)
        h.call_routine("RollLegendaryBossAce")
        carry = h.last_call_registers["F"] >> 4 & 1
        species = h.read8("wLegendaryBossSpecies")
        self.assertEqual(bool(carry), species != 0)
        return species or None

    def test_ace_roll_draws_only_unowned_species(self) -> None:
        self.arm_legendary_bargain()
        self.own(party=["MEWTWO", "MEW"], box=["CELEBI"])
        lugia = self.species["LUGIA"]
        for _ in range(12):
            self.assertEqual(self.roll_ace("SABRINA"), lugia)

    def test_ace_roll_skips_a_fully_owned_pool(self) -> None:
        self.arm_legendary_bargain()
        self.own(party=["MEW"], box=["CELEBI"])
        self.assertIsNone(self.roll_ace("ERIKA"))

    def test_ace_roll_with_nothing_owned_still_uses_the_whole_pool(self) -> None:
        self.arm_legendary_bargain()
        self.own(party=["RATTATA"])
        pool = {self.species[n] for n in legendary_pools()["SABRINA"]}
        seen = {self.roll_ace("SABRINA") for _ in range(40)}
        self.assertEqual(seen, pool)

    def latch_doors(self, slot1: int, slot2: int) -> None:
        h = self.harness
        shift = self.ram["GYM_CHOICE_DOOR2_SHIFT"]
        h.write8("wGymChoice", 1 << self.ram["BIT_GYM_CHOICE_LATCHED"] | slot2 << shift | slot1)

    def test_door_gate_follows_ownership_without_rng(self) -> None:
        h = self.harness
        lineup = [self.classes[n] for n in
                  ("BROCK", "ERIKA", "MISTY", "LT_SURGE", "KOGA", "SABRINA", "BLAINE", "GIOVANNI")]
        self.write_bytes("wRunGymLineup", lineup)
        self.latch_doors(1, 6)                       # Erika, Blaine
        draws = []

        def count_draw(*_args) -> None:
            draws.append(1)

        h.register_hook("Rangerandom", count_draw)
        try:
            self.own(party=["RATTATA"])
            h.call_routine("LegendaryBossDoors")
            self.assertEqual(h.last_call_registers["E"], 0b11)
            self.own(party=["MEW", "CELEBI"])         # Erika's pool owned out
            h.call_routine("LegendaryBossDoors")
            self.assertEqual(h.last_call_registers["E"], 0b10)
            self.own(party=["MEW", "CELEBI"], box=["HO_OH"])
            h.call_routine("LegendaryBossDoors")
            self.assertEqual(h.last_call_registers["E"], 0)
        finally:
            h.unregister_hook("Rangerandom", count_draw)
        self.assertEqual(draws, [], "the count-only query consumed RNG")
