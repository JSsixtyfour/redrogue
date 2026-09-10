#!/usr/bin/env python3
"""Source contracts for the Yellow Legacy 6A authored-map sprite slice."""

import re
import struct
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

SPRITES = (
    "DODUO",
    "PSYDUCK",
    "NIDORINO",
    "KABUTO",
    "SPEAROW",
    "CUBONE",
    "ARTICUNO",
    "ZAPDOS",
    "MOLTRES",
    "MEWTWO",
)

OBJECT_CONTRACTS = {
    "CopycatsHouse2F.asm": "SPRITE_DODUO, WALK, LEFT_RIGHT, TEXT_COPYCATSHOUSE2F_DODUO",
    "MrFujisHouse.asm": "SPRITE_PSYDUCK, STAY, UP, TEXT_MRFUJISHOUSE_PSYDUCK",
    "BillsHouse.asm": "SPRITE_KABUTO, STAY, NONE, TEXT_BILLSHOUSE_BILL_POKEMON",
    "PokemonFanClub.asm": "SPRITE_PIKACHU, STAY, LEFT, TEXT_POKEMONFANCLUB_PIKACHU",
    "ViridianNicknameHouse.asm": "SPRITE_SPEAROW, WALK, LEFT_RIGHT, TEXT_VIRIDIANNICKNAMEHOUSE_SPEAROW",
    "LavenderCuboneHouse.asm": "SPRITE_CUBONE, STAY, UP, TEXT_LAVENDERCUBONEHOUSE_CUBONE",
    "PowerPlant.asm": "SPRITE_ZAPDOS,    STAY, UP,   TEXT_POWERPLANT_ZAPDOS,    ZAPDOS,   50 | OW_POKEMON",
    "VictoryRoad2F.asm": "SPRITE_MOLTRES, STAY, UP, TEXT_VICTORYROAD2F_MOLTRES, MOLTRES, 50 | OW_POKEMON",
    "SeafoamIslandsB4F.asm": "SPRITE_ARTICUNO, STAY, DOWN, TEXT_SEAFOAMISLANDSB4F_ARTICUNO, ARTICUNO, 50 | OW_POKEMON",
    "CeruleanCaveB1F.asm": "SPRITE_MEWTWO, STAY, DOWN, TEXT_CERULEANCAVEB1F_MEWTWO, MEWTWO, 70",
}


class YellowLegacyOverworldSpriteContracts(unittest.TestCase):
    def test_ids_are_appended_in_pointer_table_order(self):
        constants = (ROOT / "constants/sprite_constants.asm").read_text()
        pointers = (ROOT / "data/sprites/sprites.asm").read_text()
        constant_order = re.findall(r"const SPRITE_([A-Z0-9_]+)", constants)
        pointer_order = re.findall(r"; SPRITE_([A-Z0-9_]+)$", pointers, re.MULTILINE)
        self.assertEqual(constant_order[-len(SPRITES):], list(SPRITES))
        self.assertEqual(pointer_order[-len(SPRITES):], list(SPRITES))

    def test_assets_are_full_walking_sheets(self):
        for sprite in SPRITES:
            path = ROOT / "gfx/sprites" / f"{sprite.lower()}.png"
            with self.subTest(sprite=sprite), path.open("rb") as image:
                self.assertEqual(image.read(8), b"\x89PNG\r\n\x1a\n")
                length = struct.unpack(">I", image.read(4))[0]
                self.assertEqual(image.read(4), b"IHDR")
                width, height = struct.unpack(">II", image.read(8))
                self.assertGreaterEqual(length, 8)
                self.assertEqual((width, height), (16, 96))

    def test_authored_objects_use_species_sprites(self):
        object_dir = ROOT / "data/maps/objects"
        for filename, expected in OBJECT_CONTRACTS.items():
            with self.subTest(filename=filename):
                source = (object_dir / filename).read_text()
                self.assertIn(expected, source)
        fuji = (object_dir / "MrFujisHouse.asm").read_text()
        self.assertIn("SPRITE_NIDORINO, STAY, NONE, TEXT_MRFUJISHOUSE_NIDORINO", fuji)


if __name__ == "__main__":
    unittest.main()
