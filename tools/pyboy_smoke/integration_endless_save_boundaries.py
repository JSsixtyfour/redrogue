"""Configured first HOF, real menu saves, reset-before-save and later Continue."""
import io
import json
from pathlib import Path
import unittest

import autoplay
from harness import RedRogueHarness
from integration_endless_journey import EVENTS, JourneyAgent, MAPS, ROOT
from menu_save_journey import cold_continue, save_with_inputs
import save_reload
from source_constants import parse_rgbds_constants
from test_key_item_effects import all_tiers
from test_key_item_equipment import bits, NAMES

OUTPUT = Path(__file__).parent / 'artifacts/endless_save_boundaries'


def retained(h):
    def cartridge(label, length):
        bank, address = h.symbols.get(label)
        return [h.pyboy.memory[bank, address + i] for i in range(length)]
    count = h.read8('wPartyCount')
    return {'charges': [h.read8(name) for name in ('wKODefianceUsages','wTurnRewindUsages','wDiceCharges')],
            'items': h.read_bytes('wRecoveryItemCounts', h.address('wItemCountsEnd') - h.address('wRecoveryItemCounts')),
            'flags': cartridge('sKeyItemsBitfield', 4), 'tiers': cartridge('sKeyItemTiers', 4),
            'party_identity': [[h.read8(f'wPartyMon{i}Species'), h.read8(f'wPartyMon{i}Type1'),
                                h.read8(f'wPartyMon{i}Type2'), h.read8(f'wPartyMon{i}CatchRate')]
                               for i in range(1, count + 1)],
            'daycare': h.read_bytes('wDayCareMon',33), 'daycare_in_use':h.read8('wDayCareInUse'),
            'daycare_elapsed': (h.read8('wBattleCount') - h.read8('wDayCareDepositBattleCount')) & 255}


class EndlessSaveBoundaryIntegrationTest(unittest.TestCase):
    def test_real_menu_save_reset_and_cold_continue_at_two_boundaries(self):
        output = OUTPUT / self._testMethodName
        output.mkdir(parents=True, exist_ok=True)
        h = RedRogueHarness(ROOT, output)
        self.addCleanup(h.close)
        autoplay.boot(h, 31, battle_count=73, difficulty='VERY_EASY')
        # Legal but configured retained state. No acquisition is claimed.
        h.set_event(EVENTS['EVENT_AI_DEFEATED'])
        h.write_sram_bytes('sKeyItemsBitfield', bits(NAMES, ['KO_DEFIANCE','TURN_REWIND','DOOR_DICE']))
        h.write_sram_bytes('sKeyItemTiers', all_tiers({name:2 for name in NAMES}))
        for label, value in (('wKODefianceUsages',1),('wTurnRewindUsages',1),('wDiceCharges',0x11)):
            h.write8(label,value)
        types = parse_rgbds_constants(ROOT/'constants/type_constants.asm')
        h.write8('wPartyMon1CatchRate',4)  # generic stored type-pair variant
        h.write8('wPartyMon1Type1',types['GRASS'])
        h.write8('wPartyMon1Type2',types['WATER'])
        mon = h.read_bytes('wPartyMon1',33)
        mon[3] = h.read8('wPartyMon1Level')
        h.pyboy.memory[h.address('wDayCareMon'):h.address('wDayCareMon')+33] = mon
        h.write8('wDayCareInUse',1)
        h.write8('wDayCareDepositBattleCount',61)
        h.write8('wWarpEntries',0,2)
        h.write8('wWarpEntries',MAPS['HALL_OF_FAME'],3)
        agent = JourneyAgent(h,accept=True,target_continuations=2)
        original = retained(h)
        saved, pre_sram = save_with_inputs(self,h,agent,output/'before_continuation')
        agent.walk('up'); agent.walk('down')
        start = h.pyboy.frame_count
        while agent.first_stage is None and h.pyboy.frame_count-start < 30_000:
            agent.step(); agent.checks.after_step()
        self.assertIsNotNone(agent.first_stage)
        self.assertEqual(h.read8('wEndlessDepth'),1)
        self.assertEqual(retained(h),original,'retained fields changed before the next saved stage')
        # HOF may write its archive, but YES must not publish new main data.
        unsaved_sram = save_reload.sram_image(h)
        reset = cold_continue(self,h,saved,unsaved_sram,output/'reset_before_next_save',expected_depth=0)
        reset.close()
        saved_one, sram_one = save_with_inputs(self,h,agent,output/'after_first_continuation')
        boot = cold_continue(self,h,saved_one,sram_one,output/'cold_continue_first',expected_depth=1)
        self.addCleanup(boot.close)
        self.assertEqual(retained(boot.h),retained(h))
        # Continue the PRIMARY journey from the cold-restarted emulator.
        h = boot.h
        agent = JourneyAgent(h,accept=True,target_continuations=2)
        agent.stage_map = agent.last_stage = h.read8('hCurMap')
        start = h.pyboy.frame_count
        agent.last_progress_frame = start
        while h.pyboy.frame_count-start < 1_500_000:
            agent.step(); agent.checks.after_step(); agent.note_progress()
            if agent.first_stage is not None and h.read8('wEndlessDepth')==2:
                break
            self.assertEqual(agent.report.runs,[], 'loss ended the natural intervening circuit')
            self.assertIsNone(agent.checks.crash)
            self.assertEqual(h.hook_errors,[])
        else:
            self.fail('second continuation not reached')
        saved_two,sram_two=save_with_inputs(self,h,agent,output/'after_second_continuation')
        second=cold_continue(self,h,saved_two,sram_two,output/'cold_continue_second',expected_depth=2)
        self.addCleanup(second.close)
        self.assertEqual(retained(second.h),retained(h))
        result={'provenance':'configured first HOF, legal retained-state fixture, real save/continuation inputs',
                'injected_fields':['EVENT_AI_DEFEATED','key item ownership/tiers and spent counters',
                    'party1 stored type pair','daycare mon/in-use/deposit snapshot','lobby arrival warp'],
                'rom_sha256':h.rom_sha256,'sym_sha256':h.sym_sha256,
                'primary_cold_restart_between_circuits':True,'final_depth':second.h.read8('wEndlessDepth'),
                'intervening_circuit_stages':agent.report.stages_cleared,
                'intervening_circuit_battles':agent.report.battles_won,
                'final_retained':retained(second.h),'events':agent.report.events,'inputs':agent.full_inputs}
        (output/'journey.json').write_text(json.dumps(result,indent=2)+'\n')
        self.assertGreaterEqual(agent.report.stages_cleared,8)
        self.assertGreaterEqual(agent.report.battles_won,8)


if __name__ == '__main__':
    unittest.main(verbosity=2)
