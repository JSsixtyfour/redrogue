"""Psychic Psyduck/Golduck: the Facility's wandering optional encounter.

Exact odds, the placement order (a block in the Facility, then the warp room, then
none), the species and move ladders, the contact rule on every side and facing,
and real trips: battle, gift, the SPECIAL FORMS credit, the Facility's own script
afterwards, and a save. Purple itself is in test_warden_detox.
"""
from __future__ import annotations

import io
import re
import unittest
from collections import Counter, deque

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from audit_facility_stranded_quadrants import BLOCKSET, passable
from audit_facility_pad_sites import FIRST_PAD_WARP, PAD_NONE
import save_reload
import test_facility_subroom as fs
import test_optional_encounter as encounter
from test_optional_encounter import direct_call
from test_optional_cold_moves import MOVES, SPECIES

ROOT, ARTIFACTS = fs.ROOT, fs.ARTIFACTS
TYPES = parse_rgbds_constants(ROOT / "constants/type_constants.asm")
RAM = parse_rgbds_constants(ROOT / "constants/ram_constants.asm")
DEX = parse_rgbds_constants(ROOT / "constants/pokedex_constants.asm")
FIRST = RAM["OPTIONAL_PACKAGE_PSYCHIC"]
SUPPORT = ("AGILITY", "BARRIER", "HYPNOSIS", "KINESIS", "MEDITATE", "CONFUSE_RAY")
PACKAGES = range(FIRST, FIRST + len(SUPPORT))
FLAGS = 12  # BIT_SPECIAL_FORM | BIT_TYPE_VARIANT
MON_SPRITE = 5  # SPRITE_MONSTER
SLOT = 13  # FACILITY_OPTIONAL_MON
SCRATCH_X, SCRATCH_Y = 8, 9  # FACSUB_SCRATCH_MON_X/Y
DOWN, UP, LEFT, RIGHT = 0, 4, 8, 12  # SPRITE_FACING_*
RANGE = {DOWN: 0xD0, UP: 0xD1, LEFT: 0xD2, RIGHT: 0xD3}  # fixed-facing movement byte 2
PAD = {"right": 0x10, "left": 0x20, "up": 0x40, "down": 0x80}
CARRY = 0x10


def attack_for(level):
    return "CONFUSION" if level < 20 else "PSYBEAM" if level < 36 else "PSYCHIC_M"


def return_now(h):
    regs, memory = h.pyboy.register_file, h.pyboy.memory
    sp = regs.SP
    regs.PC = memory[sp] | memory[sp + 1] << 8
    regs.SP = sp + 2


