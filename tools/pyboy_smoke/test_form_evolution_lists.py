"""Form-aware evolution lists (FORM_EVOLUTION_LISTS_PLAN.md, Phase 1).

A form evolves through its OWN list in data/pokemon/form_evos_moves/<form>.asm,
and an empty list means it never evolves, exactly like a final Pokemon. The
static tests guard the one way that design can silently break - a form losing
an evolution it ought to have - and the ROM tests drive the real lookup and the
real evolution loop.
"""
import io
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

    def test_every_form_is_obtainable(self):
        """Every form record can reach a player: rolled from a reward/wild pool
        (an active `rarity_mon SPECIES, n` line), set by a stone row of a base
        species, or evolved into from an obtainable form's own list. A form none
        of those reach is dead content - e.g. a pool line commented out as
        "evolution only" whose source form then lost the entry."""
        import re
        rarity = (REPO_ROOT / 'engine/pokemon/rarity.asm').read_text(encoding='utf-8')
        reach = {(m.group(1), int(m.group(2))) for m in
                 re.finditer(r'^\s*rarity_mon\s+([A-Z_0-9]+)\s*,\s*(\d+)', rarity, re.M)
                 if int(m.group(2)) >= 1}
        reach |= {(target, int(n)) for _stone, target, n in seed.table_rows('EvoStoneForms', 3)}
        # the other stone-set forms are `evo_item_form` entries in the base lists
        base_text = (REPO_ROOT / 'data/pokemon/evos_moves.asm').read_text(encoding='utf-8')
        reach |= {(m.group(2), int(m.group(1))) for m in re.finditer(
            r'^\s*evo_\w+_form\s+(\d+)\s*,.*,\s*([A-Z_0-9]+)\s*(?:;.*)?$', base_text, re.M)}
        blocks = form_blocks()
        explicit = {}
        for path in seed.OUT_DIR.glob('*.asm'):
            text = path.read_text(encoding='utf-8')
            label = next(seed.LABEL_RE.match(l).group(1) for l in text.split('\n')
                         if seed.LABEL_RE.match(l))
            explicit[seed.pointer_table()[label]] = [
                (m.group(2), int(m.group(1))) for m in
                re.finditer(r'^\s*evo_\w+_form\s+(\d+)\s*,.*,\s*([A-Z_0-9]+)\s*$', text, re.M)]
        grown = True
        while grown:
            grown = False
            for key in list(reach):
                for target_form in explicit.get(key, []):
                    if target_form not in reach:
                        reach.add(target_form)
                        grown = True
        self.assertEqual(sorted(set(blocks) - reach), [], 'forms no player can obtain')

    def test_phase2_stone_rows_live_in_the_base_lists(self):
        """Phase 2 data steps: the four non-Eevee stone-set forms are form entries
        in their base species' lists, EvoStoneForms is Eevee-only, and the two
        retired tables and plain Farfetch'd's evolution are gone."""
        import re
        base = (REPO_ROOT / 'data/pokemon/evos_moves.asm').read_text(encoding='utf-8')
        for label, stone, target in (('Cubone', 'DUSK_STONE', 'MAROWAK'),
                                     ('Pikachu', 'MOON_STONE', 'RAICHU'),
                                     ('Exeggcute', 'MOON_STONE', 'EXEGGUTOR'),
                                     ('Koffing', 'MOON_STONE', 'WEEZING')):
            block = base.split(f'{label}EvosMoves:', 1)[1].split('db 0', 1)[0]
            self.assertRegex(block, rf'evo_item_form\s+1,\s*{stone},\s*1,\s*{target}', label)
        engine = (REPO_ROOT / 'engine/pokemon/evos_moves.asm').read_text(encoding='utf-8')
        for gone in ('FormEvoStones:', 'FormNoEvolve:', 'EvoStoneMatchesUsed', 'IsPartyMonEvoBlocked'):
            self.assertNotIn(gone, engine, gone)
        targets = [t for _stone, t, _n in seed.table_rows('EvoStoneForms', 3)]
        self.assertEqual(targets, ['FLAREON', 'JOLTEON', 'JOLTEON', 'VAPOREON', 'VAPOREON'],
                         'EvoStoneForms must hold only the five Eevee rows')
        farfetchd = base.split('FarfetchdEvosMoves:', 1)[1].split('; Learnset', 1)[0]
        self.assertNotRegex(farfetchd, r'^\s*db\s+EVOLVE_', "plain Farfetch'd never evolves")

    def test_eevee_side_tables_follow_eevees_list(self):
        """Eevee keeps its five form rows in EvoStoneForms (the 33-byte buffer),
        so three tables must agree by position with EeveeEvosMoves: the Mist
        Stone's stone per branch, and the generated roll's (species, form) per
        branch. RGBDS ASSERTs cannot compare data bytes, so this test does."""
        import re
        base = (REPO_ROOT / 'data/pokemon/evos_moves.asm').read_text(encoding='utf-8')
        block = base.split('EeveeEvosMoves:', 1)[1].split('	db 0', 1)[0]
        entries = re.findall(r'^\s*db\s+EVOLVE_ITEM,\s*(\w+),\s*\d+,\s*(\w+)', block, re.M)
        self.assertEqual(len(entries), 8)
        stone_forms = {(st, t): int(n) for st, t, n in seed.table_rows('EvoStoneForms', 3)}
        expected = [(target, stone_forms.get((stone, target), 0)) for stone, target in entries]

        forms = (REPO_ROOT / 'custom_functions/func_forms.asm').read_text(encoding='utf-8')
        branches = forms.split('EeveeBranches:', 1)[1].split('EeveeBranchesEnd:', 1)[0]
        rolled = [(sp, int(n)) for sp, n in re.findall(r'^\s*db\s+(\w+),\s*(\d+)', branches, re.M)]
        self.assertEqual(rolled, expected, 'EeveeBranches is out of step with EeveeEvosMoves')

        chooser = (REPO_ROOT / 'engine/pokemon/mist_stone_chooser.asm').read_text(encoding='utf-8')
        table = chooser.split('EeveeMistStones:', 1)[1].split('EeveeMistStonesEnd:', 1)[0]
        stones = [w.strip() for line in re.findall(r'^\s*db\s+([^;\r\n]+)', table, re.M)
                  for w in line.split(',')]
        self.assertEqual(stones, [stone for stone, _target in entries],
                         'EeveeMistStones is out of step with EeveeEvosMoves')

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


