"""A completed lobby trade must restore the scrolled BG map without lost writes."""
from pathlib import Path
import unittest

from harness import RedRogueHarness

ROOT = Path(__file__).resolve().parents[2]


class TradeRedrawTest(unittest.TestCase):
    def trade(self, *, sgb=False, cgb=False):
        h = RedRogueHarness(ROOT, ROOT/'builds/route_issue_20261027/trade_tests', cgb_mode=cgb)
        try:
            h.boot_to_lobby(battle_count=37)
            if sgb:
                # PyBoy does not emulate the SNES side; execute the GB's SGB
                # packet path and measure the GB PPU transfer deadlines.
                h.write8('wOnSGB',1)
            h.tick(60)
            def move(button):
                h.tap(button,4);h.tick(30)
            for label, direction, target, predicate in (
                ('wYCoord','up',10,lambda x,t:x<=t),
                ('wXCoord','left',4,lambda x,t:x<=t),
                ('wYCoord','down',11,lambda x,t:x>=t),
            ):
                for _ in range(8):
                    if predicate(h.read8(label),target):
                        break
                    move(direction)
            move('right')  # face the trader at (5,11)
            self.assertEqual((h.read8('wXCoord'),h.read8('wYCoord')),(4,11))
            h.write8('wroguenpctradegive',h.read8('wPartySpecies'))
            h.write8('wroguenpctradeget',0x24)  # Pidgey: no trade evolution
            h.write8('wroguenpctradeform',0)
            restored=h.hook_flag('InGameTrade_RestoreScreen')
            finished=h.hook_flag('InGameTrade_DoTrade.tradeSucceeded')
            blocked=[]
            def at_write(_):
                if restored['count']>=2 and h.pyboy.memory[0xff41]&3==3:
                    r=h.pyboy.register_file
                    blocked.append((r.D<<8|r.E,h.pyboy.memory[0xff44]))
            bank,addr=h.symbols.get('RedrawRowOrColumn.loop2')
            h.pyboy.hook_register(bank,addr+1,at_write,None)
            h.pyboy.hook_register(bank,addr+4,at_write,None)
            for _ in range(700):
                h.tap('a',2);h.tick(12)
                if finished['count']:
                    break
            self.assertTrue(finished['count'],'trade did not complete')
            for _ in range(16):
                h.tap('b',2);h.tick(12)
            h.tick(30)
            self.assertEqual(h.read8('hWY'),144)
            # Compare the actual wrapped BG map, not just the WRAM tilemap:
            # the original fault left WRAM correct and dropped VRAM writes.
            sx,sy=h.read8('hSCX')//8,h.read8('hSCY')//8
            expected=h.read_bytes('wTileMap',360)
            actual=[h.pyboy.memory[0x9800+((sy+y)%32)*32+(sx+x)%32]
                    for y in range(18) for x in range(20)]
            self.assertEqual(actual,expected)
            self.assertEqual(blocked,[],'row writes ran into locked VRAM')
        finally:
            h.close()

    def test_dmg_trade_restores_background(self):
        self.trade()

    def test_sgb_packet_path_trade_restores_background(self):
        self.trade(sgb=True)

if __name__=='__main__':
    unittest.main()
