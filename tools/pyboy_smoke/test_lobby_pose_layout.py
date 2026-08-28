"""Executable layout specification, NOT a loader or emulator test.

No game assembly consumes this model. Upload scheduling, OAM remapping, and
cache invalidation must be proven separately before integration.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
# Physical bank-0 OBJ tile bases. Logical image indices are a separate API.
FULL = {
    "PLAYER": 0x00,
    "FOLLOWER": 0x0C,
    "SPRITE_MIDDLE_AGED_MAN": 0x18,
    "SPRITE_NURSE": 0x24,
    "SPRITE_CLERK": 0x30,
    "SPRITE_GENTLEMAN": 0x3C,
    "SPRITE_GRANNY": 0x48,
    "SPRITE_SILPH_PRESIDENT": 0x54,
    "SPRITE_YOUNGSTER": 0x60,
}
CACHED = {
    "SPRITE_CHANNELER": 0x6C,
    "SPRITE_SUPER_NERD": 0x70,
    "SPRITE_GAMEBOY_KID": 0x74,
}
WALKERS = {"PLAYER", "FOLLOWER", "SPRITE_MIDDLE_AGED_MAN"}
HEALING = set(range(0x7C, 0x7F))  # current CopyVideoData copies THREE tiles


def standing_source(facing):
    return {"DOWN": 0, "UP": 4, "LEFT": 8, "RIGHT": 8}[facing]


class LobbyPoseLayoutTests(unittest.TestCase):
    def test_current_roster_and_movement_match_specification(self):
        source = (ROOT / "data/maps/objects/IndigoPlateauLobby.asm").read_text()
        actors = [line.partition(";")[0].split(",") for line in source.splitlines()
                  if line.strip().startswith("object_event ")]
        self.assertEqual(len(actors), 11)
        pictures = [a[2].strip() for a in actors]
        self.assertEqual(set(pictures), (set(FULL) - {"PLAYER", "FOLLOWER"}) | set(CACHED))
        self.assertEqual(pictures.count("SPRITE_CLERK"), 2)
        for actor in actors:
            picture, movement = actor[2].strip(), actor[3].strip()
            self.assertEqual(movement, "WALK" if picture in WALKERS else "STAY")
        # A four-tile cache must not be shared by independently facing actors.
        for picture in CACHED:
            self.assertEqual(pictures.count(picture), 1)

    def test_ranges_are_disjoint_and_leave_healing_scratch(self):
        used = set()
        for table, size in ((FULL, 12), (CACHED, 4)):
            for base in table.values():
                tiles = set(range(base, base + size))
                self.assertFalse(used & tiles)
                used |= tiles
        self.assertEqual(used, set(range(0x78)))
        self.assertFalse(used & HEALING)
        self.assertLess(max(used | HEALING), 0x80)

    def test_walking_halves_preserve_legacy_plus_80_addressing(self):
        walking = set()
        for picture in WALKERS:
            base = FULL[picture] + 0x80
            walking.update(range(base, base + 12))
        self.assertEqual(walking, set(range(0x80, 0xA4)))
        self.assertEqual(FULL["FOLLOWER"], 12)  # existing physical slot 2

    def test_all_facings_retain_original_four_tiles(self):
        sheet = tuple(range(12))  # distinct source tile identities
        for picture, base in CACHED.items():
            cache = None
            for facing in ("DOWN", "UP", "LEFT", "RIGHT", "DOWN", "LEFT"):
                offset = standing_source(facing)
                cache = sheet[offset:offset + 4]
                with self.subTest(picture=picture, facing=facing):
                    self.assertEqual(cache, tuple(range(offset, offset + 4)))
                    self.assertEqual(len(range(base, base + 4)), 4)
            # RIGHT uses LEFT's bytes plus existing flipped OAM, not new art.
            self.assertEqual(standing_source("RIGHT"), standing_source("LEFT"))

    def test_text_and_healing_overlays_do_not_overwrite_standing_tiles(self):
        vram = list(range(256))
        original = vram[:0x78]
        vram[0x80:] = ["font"] * 128  # conservatively reserve the entire half
        for tile in HEALING:
            vram[tile] = "heal"
        self.assertEqual(vram[:0x78], original)

    def test_nurse_legacy_pose_bytes_need_physical_remapping(self):
        for legacy_image, offset in ((0x18, 8), (0x14, 4)):
            self.assertEqual(legacy_image & 0x0C, offset)
            self.assertEqual(FULL["SPRITE_NURSE"] + offset, 0x24 + offset)
        # This specification does not assume the legacy high nibble is VRAM.
        self.assertNotEqual(FULL["SPRITE_NURSE"], 0x0C)


if __name__ == "__main__":
    unittest.main()
