"""Softboiled party-menu visibility and the real HP-transfer path.

UI waits/animations and target selection are stubbed; HP arithmetic, item
dispatch, donor eligibility, and pseudo-item cleanup execute in the ROM.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_move_tutor_prices import run_entry, return_from_call

ROOT = Path(__file__).resolve().parents[2]
MOVES = parse_rgbds_constants(ROOT / "constants/move_constants.asm")


class SoftboiledFieldTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = RedRogueHarness(ROOT, Path(__file__).parent / "artifacts")
        cls.h.boot_fight2(seed=1)

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def test_only_softboiled_is_exposed_in_every_move_slot(self):
        h = self.h
        for slot in range(5):
            with self.subTest(slot=slot):
                def setup(h):
                    h.write8("hWhichPokemon", 0)
                    moves = [MOVES[m] for m in ("SURF", "STRENGTH", "CUT", "FLY")]
                    if slot < 4:
                        moves[slot] = MOVES["SOFTBOILED"]
                    for i, move in enumerate(moves):
                        h.write8("wPartyMon1Moves", move, offset=i)
                result = run_entry(h, "DisplayFieldMoveMonMenu", setup=setup,
                    hooks={"UpdateSprites": lambda _: return_from_call(h)},
                    capture=lambda h: {"count": h.read8("wNumFieldMoves"),
                        "x": h.read8("hFieldMoveMonMenuTopMenuItemX"),
                        "tiles": h.read_bytes("wTileMap", 360)})
                self.assertEqual(result["count"], int(slot < 4))
                self.assertEqual(result["x"], 8 if slot < 4 else 12)
                if slot < 4:
                    # Standard font: A=$80. Verify every letter at the actual
                    # menu coordinates, including the unchanged Stats row.
                    self.assertEqual(result["tiles"][209:219],
                                     [0x80 + ord(c) - ord("A") for c in "SOFTBOILED"])
                    self.assertEqual(result["tiles"][249:254],
                                     [0x80 + ord(c) - ord("A") for c in "STATS"])

    def transfer(self, donor_hp=100, target_hp=10, cancel=False):
        h = self.h
        def setup(h):
            for label, value in (("hIsInBattle", 0), ("hWhichPokemon", 0),
                                 ("wRogueFlagsBitfield", 0), ("wPartyCount", 2),
                                 ("wPseudoItemID", 0), ("wPartyAndBillsPCSavedMenuItem", 0)):
                h.write8(label, value)
            for label, value in (("wPartyMon1HP", donor_hp), ("wPartyMon1MaxHP", 200),
                                 ("wPartyMon2HP", target_hp), ("wPartyMon2MaxHP", 100)):
                h.write8(label, value >> 8)
                h.write8(label, value & 255, offset=1)
        def choose(_):
            h.write8("hWhichPokemon", 1)
            h.write8("wCurPartySpecies", h.read8("wPartySpecies", offset=1))
            h.pyboy.register_file.F = 0x10 if cancel else 0
            return_from_call(h)
        hooks = {name: (lambda _: return_from_call(h)) for name in
                 ("PrintText", "PlaySoundWaitForCurrent", "UpdateHPBar2",
                  "ClearScreen", "RedrawPartyMenu", "DelayFrames", "WaitForTextScrollButtonPress")}
        hooks["GoBackToPartyMenu"] = choose
        return run_entry(h, "UseSoftboiledFieldMove", setup=setup, hooks=hooks,
            capture=lambda h: {"donor": h.read_bytes("wPartyMon1HP", 2),
                "target": h.read_bytes("wPartyMon2HP", 2),
                "pseudo": h.read8("wPseudoItemID"),
                "cursor": h.read8("wPartyAndBillsPCSavedMenuItem"),
                "bag": h.read_bytes("wRecoveryItemCounts",
                    h.address("wItemCountsEnd") - h.address("wRecoveryItemCounts")),
                "pp": h.read_bytes("wPartyMon1PP", 4)})

    def test_transfer_caps_recipient_and_consumes_no_item_or_pp(self):
        bag = self.h.read_bytes("wRecoveryItemCounts",
            self.h.address("wItemCountsEnd") - self.h.address("wRecoveryItemCounts"))
        pp = self.h.read_bytes("wPartyMon1PP", 4)
        for target, expected in ((10, 50), (90, 100)):
            with self.subTest(target=target):
                result = self.transfer(target_hp=target)
                self.assertEqual(result["donor"], [0, 60])
                self.assertEqual(result["target"], [0, expected])
                self.assertEqual(result["pseudo"], 0)
                self.assertEqual(result["cursor"], 0)
                self.assertEqual(result["bag"], bag)
                self.assertEqual(result["pp"], pp)

    def test_low_hp_cancel_full_and_fainted_do_not_spend_hp(self):
        for hp, target, cancel in ((39, 10, False), (40, 10, False),
                                   (100, 10, True), (100, 100, False),
                                   (100, 0, False)):
            with self.subTest(donor=hp, target=target, cancel=cancel):
                result = self.transfer(hp, target, cancel)
                self.assertEqual(result["donor"], [0, hp])
                self.assertEqual(result["target"], [0, target])
                self.assertEqual(result["pseudo"], 0)
