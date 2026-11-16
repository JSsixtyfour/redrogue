"""Compiled identity valuation, conditional Mankey pools, and reward colours."""
import io
from pathlib import Path
import unittest
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_map_constants
import test_swinub_rarity as swinub

ROOT = Path(__file__).resolve().parents[2]
SPECIES = parse_rgbds_constants(ROOT / 'constants/pokemon_constants.asm')
SPRITES = parse_rgbds_constants(ROOT / 'constants/sprite_constants.asm')
MAPS = parse_map_constants(ROOT / 'constants/map_constants.asm')

class RewardFormColourTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts', cgb_mode=True)
        cls.h.boot_to_lobby()
        cls.state = io.BytesIO()
        cls.h.save_state(cls.state)
    tearDownClass = classmethod(swinub.SwinubRarityTest.tearDownClass.__func__)
    configure = swinub.SwinubRarityTest.configure

    def test_reward_cache_reads_each_form_slot(self):
        self.configure(7,7)
        h = self.h
        h.write8('hCurMap',MAPS['REWARD_ROOM'])
        for i,(species,form) in enumerate((('MAGNETON',1),('JIGGLYPUFF',1),('MAGNETON',0))):
            h.write8('wRoguePokemon1',SPECIES[species],offset=i)
            h.write8('wRoguePokemonForm1',form,offset=i)
            h.write8('wSpriteStateData1',SPRITES['SPRITE_POKE_BALL'],offset=(i+1)*16)
        h.call_routine('RefreshBallRarityCache')
        self.assertEqual([h.read8('wBallRarityPal',offset=i) for i in (1,2,3)], [2,3,7])
        h.write8('hCurMap',MAPS['INDIGO_PLATEAU_LOBBY'])
