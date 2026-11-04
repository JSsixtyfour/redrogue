"""Exact categorical bins and production-path reset/gating, actual ROM code."""
import io
import unittest
from collections import Counter
from harness import RedRogueHarness
from source_constants import parse_map_constants,parse_rgbds_constants
from test_optional_cold_moves import SPECIES
from test_forest_grotto import ROOT,ARTIFACTS


class OptionalEncounterOddsTest(unittest.TestCase):
    def test_cave_theme_has_exactly_33_cold_bins(self):
        h=RedRogueHarness(ROOT,ARTIFACTS)
        try:
            h.boot_to_lobby(battle_count=11,encounter_kind=4);h.tick(240)
            flags=parse_rgbds_constants(ROOT/'constants/ram_constants.asm')
            h.write8('wStatusFlags6',h.read8('wStatusFlags6')&~(1<<flags['BIT_DEBUG2_MODE']))
            h.write8('wStageEvent',0);base=io.BytesIO();h.save_state(base)
            maps=parse_map_constants(ROOT/'constants/map_constants.asm');context={}
            h.register_hook('PCRollBoss.paletteRolled',lambda _:setattr(h.pyboy.register_file,'A',context['roll']))
            ranges=[]
            h.register_hook('OptionalCaveOutcome',lambda _:ranges.append(h.pyboy.register_file.C))
            counts=Counter()
            for roll in range(100):
                h.load_state(base);context['roll']=roll
                h.preload_wild_area(maps['PROCEDURAL_CAVE_1'])
                theme=h.read_sram_bytes('sProcCavePalette',1,bank=0)[0]
                self.assertEqual(theme,int(roll>=67),roll);counts[theme]+=1
            self.assertEqual(counts,Counter({0:67,1:33}))
            self.assertEqual(ranges,[33]*33) # production cold draws use range33
            # 100 theme bins x33 conditional encounter bins: exact nominal
            # totals before the accepted no-ladder availability loss.
            self.assertEqual(counts[1]*10,330) #330/3300 =10%
            self.assertEqual(counts[1]*5,165) #165/3300 =5%
            self.assertEqual(counts[0]*33+counts[1]*18,2805) #85%
            self.assertFalse(h.hook_errors,h.hook_errors)
        finally:h.close()

    def test_every_forest_and_cave_bin(self):
        h=RedRogueHarness(ROOT,ARTIFACTS)
        try:
            h.boot_to_lobby();h.park_before_hijack();base=io.BytesIO();h.save_state(base)
            maps=parse_map_constants(ROOT/'constants/map_constants.asm');context={}
            def input_bin(_):
                h.pyboy.memory[0x0000]=10;h.pyboy.memory[0x4000]=0
                h.pyboy.memory[h.address('sProcForestPalette')]=context['season']
                h.pyboy.register_file.A=context['roll']
            h.register_hook('OptionalForestOutcome',input_bin);h.register_hook('OptionalCaveOutcome',input_bin)
            counts={}
            for kind in ('forest','cave'):
                for season in (range(4) if kind=='forest' else (1,)):
                    outcomes=Counter()
                    for roll in range(100 if kind=='forest' else 33):
                        h.load_state(base);context.update(season=season,roll=roll)
                        for i in range(7):h.write8('wOptionalEncounterSpecies',0,offset=i)
                        h.call_routine('OptionalForestOutcome' if kind=='forest' else 'OptionalCaveOutcome')
                        expected=(SPECIES['SNORLAX'] if season==3 else SPECIES['BUTTERFREE']) if kind=='forest' and roll<(24,4,12,20)[season] else SPECIES['ONIX'] if kind=='cave' and roll<10 else SPECIES['SNORLAX'] if kind=='cave' and roll<15 else 0
                        actual=h.read8('wOptionalEncounterSpecies');self.assertEqual(actual,expected,(kind,season,roll))
                        outcomes[actual]+=1
                        if actual:
                            self.assertEqual(h.read8('wOptionalEncounterMap'),maps['PROCEDURAL_FOREST_GROTTO' if kind=='forest' else 'PROCEDURAL_CAVE_SUBROOM'])
                            self.assertGreater(h.read8('wOptionalEncounterLevel'),0)
                            self.assertEqual(h.read8('wOptionalEncounterState'),0)
                            self.assertEqual(h.read_bytes('wOptionalEncounterScript',2),[0,0])
                            package=h.read8('wOptionalEncounterPackage')
                            self.assertEqual(package,1) if actual==SPECIES['BUTTERFREE'] else self.assertIn(package,(2,3))
                        else:self.assertEqual(h.read_bytes('wOptionalEncounterSpecies',7),[0]*7)
                    counts[kind,season]=outcomes
            self.assertEqual(sum(counts['forest',s][SPECIES['BUTTERFREE']] for s in range(4)),40)
            self.assertEqual(sum(counts['forest',s][SPECIES['SNORLAX']] for s in range(4)),20)
            self.assertEqual(counts['cave',1],Counter({SPECIES['ONIX']:10,SPECIES['SNORLAX']:5,0:18}))
            self.assertFalse(h.hook_errors,h.hook_errors)
        finally:h.close()

    def test_warm_cave_clears_old_assignment_without_rolling(self):
        h=RedRogueHarness(ROOT,ARTIFACTS)
        try:
            h.boot_to_lobby();h.park_before_hijack()
            flags=parse_rgbds_constants(ROOT/'constants/ram_constants.asm')
            h.write8('wStatusFlags6',h.read8('wStatusFlags6')&~(1<<flags['BIT_DEBUG2_MODE']))
            for i in range(7):h.write8('wOptionalEncounterSpecies',165,offset=i)
            def warm(_):
                h.pyboy.memory[0x0000]=10;h.pyboy.memory[0x4000]=0
                h.pyboy.memory[h.address('sProcCavePalette')]=0
            h.register_hook('OptionalCaveAssignEncounter',warm)
            rolls=h.hook_flag('OptionalCaveOutcome')
            h.call_routine('OptionalCaveAssignEncounter')
            self.assertEqual(h.read_bytes('wOptionalEncounterSpecies',7),[0]*7)
            self.assertEqual(rolls['count'],0)
        finally:h.close()