class FacilityAssignmentTest(unittest.TestCase):
    def setUp(self):
        self.h = h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        h.park_before_hijack()
        self.maps = fs.parse_map_constants(ROOT / "constants/map_constants.asm")
        self.base = io.BytesIO()
        h.save_state(self.base)

    def production(self):
        h = self.h
        h.write8("wStatusFlags6", h.read8("wStatusFlags6") & ~(1 << RAM["BIT_DEBUG2_MODE"]))

    def set_pad(self, value):
        raw = self.h.read_sram_bytes("sProcFacilityGenScratch", fs.SCRATCH_PAD + 1)
        raw[fs.SCRATCH_PAD] = value
        self.h.write_sram_bytes("sProcFacilityGenScratch", raw)

    def open_sram(self, _):
        memory = self.h.pyboy.memory
        memory[0x0000], memory[0x6000], memory[0x4000] = 10, 1, 1

    def test_every_bin_is_ten_in_a_hundred(self):
        h = self.h
        context = {}
        h.register_hook("OptionalFacilityOutcome",
                        lambda _: setattr(h.pyboy.register_file, "A", context["roll"]))
        outcomes = Counter()
        for roll in range(100):
            h.load_state(self.base)
            context["roll"] = roll
            for i in range(7):
                h.write8("wOptionalEncounterSpecies", 0, offset=i)
            h.call_routine("OptionalFacilityOutcome")
            species = h.read8("wOptionalEncounterSpecies")
            self.assertEqual(bool(species), roll < 10, roll)
            outcomes[bool(species)] += 1
            if species:
                self.assertIn(species, (SPECIES["PSYDUCK"], SPECIES["GOLDUCK"]))
                self.assertIn(h.read8("wOptionalEncounterPackage"), PACKAGES)
                self.assertEqual(h.read8("wOptionalEncounterMap"), self.maps["PROCEDURAL_FACILITY"])
                self.assertGreater(h.read8("wOptionalEncounterLevel"), 0)
                self.assertEqual(h.read8("wOptionalEncounterState"), 0)
            else:
                self.assertEqual(h.read_bytes("wOptionalEncounterSpecies", 7), [0] * 7)
        self.assertEqual(outcomes, Counter({True: 10, False: 90}))
        self.assertFalse(h.hook_errors, h.hook_errors)

    def assign(self, pad, roll, found):
        """found: whether OptionalFacilityFindSpot reports a block."""
        h = self.h
        h.load_state(self.base)
        self.production()
        self.set_pad(pad)
        for i in range(7):
            h.write8("wOptionalEncounterSpecies", 165, offset=i)
        ranges = []

        def outcome(_):
            ranges.append(h.pyboy.register_file.C)
            h.pyboy.register_file.A = roll

        def spot(_):
            h.pyboy.register_file.F = CARRY if found else 0

        hooks = (("OptionalFacilityAssignEncounter", self.open_sram), ("OptionalFacilityOutcome", outcome),
                 ("OptionalFacilityPlaceEncounter", self.open_sram),
                 ("OptionalFacilityPlaceEncounter.haveSpot", spot))
        for hook in hooks:
            h.register_hook(*hook)
        h.write8("hCurMap", self.maps["PROCEDURAL_FACILITY"])
        try:
            direct_call(h, "OptionalFacilityAssignEncounter")
            direct_call(h, "OptionalFacilityPlaceEncounter")
        finally:
            for hook in hooks:
                h.unregister_hook(*hook)
        self.assertEqual(ranges, [100], "one roll, over a hundred")

    def test_placement_prefers_the_facility_then_the_warp_room_then_nothing(self):
        h = self.h
        self.assign(0, 0, found=True)
        self.assertEqual(h.read8("wOptionalEncounterMap"), self.maps["PROCEDURAL_FACILITY"])
        self.assign(len(fs.PAD_SITES), 0, found=True)
        self.assertEqual(h.read8("wOptionalEncounterMap"), self.maps["PROCEDURAL_FACILITY"], "needs no pad")
        self.assign(0, 0, found=False)
        self.assertEqual(h.read8("wOptionalEncounterMap"), self.maps["PROCEDURAL_FACILITY_SUBROOM"])
        self.assertIn(h.read8("wOptionalEncounterPackage"), PACKAGES)
        for pad in (len(fs.PAD_SITES), 0xFF):
            self.assign(pad, 0, found=False)
            self.assertEqual(h.read_bytes("wOptionalEncounterSpecies", 7), [0] * 7, "nowhere")

    def test_a_miss_clears_a_stale_encounter_and_skips_the_search(self):
        h = self.h
        search = h.hook_flag("OptionalFacilityFindSpot")
        self.assign(0, 10, found=True)
        self.assertEqual(h.read_bytes("wOptionalEncounterSpecies", 7), [0] * 7)
        self.assertEqual(search["count"], 0)

    def test_assignment_leaves_the_level_and_the_sram_bank_for_the_bake(self):
        h = self.h
        h.load_state(self.base)
        self.production()
        h.write8("wCurEnemyLevel", 77)
        h.register_hook("OptionalFacilityAssignEncounter", self.open_sram)
        reopened = h.hook_flag("OptionalFacilityOpenSRAM")
        direct_call(h, "OptionalFacilityAssignEncounter")
        self.assertEqual(h.read8("wCurEnemyLevel"), 77)
        self.assertGreaterEqual(reopened["count"], 1)

    def test_the_species_follows_psyducks_evolution_level(self):
        h = self.h
        text = (ROOT / "data/pokemon/evos_moves.asm").read_text(encoding="utf-8")
        evolves = int(re.search(r"PsyduckEvosMoves:.*?EVOLVE_LEVEL, (\d+), GOLDUCK", text, re.S).group(1))
        context = {}
        h.register_hook("OptionalForcePink.level",
                        lambda _: setattr(h.pyboy.register_file, "A", context["level"]))
        for level, species in ((1, "PSYDUCK"), (evolves - 1, "PSYDUCK"), (evolves, "GOLDUCK"), (100, "GOLDUCK")):
            with self.subTest(level=level):
                h.load_state(self.base)
                context["level"] = level
                h.call_routine("OptionalForcePsychic")
                self.assertEqual(h.read8("wOptionalEncounterSpecies"), SPECIES[species])
                self.assertEqual(h.read8("wOptionalEncounterLevel"), level)

    def test_all_six_support_moves_can_be_rolled(self):
        h = self.h
        seen = Counter()
        for seed in range(90):
            h.load_state(self.base)
            h.seed_rng((seed * 17 & 255, seed * 5 & 255, seed & 255, 1))
            h.call_routine("OptionalForcePsychic")
            seen[h.read8("wOptionalEncounterPackage")] += 1
        self.assertEqual(set(seen), set(PACKAGES), seen)

    def test_moves_at_every_boundary_in_both_pp_layouts(self):
        h = self.h
        bank, addr = h.symbols.get("Moves")
        raw = h.rom_path.read_bytes()
        start = bank * 16384 + addr - 16384
        for species in ("PSYDUCK", "GOLDUCK"):
            for level in (1, 19, 20, 35, 36, 100):
                for package, status in zip(PACKAGES, SUPPORT):
                    for struct, pp_offset in (("wEnemyMon", 25), ("wPartyMon6", 29), ("wBoxMon1", 29)):
                        h.load_state(self.base)
                        base = h.address(struct)
                        h.pyboy.memory[base:base + 33] = [0xA5] * 33
                        h.pyboy.memory[base] = SPECIES[species]
                        h.pyboy.memory[base + 8:base + 12] = [MOVES[m] for m in ("TACKLE", "GROWL", "POUND", "LEER")]
                        h.write8("wOptionalEncounterSpecies", SPECIES[species])
                        h.write8("wOptionalEncounterLevel", level)
                        h.write8("wOptionalEncounterPackage", package)

                        def inject(_, base=base, pp_offset=pp_offset):
                            regs = h.pyboy.register_file
                            regs.D, regs.E, regs.B = base >> 8, base & 255, pp_offset - 8

                        h.register_hook("OptionalGrantColdMoves", inject)
                        h.call_routine("OptionalGrantColdMoves")
                        h.unregister_hook("OptionalGrantColdMoves", inject)
                        expected = [MOVES[m] for m in ("TACKLE", "GROWL", status, attack_for(level))]
                        where = (species, level, package, struct)
                        self.assertEqual(list(h.pyboy.memory[base + 8:base + 12]), expected, where)
                        self.assertEqual(list(h.pyboy.memory[base + pp_offset:base + pp_offset + 4]),
                                         [raw[start + (m - 1) * 6 + 5] for m in expected], where)

    def grant(self, package, level, names):
        h = self.h
        h.load_state(self.base)
        base = h.address("wPartyMon6")
        h.write8("wOptionalEncounterLevel", level)
        h.write8("wOptionalEncounterPackage", package)
        h.pyboy.memory[base + 8:base + 12] = [MOVES[m] for m in names] + [0] * (4 - len(names))

        def inject(_):
            regs = h.pyboy.register_file
            regs.D, regs.E, regs.B = base >> 8, base & 255, 21

        h.register_hook("OptionalGrantColdMoves", inject)
        h.call_routine("OptionalGrantColdMoves")
        h.unregister_hook("OptionalGrantColdMoves", inject)
        return list(h.pyboy.memory[base + 8:base + 12])

    def test_no_move_is_duplicated_and_a_natural_psychic_move_makes_room(self):
        got = self.grant(FIRST, 46, ("CONFUSION", "PSYCHIC_M", "TAIL_WHIP", "AGILITY"))
        self.assertEqual(got, [MOVES["TAIL_WHIP"], MOVES["AGILITY"], MOVES["PSYCHIC_M"], 0])
        got = self.grant(FIRST + 4, 25, ("PSYBEAM", "MEDITATE"))
        self.assertEqual(got, [MOVES["MEDITATE"], MOVES["PSYBEAM"], 0, 0])

    def test_cold_packages_still_keep_a_psychic_support_move(self):
        got = self.grant(2, 46, ("MEDITATE", "TACKLE", "BLIZZARD"))
        self.assertEqual(got, [MOVES["MEDITATE"], MOVES["TACKLE"], MOVES["MIST"], MOVES["BLIZZARD"]])

    def test_type_pair_survives_evolving_into_golduck(self):
        h = self.h
        h.load_state(self.base)
        base = h.address("wPartyMon1")
        h.pyboy.memory[base] = SPECIES["PSYDUCK"]
        h.pyboy.memory[base + 5:base + 8] = [TYPES["WATER"], TYPES["PSYCHIC_TYPE"], FLAGS]
        h.write8("wPokedexNum", SPECIES["GOLDUCK"])
        h.write8("wPredefHL", base >> 8)
        h.write8("wPredefHL", base & 255, offset=1)
        h.call_routine("SetPartyMonTypes", limit=4000)
        self.assertEqual(list(h.pyboy.memory[base + 5:base + 8]), [TYPES["WATER"], TYPES["PSYCHIC_TYPE"], FLAGS])

    def test_pink_is_neither_stage_s_shiny_or_natural_colour(self):
        names = (ROOT / "data/pokemon/palettes.asm").read_text(encoding="utf-8")
        code = (ROOT / "engine/gfx/palettes.asm").read_text(encoding="utf-8")
        table = re.search(r"ShinyPaletteMap:\s*(.*?)\n\s*\n", code.replace("\r\n", "\n"), re.S).group(1)
        shiny = dict((b, a) for a, b in re.findall(r"db (PAL_\w+)\s*; (PAL_\w+)", table))
        for species in ("PSYDUCK", "GOLDUCK"):
            natural = re.search(r"db (PAL_\w+)\s*; %s\b" % species, names).group(1)
            self.assertNotEqual(natural, "PAL_PINKMON", species)
            self.assertNotEqual(shiny[natural], "PAL_PINKMON", species)

    def test_every_ball_is_refused(self):
        h = self.h
        items = parse_rgbds_constants(ROOT / "constants/item_constants.asm")
        calls = []

        def text(_):
            calls.append(1)
            return_now(h)

        h.pyboy.hook_register(*h.symbols.get("PrintText"), text, None)
        for item, refused in (("MASTER_BALL", True), ("POKE_BALL", True), ("SAFARI_BALL", True), ("POTION", False)):
            with self.subTest(item=item):
                h.load_state(self.base)
                calls.clear()
                h.write8("hCurMap", self.maps["PROCEDURAL_FACILITY"])
                h.write8("wOptionalEncounterMap", self.maps["PROCEDURAL_FACILITY"])
                h.write8("wOptionalEncounterSpecies", SPECIES["PSYDUCK"])
                h.write8("wOptionalEncounterPackage", FIRST)
                h.write8("wCurItem", items[item])
                h.call_routine("OptionalEncounterCaptureGate")
                self.assertEqual(bool(calls), refused)
        h.pyboy.hook_deregister(*h.symbols.get("PrintText"))