class GeneratedFormEvolutionTest(HarnessTestCase):
    """EvolvePoolMon: generated reward / wild / roster mons, and the party-spec
    builder's pinned forms, evolve a FORM through its own list too."""

    def evolve(self, species, form, level):
        h = self.harness
        h.write8('wCurEnemyLevel', level)
        bank, addr = h.symbols.get('EvolvePoolMon')

        def args(_):
            h.pyboy.register_file.D = SPECIES[species]
            h.pyboy.register_file.E = form
        h.pyboy.hook_register(bank, addr, args, None)
        try:
            h.call_routine('EvolvePoolMon')
        finally:
            h.pyboy.hook_deregister(bank, addr)
        regs = h.last_call_registers
        return regs['D'], regs['E']

    def test_forms_follow_their_own_lines(self):
        h = self.harness
        h.boot_to_lobby()
        cases = (
            (('RATTATA', 1, 30), ('RATICATE', 1)),
            (('GEODUDE', 1, 30), ('GRAVELER', 1)),
            (('GEODUDE', 1, 40), ('GOLEM', 1)),      # A-Graveler's trade entry, 35+ floor
            (('FARFETCHD', 1, 30), ('SIRFETCHD', 0)),  # a plain entry leaves the form
            (('JIGGLYPUFF', 1, 60), ('JIGGLYPUFF', 1)),  # Scream Tail: empty list
            (('FARFETCHD', 0, 30), ('FARFETCHD', 0)),  # plain Farfetch'd: its list is empty
            (('RATTATA', 0, 30), ('RATICATE', 0)),    # control: a base species
        )
        for (species, form, level), (want_species, want_form) in cases:
            with self.subTest(species=species, form=form, level=level):
                self.assertEqual(self.evolve(species, form, level),
                                 (SPECIES[want_species], want_form))


