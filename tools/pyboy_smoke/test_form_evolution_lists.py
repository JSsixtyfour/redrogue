"""Form-aware evolution lists (FORM_EVOLUTION_LISTS_PLAN.md, Phase 1).

A form evolves through its OWN list in data/pokemon/form_evos_moves/<form>.asm,
and an empty list means it never evolves, exactly like a final Pokemon. The
static tests guard the one way that design can silently break - a form losing
an evolution it ought to have - and the ROM tests drive the real lookup and the
real evolution loop.
"""
import sys
import unittest

from source_constants import parse_rgbds_constants, parse_trainer_constants
from test_smoke import HarnessTestCase, REPO_ROOT

sys.path.insert(0, str(REPO_ROOT / 'tools'))
import seed_form_evolutions as seed  # noqa: E402

SPECIES = parse_rgbds_constants(REPO_ROOT / 'constants/pokemon_constants.asm')
MOVES = parse_rgbds_constants(REPO_ROOT / 'constants/move_constants.asm')
TYPES = parse_rgbds_constants(REPO_ROOT / 'constants/type_constants.asm')
TRAINERS = parse_trainer_constants(REPO_ROOT / 'constants/trainer_constants.asm')
STRUCT = 44

# Forms that are final ON PURPOSE although their base species evolves into a
# species that has the same form. Empty today; adding a form here is a design
# decision ("this form never evolves"), never a way to quiet the test.
INTENDED_FINAL_FORMS = set()


def form_blocks():
    """(species, form) -> list of (kind, target, level) in that form's block."""
    pointers = seed.pointer_table()
    out = {}
    for path in sorted(seed.OUT_DIR.glob('*.asm')):
        lines = path.read_text(encoding='utf-8').split('\n')
        label = next(seed.LABEL_RE.match(l).group(1) for l in lines if seed.LABEL_RE.match(l))
        entries = []
        for line in lines[1:]:
            if seed.ZERO_RE.match(line):
                break
            code = line.split(';')[0].strip()
            if not code:
                continue
            words = [w.strip() for w in code.replace('\t', ' ').split(None, 1)[1].split(',')]
            head = code.split()[0]
            if head == 'db':
                kind, rest = words[0], words[1:]
            else:  # evo_level_form / evo_item_form / evo_trade_form <form>, ...
                kind, rest = head, words[1:]
            level = rest[-2]
            entries.append((kind, rest[-1], level))
        out[pointers[label]] = entries
    return out


class FormEvolutionListStaticTest(unittest.TestCase):
    def test_no_form_silently_loses_an_evolution(self):
        """Every form whose base species evolves into a species that ALSO has
        this form must list an evolution of its own. Under "empty = never"
        a missed migration would otherwise just quietly stop evolving."""
        index = seed.build_species_index()
        by_index = {v: k for k, v in index.items()}
        label_of = {by_index[i + 1]: lab for i, lab in enumerate(seed.build_dw_list())
                    if (i + 1) in by_index}
        lists = seed.base_lists()
        recs = seed.form_records()
        blocks = form_blocks()
        missing = []
        for (species, form), entries in blocks.items():
            if entries or (species, form) in INTENDED_FINAL_FORMS:
                continue
            targets = {e[-1] for e in lists[label_of[species]]}
            if any((t, form) in recs for t in targets):
                missing.append(f'{species} form {form}')
        self.assertEqual(missing, [], 'forms that lost their evolution')

    def test_drift_from_the_base_species_is_reported(self):
        """Warning only: a form whose evolution level differs from its base
        species' entry into the same target. Changing Rattata's level and
        forgetting A-Rattata shows up here; a deliberate difference is fine."""
        index = seed.build_species_index()
        by_index = {v: k for k, v in index.items()}
        label_of = {by_index[i + 1]: lab for i, lab in enumerate(seed.build_dw_list())
                    if (i + 1) in by_index}
        lists = seed.base_lists()
        for (species, form), entries in form_blocks().items():
            base = {e[-1]: e[-2] for e in lists[label_of[species]]}
            for _kind, target, level in entries:
                if target in base and base[target] != level:
                    print(f'\nNOTE: {species} form {form} -> {target} at {level}, '
                          f'base species at {base[target]}')

    def test_seeding_tool_has_nothing_pending(self):
        """Every form block is in the new shape: re-running the seeder writes nothing."""
        old = sys.argv
        sys.argv = ['seed_form_evolutions.py', '--check']
        try:
            seed.main()
        except SystemExit as e:
            self.fail(f'seed_form_evolutions.py --check exited {e.code}')
        finally:
            sys.argv = old


