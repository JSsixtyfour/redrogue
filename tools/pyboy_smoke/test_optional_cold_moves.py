"""Actual ROM cold-move grants: inclusive tiers, both PP layouts, compact slots."""
import io
import unittest
from pathlib import Path
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
import test_optional_encounter as encounter

ROOT=Path(__file__).resolve().parents[2]
MOVES=parse_rgbds_constants(ROOT/'constants/move_constants.asm')
SPECIES=parse_rgbds_constants(ROOT/'constants/pokemon_constants.asm')


class OptionalColdMovesTest(unittest.TestCase):
    def test_all_boundaries_species_choices_and_struct_pp_layouts(self):
        h=RedRogueHarness(ROOT,ROOT/'tools/pyboy_smoke/artifacts')
        try:
            h.boot_to_lobby();h.park_before_hijack()
            snapshot=io.BytesIO();h.save_state(snapshot)
            bank,addr=h.symbols.get('Moves')
            raw=h.rom_path.read_bytes();start=bank*16384+addr-16384
            for species in ('ONIX','SNORLAX'):
                for level in (0,1,30,31,35,36,45,46,235):
                    attack='AURORA_BEAM' if level<=30 or (species=='ONIX' and level<=35) else 'ICE_PUNCH' if level<=35 else 'ICE_BEAM' if level<=45 else 'BLIZZARD'
                    for package,status in ((2,'MIST'),(3,'HAZE')):
                        for struct,pp_offset in (('wEnemyMon',25),('wPartyMon6',29),('wBoxMon1',29)):
                            h.load_state(snapshot);base=h.address(struct)
                            h.pyboy.memory[base:base+33]=[0xa5]*33
                            h.pyboy.memory[base]=SPECIES[species]
                            h.pyboy.memory[base+8:base+12]=[MOVES['TACKLE'],MOVES['GROWL'],MOVES['POUND'],MOVES['LEER']]
                            h.write8('wOptionalEncounterSpecies',SPECIES[species]);h.write8('wOptionalEncounterLevel',level)
                            h.write8('wOptionalEncounterPackage',package)
                            before=list(h.pyboy.memory[base:base+33])
                            def inject(_):
                                h.pyboy.register_file.D=base>>8;h.pyboy.register_file.E=base&255;h.pyboy.register_file.B=pp_offset-8
                            h.register_hook('OptionalGrantColdMoves',inject)
                            h.call_routine('OptionalGrantColdMoves')
                            h.unregister_hook('OptionalGrantColdMoves',inject)
                            expected=[MOVES[x] for x in ('TACKLE','GROWL',status,attack)]
                            self.assertEqual(list(h.pyboy.memory[base+8:base+12]),expected,(species,level,package,struct))
                            self.assertEqual(list(h.pyboy.memory[base+pp_offset:base+pp_offset+4]),[raw[start+(m-1)*6+5] for m in expected])
                            after=list(h.pyboy.memory[base:base+33])
                            for i in set(range(33))-set(range(8,12))-set(range(pp_offset,pp_offset+4)):
                                self.assertEqual(after[i],before[i],(struct,i))
        finally:h.close()

    def test_empty_slots_and_existing_special_moves_compact_without_duplicates(self):
        h=RedRogueHarness(ROOT,ROOT/'tools/pyboy_smoke/artifacts')
        try:
            h.boot_to_lobby();h.park_before_hijack();snapshot=io.BytesIO();h.save_state(snapshot)
            for names in ((),('TACKLE',),('MIST','ICE_PUNCH'),('HAZE','AURORA_BEAM','ICE_BEAM','BLIZZARD')):
                h.load_state(snapshot);base=h.address('wPartyMon6')
                h.write8('wOptionalEncounterSpecies',SPECIES['SNORLAX']);h.write8('wOptionalEncounterLevel',46);h.write8('wOptionalEncounterPackage',2)
                h.pyboy.memory[base+8:base+12]=[MOVES[x] for x in names]+[0]*(4-len(names))
                def inject(_):h.pyboy.register_file.D=base>>8;h.pyboy.register_file.E=base&255;h.pyboy.register_file.B=21
                h.register_hook('OptionalGrantColdMoves',inject);h.call_routine('OptionalGrantColdMoves');h.unregister_hook('OptionalGrantColdMoves',inject)
                ordinary=[MOVES['TACKLE']] if 'TACKLE' in names else []
                expected=ordinary+[MOVES['MIST'],MOVES['BLIZZARD']]
                self.assertEqual(list(h.pyboy.memory[base+8:base+12]),expected+[0]*(4-len(expected)))
        finally:h.close()


class ForestSnowlaxTest(encounter.OptionalEncounterTest):
    cold_fixture=True
