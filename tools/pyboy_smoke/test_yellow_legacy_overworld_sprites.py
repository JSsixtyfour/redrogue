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
    "IgasDojo.asm": "SPRITE_NIDORINO, WALK, ANY_DIR, TEXT_IGASDOJO_NIDORINO",
    "PowerPlant.asm": "SPRITE_ZAPDOS,    STAY, UP,   TEXT_POWERPLANT_ZAPDOS,    ZAPDOS,   50 | OW_POKEMON",
    "VictoryRoad2F.asm": "SPRITE_MOLTRES, STAY, UP, TEXT_VICTORYROAD2F_MOLTRES, MOLTRES, 50 | OW_POKEMON",
    "SeafoamIslandsB4F.asm": "SPRITE_ARTICUNO, STAY, DOWN, TEXT_SEAFOAMISLANDSB4F_ARTICUNO, ARTICUNO, 50 | OW_POKEMON",
    "CeruleanCaveB1F.asm": "SPRITE_MEWTWO, STAY, DOWN, TEXT_CERULEANCAVEB1F_MEWTWO, MEWTWO, 70",
}

# 16x96 sheets whose six frames are one front-facing pose alternating with a
# second front-facing pose (a party-menu bounce). They are the right size for
# the walking-slot loader but cannot turn, so they are room dolls only.
PARTY_POSE = ("MEW", "MEWTWO")

# Sheet frame order: standing down, up, left, then walking down, up, left.
FRAME_NAMES = ("stand down", "stand up", "stand left", "walk down", "walk up", "walk left")
# Measured art gaps on sheets the follower/boss lookup still uses. Each entry
# must still show its gap, so fixing the art fails the test until it is removed.
NO_STEP_FRAMES = ("NIDORINO", "PSYDUCK")  # walk frames are copies of the standing frames
WRONG_FACING_WALK = ("MOLTRES",)          # walk down is the stand up frame


def sheet_frames(sprite: str) -> list[bytes]:
    """The six 16x16 frames of a built sheet (4 tiles, 64 bytes each)."""
    raw = (ROOT / "gfx" / "sprites" / f"{sprite.lower()}.2bpp").read_bytes()
    assert len(raw) == 384, f"{sprite} is not a 16x96 sheet"
    return [raw[64 * i:64 * i + 64] for i in range(6)]


def lookup_sprites() -> set[str]:
    """Every SPRITE_* the follower/boss/encounter lookup can return."""
    source = (ROOT / "custom_functions/procedural_cave_gen.asm").read_text()
    species = source.split("\n.speciesSprites\n", 1)[1].split(".speciesSpritesEnd", 1)[0]
    forms = source.split("\n.formSprites\n", 1)[1].split(".formSpritesEnd", 1)[0]
    return set(re.findall(r"^\s*db [^;\n]*\bSPRITE_(\w+)", species + forms, re.M))


def sheet_gaps(sprite: str) -> dict[str, list[str]]:
    f = sheet_frames(sprite)
    turns = [f"{FRAME_NAMES[a]} == {FRAME_NAMES[b]}"
             for a, b in ((0, 1), (0, 2), (1, 2)) if f[a] == f[b]]
    steps = [FRAME_NAMES[d + 3] for d in range(3) if f[d + 3] == f[d]]
    facing = [f"{FRAME_NAMES[d + 3]} == {FRAME_NAMES[s]}"
              for d in range(3) for s in range(3) if s != d and f[d + 3] == f[s]]
    return {"turns": turns, "steps": steps, "facing": facing}


