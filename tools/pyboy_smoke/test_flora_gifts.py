"""Flora's menu must use the rolled Spore species on draw, hover and claim."""
import io
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
SPECIES = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")


class FloraGiftTest(unittest.TestCase):
    def test_cached_species_in_each_slot(self):
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.addCleanup(h.close)
        h.boot_to_lobby()
        h.park_before_hijack(idle=True)
        baseline = io.BytesIO()
        h.save_state(baseline)
        regs = h.pyboy.register_file
        names, grants = [], []

        def return_now():
            sp = regs.SP
            regs.PC = h.pyboy.memory[sp] | h.pyboy.memory[sp + 1] << 8
            regs.SP = sp + 2

        def hover(_):
            names.append(h.read_bytes("wNameBuffer", 10))
            return_now()

        def grant(_):
            grants.append(regs.A)
            regs.F = 0  # stop before the interactive party/box flow
            return_now()

        h.register_hook("PrintText", hover)
        h.register_hook("BridgeGiveMon", grant)
        h.register_hook("BridgePrintGiftDesc", lambda _: setattr(regs, "A", slot))
        h.register_hook("BridgeDoGift", lambda _: setattr(regs, "A", slot))

        def tiles(label):
            return [0x7f if c == " " else 0x80 + ord(c) - ord("A") for c in label]

        for slot, cache in enumerate(("wRoguePokemon2", "wRoguePokemon3", "wRoguePokemonForm2")):
            for species in ("BELLOSSOM", "VILEPLUME"):
                with self.subTest(slot=slot, species=species):
                    for routine in ("BridgePlaceGiftNames", "BridgePrintGiftDesc", "BridgeDoGift"):
                        baseline.seek(0)
                        h.load_state(baseline)
                        h.write8("hCurMap", MAPS["FLORAS_GROTTO"])
                        for i in range(3):
                            h.write8("wGift1", 0 if i == slot else 4, offset=i)
                        h.write8("wRoguePokemonForm3", 0xab)
                        h.write8(cache, SPECIES[species])
                        title = tiles("SPORE " + species)
                        row = h.call_routine(routine, capture=lambda hh: hh.read_bytes(
                            "wTileMap", len(title), offset=2 + 20 * (4 + slot * 2)))
                        if routine == "BridgePlaceGiftNames":
                            self.assertEqual(row, title)
                        elif routine == "BridgePrintGiftDesc":
                            self.assertEqual(names[-1][:len(species)], tiles(species))
                        else:
                            self.assertEqual(grants[-1], SPECIES[species])

    def test_flora_eligibility_stores_resolved_species_without_touching_rescue(self):
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.addCleanup(h.close)
        h.boot_to_lobby()
        h.park_before_hijack(idle=True)
        baseline = io.BytesIO()
        h.save_state(baseline)
        for slot, cache in enumerate(("wRoguePokemon2", "wRoguePokemon3", "wRoguePokemonForm2")):
            baseline.seek(0)
            h.load_state(baseline)
            h.write8("hCurMap", MAPS["FLORAS_GROTTO"])
            h.write8("wBuffer", slot, offset=1)
            h.write8("wBuffer", 0, offset=3)
            h.write8("wRoguePokemon1", SPECIES["PIKACHU"])
            h.write8("wRoguePokemonForm1", 1)
            h.write8("wRoguePokemonForm3", 0)
            result = h.call_routine("BridgeGiftIsEligible", capture=lambda hh: (
                hh.read8(cache), hh.read8("wRoguePokemon1"), hh.read8("wRoguePokemonForm1")))
            self.assertEqual(result, (SPECIES["ODDISH"], SPECIES["PIKACHU"], 1))