class PartyMenuEvoStoneTest(HarnessTestCase):
    """The stone party menu's ABLE / NOT ABLE walks the mon's OWN list, form
    entries included, and a form's own list names the stone it needs."""

    CASES = (
        # (species, form, stone, able)
        ('PIKACHU', 0, 'MOON_STONE', True),       # evo_item_form entry, same stone byte
        ('PIKACHU', 0, 'THUNDER_STONE', True),    # plain entry
        ('PIKACHU', 0, 'FIRE_STONE', False),
        ('CUBONE', 0, 'DUSK_STONE', True),        # only a form entry names this stone
        ('CUBONE', 0, 'MOON_STONE', False),
        ('VULPIX', 1, 'ICE_STONE', True),         # A-Vulpix's own list
        ('VULPIX', 1, 'FIRE_STONE', False),
        ('VULPIX', 0, 'ICE_STONE', False),
        ('JIGGLYPUFF', 1, 'MOON_STONE', False),   # Scream Tail: empty list
        ('FARFETCHD', 0, 'LEAF_STONE', False),    # plain Farfetch'd: empty list
    )

    # Keep the existing test IDs, but isolate every case below. Splitting the
    # cases alone does not prevent redraw scratch state leaking into the lobby.
    def test_able_follows_the_mons_own_list_first_half(self):
        self.check(self.CASES[:5])

    def test_able_follows_the_mons_own_list_second_half(self):
        self.check(self.CASES[5:])

    def check(self, cases):
        h = self.harness
        h.boot_to_lobby()
        items = parse_rgbds_constants(REPO_ROOT / 'constants/item_constants.asm')
        menu = parse_rgbds_constants(REPO_ROOT / 'constants/menu_constants.asm')
        shown = []
        h.register_hook('RedrawPartyMenu_.placeEvolutionStoneString', lambda _: shown.append(
            (h.pyboy.register_file.D << 8) | h.pyboy.register_file.E))
        able = h.symbols.get('RedrawPartyMenu_.ableToEvolveText')[1]

        def emulate_ret(_):
            r = h.pyboy.register_file
            r.PC = h.pyboy.memory[r.SP] | (h.pyboy.memory[r.SP + 1] << 8)
            r.SP = (r.SP + 2) & 0xFFFF
        # The menu ends by printing "Use item on which?" and then Delay3-ing; both
        # wait on frames the parked harness never delivers. The verdict was
        # recorded before either, so return from each.
        h.register_hook('PrintText', emulate_ret)
        h.register_hook('Delay3', emulate_ret)
        # Capture the parked machine with its hooks installed. Re-parking after
        # a redraw resumes the interrupted lobby with menu-modified scratch RAM;
        # restore the whole baseline instead of accumulating that state.
        baseline = io.BytesIO()
        h.save_state(baseline)
        for species, form, stone, expected in cases:
            with self.subTest(species=species, form=form, stone=stone):
                h.load_state(baseline)
                shown.clear()
                h.write8('wPartyCount', 1)
                h.write8('wPartySpecies', SPECIES[species])
                h.write8('wPartySpecies', 0xFF, offset=1)
                h.write8('wPartyMon1Species', SPECIES[species])
                h.write8('wPartyMon1Level', 40)
                h.write8('wPartyMon1CatchRate', form << 5)
                h.write8('wMonDataLocation', 0)
                h.write8('wPartyMenuTypeOrMessageID', menu['EVO_STONE_PARTY_MENU'])
                h.write8('wEvoStoneItemID', items[stone])
                h.call_routine('RedrawPartyMenu_')
                self.assertEqual(len(shown), 1, 'one ABLE/NOT ABLE verdict for the one mon')
                self.assertEqual(shown[0] == able, expected)


