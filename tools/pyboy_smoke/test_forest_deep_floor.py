"""The Forest's deep floor (PROCEDURAL_DEEP_FLOOR_PLAN.md, Forest SPEC).

F0-F4 (Opus): the lobby decision, the flip between floors through the arrival
seam, floor 2's fresh state and generation, and the per-floor post-pass. The
trips use the engine's scripted-warp path (BIT_WARP_FROM_CUR_SCRIPT ->
WarpFound2), identical to a stepped-on warp from WarpFound2 on; walking the real
edge openings belongs to F8.
"""

from __future__ import annotations

import io
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
FOREST = MAPS["PROCEDURAL_FOREST"]
GROTTO = MAPS["PROCEDURAL_FOREST_GROTTO"]
TOGGLES = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
MAP_SIZE, STATE_SIZE = 400, 102
CTRL = MAP_SIZE + STATE_SIZE              # offset of the control word in region A
MAGIC, MAGIC_MASK = 0xC0, 0xE0
LIVE_2, MADE, HOUSE_2, BALLS_2, OPENING_2 = 0x01, 0x02, 0x04, 0x08, 0x10
FACING = {"N": "S", "W": "E", "E": "W"}   # floor 1's opening wall -> floor 2's
FLOOR_BIT = 0x80
FG_WARP, SECOND_WARP, FIRST_HOUSE_WARP = 31, 3, 3
ENTRANCE = (18, 35)
HOUSE_MASK = 0x1F
OFFERS = 17                               # wroguenpctradegive..wroguenpcclass


def wall(tile) -> str:
    """The map edge a warp tile (Y, X) of a 40x40-tile Forest sits on."""
    y, x = tile
    return "N" if y == 0 else "S" if y == 39 else "W" if x == 0 else "E" if x == 39 else "?"


class ForestDeepFloorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.h.allow_deep_forest_floor = True

    def tearDown(self) -> None:
        self.h.close()

    # --- state ---------------------------------------------------------
    def ctrl(self) -> list[int]:
        return self.h.read_sram_bytes("sProcCaveStagingBuffer", CTRL + 2, bank=0)[CTRL:]

    def live(self) -> tuple[bytes, bytes]:
        h = self.h
        return (bytes(h.read_sram_bytes("sProcForestStagingBuffer", MAP_SIZE, bank=0)),
                bytes(h.read_sram_bytes("sProcForestExitI", STATE_SIZE, bank=0)))

    def shadow(self) -> tuple[bytes, bytes]:
        raw = bytes(self.h.read_sram_bytes("sProcCaveStagingBuffer", MAP_SIZE + STATE_SIZE, bank=0))
        return raw[:MAP_SIZE], raw[MAP_SIZE:]

    def balls2(self) -> bool:
        return bool(self.ctrl()[0] & BALLS_2)

    def floor(self) -> int:
        return 2 if self.h.read8("wRogueFlagsBitfield2") & FLOOR_BIT else 1

    def house_site(self) -> int:
        return self.h.read_sram_bytes("sProcForestItemGot", 1, bank=0)[0] & HOUSE_MASK

    # --- fixtures --------------------------------------------------------
    def deep_forest(self, house_on_2: bool | None = None, balls_2: bool | None = None) -> None:
        """A fresh deep Forest, player on its entrance. house_on_2 and balls_2
        force the coin's bits (the house's floor, floor 2's second ball)."""
        h = self.h
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        if house_on_2 is not None or balls_2 is not None:
            def coin(_context) -> None:
                b = h.pyboy.register_file.B
                for want, bit in ((house_on_2, HOUSE_2), (balls_2, BALLS_2)):
                    if want is not None:
                        b = (b | bit) if want else (b & ~bit & 0xFF)
                h.pyboy.register_file.B = b
            h.register_hook("ForestDeepLobbyDecide.haveCtrl", coin)
        h.preload_and_enter_wild_area(FOREST, "forest")
        h.write8("wProcForestWildBudget", 0)
        h.wait_until(lambda: (h.read8("wXCoord"), h.read8("wYCoord")) == ENTRANCE, "on the entrance", 600)
        h.tick(30)

    def scripted_warp(self, warp: int, description: str, zero_budget: bool = True) -> None:
        h = self.h
        h.write8("hWarpDestinationMap", FOREST)
        h.write8("wDestinationWarpID", warp)
        h.write8("wStatusFlags3", h.read8("wStatusFlags3") | 1 << 3)   # BIT_WARP_FROM_CUR_SCRIPT
        seen = h.hook_flag("WarpFound2")
        h.wait_until(lambda: seen["count"] > 0, f"{description}: the warp", 300)
        h.wait_until(lambda: h.read8("hCurMap") == FOREST and h.read8("hJoyIgnore") == 0,
                     f"{description}: settled", 900)
        h.tick(120)
        if zero_budget:
            h.write8("wProcForestWildBudget", 0)

    def toggle_bit(self, name: str) -> int:
        n = TOGGLES[name]
        return self.h.read8("wToggleableObjectFlags", offset=n // 8) >> n % 8 & 1

    def encounter_on_deep_forest(self, species: str = "ONIX") -> None:
        """A deep Forest whose lobby rolled a cold encounter for the grotto (which
        the decision then moves to the Forest's floor 2)."""
        from test_optional_cold_moves import SPECIES
        h = self.h

        def assign(_context) -> None:
            h.write8("wOptionalEncounterSpecies", SPECIES[species])
            h.write8("wOptionalEncounterPackage", 2)
            h.write8("wOptionalEncounterLevel", 30)
            h.write8("wOptionalEncounterState", 0)
            h.write8("wOptionalEncounterScript", 0)
            h.write8("wOptionalEncounterMap", GROTTO)

        h.register_hook("ForestDeepLobbyDecide", assign)
        self.deep_forest(house_on_2=False)   # a house on floor 2 rerolls its toggles, by design

    # --- tests -----------------------------------------------------------
    def test_lobby_decides_and_resets(self) -> None:
        """Handoff check: a deep Forest's control word, floor 1, ball shown, and
        the grotto's encounter (if any) moved to the Forest; with the harness's
        default the same preload decides ordinary."""
        h = self.h
        self.deep_forest()
        ctrl = self.ctrl()
        self.assertEqual(ctrl[0] ^ ctrl[1], 0xFF, f"control pair {ctrl}")
        self.assertEqual(ctrl[0] & MAGIC_MASK, MAGIC, "not decided deep")
        self.assertEqual(ctrl[0] & (LIVE_2 | MADE | OPENING_2), 0)
        self.assertEqual(self.floor(), 1)
        self.assertEqual(h.read8("wStatusFlags2") & 0x40, 0, "floor 2's ball starts taken")
        self.assertNotEqual(h.read8("wOptionalEncounterMap"), GROTTO, "the grotto kept its encounter")
        # Floor 1 has its way down: its opening, aimed at this map's opening warps.
        warps = h.warp_entries()
        self.assertNotEqual(warps[FG_WARP][0], 0xFF, "no opening on a deep Forest")
        self.assertEqual(warps[FG_WARP][2:], [FG_WARP, FOREST])
        self.assertEqual(warps[SECOND_WARP][2:], [SECOND_WARP, FOREST])

        ordinary = RedRogueHarness(ROOT, ARTIFACTS)
        try:
            ordinary.boot_to_lobby(battle_count=11, encounter_kind=4)
            ordinary.write8("wStageEvent", 0)
            ordinary.preload_and_enter_wild_area(FOREST, "forest")
            raw = ordinary.read_sram_bytes("sProcCaveStagingBuffer", CTRL + 2, bank=0)[CTRL:]
            self.assertEqual(raw, [0x00, 0xFF], "the harness's default Forest is not ordinary")
        finally:
            ordinary.close()

    def round_trip(self, house_on_2: bool) -> None:
        h = self.h
        self.deep_forest(house_on_2)
        floor1 = self.live()
        floor1_house = self.house_site()
        opening = h.warp_entries()[FG_WARP][:2]                 # (Y, X)
        offers = h.read_bytes("wroguenpctradegive", OFFERS)
        if house_on_2:
            self.assertEqual(floor1_house, 0, "floor 1 kept the house the coin gave floor 2")
        else:
            self.assertNotEqual(floor1_house, 0, "floor 1 has no house")

        self.scripted_warp(FG_WARP, "down")
        self.assertEqual(self.floor(), 2)
        ctrl = self.ctrl()[0]
        self.assertEqual(ctrl & (LIVE_2 | MADE | OPENING_2), LIVE_2 | MADE | OPENING_2, f"ctrl {ctrl:02x}")
        # Like the grotto: out of floor 1's opening, in at floor 2's, on the facing wall.
        warps = h.warp_entries()
        here = [h.read8("wYCoord"), h.read8("wXCoord")]
        self.assertEqual(here, warps[FG_WARP][:2], "not on floor 2's opening")
        self.assertEqual(wall(warps[FG_WARP][:2]), FACING[wall(opening)],
                         f"floor 1's opening {opening}, floor 2's {warps[FG_WARP][:2]}")
        self.assertEqual(self.shadow(), floor1, "floor 1 is not in the shadow")
        floor2 = self.live()
        self.assertNotEqual(floor2[0], floor1[0], "floor 2 is floor 1's map")
        self.assertEqual(h.read_sram_bytes("sProcForestBaked", 1, bank=0)[0], 1, "floor 2 not baked")
        if house_on_2:
            self.assertNotEqual(self.house_site(), 0, "floor 2 has no house")
        else:
            self.assertEqual(self.house_site(), 0, "floor 2 kept a house the coin gave floor 1")
            self.assertEqual(h.read_bytes("wroguenpctradegive", OFFERS), offers,
                             "floor 2's generation rerolled floor 1's house offers")
        self.assertEqual((warps[1][0], warps[2][0]), (0xFF, 0xFF), "floor 2's exit is still open")
        self.assertEqual(warps[FG_WARP][2:], [FG_WARP, FOREST], "floor 2's opening does not lead up")
        self.assertEqual(warps[SECOND_WARP][2:], [SECOND_WARP, FOREST])
        for slot in (1, 4, 5, 6, 7) if self.balls2() else (1, 3, 4, 5, 6, 7):
            self.assertEqual((h.read8(f"wSprite{slot:02d}StateData2MapY"),
                              h.read8(f"wSprite{slot:02d}StateData2MapX")), (0, 0), f"slot {slot} not parked")

        self.scripted_warp(FG_WARP, "up")
        self.assertEqual(self.floor(), 1)
        self.assertEqual((h.read8("wYCoord"), h.read8("wXCoord")), tuple(opening), "not on floor 1's opening")
        self.assertEqual(self.live(), floor1, "floor 1 changed")
        self.assertEqual(self.shadow(), floor2, "floor 2 is not in the shadow")
        self.assertEqual(self.ctrl()[0] & LIVE_2, 0)

        self.scripted_warp(FG_WARP, "down again")
        self.assertEqual(self.live(), floor2, "the second descent regenerated floor 2")
        self.assertEqual([h.read8("wYCoord"), h.read8("wXCoord")], h.warp_entries()[FG_WARP][:2],
                         "the second descent did not land on floor 2's opening")

    def test_north_opening_pairs_with_floor_2_south(self) -> None:
        """Floor 1 leaves north, so floor 2's opening is carved on its south edge
        (block 89 over a connector, a deep Forest's own case), the player lands on
        it, and climbs back out of floor 1's north opening."""
        h = self.h
        forced = {"edge": False}

        def exit_west(_context) -> None:
            if not forced["edge"]:                # floor 1's generation only
                forced["edge"] = True
                h.write_sram_bytes("sProcForestExitEdge", [1], bank=0)

        def try_north(_context) -> None:
            if h.read8("wRogueFlagsBitfield2") & FLOOR_BIT == 0 and not forced.get("wall"):
                forced["wall"] = True
                h.pyboy.register_file.A = 0

        h.register_hook("PFinalizeForest", exit_west)
        h.register_hook("FGTryWall", try_north)
        self.deep_forest()
        opening = h.warp_entries()[FG_WARP][:2]
        self.assertEqual(wall(opening), "N", f"floor 1's opening {opening} is not north")
        self.scripted_warp(FG_WARP, "down")
        warps = h.warp_entries()
        self.assertEqual(wall(warps[FG_WARP][:2]), "S", f"floor 2's opening {warps[FG_WARP][:2]}")
        self.assertEqual([h.read8("wYCoord"), h.read8("wXCoord")], warps[FG_WARP][:2])
        y, x = warps[FG_WARP][:2]
        live = self.live()[0]
        self.assertEqual((live[19 * 20 + x // 2], live[18 * 20 + x // 2]), (89, 27),
                         "floor 2's south opening is not block 89 over a connector")
        self.assertEqual(warps[SECOND_WARP][:2], [y, x + 1], "the second tile is not beside the first")
        self.scripted_warp(FG_WARP, "up")
        self.assertEqual(self.floor(), 1)
        self.assertEqual([h.read8("wYCoord"), h.read8("wXCoord")], opening)

    def test_round_trip_house_on_floor_1(self) -> None:
        self.round_trip(house_on_2=False)

    def test_round_trip_house_on_floor_2(self) -> None:
        self.round_trip(house_on_2=True)

    def test_floor_2_hosts_the_encounter_and_hides_the_rest(self) -> None:
        """F5-F7: the encounter stands on floor 2 only (picture 0 on floor 1), on
        ball 4's dead end, with its own sheet; floor 1's boss, balls 2-4 and stage
        NPCs have no picture there; floor 2's one ball is shown, and its first
        entry did not re-show or hide anything on floor 1."""
        import test_optional_encounter as encounter
        h = self.h
        self.encounter_on_deep_forest()
        self.assertEqual(h.read8("wOptionalEncounterMap"), FOREST, "the encounter did not move to the Forest")
        self.assertEqual(h.read8("wSprite08StateData1"), 0, "the encounter shows on floor 1")
        self.assertNotEqual(h.read8("wSprite01StateData1"), 0, "floor 1 lost its boss picture")
        for name in ("TOGGLE_WILD_AREA_POKEBALL_2", "TOGGLE_WILD_AREA_BOSS"):  # taken / beaten on floor 1
            n = TOGGLES[name]
            h.write8("wToggleableObjectFlags", h.read8("wToggleableObjectFlags", offset=n // 8) | 1 << n % 8,
                     offset=n // 8)
        toggles = h.read_bytes("wToggleableObjectFlags", 32)

        self.scripted_warp(FG_WARP, "down")
        self.assertEqual(self.floor(), 2)
        self.assertEqual(h.read8("wSprite08StateData1"), encounter.optional_sprite(h), "no encounter picture")
        ball = h.read_sram_bytes("sProcForestBallXY", 8, bank=0)
        self.assertEqual((h.read8("wSprite08StateData2MapY"), h.read8("wSprite08StateData2MapX")),
                         (ball[6], ball[7]), "the encounter is not on ball 4's dead end")
        for slot in (1, 4, 5, 6, 7) if self.balls2() else (1, 3, 4, 5, 6, 7):
            self.assertEqual(h.read8(f"wSprite{slot:02d}StateData1"), 0, f"slot {slot} still has a picture")
        self.assertNotEqual(h.read8("wSprite02StateData1"), 0, "floor 2's ball has no picture")
        self.assertEqual(self.toggle_bit("TOGGLE_WILD_AREA_POKEBALL_1"), 0, "floor 2's ball is hidden")
        # Ball 2 is per floor: floor 1's was taken, floor 2's is its own and shown.
        self.assertEqual(self.toggle_bit("TOGGLE_WILD_AREA_POKEBALL_2"), 0, "floor 2 took floor 1's ball 2")
        after = h.read_bytes("wToggleableObjectFlags", 32)
        per_floor = {TOGGLES["TOGGLE_WILD_AREA_POKEBALL_1"], TOGGLES["TOGGLE_WILD_AREA_POKEBALL_2"]}
        for i in range(32 * 8):
            if i not in per_floor:
                self.assertEqual(after[i // 8] >> i % 8 & 1, toggles[i // 8] >> i % 8 & 1,
                                 f"floor 2's first entry changed toggle ${i:02x}")
        self.assertEqual(h.read8("wOptionalEncounterState") & 4, 0, "the encounter reads as resolved")

        self.scripted_warp(FG_WARP, "up")
        self.assertEqual(self.toggle_bit("TOGGLE_WILD_AREA_POKEBALL_2"), 1, "floor 1's taken ball 2 came back")
        self.assertEqual(h.read8("wSprite08StateData1"), 0, "the encounter followed the player up")
        self.assertNotEqual(h.read8("wSprite01StateData1"), 0, "floor 1's boss is gone after the trip")

    def generic_on_floor(self, floor: int) -> None:
        """A deep Forest whose generic trainer is rolled onto floor ordinal `floor`
        (0 = floor 1, 1 = floor 2) at ForestGenericRoll.floor."""
        h = self.h

        def force(_context) -> None:
            h.pyboy.register_file.A = floor

        h.register_hook("ForestGenericRoll.floor", force)
        try:
            self.deep_forest(house_on_2=False)
        finally:
            h.unregister_hook("ForestGenericRoll.floor", force)

    def test_generic_trainer_on_floor_2_only(self) -> None:
        """A2: rolled onto floor 2 he is absent from floor 1, stands on floor 2's own
        dead end with his class, and is absent again back on floor 1."""
        h = self.h
        self.generic_on_floor(1)
        self.assertEqual(h.read8("wSprite09StateData1"), 0, "he is on floor 1 too")
        self.assertEqual((h.read8("wSprite09StateData2MapY"), h.read8("wSprite09StateData2MapX")), (0, 0))
        self.scripted_warp(FG_WARP, "down")
        self.assertEqual(self.floor(), 2)
        picture = h.read8("wSprite09StateData1")
        cell = (h.read8("wSprite09StateData2MapY"), h.read8("wSprite09StateData2MapX"))
        self.assertNotEqual(picture, 0, "no generic trainer on floor 2")
        self.assertNotEqual(cell, (0, 0))
        self.assertNotEqual(h.read8("wMapSpriteExtraData", offset=8 * 2), 0, "no class")
        self.scripted_warp(FG_WARP, "up")
        self.assertEqual(h.read8("wSprite09StateData1"), 0, "he followed the player up")
        self.scripted_warp(FG_WARP, "down")
        self.assertEqual(h.read8("wSprite09StateData1"), picture)
        self.assertEqual((h.read8("wSprite09StateData2MapY"), h.read8("wSprite09StateData2MapX")), cell,
                         "floor 2's second visit moved him")

    def test_generic_trainer_stays_on_floor_1(self) -> None:
        """Rolled onto floor 1, the route trainer (object 9) belongs to it: picture 0
        and parked on floor 2, and back on the same cell, class and flag after the
        round trip."""
        h = self.h
        self.generic_on_floor(0)
        picture = h.read8("wSprite09StateData1")
        cell = (h.read8("wSprite09StateData2MapY"), h.read8("wSprite09StateData2MapX"))
        self.assertNotEqual(picture, 0, "no generic trainer on floor 1")
        self.assertNotEqual(cell, (0, 0))
        extra = h.read_bytes("wMapSpriteExtraData", 2, offset=8 * 2)
        self.scripted_warp(FG_WARP, "down")
        self.assertEqual(self.floor(), 2)
        self.assertEqual(h.read8("wSprite09StateData1"), 0, "he followed the player down")
        self.assertEqual((h.read8("wSprite09StateData2MapY"), h.read8("wSprite09StateData2MapX")), (0, 0))
        self.scripted_warp(FG_WARP, "up")
        self.assertEqual(h.read8("wSprite09StateData1"), picture)
        self.assertEqual((h.read8("wSprite09StateData2MapY"), h.read8("wSprite09StateData2MapX")), cell)
        self.assertEqual(h.read_bytes("wMapSpriteExtraData", 2, offset=8 * 2), extra)

    def test_second_ball_is_per_floor(self) -> None:
        """D1: a two-ball floor 2 shows ball 2 on its own dead end; taking it
        there leaves floor 1's ball 2 as it was, and it stays taken."""
        h = self.h
        self.deep_forest(house_on_2=False, balls_2=True)
        self.scripted_warp(FG_WARP, "down")
        self.assertTrue(self.balls2())
        pos = lambda s: (h.read8(f"wSprite{s:02d}StateData2MapY"), h.read8(f"wSprite{s:02d}StateData2MapX"))
        self.assertNotEqual(h.read8("wSprite03StateData1"), 0, "floor 2's second ball has no picture")
        self.assertNotEqual(pos(3), (0, 0), "floor 2's second ball is parked")
        self.assertNotIn(pos(3), {pos(2), pos(8)}, "floor 2's second ball shares a cell")
        self.assertEqual(self.toggle_bit("TOGGLE_WILD_AREA_POKEBALL_2"), 0, "floor 2's ball 2 starts taken")
        n = TOGGLES["TOGGLE_WILD_AREA_POKEBALL_2"]
        h.write8("wToggleableObjectFlags", h.read8("wToggleableObjectFlags", offset=n // 8) | 1 << n % 8,
                 offset=n // 8)                                    # taken on floor 2
        self.scripted_warp(FG_WARP, "up")
        self.assertEqual(self.toggle_bit("TOGGLE_WILD_AREA_POKEBALL_2"), 0, "floor 1's ball 2 took floor 2's")
        self.assertTrue(h.read8("wStatusFlags2") & 0x80, "floor 2's taken ball 2 was not kept")
        self.scripted_warp(FG_WARP, "down")
        self.assertEqual(self.toggle_bit("TOGGLE_WILD_AREA_POKEBALL_2"), 1, "floor 2's ball 2 came back")

    def test_one_ball_floor_removes_ball_2(self) -> None:
        h = self.h
        self.deep_forest(house_on_2=False, balls_2=False)
        self.scripted_warp(FG_WARP, "down")
        self.assertFalse(self.balls2())
        self.assertEqual(h.read8("wSprite03StateData1"), 0, "a one-ball floor 2 shows ball 2")
        self.assertEqual((h.read8("wSprite03StateData2MapY"), h.read8("wSprite03StateData2MapX")), (0, 0))

    def test_no_encounter_leaves_floor_2_empty(self) -> None:
        h = self.h
        self.deep_forest()
        h.write8("wOptionalEncounterMap", 0)
        h.write8("wOptionalEncounterPackage", 0)
        self.scripted_warp(FG_WARP, "down")
        self.assertEqual(h.read8("wSprite08StateData1"), 0, "an encounter stands on floor 2 with none assigned")

    def test_follower_spawns_on_the_arrival_after_the_first_descent(self) -> None:
        """The first descent generates floor 2 in the seam, where
        PFRestageEventSprites can run InitMapSprites (and FollowerPrepareMap)
        before FGResolveArrival places the player. The follower must still spawn
        on the arrival, then trail the player by one tile."""
        h = self.h
        self.deep_forest(house_on_2=False)
        self.assertNotEqual(h.read8("wSprite15StateData1PictureID"), 0, "no follower to check")
        for step in ("up", "left"):
            h.move_tile(step)
            h.tick(20)
        def positions():
            return ((h.read8("wYCoord"), h.read8("wXCoord")),
                    (h.read8("wSprite15StateData2MapY") - 4, h.read8("wSprite15StateData2MapX") - 4))

        for trip in ("down", "up", "down again"):
            self.scripted_warp(FG_WARP, trip)
            player, follower = positions()
            self.assertEqual(follower, player, f"{trip}: the follower spawned away from the arrival")
        # On floor 2: one accepted step that stays on floor 2, and it trails by one.
        for step in ("up", "down", "left", "right"):
            before, _ = positions()
            h.move_tile(step)
            h.tick(20)
            player, follower = positions()
            if player != before and self.floor() == 2:
                self.assertEqual(abs(follower[0] - player[0]) + abs(follower[1] - player[1]), 1,
                                 f"the follower is not one tile behind after {step}: {follower} vs {player}")
                break
        else:
            self.fail("no accepted step on floor 2")

    def test_the_run_state_survives_a_floor_2_generation(self) -> None:
        """What floor 2's finalize rerolls and the descent must give back: the
        boss form and the wild-battle budget (the no-restore mutation only failed
        through the house offers). wRoguePokemon1 itself is re-read from the SRAM
        boss species on every load, so it is checked against that."""
        h = self.h
        self.deep_forest(house_on_2=False)
        species = h.read_sram_bytes("sProcForestBossSpecies", 1, bank=0)[0]
        h.write8("wRoguePokemonForm1", 0x05)
        h.write8("wProcForestWildBudget", 77)
        self.scripted_warp(FG_WARP, "down", zero_budget=False)
        self.assertEqual(self.floor(), 2)
        for label, want in (("wRoguePokemon1", species), ("wRoguePokemonForm1", 0x05), ("wProcForestWildBudget", 77)):
            self.assertEqual(h.read8(label), want, f"floor 2's generation changed {label}")
        self.scripted_warp(FG_WARP, "up", zero_budget=False)
        for label, want in (("wRoguePokemon1", species), ("wRoguePokemonForm1", 0x05), ("wProcForestWildBudget", 77)):
            self.assertEqual(h.read8(label), want, f"the climb changed {label}")

    def test_sign_text_is_true_on_floor_1(self) -> None:
        """The sign speaks for the whole forest: its house may be on floor 2, and
        floor 2 has no boss, so neither line may say otherwise. Step up from the
        entrance and read it."""
        h = self.h
        lines = {0: "in this forest", 1: "this forest"}
        self.deep_forest()
        variant = h.read_sram_bytes("sProcForestSignVariant", 1, bank=0)[0]
        self.assertIn(variant, lines)
        sign_y, sign_x = h.read_bytes("wSignCoords", 2)      # 32 or 33: patched per placed block
        self.assertEqual(sign_x, ENTRANCE[0], "the sign is not above the entrance")
        while h.read8("wYCoord") > sign_y + 1:
            y = h.read8("wYCoord")
            h.tap("up", 4)
            h.wait_until(lambda: (h.read8("wYCoord"), h.read8("hJoyIgnore")) == (y - 1, 0), "a step up", 300)
        h.tick(10)
        h.tap("a", 4)
        h.tick(80)
        text = []
        for tile in h.read_bytes("wTileMap", 360):
            text.append(chr(ord("A") + tile - 0x80) if 0x80 <= tile <= 0x99
                        else chr(ord("a") + tile - 0xA0) if 0xA0 <= tile <= 0xB9 else " ")
        text = "".join(text)
        self.assertIn(lines[variant], text, f"sign: {text.split()!r}")
        self.assertIn("REST HOUSE" if variant == 0 else "guards", text)


# The CGB run of these tests is test_cgb_forest_deep_floor.py: the smoke runner
# picks a worker's hardware from the module name.


if __name__ == "__main__":
    unittest.main()
