"""Textbox masking and sprite lifecycle checks for the shared NPC update path.

The isolated probe captures a real routine return before the overworld resumes.
It is also reusable for byte-for-byte comparisons against an archived ROM.
"""
import io
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
RNG = [3, 71, 19, 89, 137, 211, 47, 163, 29, 103]
TOGGLES = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")


class SpriteProbe:
    def __init__(self, rom_root=ROOT):
        self.h = RedRogueHarness(rom_root, ROOT / "tools/pyboy_smoke/artifacts")
        self.h.boot_to_lobby()
        self.h.tick(120)
        self.state = io.BytesIO()
        self.h.save_state(self.state)
        self.output = None
        self.h.register_hook("Bankswitch.Return", self.returned)

    def close(self):
        self.h.close()

    def returned(self, _):
        h = self.h
        if h.pyboy.register_file.SP != self.return_sp:
            return  # an inner farcall returning through the same HOME label
        self.output = {
            "state1": h.read_bytes("wSpriteStateData1", 256),
            "state2": h.read_bytes("wSpriteStateData2", 256),
            "random": h.read_bytes("wRandomTable", 10),
            "random_add": h.read8("hRandomAdd"),
            "random_sub": h.read8("hRandomSub"),
            "hidden": h.read8("hIsToggleableObjectOff"),
            "toggle_flags": h.read_bytes("wToggleableObjectFlags", 32),
            "carry": bool(h.pyboy.register_file.F & 0x10),
            "stack": h.pyboy.register_file.SP,
        }
        h.pyboy.register_file.PC = h.address("DelayFrame.halt")

    def run(self, y=44, x=40, covered=(), hidden=False, movement=255,
            status=2, facing=0, animation=0, font=0, walk=0, grass=0,
            routine="CheckSpriteAvailability", slot=1):
        h = self.h
        self.state.seek(0)
        h.load_state(self.state)
        h.pyboy.memory[0xffff] = 0
        for name in ("wSpriteStateData1", "wSpriteStateData2"):
            base = h.address(name)
            h.pyboy.memory[base:base+256] = [0] * 256
        # Extended padding makes wrap/edge samples deterministic too.
        tilemap = h.address("wTileMap")
        h.pyboy.memory[tilemap:tilemap+1024] = [0] * 1024
        for index in covered:
            h.pyboy.memory[tilemap + index] = 0x7f  # actual textbox/space tile
        h.write8("hCurrentSpriteOffset", slot * 16)
        h.write8("hTilePlayerStandingOn", 0x20)
        h.write8("wFontLoaded", font)
        h.write8("wWalkCounter", walk)
        h.write8("wGrassTile", grass)
        h.write8("wOptions2", 0)  # single-speed cadence
        h.write8("wStatusFlags3", 0)
        h.write8("wPlayerDirection", 1)
        h.write8("wXCoord", 0)
        h.write8("wYCoord", 0)
        # The real lobby list: only slots 7-12 are toggleable.
        for i in range(6):
            h.write8("wToggleableObjectList", 7+i, 2*i)
            h.write8("wToggleableObjectList", TOGGLES["TOGGLE_PC_PSYCHIC"]+i, 2*i+1)
        h.write8("wToggleableObjectList", 255, 12)
        flags = h.address("wToggleableObjectFlags")
        h.pyboy.memory[flags:flags+32] = [255 if hidden else 0] * 32
        h.write8("wMapSpriteData", 0xd0, (slot-1)*2)  # fixed DOWN
        data1 = h.address("wSpriteStateData1") + slot * 16
        data2 = h.address("wSpriteStateData2") + slot * 16
        h.pyboy.memory[data1:data1+16] = [1, status, 255, 0, y, 0, x, 0, animation, facing, 0, 0, 0, 0, 0, 0]
        h.pyboy.memory[data2:data2+16] = [16, 0, 8, 8, 4, 4, movement, 0x80, 23, 0, 0, 0, 3, 0, 0, 0]
        h.pyboy.memory[h.address("wRandomTable"):h.address("wRandomTable")+10] = RNG
        h.write8("hRandomAdd", 0)
        h.write8("hRandomSub", 0)
        return self.call(routine)

    def call(self, routine):
        h = self.h
        sp = 0xdff0
        target = h.address("Bankswitch.Return")
        h.pyboy.memory[sp:sp+2] = [target & 255, target >> 8]
        bank, addr = h.symbols.get(routine)
        h.pyboy.memory[0x2000] = bank
        h.write8("hLoadedROMBank", bank)
        h.pyboy.register_file.SP = sp
        h.pyboy.register_file.PC = addr
        self.return_sp = sp + 2
        self.output = None
        h.wait_until(lambda: self.output is not None, "sprite update return", 4)
        assert self.output["stack"] == sp + 2
        assert not h.hook_errors, h.hook_errors
        return self.output