class GetEvoListForMonTest(HarnessTestCase):
    def lookup(self, species, form):
        h = self.harness
        bank, addr = h.symbols.get('GetEvoListForMon')

        def args(_):
            h.pyboy.register_file.D = SPECIES[species]
            h.pyboy.register_file.E = form
        h.pyboy.hook_register(bank, addr, args, None)
        try:
            h.call_routine('GetEvoListForMon')
        finally:
            h.pyboy.hook_deregister(bank, addr)
        return h.last_call_registers['HL']

    def test_each_form_gets_its_own_list_and_never_the_base_one(self):
        h = self.harness
        h.boot_to_lobby()
        address = lambda label: h.symbols.get(label)[1]
        self.assertEqual(self.lookup('RATTATA', 0), address('RattataEvosMoves'))
        self.assertEqual(self.lookup('RATTATA', 1), address('ArattataFormEvosMoves'))
        # RATTATA has no form 2: that reads as "never evolves", not as Rattata's list
        self.assertEqual(self.lookup('RATTATA', 2), address('NoEvolutionsList'))
        self.assertEqual(self.lookup('VULPIX', 1), address('AvulpixFormEvosMoves'))


class FormEvolutionFlowTest(HarnessTestCase):
    """The real evolution loop through real KOs (the test_evolution_flow fixture
    shape). Slot 0 A-Sandshrew evolves mid-battle; slots 1-2 evolve after it."""

    def test_forms_evolve_through_their_own_lists(self):
        h = self.harness
        mon = lambda name, level, move: dict(species=SPECIES[name], level=level, moves=[MOVES[move]])
        h.inject_fight2_spec(
            [mon('SANDSHREW', 22, 'SCRATCH'), mon('RATTATA', 20, 'TACKLE'), mon('RATTATA', 20, 'TACKLE')],
            [mon('MAGIKARP', 2, 'SPLASH')] * 2,
            trainer_class=TRAINERS['COOLTRAINER_M'], ai_tier=0,
        )
        h.boot_fight2(seed=1)
        h.write8('wOptions', h.read8('wOptions') | 0x40)
        if h.hardware_mode == 'CGB':
            h.write8('wOptions2', h.read8('wOptions2') | 0xc0)
        # slot 0: A-Sandshrew (form 1); slot 1: RATTATA form 2, which has no
        # record and so must never evolve; slot 2: plain Rattata, the control
        for slot, form in ((0, 1), (1, 2)):
            a = h.address('wPartyMon1CatchRate') + slot * STRUCT
            h.pyboy.memory[a] = (h.pyboy.memory[a] & 0x9f) | (form << 5)
        h.write8('wBattleMonCatchRate', (h.read8('wBattleMonCatchRate') & 0x9f) | (1 << 5))
        seeded, party = [], []

        def seed_flags(_):
            if not seeded:
                h.write8('wCanEvolveFlags', 7)
                seeded.append(True)

        def snap(_):
            if party:
                return
            for slot in range(3):
                o = slot * STRUCT
                rd = lambda label: h.pyboy.memory[h.address(label) + o]
                party.append(dict(species=rd('wPartyMon1Species'),
                                  form=(rd('wPartyMon1CatchRate') >> 5) & 3,
                                  types=(rd('wPartyMon1Type1'), rd('wPartyMon1Type2'))))
        h.register_hook('RogueTryMidBattleEvolution', seed_flags)
        h.register_hook('EndOfBattle.clearBattleState', snap)
        crash = h.hook_flag('CrashScreen')
        for frame in range(6500):
            if frame % 12 == 0:
                h.pyboy.button_press('a')
            elif frame % 12 == 2:
                h.pyboy.button_release('a')
            h.tick(1)
            if party or crash['count']:
                break
        self.assertEqual(crash['count'], 0)
        self.assertTrue(party, h.diagnostic_state())
        self.assertEqual(party[0], dict(species=SPECIES['SANDSLASH'], form=1,
                                        types=(TYPES['ICE'], TYPES['ICE'])))
        self.assertEqual((party[1]['species'], party[1]['form']), (SPECIES['RATTATA'], 2))
        self.assertEqual((party[2]['species'], party[2]['form']), (SPECIES['RATICATE'], 0))


if __name__ == '__main__':
    unittest.main()