class YellowLegacyOverworldSpriteContracts(unittest.TestCase):
    def test_ids_are_appended_in_pointer_table_order(self):
        constants = (ROOT / "constants/sprite_constants.asm").read_text()
        pointers = (ROOT / "data/sprites/sprites.asm").read_text()
        constant_order = re.findall(r"const SPRITE_([A-Z0-9_]+)", constants)
        pointer_order = re.findall(r"; SPRITE_([A-Z0-9_]+)$", pointers, re.MULTILINE)
        # One contiguous run in both tables; later batches
        # (test_yl_sprites_batch2.py) append after it.
        for order in (constant_order, pointer_order):
            start = order.index(SPRITES[0])
            self.assertEqual(order[start:start + len(SPRITES)], list(SPRITES))

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

    def test_authored_objects_use_their_configured_sprites(self):
        object_dir = ROOT / "data/maps/objects"
        for filename, expected in OBJECT_CONTRACTS.items():
            with self.subTest(filename=filename):
                source = (object_dir / filename).read_text()
                self.assertIn(expected, source)
        fuji = (object_dir / "MrFujisHouse.asm").read_text()
        self.assertIn("SPRITE_NIDORINO, STAY, NONE, TEXT_MRFUJISHOUSE_NIDORINO", fuji)

    def test_dynamic_consumers_share_dedicated_lookup_with_fallback(self):
        procedural = (ROOT / "custom_functions/procedural_cave_gen.asm").read_text()
        follower = (ROOT / "engine/overworld/follower_yellow_test.asm").read_text()
        lookup = procedural.split("PCGetDedicatedPokemonSprite::", 1)[1].split(
            "; ============================================================", 1
        )[0]
        for sprite in SPRITES:
            if sprite in PARTY_POSE:
                self.assertNotIn(f"SPRITE_{sprite}", lookup)
            else:
                self.assertIn(f"db {sprite}, SPRITE_{sprite}", lookup)
        dorm = (ROOT / "custom_functions/room_decor.asm").read_text()
        self.assertIn("db SPRITE_MEWTWO       ; 21 MEWTWO", dorm)
        self.assertIn("ld a, [wRoguePokemonForm1]", procedural)
        # Bosses and optional encounters share one resolver: dedicated first.
        self.assertRegex(
            procedural,
            r"(?s)PCGetSpeciesOWSprite::\s+call PCGetDedicatedPokemonSprite\s+"
            r"ret c\s+call PCGetPokemonSpriteCategory",
        )
        self.assertRegex(procedural, r"(?s)PCGetBossOWSprite::.*?call PCGetSpeciesOWSprite")
        optional = (ROOT / "custom_functions/optional_encounter.asm").read_text()
        self.assertRegex(
            optional,
            r"(?s)OptionalEncounterPatchSprite::.*?ld a, \[wOptionalEncounterSpecies\].*?"
            r"farcall PCGetSpeciesOWSprite",
        )
        self.assertIn("farcall PCGetDedicatedPokemonSprite", follower)
        self.assertIn("and FORM_MASK | %00001010", follower)
        self.assertRegex(
            follower,
            r"(?s)FollowerResolveActiveSpecies:.*?ld hl, wPartyMons\s+"
            r"ld bc, PARTYMON_STRUCT_LENGTH\s+call AddNTimes.*?"
            r"ld bc, MON_CATCH_RATE\s+add hl, bc\s+ld d, \[hl\]",
        )

    def test_lookup_sheets_turn_and_step(self):
        # A size check passes a padded one-pose image; this compares the frames.
        for sprite in sorted(lookup_sprites()):
            with self.subTest(sprite=sprite):
                gaps = sheet_gaps(sprite)
                self.assertEqual(gaps["turns"], [], "cannot face every direction")
                if sprite in NO_STEP_FRAMES:
                    self.assertEqual(len(gaps["steps"]), 3, "art fixed: drop it from NO_STEP_FRAMES")
                else:
                    self.assertEqual(gaps["steps"], [], "walks without a step frame")
                if sprite in WRONG_FACING_WALK:
                    self.assertNotEqual(gaps["facing"], [], "art fixed: drop it from WRONG_FACING_WALK")
                else:
                    self.assertEqual(gaps["facing"], [], "a walk frame faces another direction")

    def test_party_pose_sheets_are_caught_by_the_frame_check(self):
        # The check above must reject the sheets that motivated it.
        for sprite in PARTY_POSE:
            with self.subTest(sprite=sprite):
                self.assertNotEqual(sheet_gaps(sprite)["turns"], [])
                self.assertNotIn(sprite, lookup_sprites())


if __name__ == "__main__":
    unittest.main()