class ContactRuleTest(unittest.TestCase):
    """OptionalEncounterContact itself, with the talk and the bubble answered."""

    PLAYER = (20, 20)
    SIDES = {"below": ((0, 1), DOWN, "up", UP), "above": ((0, -1), UP, "down", DOWN),
             "left": ((-1, 0), LEFT, "right", RIGHT), "right": ((1, 0), RIGHT, "left", LEFT)}

    def setUp(self):
        self.h = h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        h.park_before_hijack()
        self.maps = fs.parse_map_constants(ROOT / "constants/map_constants.asm")
        self.base = io.BytesIO()
        h.save_state(self.base)
        self.talks, self.bubbles = [], []

        def talk(_):
            self.talks.append(h.read8("hTextID"))
            return_now(h)

        def bubble(_):
            self.bubbles.append(h.read8("wEmotionBubbleSpriteIndex"))
            return_now(h)

        h.pyboy.hook_register(*h.symbols.get("DisplayTextID"), talk, None)
        h.pyboy.hook_register(*h.symbols.get("EmotionBubble"), bubble, None)
        h.pyboy.hook_register(*h.symbols.get("UpdateSprites"), lambda _: return_now(h), None)

    def run_contact(self, offset, facing, held=0, slot=SLOT, room="PROCEDURAL_FACILITY", package=FIRST,
                    state=0, status=1, setup=None):
        """offset: the player relative to it. Out: (talked, bubbled, player facing)."""
        h = self.h
        h.load_state(self.base)
        self.talks.clear()
        self.bubbles.clear()
        mx, my = self.PLAYER[0] - offset[0], self.PLAYER[1] - offset[1]
        h.write8("hCurMap", self.maps[room])
        h.write8("wOptionalEncounterMap", self.maps[room])
        h.write8("wOptionalEncounterSpecies", SPECIES["PSYDUCK"])
        h.write8("wOptionalEncounterPackage", package)
        h.write8("wOptionalEncounterState", state)
        h.write8("wProceduralCave1CurScript", 0)
        h.write8("wCurOpponent", 0)
        h.write8("hJoyIgnore", 0)
        h.write8("hSimulatedJoypadStatesIndex", 0)
        h.write8("wNumberOfWarps", 0)
        h.write8("wXCoord", self.PLAYER[0])
        h.write8("wYCoord", self.PLAYER[1])
        h.write8(f"wSprite{slot:02d}StateData2MapX", mx + 4)
        h.write8(f"wSprite{slot:02d}StateData2MapY", my + 4)
        h.write8(f"wSprite{slot:02d}StateData1FacingDirection", facing)
        h.write8(f"wSprite{slot:02d}StateData1MovementStatus", status)
        if setup:
            setup()
        h.register_hook("OptionalEncounterContact", lambda _: h.write8("hJoyHeld", held))
        h.call_routine("OptionalEncounterContact", limit=2000)
        return list(self.talks), list(self.bubbles), h.read8("wSpritePlayerStateData1FacingDirection")

    def test_any_side_any_facing_and_any_button_starts_it(self):
        for side, (offset, _, _, player) in self.SIDES.items():
            for facing in (DOWN, UP, LEFT, RIGHT):
                for held in (0, *PAD.values()):
                    with self.subTest(side=side, facing=facing, held=held):
                        self.assertEqual(self.run_contact(offset, facing, held=held), ([SLOT], [SLOT], player))

    def test_nothing_past_one_tile_or_on_a_diagonal(self):
        for offset in ((0, 2), (2, 0), (1, 1), (-1, 1), (0, 0)):
            for facing in (DOWN, UP, LEFT, RIGHT):
                with self.subTest(offset=offset, facing=facing):
                    self.assertEqual(self.run_contact(offset, facing, held=0xF0)[0], [])

    def test_the_warp_room_uses_its_own_slot(self):
        talks, bubbles, _ = self.run_contact((0, 1), DOWN, slot=3, room="PROCEDURAL_FACILITY_SUBROOM")
        self.assertEqual((talks, bubbles), ([3], [3]))

    def test_it_waits_for_a_finished_step_and_a_free_player(self):
        h = self.h
        self.assertEqual(self.run_contact((0, 1), DOWN, status=3)[0], [], "mid-step")
        self.assertEqual(self.run_contact((0, 1), DOWN, status=2)[0], [SLOT], "delayed is standing")
        self.assertEqual(self.run_contact((0, 1), DOWN, status=0x81)[0], [SLOT], "the face-player bit")
        for label, value in (("hJoyIgnore", 0xFF), ("wCurOpponent", 1), ("hSimulatedJoypadStatesIndex", 2),
                             ("wProceduralCave1CurScript", 1)):
            with self.subTest(label=label):
                self.assertEqual(self.run_contact((0, 1), DOWN, setup=lambda: h.write8(label, value))[0], [])

    def test_a_finished_or_authored_encounter_never_starts_itself(self):
        self.assertEqual(self.run_contact((0, 1), DOWN, state=2)[0], [], "defeated: the offer's turn")
        self.assertEqual(self.run_contact((0, 1), DOWN, state=4)[0], [], "resolved")
        for package in (1, 2, 3):
            self.assertEqual(self.run_contact((0, 1), DOWN, package=package)[0], [], "stays talk-only")

    def test_never_on_a_warp_tile(self):
        h = self.h

        def on_warp():
            h.write8("wNumberOfWarps", 2)
            for offset, value in enumerate((9, 9, 0, 0, self.PLAYER[1], self.PLAYER[0], 0, 0)):
                h.write8("wWarpEntries", value, offset=offset)

        self.assertEqual(self.run_contact((0, 1), DOWN, setup=on_warp)[0], [])


