"""A completed lobby trade must restore the scrolled BG map without lost writes."""
from pathlib import Path
import unittest

from harness import RedRogueHarness

ROOT = Path(__file__).resolve().parents[2]


class TradeRedrawTest(unittest.TestCase):
    def trade(self, *, sgb=False, cgb=False, given=0x54, received=0x24, form=0):
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
            # PIKACHU ($54) differs from TRADE_FOR_RANDOM ($0a). The debug
            # party's CATERPIE ($0a) otherwise masks their shared-memory bug.
            h.write8('wPartySpecies',given)
            h.write8('wPartyMon1Species',given)
            h.write8('wroguenpctradegive',given)
            h.write8('wroguenpctradeget',received)  # default Pidgey: no evolution
            h.write8('wroguenpctradeform',form)
            restored=h.hook_flag('InGameTrade_RestoreScreen')
            finished=h.hook_flag('InGameTrade_DoTrade.tradeSucceeded')
            exchanges=h.hook_flag('InGameTrade_PrepareTradeData')
            results=[]
            def result_text(_):
                if h.pyboy.register_file.HL==h.address('_TradedForText'):
                    results.append(h.pyboy.frame_count)
            h.register_hook('TextCommandProcessor',result_text)
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
            self.assertEqual(exchanges['count'],1)
            self.assertEqual(h.read8('wWhichTrade'),10)  # TRADE_FOR_RANDOM
            self.assertEqual(len(results),1,'trade result printed more than once')
            self.assertEqual(h.read8('hWY'),144)
            # Compare the actual wrapped BG map, not just the WRAM tilemap:
            # the original fault left WRAM correct and dropped VRAM writes.
            sx,sy=h.read8('hSCX')//8,h.read8('hSCY')//8
            expected=h.read_bytes('wTileMap',360)
            actual=[h.pyboy.memory[0x9800+((sy+y)%32)*32+(sx+x)%32]
                    for y in range(18) for x in range(20)]
            self.assertEqual(actual,expected)
            self.assertEqual(blocked,[],'row writes ran into locked VRAM')
            stride=h.address('wPartyMon2CatchRate')-h.address('wPartyMon1CatchRate')
            catch_rate=h.read8('wPartyMon1CatchRate',(h.read8('wPartyCount')-1)*stride)
            self.assertEqual(catch_rate & 0x60,form << 5)
            self.assertFalse(h.hook_errors,h.hook_errors)
        finally:
            h.close()

    def test_dmg_trade_restores_background(self):
        self.trade()

    def test_sgb_packet_path_trade_restores_background(self):
        self.trade(sgb=True)

    def test_caterpie_trade_still_has_one_result(self):
        self.trade(given=0x0a)

    def test_sgb_trade_retains_offered_form(self):
        self.trade(sgb=True,received=0x4d,form=1)  # Alolan Meowth

if __name__=='__main__':
    unittest.main()
