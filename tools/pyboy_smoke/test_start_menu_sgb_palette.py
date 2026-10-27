"""START close provides an explicit SGB palette/attribute recovery boundary."""
from pathlib import Path
import unittest

from harness import RedRogueHarness

ROOT = Path(__file__).resolve().parents[2]


class StartMenuSGBPaletteTest(unittest.TestCase):
    def check_close(self, *, sgb=False, cgb=False, button='b'):
        h = RedRogueHarness(ROOT, ROOT/'builds/sgb_palette_recovery_20261027/tests', cgb_mode=cgb)
        try:
            h.boot_to_lobby(battle_count=37)
            if sgb:
                # Exercise GB-side packet production. PyBoy does not emulate
                # the SNES palette state or the EverDrive menu.
                h.write8('wOnSGB', 1)
                h.write8('wDefaultPaletteCommand', 9)  # SET_PAL_OVERWORLD
                h.write8('wLastMap', 0x0c)  # ROUTE_1: lobby inherits PAL_ROUTE
            h.tick(60)
            packets = []
            def sent(_):
                ptr = h.pyboy.register_file.HL
                packets.append(list(h.pyboy.memory[ptr:ptr+16]))
            h.register_hook('SendSGBPacket', sent)
            refresh = h.hook_flag('RunDefaultPaletteCommand')
            party = h.hook_flag('StartMenu_Pokemon')
            h.tap('start', 4)
            h.tick(30)
            self.assertEqual(packets, [])
            refresh_before = refresh['count']
            h.tap(button, 4)
            h.tick(60)
            self.assertEqual(h.read8('hWY'), 144)
            self.assertEqual(party['count'], 0)
            if sgb and not cgb:
                self.assertEqual(refresh['count'] - refresh_before, 1)
                self.assertEqual(len(packets), 2)
                self.assertEqual(packets[0], [0x51]+[0]*15)  # PAL_SET: PAL_ROUTE
                self.assertEqual(packets[1], [0x21,1,3,0,0,0,19,17]+[0]*8)
            else:
                self.assertEqual(refresh['count'], refresh_before)
                self.assertEqual(packets, [])
            # Full map inspection ensures the refresh leaves the restored
            # overworld tilemap and its wrapped physical BG map in agreement.
            sx, sy = h.read8('hSCX')//8, h.read8('hSCY')//8
            actual = [h.pyboy.memory[0x9800+((sy+y)%32)*32+(sx+x)%32]
                      for y in range(18) for x in range(20)]
            self.assertEqual(actual, h.read_bytes('wTileMap', 360))
        finally:
            h.close()

    def test_sgb_b_close_refreshes_room(self):
        self.check_close(sgb=True)

    def test_sgb_start_close_refreshes_room(self):
        self.check_close(sgb=True, button='start')

    def test_dmg_close_skips_refresh(self):
        self.check_close()