class FacilityPlacementTest(unittest.TestCase):
    def setUp(self):
        blockset = fs.subroom.premades.BLOCKSET.read_bytes()
        self.pieces, self.landings, _ = fs.subroom.solve_all(blockset)

    def test_the_rom_table_is_current(self):
        self.assertEqual(fs.subroom.OUT_SPOTS.read_text(encoding="utf-8"),
                         fs.subroom.generate_mon_spots(self.pieces))

    def test_every_warp_room_keeps_everything_reachable_around_the_pokemon(self):
        self.assertTrue(self.pieces)
        sub = fs.subroom
        for piece in self.pieces:
            with self.subTest(piece=piece["file"]):
                nerd, ball, mon = piece["nerd"], piece["ball"], piece["mon"]
                self.assertEqual(len({nerd, ball, mon, piece["pad"]}), 4, "two share a tile")
                self.assertIn(mon, piece["walk"])
                free = piece["walk"] - {nerd, ball, mon}
                reached = sub.flood(free, sub.neighbours(piece["pad"]))
                self.assertEqual(reached, free, "something was cut off")
                self.assertIn((nerd[0], nerd[1] + 1), reached, "the Super Nerd's talk tile")
                self.assertTrue(set(sub.neighbours(ball)) & reached, "the ball")
                self.assertTrue(set(sub.neighbours(mon)) & reached, "the Pokemon")

    def test_the_rom_places_it_on_each_room_s_proven_tile(self):
        h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        h.park_before_hijack()
        room = fs.parse_map_constants(ROOT / "constants/map_constants.asm")["PROCEDURAL_FACILITY_SUBROOM"]
        base = io.BytesIO()
        h.save_state(base)
        for index, piece in enumerate(self.pieces):
            with self.subTest(piece=piece["file"]):
                h.load_state(base)
                raw = h.read_sram_bytes("sProcFacilityGenScratch", fs.SCRATCH_PIECE + 1)
                raw[fs.SCRATCH_PIECE] = index
                h.write_sram_bytes("sProcFacilityGenScratch", raw)
                h.write8("hCurMap", room)
                h.write8("wOptionalEncounterMap", room)
                h.write8("wOptionalEncounterSpecies", SPECIES["GOLDUCK"])
                h.write8("wOptionalEncounterPackage", FIRST + 1)
                h.call_routine("OptionalEncounterPlaceFacility")
                self.assertEqual((h.read8("wSprite03StateData2MapX") - 4, h.read8("wSprite03StateData2MapY") - 4),
                                 piece["mon"])


