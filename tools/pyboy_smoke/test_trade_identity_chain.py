"""Configured real NPC trade -> compaction -> SRAM-only cold Continue."""
import json
from pathlib import Path
import unittest
from unittest.mock import patch

import autoplay
import save_reload
from purchase_scenario import evidence
from source_constants import parse_rgbds_constants
import test_trade_redraw as trade_driver


def party(h):
    count = h.read8('wPartyCount')
    stride = h.address('wPartyMon2Species') - h.address('wPartyMon1Species')
    width = h.address('wPartyMon2OT') - h.address('wPartyMon1OT')
    return {'count': count, 'species': h.read_bytes('wPartySpecies', count + 1),
            'mons': [h.read_bytes('wPartyMons', stride, slot * stride) for slot in range(count)],
            'ot': [h.read_bytes('wPartyMonOT', width, slot * width) for slot in range(count)],
            'names': [h.read_bytes('wPartyMonNicks', width, slot * width) for slot in range(count)]}


def run_chain(test, *, cgb, output=None):
    root = Path(__file__).resolve().parents[2]
    species = parse_rgbds_constants(root/'constants/pokemon_constants.asm')
    output = Path(output) if output is not None else Path(__file__).parent/'artifacts'/f"trade_identity_chain_{'cgb' if cgb else 'dmg'}"
    output.mkdir(parents=True, exist_ok=True)
    context = {}; removed = []
    def before(h):
        context['before'] = party(h)
        h.register_hook('RemovePokemon', lambda _: removed.append(h.read8('hWhichPokemon')))
        with (output/'before.state').open('wb') as stream: h.save_state(stream)
    def after(h):
        traded = party(h)
        test.assertEqual(len(removed), 1)
        slot = removed[0]; original = context['before']
        test.assertEqual(original['species'][slot], species['PIKACHU'])
        test.assertEqual(traded['count'], original['count'])
        test.assertEqual(traded['species'], original['species'][:slot] + original['species'][slot+1:-1] + [species['MEOWTH'], 255])
        for field in ('mons', 'ot', 'names'):
            test.assertEqual(traded[field][:-1], original[field][:slot] + original[field][slot+1:], field)
        test.assertEqual(traded['mons'][-1][0], species['MEOWTH'])
        form_offset = h.address('wPartyMon1CatchRate') - h.address('wPartyMon1Species')
        test.assertEqual(traded['mons'][-1][form_offset] & 0x60, 0x20)
        evidence(h, output, 'after_trade')
        with (output/'traded.state').open('wb') as stream: h.save_state(stream)
        test.assertTrue(save_reload.settle(h))
        save_reload.save_now(h)
        sram = save_reload.sram_image(h); (output/'saved.sav').write_bytes(sram)
        with patch.object(autoplay, 'ROM', autoplay.DEBUG_ROM):
            boot = save_reload.Reboot(sram, cgb_mode=cgb)
        test.addCleanup(boot.close); boot.load()
        test.assertEqual(boot.status, 2); test.assertTrue(boot.overworld)
        restored = party(boot.h)
        test.assertEqual(restored, traded, 'trade identity changed across cold Continue')
        # Use existing ordinary movement, with no party/map/cursor writes.
        agent = autoplay.AutoplayAgent(boot.h, seed=7)
        start = agent.position(); grid = agent.read_grid()
        warps = {(x,y) for y,x,_,_ in boot.h.warp_entries()}
        moves = [(direction,target) for direction,target in grid.moves(*start)
                 if target not in agent.obstacles() and target not in warps]
        test.assertTrue(moves)
        test.assertTrue(agent.walk(moves[0][0]), 'cold Continue did not restore legal movement')
        test.assertNotEqual(agent.position(), start)
        test.assertEqual(party(boot.h), traded)
        test.assertFalse(boot.h.hook_errors)
        evidence(boot.h, output, 'after_continue')
        with (output/'continued.state').open('wb') as stream: boot.h.save_state(stream)
        record={'hardware_mode':h.hardware_mode,'rom_sha256':h.rom_sha256,'sym_sha256':h.sym_sha256,
                'fixture':'existing NPC-trade given species and offered species/form setup only',
                'save':'writer invoked at settled overworld; SRAM-only cold Continue',
                'post_trade_fixture_writes':[],'given_slot':slot,'before':original,'traded':traded,
                'restored':restored,'movement':{'from':start,'to':agent.position()},
                'scope':'full trade animation and compaction; party fields preserved across cold load'}
        (output/'chain.json').write_text(json.dumps(record,indent=2))
    trade_driver.TradeRedrawTest.trade(test,cgb=cgb,given=species['PIKACHU'],
        received=species['MEOWTH'],form=1,before_trade=before,after_trade=after,output=output/'trade')


class TradeIdentityChainTest(unittest.TestCase):
    def test_form_trade_compaction_then_cold_continue(self):
        run_chain(self,cgb=False)
