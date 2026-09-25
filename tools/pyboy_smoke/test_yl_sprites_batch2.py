"""Yellow Legacy sprite batch 2: 24 Pokemon sheets in three shapes.

Walking sheets (16x96) are followers/bosses and dolls; standing-only (16x48)
and one-pose (16x16) sheets are dolls only and are padded to the 384 bytes the
walking-slot loader always reads (sheet, then sheet + $C0 for walk frames).
"""

from pathlib import Path
import re
import struct
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants


ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

WALKING = ("FEAROW", "KANGASKHAN", "LAPRAS", "MACHOP", "MEW", "NIDORAN_F", "PIDGEY", "SLOWPOKE")
STANDING = ("VAPOREON", "BULBASAUR", "CLEFAIRY", "JIGGLYPUFF", "MACHOKE", "MEOWTH", "MR_MIME",
            "NIDORAN_M", "ODDISH", "PIDGEOT", "POLIWRATH", "SANDSHREW", "SEEL2")
ONE_POSE = ("JOLTEON", "FLAREON", "WIGGLYTUFF")
BATCH = WALKING + STANDING + ONE_POSE
SHAPE = {**{n: (16, 96) for n in WALKING}, **{n: (16, 48) for n in STANDING}, **{n: (16, 16) for n in ONE_POSE}}
SHEET_BYTES = 384


def sprite_ids() -> dict[str, int]:
    source = (ROOT / "constants" / "sprite_constants.asm").read_text(encoding="utf-8")
    return {m[0]: int(m[1], 16) for m in re.findall(r"const SPRITE_(\w+)\s*; \$([0-9a-f]{2})", source)}


def png_size(name: str) -> tuple[int, int]:
    data = (ROOT / "gfx" / "sprites" / f"{name.lower()}.png").read_bytes()
    return struct.unpack(">II", data[16:24])


def padded_sheet(name: str) -> bytes:
    raw = (ROOT / "gfx" / "sprites" / f"{name.lower()}.2bpp").read_bytes()
    return (raw * (SHEET_BYTES // len(raw)))[:SHEET_BYTES]


class BatchTwoSourceTest(unittest.TestCase):
    def test_ids_follow_batch_one_in_pointer_table_order(self) -> None:
        constants = (ROOT / "constants" / "sprite_constants.asm").read_text(encoding="utf-8")
        pointers = (ROOT / "data" / "sprites" / "sprites.asm").read_text(encoding="utf-8")
        for order in (re.findall(r"const SPRITE_(\w+)", constants),
                      re.findall(r"; SPRITE_(\w+)$", pointers, re.M)):
            start = order.index(BATCH[0])
            self.assertEqual(order[start - 1], "MEWTWO")
            self.assertEqual(order[start:start + len(BATCH)], list(BATCH))
        ids = sprite_ids()
        self.assertEqual([ids[n] for n in BATCH], list(range(ids["MEWTWO"] + 1, ids["MEWTWO"] + 1 + len(BATCH))),
                         "the hex comments on the constants drifted from their real values")

    def test_png_shapes(self) -> None:
        for name in BATCH:
            with self.subTest(name=name):
                self.assertEqual(png_size(name), SHAPE[name])

    def test_only_walking_sheets_resolve_for_followers_and_bosses(self) -> None:
        source = (ROOT / "custom_functions" / "procedural_cave_gen.asm").read_text(encoding="utf-8")
        table = source.split("\n.speciesSprites\n", 1)[1].split(".speciesSpritesEnd", 1)[0]
        for name in WALKING:
            self.assertIn(f"db {name}, SPRITE_{name}", table)
        for name in STANDING + ONE_POSE:
            self.assertNotIn(f"SPRITE_{name}", table, f"{name} has no walk frames")


class BatchTwoRuntimeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.harness = RedRogueHarness(ROOT, ARTIFACTS)
        self.maps = parse_map_constants(ROOT / "constants" / "map_constants.asm")

    def tearDown(self) -> None:
        self.harness.close()

    def park(self) -> None:
        pc = self.harness.pyboy.register_file.PC
        if self.harness.address("VBlank") <= pc < self.harness.address("DelayFrame"):
            return
        bank = self.harness.read8("hLoadedROMBank")
        name = self.harness.symbols.nearest(bank, pc) or ""
        self.assertTrue(
            name.startswith("PrepareOAMData") and bank == self.harness.symbols.bank("PrepareOAMData"),
            f"not parked in a VBlank context: PC=${pc:04x} bank ${bank:02x} ({name})",
        )

    def test_each_shape_loads_both_halves_from_its_own_sheet(self) -> None:
        h = self.harness
        ids = sprite_ids()
        h.boot_debug1(self.maps["SILPH_CO_DORM"])
        chosen = ("MEW", "VAPOREON", "JOLTEON")  # one per shape
        for slot, name in enumerate(chosen, start=1):
            h.write8(f"wSprite0{slot}StateData1", ids[name])
        self.park()
        h.call_routine("InitMapSprites")
        memory = h.pyboy.memory
        vram = h.address("vNPCSprites")
        for slot, name in enumerate(chosen, start=1):
            base = h.read8(f"wSprite0{slot}StateData2ImageBaseOffset")
            with self.subTest(name=name, base=base):
                self.assertTrue(1 <= base <= 10, "not given a walking VRAM slot")
                standing = vram + (base - 1) * 192
                walking = standing + 0x800
                sheet = padded_sheet(name)
                self.assertEqual(bytes(memory[standing:standing + 192]), sheet[:192], "standing half")
                self.assertEqual(bytes(memory[walking:walking + 192]), sheet[192:], "walk half")


if __name__ == "__main__":
    unittest.main()