class HiddenProbe(SpriteProbe):
    def run_hidden(self, map_id, slot, flags, checkpoint=False):
        h = self.h
        self.state.seek(0)
        h.load_state(self.state)
        h.pyboy.memory[0xffff] = 0
        for name in ("wSpriteStateData1", "wSpriteStateData2"):
            base = h.address(name)
            h.pyboy.memory[base:base+256] = [0] * 256
        h.write8("hCurMap", map_id)
        h.write8("hCurrentSpriteOffset", slot * 16)
        h.write8("wStageClassCache", 0)
        h.write8("wStageClassCacheMap", 255)
        h.write8("wBattleCount", 29 if checkpoint else 11)
        h.write8("wObtainedBadges", 7 if checkpoint else 0)
        h.write8("wWarpedFromWhichMap", MAPS["REWARD_ROOM"])
        rows = [(7+i, TOGGLES["TOGGLE_PC_PSYCHIC"]+i) for i in range(6)] if map_id == MAPS["INDIGO_PLATEAU_LOBBY"] else [(i, 32+i) for i in range(1,16)]
        for i,(obj,bit) in enumerate(rows):
            h.write8("wToggleableObjectList", obj, 2*i)
            h.write8("wToggleableObjectList", bit, 2*i+1)
        h.write8("wToggleableObjectList", 255, 2*len(rows))
        base = h.address("wToggleableObjectFlags")
        h.pyboy.memory[base:base+32] = flags
        base = h.address("wRandomTable")
        h.pyboy.memory[base:base+10] = RNG
        h.write8("hRandomAdd", 0)
        h.write8("hRandomSub", 0)
        return self.call("IsObjectHidden")


class LobbyLiveVisibilityTest(unittest.TestCase):
    def setUp(self):
        self.probe = HiddenProbe()

    def tearDown(self):
        self.probe.close()

    def test_all_service_flag_combinations_are_live(self):
        for combination in range(64):
            flags = [0] * 32
            for service in range(6):
                bit = TOGGLES["TOGGLE_PC_PSYCHIC"] + service
                if combination & (1 << service):
                    flags[bit//8] |= 1 << (bit%8)
            for service in range(6):
                result = self.probe.run_hidden(MAPS["INDIGO_PLATEAU_LOBBY"], service+7, flags)
                self.assertEqual(bool(result["hidden"]), bool(combination & (1 << service)))
                self.assertEqual(result["toggle_flags"], flags)
                self.assertEqual(result["random"], RNG)

    def test_nurse_clerks_and_daycare_do_not_inherit_service_toggle_bits(self):
        for slot in range(1,7):
            result = self.probe.run_hidden(MAPS["INDIGO_PLATEAU_LOBBY"], slot, [255]*32)
            self.assertEqual(result["hidden"], 0)

    def test_checkpoint_attendant_keeps_its_eligibility_gate(self):
        for flags in ([0]*32, [255]*32):
            for checkpoint in (False,True):
                result = self.probe.run_hidden(MAPS["INDIGO_PLATEAU_LOBBY"], 13, flags, checkpoint)
                self.assertEqual(bool(result["hidden"]), not checkpoint)
                self.assertEqual(result["toggle_flags"], flags)


class SpriteVisibilityTest(unittest.TestCase):
    def setUp(self):
        self.probe = SpriteProbe()

    def tearDown(self):
        self.probe.close()

    def test_aligned_sprite_masks_each_corner_and_recovers(self):
        # (y=44,x=40) occupies tile-map indices 125,126,145,146.
        for corner in (125, 126, 145, 146):
            with self.subTest(corner=corner):
                result = self.probe.run(covered=[corner])
                self.assertTrue(result["carry"])
                self.assertEqual(result["state1"][18], 255)
        result = self.probe.run()
        self.assertFalse(result["carry"])
        self.assertEqual(result["state1"][18], 0x20)

    def test_partial_vertical_step_still_masks_destination_tiles(self):
        # One pixel below alignment: only the rounded-UP footprint hits 185.
        result = self.probe.run(y=45, covered=[185])
        self.assertTrue(result["carry"])
        self.assertEqual(result["state1"][18], 255)
        result = self.probe.run(y=45, covered=[105])
        self.assertFalse(result["carry"], "unrelated upper row must not mask")

    def test_hidden_object_stays_hidden_then_reappears(self):
        self.assertTrue(self.probe.run(hidden=True, slot=7)["carry"])
        self.assertFalse(self.probe.run(hidden=False, slot=7)["carry"])

    def test_grass_priority_is_retained_while_player_scrolls(self):
        result = self.probe.run(walk=8, grass=1)
        self.assertEqual(result["state2"][23], 0x80)
        result = self.probe.run(walk=0, grass=1)
        self.assertEqual(result["state2"][23], 0)
        result = self.probe.run(walk=0, grass=0)
        self.assertEqual(result["state2"][23], 0x80)

    def test_facing_and_animation_are_published_during_scroll(self):
        for facing in (0, 4, 8, 12):
            for frame in range(4):
                result = self.probe.run(facing=facing, animation=frame, walk=8)
                self.assertEqual(result["state1"][18], 0x20 + facing + frame)

    def test_visibility_does_not_consume_rng(self):
        for y in (44, 45, 252, 255):
            result = self.probe.run(y=y, movement=0)
            self.assertEqual(result["random"], RNG)
            self.assertEqual(result["random_add"], 0)
            self.assertEqual(result["random_sub"], 0)


if __name__ == "__main__":
    unittest.main()
