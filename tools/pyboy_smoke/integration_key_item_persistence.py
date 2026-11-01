"""All fourteen items and three live tiers through the real save writer/Continue.

Ownership, loadouts and spent charges are configured. SaveGameData is invoked
directly; actual menu input is covered by integration_endless_save_boundaries.
"""
import json
from itertools import product
from pathlib import Path
import unittest

import autoplay
from harness import RedRogueHarness
from menu_save_journey import cold_continue
import save_reload
from test_key_item_effects import all_tiers
from test_key_item_equipment import NAMES, bits

ROOT=Path(__file__).resolve().parents[2]
OUTPUT=Path(__file__).parent/'artifacts/key_item_persistence'


def fields(h):
    def cartridge(label):
        bank,address=h.symbols.get(label)
        return [h.pyboy.memory[bank,address+i] for i in range(4)]
    return {'ownership_and_equipment':cartridge('sKeyItemsBitfield'),
            'tiers':cartridge('sKeyItemTiers'),
            'run_counters':{label:h.read8(label) for label in
                ('wKODefianceUsages','wTurnRewindUsages','wDiceCharges',
                 'wHealAllItemLevel','wRestorePPItemLevel')}}


class KeyItemPersistenceIntegrationTest(unittest.TestCase):
    def test_all_items_live_tiers_equipped_and_pc_owned_through_cold_continue(self):
        h=RedRogueHarness(ROOT,OUTPUT)
        self.addCleanup(h.close)
        autoplay.boot(h,31,battle_count=7,difficulty='NORMAL')
        rows=[]
        for tier in range(3):
            for index,charge_state in product(range(0,len(NAMES),3),('depleted','partial','full')):
                active=NAMES[index:index+3]
                case=OUTPUT/f'tier_{tier}_group_{index//3}_{charge_state}'
                with self.subTest(tier=tier,active=active,charge_state=charge_state):
                    flags=bits(NAMES,active)
                    tiers=all_tiers({name:tier for name in NAMES})
                    h.write_sram_bytes('sKeyItemsBitfield',flags)
                    h.write_sram_bytes('sKeyItemTiers',tiers)
                    h.call_routine('RogueResetRunState')
                    counters={'depleted':(0,0,0),'partial':(0,1,0x10),
                              'full':(tier+1,tier+2,(tier+1)*0x15)}[charge_state]
                    for label,value in zip(('wKODefianceUsages','wTurnRewindUsages','wDiceCharges'),counters):
                        h.write8(label,value)
                    self.assertTrue(save_reload.settle(h))
                    expected=fields(h)
                    saved=save_reload.save_now(h)
                    sram=save_reload.sram_image(h)
                    boot=cold_continue(self,h,saved,sram,case,expected_depth=0)
                    try:
                        self.assertEqual(fields(boot.h),expected)
                        self.assertEqual(expected['ownership_and_equipment'],flags)
                        self.assertEqual(expected['tiers'],tiers)
                        rows.append({'tier':tier,'active':active,'charge_state':charge_state,
                                     'expected':expected,'loaded':fields(boot.h)})
                    finally:
                        boot.close()
        OUTPUT.mkdir(parents=True,exist_ok=True)
        (OUTPUT/'matrix.json').write_text(json.dumps({'provenance':__doc__,
            'rom_sha256':h.rom_sha256,'sym_sha256':h.sym_sha256,'cases':rows},indent=2)+'\n')
        self.assertEqual(len(rows),45)
        for name in NAMES:
            for tier in range(3):
                self.assertTrue(any(row['tier']==tier and name in row['active'] for row in rows))
                self.assertTrue(any(row['tier']==tier and name not in row['active'] for row in rows))


if __name__=='__main__':
    unittest.main(verbosity=2)