class MistStoneChooserTest(HarnessTestCase):
    """The chooser (moved to bank $31) walks the mon's OWN list and names each
    offer by the form that entry evolves it into."""

    def test_a_form_is_offered_its_own_evolution_by_name(self):
        h = self.harness
        h.boot_to_lobby()
        h.write8('hWhichPokemon', 0)
        h.write8('wPartySpecies', SPECIES['MEOWTH'])
        h.write8('wPartyMon1Species', SPECIES['MEOWTH'])
        a = h.address('wPartyMon1CatchRate')
        h.pyboy.memory[a] = (h.pyboy.memory[a] & 0x9f) | (1 << 5)   # A-Meowth
        offers = []
        menu = parse_rgbds_constants(REPO_ROOT / 'constants/menu_constants.asm')

        def emulate_ret():
            r = h.pyboy.register_file
            r.PC = h.pyboy.memory[r.SP] | (h.pyboy.memory[r.SP + 1] << 8)
            r.SP = (r.SP + 2) & 0xFFFF

        def on_print(_):
            text_bank, text_addr = h.symbols.get('MistStoneChoiceText')
            if h.pyboy.register_file.HL == text_addr and h.read8('hLoadedROMBank') == text_bank:
                buf = h.address('wNameBuffer')
                raw = h.pyboy.memory[buf:buf + 11]
                offers.append(bytes(raw[:list(raw).index(0x50)]))
                emulate_ret()

        def on_box(_):
            h.write8('wMenuExitMethod', menu['CHOSE_FIRST_ITEM'])  # "yes"
            emulate_ret()
        h.register_hook('PrintText', on_print)
        h.register_hook('DisplayTextBoxID', on_box)
        h.call_routine('MistStoneChooseEvolution')
        chars = {0x80 + i: c for i, c in enumerate('ABCDEFGHIJKLMNOPQRSTUVWXYZ')}
        chars[0xE3] = '-'
        names = [''.join(chars.get(b, '?') for b in o) for o in offers]
        self.assertEqual(names, ['A-PERSIAN'])
        self.assertEqual(h.read8('wEvoNewSpecies'), SPECIES['PERSIAN'])


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

    def test_a_form_trade_evolution_also_evolves_at_its_level(self):
        """The trade-or-level rule holds for a FORM's own trade entry: A-Graveler's
        `evo_trade_form 1, 38, GOLEM` levels into A-Golem with no trade at all."""
        h = self.harness
        mon = lambda name, level, move: dict(species=SPECIES[name], level=level, moves=[MOVES[move]])
        h.inject_fight2_spec([mon('GRAVELER', 38, 'TACKLE')], [mon('MAGIKARP', 2, 'SPLASH')] * 2,
                             trainer_class=TRAINERS['COOLTRAINER_M'], ai_tier=0)
        h.boot_fight2(seed=1)
        h.write8('wOptions', h.read8('wOptions') | 0x40)
        if h.hardware_mode == 'CGB':
            h.write8('wOptions2', h.read8('wOptions2') | 0xc0)
        for label in ('wPartyMon1CatchRate', 'wBattleMonCatchRate'):
            h.write8(label, (h.read8(label) & 0x9f) | (1 << 5))
        seeded, final = [], {}

        def seed_flags(_):
            if not seeded:
                h.write8('wCanEvolveFlags', 1)
                seeded.append(True)

        def snap(_):
            if not final:
                final.update(species=h.read8('wPartyMon1Species'),
                             form=(h.read8('wPartyMon1CatchRate') >> 5) & 3)
        h.register_hook('RogueTryMidBattleEvolution', seed_flags)
        h.register_hook('EndOfBattle.clearBattleState', snap)
        crash = h.hook_flag('CrashScreen')
        for frame in range(6500):
            if frame % 12 == 0:
                h.pyboy.button_press('a')
            elif frame % 12 == 2:
                h.pyboy.button_release('a')
            h.tick(1)
            if final or crash['count']:
                break
        self.assertEqual(crash['count'], 0)
        self.assertEqual(final, dict(species=SPECIES['GOLEM'], form=1), h.diagnostic_state())


if __name__ == '__main__':
    unittest.main()
