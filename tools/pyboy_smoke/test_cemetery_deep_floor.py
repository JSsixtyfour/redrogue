"""The Cemetery's two extra floors (PROCEDURAL_DEEP_FLOOR_PLAN.md, Cemetery SPEC).

C0-C3 (Opus): the decision, the seam, the reconcile and exchange, and the two
retargeted stairs. Each stair is taken through the live map's own warp entry
(so a retarget is exercised, not bypassed), with the engine's scripted-warp
path. That path does not set wWarpedFromWhichWarp (it is computed from a
stepped-on warp), so the test supplies the stair it took at the seam's entry.
"""

from __future__ import annotations

import io
import unittest
from pathlib import Path

import save_reload
from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
TOGGLES = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
SPRITES = parse_rgbds_constants(ROOT / "constants/sprite_constants.asm")
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
CEM = {n: MAPS[f"PROCEDURAL_CEMETERY_{n}"] for n in (1, 2, 3, 4)}
FLOOR = {v: k for k, v in CEM.items()}
ROUND = parse_rgbds_constants(ROOT / "constants/round_constants.asm")
MAGIC, MAGIC_MASK, LIVE_2B, LIVE_3B = 0x80, 0xE0, 0x01, 0x02
GOT_2B, GOT_3B = 0x04, 0x08            # CEM_DEEP_SHADOW_BITS: that b floor has no ball
MAP_SIZE = 90
FLOOR_BIT = 0x80
EAST, WEST = (9, 18), (9, 3)          # a stair's (Y, X)


class CemeteryDeepFloorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.h.allow_deep_cemetery_floor = True

    def tearDown(self) -> None:
        self.h.close()

    # --- state -----------------------------------------------------------
    def ctrl(self) -> list[int]:
        return self.h.read_sram_bytes("sProcCaveStagingBuffer", 2, bank=0)

    def floor_map(self, n: int) -> bytes:
        return bytes(self.h.read_sram_bytes("sProcCemeteryMaps", 4 * MAP_SIZE, bank=0)
                     [(n - 1) * MAP_SIZE:n * MAP_SIZE])

    def on_b(self) -> bool:
        return bool(self.h.read8("wRogueFlagsBitfield2") & FLOOR_BIT)

    def where(self) -> tuple[int, bool]:
        return FLOOR[self.h.read8("hCurMap")], self.on_b()

    # --- fixtures --------------------------------------------------------
    def enter(self, battle_count: int = 41, balls: int | None = None) -> None:
        """balls forces the b floors' ball coin: 0 both keep one, GOT_2B 2b has
        none, GOT_3B 3b has none (CemDeepLobbyDecide.balls, register c)."""
        h = self.h
        if balls is not None:
            def coin(_context) -> None:
                h.pyboy.register_file.C = balls
            h.register_hook("CemDeepLobbyDecide.balls", coin)
        h.boot_to_lobby(battle_count=battle_count, encounter_kind=4)
        h.write8("wStageEvent", 0)
        h.preload_and_enter_wild_area(CEM[1], "cemetery")
        h.wait_until(lambda: h.read8("hJoyIgnore") == 0, "settled", 900)
        h.tick(60)
        h.write8("wProcCemWildBudget", 0)

    def stair(self, entry: int, description: str) -> None:
        """Take the live map's warp entry `entry` as if stepped on."""
        h = self.h
        src = h.read8("hCurMap")
        y, x, warp, dest = h.warp_entries()[entry]
        script = h.hook_flag(f"ProceduralCemetery{FLOOR[src]}_Script")
        h.wait_until(lambda: script["count"] > 0 and h.read8("hJoyIgnore") == 0,
                     f"{description}: the map script runs", 900)

        def took(_context) -> None:
            h.write8("wWarpedFromWhichWarp", entry)
        h.register_hook("CemDeepSeam", took)
        try:
            h.write8("hWarpDestinationMap", dest)
            h.write8("wDestinationWarpID", warp)
            h.write8("wStatusFlags3", h.read8("wStatusFlags3") | 1 << 3)   # BIT_WARP_FROM_CUR_SCRIPT
            seen = h.hook_flag("WarpFound2")
            # hCurMap and hJoyIgnore read "arrived" before the arrival code has
            # run (measured: the seam ran after a wait on them alone returned),
            # so wait for the Cemetery load itself, which follows the seam.
            loaded = h.hook_flag("CemDeepFinalizeMap")
            h.wait_until(lambda: seen["count"] > 0, f"{description}: the warp", 300)
            h.wait_until(lambda: loaded["count"] > 0, f"{description}: the floor loads", 1500)
            h.wait_until(lambda: h.read8("hCurMap") == dest and h.read8("hJoyIgnore") == 0,
                         f"{description}: settled", 1500)
        finally:
            h.unregister_hook("CemDeepSeam", took)
        h.tick(60)
        h.write8("wProcCemWildBudget", 0)
        self.assertEqual((h.read8("wYCoord"), h.read8("wXCoord")), tuple(h.warp_entries()[warp][:2]),
                         f"{description}: not on the arrival stair")

    # --- tests -----------------------------------------------------------
    def test_decided_deep_from_round_5_only(self) -> None:
        h = self.h
        self.enter(battle_count=4 * ROUND["ROUND_BATTLES"])
        ctrl = self.ctrl()
        self.assertEqual(ctrl[0] ^ ctrl[1], 0xFF, f"control pair {ctrl}")
        self.assertEqual(ctrl[0] & (MAGIC_MASK | LIVE_2B | LIVE_3B), MAGIC, f"control {ctrl[0]:02x}")
        self.assertFalse(self.on_b())
        early = RedRogueHarness(ROOT, ARTIFACTS)
        try:
            early.allow_deep_cemetery_floor = True
            early.boot_to_lobby(battle_count=4 * ROUND["ROUND_BATTLES"] - 1, encounter_kind=4)
            early.write8("wStageEvent", 0)
            early.preload_and_enter_wild_area(CEM[1], "cemetery")
            self.assertEqual(early.read_sram_bytes("sProcCaveStagingBuffer", 2, bank=0), [0x00, 0xFF],
                             "round 4 decided deep")
        finally:
            early.close()
        default = RedRogueHarness(ROOT, ARTIFACTS)
        try:
            default.boot_to_lobby(battle_count=41, encounter_kind=4)
            default.write8("wStageEvent", 0)
            default.preload_and_enter_wild_area(CEM[1], "cemetery")
            self.assertEqual(default.read_sram_bytes("sProcCaveStagingBuffer", 2, bank=0), [0x00, 0xFF],
                             "the harness's default Cemetery is not ordinary")
        finally:
            default.close()

    def test_the_chain_down_and_back(self) -> None:
        h = self.h
        self.enter()
        maps = {}
        # Down: 1 -> 2a -> 3a -> 2b -> 3b -> 4, always by the down stair (entry 1).
        for want in ((2, False), (3, False), (2, True), (3, True), (4, False)):
            self.stair(1, f"down to {want}")
            self.assertEqual(self.where(), want)
            floor, leg_b = want
            if floor in (2, 3):
                live = self.ctrl()[0] & (LIVE_2B if floor == 2 else LIVE_3B)
                self.assertEqual(bool(live), leg_b, f"{want}: the live state is the other leg")
                maps[want] = self.floor_map(floor)
        self.assertNotEqual(maps[(2, True)], maps[(2, False)], "2b is 2a's map")
        self.assertNotEqual(maps[(3, True)], maps[(3, False)], "3b is 3a's map")
        # Up: 4 -> 3b -> 2b -> 3a -> 2a -> 1, always by the up stair (entry 0).
        for want in ((3, True), (2, True), (3, False), (2, False), (1, False)):
            self.stair(0, f"up to {want}")
            self.assertEqual(self.where(), want)
            if want in maps:
                self.assertEqual(self.floor_map(want[0]), maps[want], f"{want} changed on the way back")

    # --- C4: the projections ----------------------------------------------
    def poke(self, **fields: int) -> None:
        """Write the Cemetery control block's CHAN_ORD / HIDE_ORD, in SRAM bank 0."""
        h = self.h
        block = h.read_sram_bytes("sProcCaveStagingBuffer", 5, bank=0)
        for name, value in fields.items():
            block[{"chan": 3, "hide": 4}[name]] = value
        h.write_sram_bytes("sProcCaveStagingBuffer", block, bank=0)

    def hideout(self) -> tuple[int, int, int]:
        h = self.h
        return (h.read_sram_bytes("sStageEventHideoutFloor", 1, bank=0)[0],
                *h.read_sram_bytes("sStageEventHideoutX", 2, bank=0))

    def item_got(self) -> int:
        return self.h.read_sram_bytes("sProcCemeteryItemGot", 1, bank=0)[0]

    def hidden(self, name: str) -> bool:
        n = TOGGLES[name]
        return bool(self.h.read8("wToggleableObjectFlags", offset=n // 8) >> n % 8 & 1)

    def ordinal(self) -> int:
        floor, leg_b = self.where()
        return {(1, False): 0, (2, False): 1, (3, False): 2,
                (2, True): 3, (3, True): 4, (4, False): 5}[(floor, leg_b)]

    def test_channeler_stands_on_exactly_one_floor(self) -> None:
        """His ordinal 0-5 over 1, 2, 3, 2b, 3b, 4: shown on that floor only, and
        the projection keeps his floor index and his picture and flag in step."""
        h = self.h
        self.enter()
        # (ordinal, direction): down passes end on 4, up passes on 1.
        passes = [(3, 1), (4, 0), (5, 1), (0, 0), (1, 1), (2, 0)]
        for chan, entry in passes:
            self.poke(chan=chan)
            for _ in range(5):
                self.stair(entry, f"ordinal {chan}")
                here = self.ordinal()
                idx = FLOOR[h.read8("hCurMap")] - 1
                mask = (self.item_got() >> 4) & 3
                self.assertEqual(mask == idx, here == chan,
                                 f"ordinal {chan}: floor {here} (index {idx}) reads his floor as {mask}")
                self.assertEqual(self.hidden(f"TOGGLE_CEMETERY_{idx + 1}_CHANNELER"), here != chan,
                                 f"ordinal {chan}: his flag on floor {here}")
                # What the player sees: the sprite patch runs before the stage
                # dispatch, so it must already read this floor's projection.
                picture = h.read8("wSprite04StateData1")      # SPRITESTATEDATA1_PICTUREID = 0
                self.assertEqual(picture == SPRITES["SPRITE_CHANNELER"], here == chan,
                                 f"ordinal {chan}: his picture on floor {here} is {picture}")

    def test_hideout_follows_its_ordinal_and_picks_one_cell(self) -> None:
        h = self.h
        self.enter()
        none = 0xFF
        self.assertEqual(self.hideout(), (none, none, none), "a Cemetery with no event armed")
        h.write_sram_bytes("sStageEventHideoutFloor", [1], bank=0)    # armed, floor to be projected
        self.poke(hide=4)                                              # 3b
        for want in (1, 2, 3, 4, 5):
            self.stair(1, f"down to ordinal {want}")
            here = self.ordinal()
            self.assertEqual(here, want)
            floor, x, y = self.hideout()
            idx = FLOOR[h.read8("hCurMap")] - 1
            self.assertNotEqual(floor, none, "a projection wrote NO_HIDEOUT")
            self.assertEqual(floor == idx, here == 4, f"ordinal {here}: hideout floor {floor}")
            # The cell is picked when ordinal 4's floor generates, and kept after.
            self.assertEqual((x, y) != (none, none), here >= 4, f"ordinal {here}: the cell is {(x, y)}")
        # Disarmed since the lobby: the next load keeps it that way for good.
        h.write_sram_bytes("sStageEventHideoutFloor", [none], bank=0)
        self.stair(0, "up, disarmed")
        self.assertEqual(self.hideout()[0], none)
        self.assertEqual(h.read_sram_bytes("sProcCaveStagingBuffer", 5, bank=0)[4], none,
                         "the lobby's ordinal outlived the disarm")

    def test_a_real_villain_hides_on_its_ordinal_only(self) -> None:
        """A real stage event (Jessie & James), its intro dismissed: for each
        hideout ordinal 1-5, the pair is drawn and stands on the picked cell on
        that floor only, and is absent (picture 0, off-grid) on the others."""
        from audit_cemetery_stage_event import stage_event_constants
        const = stage_event_constants()
        h = self.h
        h.boot_to_lobby(battle_count=41, encounter_kind=4)
        h.write8("wStageEvent", const["STAGE_EVENT_JESSIE_JAMES"])
        lobby = io.BytesIO()
        h.save_state(lobby)
        for hide in (1, 2, 3, 4, 5):
            h.load_state(lobby)
            h.preload_and_enter_wild_area(CEM[1], "cemetery")
            self.assertNotEqual(self.hideout()[0], 0xFF, "the event rolled no hideout")
            for _ in range(8):                      # the intro text, then the vanish
                h.tap("a", frames=12)
                h.tick(40)
            phase = (h.read8("wStageEvent") & const["STAGE_EVENT_PHASE_MASK"]) >> const["STAGE_EVENT_PHASE_SHIFT"]
            self.assertEqual(phase, const["STAGE_EVENT_PHASE_HIDING"], "the intro was not dismissed")
            h.write8("wProcCemWildBudget", 0)
            self.poke(hide=hide)
            for stop in range(1, 6):
                self.stair(1, f"hideout {hide}: down to stop {stop}")
                self.assertEqual(self.ordinal(), stop)
                pics = (h.read8("wSprite02StateData1"), h.read8("wSprite03StateData1"))
                pos = [tuple(p) for p in h.sprite_positions(4)][1:3]
                if stop == hide:
                    _, hx, hy = self.hideout()
                    self.assertNotEqual((hx, hy), (0xFF, 0xFF), f"hideout {hide}: no cell picked")
                    self.assertTrue(all(pics), f"hideout {hide}: the pair is not drawn on its floor")
                    self.assertEqual(pos, [(hy * 2, hx * 2), (hy * 2, hx * 2 + 1)],
                                     f"hideout {hide}: the pair is not on its cell")
                else:
                    self.assertEqual(pics, (0, 0), f"hideout {hide}: a phantom pair on stop {stop}")
                    self.assertEqual(pos, [(-4, -4), (-4, -4)], f"hideout {hide}: the pair placed on stop {stop}")

    def test_each_leg_gives_its_own_item(self) -> None:
        """The pickup (engine/events/pick_up_item.asm) gives wRogueItem, which the
        load takes from the live floor's sProcCemeteryItem slot: on a b leg it
        must be the b floor's item, kept across a revisit."""
        h = self.h
        self.enter()
        given = {}
        for entry, stops in ((1, 5), (0, 5)):
            for _ in range(stops):
                self.stair(entry, "chain")
                floor, leg_b = self.where()
                live = h.read_sram_bytes("sProcCemeteryItem", 4, bank=0)[floor - 1]
                item = h.read8("wRogueItem")
                self.assertEqual(item, live, f"{(floor, leg_b)} gives {item}, its slot holds {live}")
                self.assertEqual(given.setdefault((floor, leg_b), item), item,
                                 f"{(floor, leg_b)}'s item changed on the way back")

    def test_one_b_floor_may_have_no_ball(self) -> None:
        """As the other areas' floor 2: the two b floors add 1 or 2 balls. Here
        the coin leaves one of them without: its ball reads as collected and
        is hidden from the first visit, the other b floor's is shown."""
        for balls, empty, full in ((GOT_2B, 2, 3), (GOT_3B, 3, 2)):
            with self.subTest(empty=f"{empty}b"):
                self.h.close()
                self.h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=self.h.hardware_mode == "CGB")
                self.h.allow_deep_cemetery_floor = True
                self.enter(balls=balls)
                for _ in range(4):
                    self.stair(1, "down to 3b")
                    floor, leg_b = self.where()
                    if leg_b:
                        bit = 1 << (floor - 1)
                        got = bool(self.item_got() & bit)
                        self.assertEqual(got, floor == empty, f"{floor}b's ball reads {'taken' if got else 'there'}")
                        self.assertEqual(self.hidden(f"TOGGLE_CEMETERY_{floor}_POKEBALL"), floor == empty)
                    elif floor in (2, 3):
                        self.assertFalse(self.item_got() & 1 << (floor - 1), f"{floor}a lost its ball")

    def test_each_leg_keeps_its_own_ball(self) -> None:
        h = self.h
        self.enter(balls=0)
        self.stair(1, "down to 2a")
        h.write_sram_bytes("sProcCemeteryItemGot", [self.item_got() | 2], bank=0)   # 2a's ball taken
        self.stair(1, "3a")
        self.stair(1, "2b")
        self.assertEqual(self.where(), (2, True))
        self.assertEqual(self.item_got() & 2, 0, "2a's taken ball is gone from 2b")
        self.assertFalse(self.hidden("TOGGLE_CEMETERY_2_POKEBALL"), "2b's ball is not shown")
        h.write_sram_bytes("sProcCemeteryItemGot", [self.item_got() | 2], bank=0)   # 2b's ball taken
        self.stair(1, "3b")
        self.assertEqual(self.item_got() & 4, 0, "3a's ball state leaked into 3b")
        self.stair(1, "4")
        self.stair(0, "up to 3b")
        self.stair(0, "up to 2b")
        self.assertEqual(self.where(), (2, True))
        self.assertTrue(self.item_got() & 2, "2b's ball is back")
        self.assertTrue(self.hidden("TOGGLE_CEMETERY_2_POKEBALL"))
        self.stair(0, "up to 3a")
        self.stair(0, "up to 2a")
        self.assertEqual(self.where(), (2, False))
        self.assertTrue(self.item_got() & 2, "2a's ball is back after 2b's was taken")
        self.assertTrue(self.hidden("TOGGLE_CEMETERY_2_POKEBALL"))

    def test_prefabs_are_never_reused_across_six_floors(self) -> None:
        h = self.h
        self.enter()
        used = lambda: int.from_bytes(bytes(h.read_sram_bytes("sProcCemeteryUsedPrefabs", 2, bank=0)), "little")
        before = used()
        for _ in range(5):
            self.stair(1, "down")
            now = used()
            self.assertEqual(now & before, before, "a prefab was released")
            self.assertLessEqual(bin(now & ~before).count("1"), 1, "a floor used two prefabs")
            before = now

    # --- C6: save, reset, Continue -----------------------------------------
    def continue_from(self, sram: bytes):
        reboot = save_reload.Reboot(sram, cgb_mode=self.h.hardware_mode == "CGB")
        reboot.load()
        self.assertTrue(reboot.overworld, "Continue did not reach the overworld")
        return reboot

    def save_now(self) -> None:
        h = self.h
        self.assertTrue(save_reload.settle(h))
        h.park_before_hijack()
        h.call_routine("SaveGameData")

    def test_reset_without_saving_repairs_the_leg(self) -> None:
        """Save on 2b, walk on to 3a and 2a (their state goes live), cut the power:
        Continue loads the save's 2b, so the floor bit repairs the live maps."""
        h = self.h
        self.enter()
        for _ in range(3):
            self.stair(1, "down to 2b")
        self.assertEqual(self.where(), (2, True))
        two_b = self.floor_map(2)
        self.save_now()
        self.stair(0, "3a")
        self.stair(0, "2a")
        self.assertEqual(self.where(), (2, False))
        self.assertNotEqual(self.floor_map(2), two_b)
        reboot = self.continue_from(save_reload.sram_image(h))
        mine = self.h
        try:
            self.h = reboot.h
            self.assertEqual(self.where(), (2, True), "Continue is not on 2b")
            self.assertEqual(self.floor_map(2), two_b, "Continue loaded 2a's map as 2b")
            self.assertTrue(self.ctrl()[0] & LIVE_2B)
        finally:
            self.h = mine
            reboot.close()

    def test_save_and_continue_on_3b(self) -> None:
        h = self.h
        self.enter()
        for _ in range(4):
            self.stair(1, "down to 3b")
        self.assertEqual(self.where(), (3, True))
        three_b = self.floor_map(3)
        self.save_now()
        reboot = self.continue_from(save_reload.sram_image(h))
        mine = self.h
        try:
            self.h = reboot.h
            self.assertEqual(self.where(), (3, True))
            self.assertEqual(self.floor_map(3), three_b, "Continue changed 3b")
            self.stair(1, "on to 4")
            self.assertEqual(self.where(), (4, False))
            self.stair(0, "back to 3b")
            self.assertEqual(self.where(), (3, True))
            self.assertEqual(self.floor_map(3), three_b)
        finally:
            self.h = mine
            reboot.close()

    def test_ordinary_cemetery_keeps_four_floors(self) -> None:
        h = self.h
        h.allow_deep_cemetery_floor = False
        self.enter()
        for want in (2, 3, 4):
            self.stair(1, f"down to {want}")
            self.assertEqual(self.where(), (want, False))


if __name__ == "__main__":
    unittest.main()
