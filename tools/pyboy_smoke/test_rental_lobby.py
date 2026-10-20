"""Live DMG/CGB receptionist, packed tile transfers and text close lifecycle."""

from pathlib import Path

import unittest

from harness import RedRogueHarness

from source_constants import parse_rgbds_constants

from test_move_tutor_prices import run_entry, return_from_call



ROOT = Path(__file__).resolve().parents[2]

ART = Path(__file__).parent / "artifacts"





class RentalLobbyTest(unittest.TestCase):

    def live(self, cgb):

        h = RedRogueHarness(ROOT, ART, cgb_mode=cgb)

        self.addCleanup(h.close)

        h.boot_to_lobby()

        h.tick(180)

        self.assertEqual(h.read8("wNumSprites"), 13)

        self.assertEqual([h.read8(f"wSprite{i:02}StateData2ImageBaseOffset") for i in range(1,14)],

                         [3,4,4,5,11,12,6,7,8,9,13,14,14])

        for name, address in (("GameboyKidSprite", 0x86C0), ("LinkReceptionistSprite", 0x8700)):

            bank, source = h.symbols.get(name)

            offset = bank * 0x4000 + source - 0x4000

            self.assertEqual(bytes(h.pyboy.memory[address:address+64]),

                             h._rom_file.getvalue()[offset:offset+64])

        # A genuine approach around the existing counter, with no teleport.

        for direction, field, target in (("up","wYCoord",9), ("left","wXCoord",3),

                                         ("up","wYCoord",2), ("right","wXCoord",7)):

            h.pyboy.button_press(direction)

            h.wait_until(lambda: h.read8(field) == target, direction, 600)

            h.pyboy.button_release(direction)

            h.tick(40)

        h.tap("up")

        h.tick(40)

        h.call_routine("RentalResetRecord")

        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")

        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")

        for field, value in {"wRentalOfferFlags":3, "wRentalOfferSpecies":species["PIKACHU"],

            "wRentalOfferForm":0, "wRentalOfferClass":1, "wRentalOfferLevel":25,

            "wRentalOfferSource":0, "wBoxCount":0, "wBoxSpecies":255}.items():

            h.write8(field,value)

        for field, data in (("wRentalOfferDVs",[0x12,0x34]),

                            ("wRentalOfferMoves",[moves["THUNDERBOLT"],moves["SURF"],0,0]),

                            ("wPlayerMoney",[0,0x50,0])):

            for i,value in enumerate(data): h.write8(field,value,offset=i)

        offer = h.read_bytes("wRentalOfferSpecies",12)

        party = h.read_bytes("wPartyCount", h.address("wPartyDataEnd") - h.address("wPartyCount"))

        entries = h.hook_flag("RentalInteraction")

        menus = h.hook_flag("YesNoChoice")

        text_pages = []

        def capture_page():
            page = h.read_bytes("wTileMap",360)
            text_pages.append(page)
            name_tiles = bytes(0x80 + ord(char) - ord("A") for char in "PIKACHU")
            if name_tiles in bytes(page):
                h.pyboy.screen.image.save(ART / ("rental_name_cgb.png" if cgb else "rental_name_dmg.png"))
        h.hook_flag("ManualTextScroll", action=capture_page)

        def open_menu(count):

            h.tap("a")

            for _ in range(30):

                h.tick(12,render=True)

                if menus["count"] == count: break

                h.tap("a")

            self.assertEqual(menus["count"],count)

            h.tick(30,render=True)

        def close_text():
            # Final prompt owns the only acknowledgement. One A must close it.
            h.tick(60)
            self.assertTrue(h.read8("wFontLoaded") & 1)
            h.tap("a")
            h.tick(90)
            self.assertFalse(h.read8("wFontLoaded") & 1,
                             "final rental message required a second A press")

        open_menu(1)

        # Assert rendered glyphs, not only source buffers or transaction state.

        def glyphs(text):

            import re

            mapping = dict((char,int(value,16)) for char,value in re.findall(

                r'charmap "(.)",\s*\$([0-9a-fA-F]+)',

                (ROOT / "constants/charmap.asm").read_text(encoding="utf-8")))

            return bytes(mapping[char] for char in text)

        self.assertTrue(any(glyphs("PIKACHU") in bytes(page) for page in text_pages))

        self.assertTrue(any(glyphs("Level  25") in bytes(page) or glyphs("Level 25") in bytes(page)

                            for page in text_pages))

        self.assertIn(glyphs("One zone: ¥2500"),bytes(h.read_bytes("wTileMap",360)))

        h.pyboy.screen.image.save(ART / ("rental_preview_cgb.png" if cgb else "rental_preview_dmg.png"))

        h.tap("b")

        close_text()

        self.assertEqual(h.read_bytes("wRentalOfferSpecies",12),offer)

        self.assertEqual(h.read_bytes("wPlayerMoney",3),[0,0x50,0])

        self.assertEqual(h.read8("wRentalOwner"),0)

        open_menu(2)

        h.tap("a")

        close_text()

        self.assertEqual(h.read_bytes("wPartyCount",len(party)),party)

        self.assertEqual(h.read_bytes("wPlayerMoney",3),[0,0x25,0])

        self.assertEqual(h.read8("wBoxCount"),1)

        self.assertEqual(h.read_bytes("wBoxMon1Moves",4),offer[5:9])

        self.assertEqual(h.read8("wRentalOwner"),7+20*(h.read8("wCurrentBoxNum") & 127))

        self.assertEqual(h.read8("hWY"),144)

        self.assertEqual(h.read8("hJoyIgnore"),0)

        h.tap("a")

        close_text()

        self.assertEqual(entries["count"],3)

        self.assertEqual(menus["count"],2)

        self.assertEqual(h.read_bytes("wPlayerMoney",3),[0,0x25,0])



    def test_live_dmg_preview_cancel_box_purchase_and_second_denial(self):

        self.live(False)



    def test_normal_appearance_threshold_and_debug_override(self):

        h = RedRogueHarness(ROOT,ART)

        self.addCleanup(h.close)

        h.boot_to_lobby()

        const = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")

        toggle = const["TOGGLE_PC_RENTAL_OFFICIAL"]

        def roll(value, debug):

            def rng(_):

                h.pyboy.register_file.A = value

                return_from_call(h)

            return run_entry(h,"PCLobbyExtrasSetup",setup=lambda h: h.write8("wStatusFlags6",2 if debug else 0),

                hooks={"Random":rng}, capture=lambda h:{"hidden": bool(h.read8("wToggleableObjectFlags", offset=toggle//8) & (1 << (toggle%8)))})

        for value in (0,84,85,255):

            self.assertEqual(roll(value,False)["hidden"],value>=85)

        self.assertFalse(roll(255,True)["hidden"])