class FacilityTripBase(unittest.TestCase):
    """Real generation, real walking and a real battle in the Facility itself."""

    harness_args: dict = {}
    mash_until = encounter.OptionalEncounterTest.mash_until

    def setUp(self):
        self.maps = fs.parse_map_constants(ROOT / "constants/map_constants.asm")
        self.h = RedRogueHarness(ROOT, ARTIFACTS, **self.harness_args)
        self.addCleanup(self.h.close)
        h = self.h
        self.level = 19
        self.context = {"force": False, "spot": None, "hold": None}

        def assign(_):  # Debug 2's fixture keys on the palette; SRAM bank 1 is open.
            h.pyboy.memory[h.address("sProcFacilityPalette")] = 1 if self.context["force"] else 0

        def spot(_):
            block = self.context["spot"]
            if block:
                base = h.address("sProcFacilityGenScratch")
                h.pyboy.memory[base + SCRATCH_X], h.pyboy.memory[base + SCRATCH_Y] = block
                h.pyboy.register_file.F = CARRY

        h.register_hook("OptionalFacilityAssignEncounter", assign)
        h.register_hook("OptionalFacilityPlaceEncounter.haveSpot", spot)
        h.register_hook("OptionalForcePink.level", lambda _: setattr(h.pyboy.register_file, "A", self.level))

        def placed(_):  # It wanders from the first frame: a held one is held from the load.
            facing = self.context["hold"]
            if facing is not None:
                h.write8(f"wSprite{SLOT}StateData2MovementByte1", 0xFF)
                h.write8("wMapSpriteData", RANGE[facing], offset=(SLOT - 1) * 2)

        h.register_hook("OptionalEncounterPlaceFacility", placed)
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        self.lobby = io.BytesIO()
        h.save_state(self.lobby)

    # Layout seeds plan_spot tries in order. New premade art reshuffles every
    # layout, so one fixed seed can lose its last usable spot near the entrance.
    PLAN_SEEDS = ((23, 201, 77, 9), (5, 9, 131, 17), (211, 40, 66, 3), (90, 180, 2, 41))

    def enter(self, force, spot=None, seed=None, hold=None):
        """seed=None means the seed plan_spot chose, else the first PLAN_SEEDS entry."""
        h = self.h
        if seed is None:
            seed = getattr(self, "plan_seed", self.PLAN_SEEDS[0])
        h.load_state(self.lobby)
        h.seed_rng(seed)
        self.context.update(force=force, spot=spot, hold=hold)
        h.preload_and_enter_wild_area(self.maps["PROCEDURAL_FACILITY"], "facility")
        h.write8("wProcFacilityWildBudget", 0)
        if hold is not None:
            h.write8(f"wSprite{SLOT}StateData1FacingDirection", hold)

    def here(self):
        return self.h.read8("wXCoord"), self.h.read8("wYCoord")

    def object_tiles(self):
        h = self.h
        tiles = set()
        for slot in range(1, SLOT):
            if h.read8(f"wSprite{slot:02d}StateData1"):
                tiles.add((h.read8(f"wSprite{slot:02d}StateData2MapX") - 4,
                           h.read8(f"wSprite{slot:02d}StateData2MapY") - 4))
        return tiles

    def cells(self):
        h = self.h
        layout = h.read_bytes("wOverworldMap", 601)
        playable = tuple(layout[81 + r * 26 + c] for r in range(20) for c in range(20))
        cells = passable(BLOCKSET.read_bytes(), playable) - self.object_tiles()
        warps = h.warp_entries()
        return cells - {(w[1], w[0]) for w in warps[FIRST_PAD_WARP:] if w[0] != PAD_NONE}

    def route(self, cells, start, goal):
        prev = {start: None}
        todo = deque([start])
        while todo:
            cur = todo.popleft()
            if cur == goal:
                break
            for dx, dy, button in ((0, -1, "up"), (0, 1, "down"), (-1, 0, "left"), (1, 0, "right")):
                nxt = (cur[0] + dx, cur[1] + dy)
                if nxt in cells and nxt not in prev:
                    prev[nxt] = (cur, button)
                    todo.append(nxt)
        self.assertIn(goal, prev, f"no route from {start} to {goal}")
        path = []
        while prev[goal]:
            goal, button = prev[goal]
            path.append(button)
        return path[::-1]

    @staticmethod
    def clear_of(tile, cells):
        """Floor that never comes beside `tile`, except the tile below it."""
        x, y = tile
        return cells - {(x, y), (x, y - 1), (x - 1, y), (x + 1, y)}

    def plan_spot(self):
        """A plain-floor block near the entrance whose quadrant tile can be approached from below.

        Plain floor only, as OptionalFacilityPlaceEncounter's own search requires
        (test_a_real_search_finds_a_valid_block). And on screen from the arrival
        tile (x -4..+5, y -4..+4): an off-screen sprite has ImageIndex $FF and the
        overworld engine never moves it, so the wander test would see one tile.
        Measured 2026-11-10: spots at dx -5 and dy -6 froze, dx -1/+1 at dy -4 wandered.

        Forced here too: the preload's roll spends RNG, and the layout must match.
        Tries each PLAN_SEEDS layout in turn and records the one used in
        self.plan_seed, which later enter() calls in the test reuse."""
        for seed in self.PLAN_SEEDS:
            self.plan_seed = seed
            found = self._plan_spot_in_current_layout()
            if found:
                return found
        self.fail("no spot near the entrance in any PLAN_SEEDS layout")

    def _plan_spot_in_current_layout(self):
        self.enter(force=True)
        cells, start = self.cells(), self.here()
        layout = self.h.read_bytes("wOverworldMap", 601)
        seen, todo = {start}, deque([start])
        while todo:
            cur = todo.popleft()
            x, y = cur
            if (x & 1 and y & 1 and (x, y + 1) in cells
                    and abs(x - start[0]) + abs(y - start[1]) >= 4
                    and -4 <= x - start[0] <= 4 and -4 <= y - start[1] <= 4
                    and layout[81 + (y // 2) * 26 + x // 2] == 0x0E):
                # The route to the tile below must not pass through it.
                try:
                    self.route(self.clear_of((x, y), cells), start, (x, y + 1))
                except AssertionError:
                    pass
                else:
                    return (x // 2, y // 2), (x, y)
            for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
                nxt = (x + dx, y + dy)
                if nxt in cells and nxt not in seen:
                    seen.add(nxt)
                    todo.append(nxt)
        return None

    def step(self, button):
        h = self.h
        before = self.here()
        h.pyboy.button_press(button)
        try:
            h.wait_until(lambda: self.here() != before, f"step {button} from {before}", 90)
        finally:
            h.pyboy.button_release(button)
        h.wait_until(lambda: h.read8("wWalkCounter") == 0, "step settles", 60)

    def walk_below(self, tile):
        h = self.h
        path = self.route(self.clear_of(tile, self.cells()), self.here(), (tile[0], tile[1] + 1))
        for button in path:
            self.step(button)
        h.tick(4)

    def bank1(self):
        h = self.h
        return h.hardware_mode != "CGB" or (h.pyboy.memory[0xFF70] & 7) in (0, 1)

    def fight(self, species, package, boxed):
        h = self.h
        base = "wBoxMon1" if boxed else "wPartyMon6"
        if not boxed:
            h.write8("wPartyCount", 5)
            h.write8("wPartySpecies", 255, offset=5)
            h.register_hook("AskName", lambda _: setattr(self, "decline_nickname", True))
        h.write8("wSpecialCollected", 0)
        h.write8("wSpecialCollected", 0, offset=1)
        boss, count = h.read8("wRoguePokemon1"), h.read8("wBattleCount")
        self.mash_until(lambda: self.bank1() and h.read8("hIsInBattle") == 1 and h.read8("wOptionalEncounterBattle") == 0
                        and h.read8("wEnemyMonCatchRate") & 8, "battle starts")
        self.assertEqual(h.read8("wEnemyMonSpecies"), SPECIES[species])
        self.assertEqual(h.read8("wEnemyMonLevel"), self.level)
        self.assertEqual(h.read8("wEnemyMonCatchRate") & 0x6C, FLAGS)
        self.assertEqual(h.read8("wEnemyMonType1"), TYPES["WATER"])
        self.assertEqual(h.read8("wEnemyMonType2"), TYPES["PSYCHIC_TYPE"])
        moves = h.read_bytes("wEnemyMonMoves", 4)
        self.assertEqual(moves[-2:], [MOVES[SUPPORT[package - FIRST]], MOVES[attack_for(self.level)]])
        self.assertEqual(len(set(moves)), 4, "a repeated move")
        self.assertTrue(all(h.read_bytes("wEnemyMonPP", 4)))
        self.assertEqual(h.read_bytes("wSpecialCollected", 2), [0, 0], "credited on sight")
        h.write8("wEnemyMonHP", 0)
        h.write8("wEnemyMonHP", 1, offset=1)

        def won():
            # This mash only ever picks move 1, and Psychic Psyduck carries Disable:
            # a disabled move 1 would leave it on "disabled!" for good.
            h.write8("wPlayerDisabledMove", 0)
            return self.bank1() and h.read8("hIsInBattle") == 0 and h.read8("wOptionalEncounterState") & 4

        self.mash_until(won, "battle -> gift", 3000)
        self.assertEqual(h.read8(base), SPECIES[species])
        self.assertEqual(h.read8(base, 7) & 0x6C, FLAGS)
        self.assertEqual(h.read_bytes(base, 2, 5), [TYPES["WATER"], TYPES["PSYCHIC_TYPE"]])
        self.assertEqual(h.read_bytes(base, 4, 8), moves)
        self.assertTrue(all(h.read_bytes(base, 4, 29)))
        low, high = h.read_bytes("wSpecialCollected", 2)
        self.assertEqual(low | high << 8, 1 << DEX["SPECIAL_PSYCHIC"])
        self.assertEqual((h.read8("wBattleCount"), h.read8("wRoguePokemon1")), (count, boss))
        self.mash_until(lambda: self.bank1() and h.read8("wOptionalEncounterScript") == 0, "its script idle")
        h.tap("b")
        h.tick(60)
        return base


class FacilityEncounterTripTest(FacilityTripBase):
    def assert_facility_runs_on(self):
        """Its dispatch and header are the Facility's again: walking and saving work."""
        h = self.h
        self.assertEqual(h.read8(f"wSprite{SLOT}StateData1"), 0, "still standing after the gift")
        self.assertEqual(h.read8("wProceduralCave1CurScript"), 0)
        self.assertEqual(h.read8("wOptionalEncounterState") & 6, 6)
        cells = self.cells()
        x, y = self.here()
        for dx, dy, button in ((0, 1, "down"), (0, -1, "up"), (-1, 0, "left"), (1, 0, "right")):
            if (x + dx, y + dy) in cells:
                self.step(button)
                break
        else:
            self.fail("boxed in after the battle")
        h.tick(4)
        # Stored high byte first, and the trainer scan walks it through the table.
        pointer = h.read8("wTrainerHeaderPtr") << 8 | h.read8("wTrainerHeaderPtr", offset=1)
        self.assertNotEqual(pointer, h.symbols.get("FGEncounterHeader")[1], "still on its own header")

    def test_it_notices_you_on_the_tile_it_faces(self):
        h = self.h
        block, tile = self.plan_spot()
        self.enter(force=True, spot=block, hold=DOWN)
        self.assertEqual(h.read8("wOptionalEncounterMap"), self.maps["PROCEDURAL_FACILITY"])
        self.assertEqual((h.read8(f"wSprite{SLOT}StateData2MapX") - 4, h.read8(f"wSprite{SLOT}StateData2MapY") - 4), tile)
        # On the first entry: the sprite is patched before generation runs.
        self.assertEqual(h.read8(f"wSprite{SLOT}StateData1"), MON_SPRITE)
        h.write8("wOptionalEncounterPackage", FIRST)
        bubbles = h.hook_flag("EmotionBubble")
        self.walk_below(tile)
        self.fight("PSYDUCK", FIRST, False)
        self.assertEqual(bubbles["count"], 1)
        self.assert_facility_runs_on()

    def test_stepping_beside_it_starts_it_with_its_back_turned(self):
        h = self.h
        self.level = 35
        block, tile = self.plan_spot()
        self.enter(force=True, spot=block, hold=UP)  # the player arrives below it
        h.write8("wOptionalEncounterPackage", FIRST + 3)
        bubbles = h.hook_flag("EmotionBubble")
        self.walk_below(tile)
        self.fight("GOLDUCK", FIRST + 3, True)
        self.assertEqual(bubbles["count"], 1)
        self.assert_facility_runs_on()

    def test_declining_resolves_it_without_a_gift(self):
        h = self.h
        block, tile = self.plan_spot()
        self.enter(force=True, spot=block, hold=DOWN)
        party, box = h.read8("wPartyCount"), h.read8("wBoxCount")
        h.register_hook("FGEncounterOffer.choiceMade", lambda _: h.write8("hCurrentMenuItem", 1))
        self.walk_below(tile)
        self.mash_until(lambda: self.bank1() and h.read8("hIsInBattle") == 1 and h.read8("wEnemyMonCatchRate") & 8, "battle")
        h.write8("wEnemyMonHP", 0)
        h.write8("wEnemyMonHP", 1, offset=1)
        self.mash_until(lambda: self.bank1() and h.read8("wOptionalEncounterState") & 4, "declined", 3000)
        self.assertEqual((h.read8("wPartyCount"), h.read8("wBoxCount")), (party, box))
        self.assertEqual(h.read8(f"wSprite{SLOT}StateData1"), 0)

    def test_no_room_still_removes_it_like_a_boss(self):
        """It wanders the corridors, so a full box must not leave it blocking one."""
        h = self.h
        block, tile = self.plan_spot()
        self.enter(force=True, spot=block, hold=DOWN)
        species = h.read8("wPartyMon1Species")
        h.write8("wBoxCount", 20)
        for i in range(20):
            h.write8("wBoxSpecies", species, offset=i)
            for j, byte in enumerate(h.read_bytes("wPartyMon1", 33)):
                h.write8("wBoxMon1", byte, offset=i * 33 + j)
        h.write8("wBoxSpecies", 255, offset=20)
        party, box = h.read8("wPartyCount"), h.read_bytes("wBoxMon1", 33 * 20)
        self.assertEqual(party, 6, "the gift would not reach the full box")
        self.walk_below(tile)
        self.mash_until(lambda: self.bank1() and h.read8("hIsInBattle") == 1 and h.read8("wEnemyMonCatchRate") & 8, "battle")
        h.write8("wEnemyMonHP", 0)
        h.write8("wEnemyMonHP", 1, offset=1)

        def resolved():
            h.write8("wPlayerDisabledMove", 0)
            return self.bank1() and h.read8("hIsInBattle") == 0 and h.read8("wOptionalEncounterState") & 4

        self.mash_until(resolved, "no room -> resolved", 3000)
        self.assertEqual(h.read8("wPartyCount"), party)
        self.assertEqual(h.read8("wBoxCount"), 20)
        self.assertEqual(h.read_bytes("wBoxMon1", 33 * 20), box)
        self.mash_until(lambda: self.bank1() and h.read8("wOptionalEncounterScript") == 0, "its script idle")
        h.tap("b")
        h.tick(60)
        self.assert_facility_runs_on()

    def test_a_reload_puts_it_back_on_its_tile_and_a_gift_keeps_it_gone(self):
        h = self.h
        block, tile = self.plan_spot()
        self.enter(force=True, spot=block, hold=DOWN)
        package = h.read8("wOptionalEncounterPackage")
        self.assertTrue(save_reload.settle(h))
        h.park_before_hijack()
        h.call_routine("SaveGameData")
        reboot = save_reload.Reboot(save_reload.sram_image(h), cgb_mode=h.hardware_mode == "CGB")
        try:
            reboot.load()
            self.assertTrue(reboot.overworld)
            self.assertTrue(save_reload.settle(reboot.h))
            self.assertEqual(reboot.h.read8(f"wSprite{SLOT}StateData1"), MON_SPRITE)
            self.assertEqual(reboot.h.read8("wOptionalEncounterPackage"), package)
        finally:
            reboot.close()
        self.walk_below(tile)
        base = self.fight("PSYDUCK", package, True)
        self.assertTrue(save_reload.settle(h))
        h.park_before_hijack()
        h.call_routine("SaveGameData")
        reboot = save_reload.Reboot(save_reload.sram_image(h), cgb_mode=h.hardware_mode == "CGB")
        try:
            reboot.load()
            self.assertTrue(save_reload.settle(reboot.h))
            self.assertEqual(reboot.h.read8(f"wSprite{SLOT}StateData1"), 0)
            self.assertEqual(reboot.h.read_bytes(base, 2, 5), [TYPES["WATER"], TYPES["PSYCHIC_TYPE"]])
            self.assertEqual(reboot.h.read8("wSpecialCollected", offset=1), 1 << (DEX["SPECIAL_PSYCHIC"] - 8))
        finally:
            reboot.close()

    def test_it_really_wanders_and_stays_on_floor_within_five_tiles(self):
        h = self.h
        block, tile = self.plan_spot()
        self.enter(force=True, spot=block)
        # Holding B is Debug's way past trainers and it alike, so a chance sighting
        # cannot end the watch early.
        h.pyboy.button_press("b")
        self.addCleanup(h.pyboy.button_release, "b")
        cells = passable(BLOCKSET.read_bytes(), tuple(
            h.read8("wOverworldMap", offset=81 + r * 26 + c) for r in range(20) for c in range(20)))
        seen = set()
        for _ in range(1800):
            h.pyboy.tick(render=False)
            self.assertEqual(h.read8("wOptionalEncounterScript"), 0, "started a battle with B held")
            at = (h.read8(f"wSprite{SLOT}StateData2MapX") - 4, h.read8(f"wSprite{SLOT}StateData2MapY") - 4)
            seen.add(at)
            self.assertIn(at, cells, "walked onto a wall")
            self.assertLessEqual(max(abs(at[0] - tile[0]), abs(at[1] - tile[1])), 5, "strayed too far")
        # Measured: about 19 steps a minute on screen, over 11 to 13 tiles in open
        # rooms. A tight spot near the entrance can hold it to a few.
        self.assertGreater(len(seen), 1, f"it never moved: {seen}")

    def test_a_real_search_finds_a_valid_block(self):
        # A seed's layout also depends on every VBlank Random draw before
        # generation, so any timing change reshuffles which layout a seed gives.
        # About 3% of Facilities have no valid block and no pad site and go
        # without (measured 2026-11-10: 3/100 and 2/100 before and after a
        # sprite-pass change that moved two of these four seeds' layouts). So
        # one seed going without is allowed; every seed that places it is checked.
        h = self.h
        placed = 0
        for seed in self.PLAN_SEEDS:
            with self.subTest(seed=seed):
                self.enter(force=True, seed=seed)
                if h.read8("wOptionalEncounterMap") != self.maps["PROCEDURAL_FACILITY"]:
                    continue
                placed += 1
                raw = h.read_sram_bytes("sProcFacilityGenScratch", SCRATCH_Y + 1)
                x, y = raw[SCRATCH_X], raw[SCRATCH_Y]
                self.assertTrue(1 <= x <= 18 and 3 <= y <= 18, (x, y))
                layout = h.read_bytes("wOverworldMap", 601)
                self.assertEqual(layout[81 + y * 26 + x], 0x0E, "not plain floor")
                self.assertNotIn((2 * x + 1, 2 * y + 1), self.object_tiles(), "shares a tile")
        self.assertGreaterEqual(placed, len(self.PLAN_SEEDS) - 1,
                                "too few seeds placed it in the Facility to be drift")


class FacilityWarpRoomFallbackTest(fs.FacilitySuperNerdTest):
    """No block in the Facility: the warp room hosts it, wandering the same."""

    mash_until = encounter.OptionalEncounterTest.mash_until

    def test_it_stands_in_the_warp_room_instead(self):
        h = self.h
        self.level = 32
        h.register_hook("OptionalFacilityAssignEncounter",
                        lambda _: h.pyboy.memory.__setitem__(h.address("sProcFacilityPalette"), 1))
        h.register_hook("OptionalFacilityPlaceEncounter.haveSpot",
                        lambda _: setattr(h.pyboy.register_file, "F", 0))
        h.register_hook("OptionalForcePink.level", lambda _: setattr(h.pyboy.register_file, "A", self.level))
        piece = self.enter_subroom()
        self.assertEqual(h.read8("wOptionalEncounterMap"), self.maps["PROCEDURAL_FACILITY_SUBROOM"])
        self.assertEqual(h.read8("wSprite03StateData1"), MON_SPRITE)
        # It has been wandering since the room loaded: stop it, then go by where it is.
        h.write8("wSprite03StateData2MovementByte1", 0xFF)
        h.write8("wMapSpriteData", RANGE[RIGHT], offset=2 * 2)
        h.write8("wSprite03StateData1FacingDirection", RIGHT)
        h.wait_until(lambda: h.read8("wSprite03StateData1MovementStatus") & 3 != 3, "its step ends", 60)
        mx, my = h.read8("wSprite03StateData2MapX") - 4, h.read8("wSprite03StateData2MapY") - 4
        start = piece["mon"]
        self.assertLessEqual(max(abs(mx - start[0]), abs(my - start[1])), 5, "strayed from its proven tile")
        self.assertIn((mx, my), piece["walk"], "walked onto a wall")
        piece = dict(piece, mon=(mx, my))
        h.write8("wOptionalEncounterPackage", FIRST + 3)
        # Standing on ANY tile beside it starts the battle (OptionalEncounterContact),
        # so the route has to end at the first one it reaches: a path to a
        # farther side would stop at a nearer one and wait out the contact text.
        beside = {(mx + dx, my + dy): b for b, (dx, dy) in
                  (("up", (0, 1)), ("down", (0, -1)), ("left", (1, 0)), ("right", (-1, 0)))}
        free = piece["walk"] - {piece["nerd"], piece["ball"], (mx, my)} - self.taken
        here = (h.read8("wXCoord"), h.read8("wYCoord"))
        seen, todo, spot = {here}, [here], None
        while todo and spot is None:
            x, y = todo.pop(0)
            for there in ((x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y)):
                if there in free and there not in seen:
                    seen.add(there)
                    todo.append(there)
                    if there in beside:
                        spot = there
                        break
        if spot is None:
            self.fail(f"{piece['file']}: nowhere to stand beside it")
        button = beside[spot]
        self.taken = self.taken | (set(beside) - {spot})
        self.walk_to(piece, spot)
        h.pyboy.button_press(button)
        try:
            self.mash_until(lambda: h.read8("hIsInBattle") == 1 and h.read8("wEnemyMonCatchRate") & 8, "battle")
        finally:
            h.pyboy.button_release(button)
        self.assertEqual(h.read8("wEnemyMonSpecies"), SPECIES["PSYDUCK"])
        moves = h.read_bytes("wEnemyMonMoves", 4)
        self.assertEqual(moves[-2:], [MOVES["KINESIS"], MOVES["PSYBEAM"]])
        h.write8("wEnemyMonHP", 0)
        h.write8("wEnemyMonHP", 1, offset=1)
        self.mash_until(lambda: h.read8("hIsInBattle") == 0 and h.read8("wOptionalEncounterState") & 4, "gift", 3000)
        self.assertEqual(h.read8("wBoxMon1"), SPECIES["PSYDUCK"])
        self.assertEqual(h.read_bytes("wBoxMon1", 2, 5), [TYPES["WATER"], TYPES["PSYCHIC_TYPE"]])


for _name in dir(fs.FacilitySuperNerdTest):
    if _name.startswith("test_"):
        setattr(FacilityWarpRoomFallbackTest, _name, None)


if __name__ == "__main__":
    unittest.main()
