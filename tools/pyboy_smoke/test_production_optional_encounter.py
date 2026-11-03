"""Accepted battles/gifts entered through production dispatch, Debug2 disabled."""
import test_optional_encounter as pink
import test_optional_cave_cold as cold
from source_constants import parse_rgbds_constants


def clear_debug_fixture(h):
    flags=parse_rgbds_constants(pink.geometry.ROOT/'constants/ram_constants.asm')
    h.write8('wStatusFlags6',h.read8('wStatusFlags6')&~(1<<flags['BIT_DEBUG2_MODE']))


def settle_before_trial(test):
    test.production_active=False
    original=test.h.preload_and_enter_wild_area
    def preload(*args,**kwargs):
        # As in the generation corpus, finish the boot visit's in-flight
        # preload before measuring the explicitly requested fresh stage.
        test.h.tick(240)
        test.rolls['count']=0
        test.production_active=True
        return original(*args,**kwargs)
    test.h.preload_and_enter_wild_area=preload


class ProductionPinkTest(pink.OptionalEncounterTest):
    def setUp(self):
        super().setUp()
        self.h.register_hook('OptionalForestResetEncounter',lambda _:clear_debug_fixture(self.h) if self.production_active else None)
        self.h.register_hook('OptionalForestOutcome',lambda _:setattr(self.h.pyboy.register_file,'A',0))
        self.rolls=self.h.hook_flag('OptionalForestOutcome')
        settle_before_trial(self)

    def enter_grove(self):
        result=super().enter_grove()
        self.assertEqual(self.rolls['count'],1)
        return result


class ProductionColdCaveTest(cold.CaveColdEncounterTest):
    def setUp(self):
        super().setUp()
        self.h.register_hook('OptionalCaveAssignEncounter',lambda _:clear_debug_fixture(self.h) if self.production_active else None)
        self.h.register_hook('OptionalCaveOutcome',lambda _:setattr(self.h.pyboy.register_file,'A',self.bin))
        self.rolls=self.h.hook_flag('OptionalCaveOutcome')
        settle_before_trial(self)

    def run_encounter(self,species,*args,**kwargs):
        self.bin=0 if species=='ONIX' else 10
        super().run_encounter(species,*args,**kwargs)
        self.assertEqual(self.rolls['count'],1)
