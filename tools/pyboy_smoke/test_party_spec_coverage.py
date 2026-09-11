"""Contract checks for the Phase 3 party-spec coverage tables.

These decode the spec records out of the BUILT ROMs rather than reading the
source, and that is the whole point. `data/trainers/party_specs.asm` generates
434 records from an RGBDS macro that does `DEF` arithmetic, an eight-way `ELIF`
chain and `{d:t}` label interpolation; none of those fail loudly when they are
wrong. A misindexed round would emit a level-40 team for round 1 and assemble
without a warning, which is this repo's documented
"table whose count assert passes while its rows are misaligned" failure mode one
level up: here even the count is generated, so there is nothing left for
`assert_table_length` to catch.

Nothing here boots an emulator. The runtime side - that RogueBuildParty actually
reaches these records and builds a legal party from one - is
PartySpecRoundCoverageSmokeTest in test_party_specs.py, which is capped by the
harness's ~10-invocation ceiling and so can only sample. This file is what
covers all 434.
"""
import re
import unittest

from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_smoke import REPO_ROOT

ROMS = ("pokered", "pokeblue", "pokeblue_debug")

# InitGymBattle: wTrainerNo = (wBattleCount / 10 - 1) * 3 + 1 + rand(3).
NUM_ROUND_VARIANTS = 3
NUM_GYM_ROUNDS = 8
NUM_GYM_TEAMS = NUM_GYM_ROUNDS * NUM_ROUND_VARIANTS
# InitElite4Battle derives its tier linearly from wBattleCount 86-89 instead,
# so an E4-only class is asked for twelve values, never 24.
NUM_E4_TIERS = 4
NUM_E4_TEAMS = NUM_E4_TIERS * NUM_ROUND_VARIANTS

# constants/party_spec_constants.asm bit order
BIT_ACE_LAST, BIT_NO_DUPES, BIT_ALLOW_UBER = 0, 1, 2
BASE_FLAGS = (1 << BIT_ACE_LAST) | (1 << BIT_NO_DUPES)
ALLOW_UBER = 1 << BIT_ALLOW_UBER
POOL_FORM_ROLL = 0xFF
OVERRIDES_END = 0xFF
# PartySpecOverrideFieldWidths, in bit order.
OVERRIDE_FIELD_WIDTHS = (2, 1, 1, 4, 1, 1)
BIT_POVR_SPECIES = 0

# round -> (n_mons, base_level, level_step). Asserted against the shipped
# authored rosters below rather than trusted; see test_curve_tracks_the_authored_rosters.
GYM_CURVE = {
    1: (2, 12, 2),
    2: (2, 18, 3),
    3: (3, 18, 3),
    4: (3, 25, 2),
    5: (4, 37, 2),
    6: (4, 37, 2),
    7: (5, 39, 2),
    8: (6, 40, 2),
}
GYM_MIX = {1: "MIX_GYM_EARLY", 2: "MIX_GYM_EARLY", 3: "MIX_GYM_LATE",
           4: "MIX_GYM_LATE", 5: "MIX_GYM_LATE", 6: "MIX_ELITE",
           7: "MIX_ELITE", 8: "MIX_ELITE"}

# label prefix -> (trainer class, pool, ace 1-3, ace 4-8, alt 1-3, alt 4-8,
#                  extra flags from round 7)
GYM_LEADERS = {
    "Falkner": ("FALKNER", "POOL_FALKNER", "PIDGEOTTO", "PIDGEOT", "DODUO", "FEAROW", 0),
    "Brock": ("BROCK", "POOL_BROCK", "ONIX", "RHYDON", "KABUTO", "AERODACTYL", 0),
    "Misty": ("MISTY", "POOL_MISTY", "STARYU", "STARMIE", "SEADRA", "LAPRAS", 0),
    "LtSurge": ("LT_SURGE", "POOL_LT_SURGE", "VOLTORB", "RAICHU", "MAGNEMITE", "ELECTRODE", 0),
    "Erika": ("ERIKA", "POOL_ERIKA", "GLOOM", "VILEPLUME", "WEEPINBELL", "VICTREEBEL", 0),
    "Koga": ("KOGA", "POOL_KOGA", "KOFFING", "WEEZING", "GRIMER", "MUK", 0),
    "Blaine": ("BLAINE", "POOL_BLAINE", "GROWLITHE", "ARCANINE", "PONYTA", "RAPIDASH", 0),
    "Sabrina": ("SABRINA", "POOL_SABRINA", "KADABRA", "ALAKAZAM", "DROWZEE", "HYPNO", ALLOW_UBER),
    "Giovanni": ("GIOVANNI", "POOL_GIOVANNI", "NIDORINO", "NIDOKING", "RHYHORN", "RHYDON", 0),
    "Bugsy": ("BUGSY", "POOL_BUGSY", "BUTTERFREE", "SCYTHER", "BEEDRILL", "PINSIR", 0),
    "Whitney": ("WHITNEY", "POOL_WHITNEY", "CLEFAIRY", "MILTANK", "RATICATE", "CLEFABLE", 0),
    "Morty": ("MORTY", "POOL_MORTY", "HAUNTER", "GENGAR", "GASTLY", "MISDREAVUS", 0),
    "Chuck": ("CHUCK", "POOL_CHUCK", "MACHOKE", "MACHAMP", "PRIMEAPE", "HITMONLEE", 0),
    "Jasmine": ("JASMINE", "POOL_JASMINE", "MAGNETON", "STEELIX", "MAGNEMITE", "FORRETRESS", 0),
    "Pryce": ("PRYCE", "POOL_PRYCE", "DEWGONG", "PILOSWINE", "SEEL", "DEWGONG", 0),
    "Clair": ("CLAIR", "POOL_CLAIR", "DRAGONAIR", "DRAGONITE", "DRATINI", "KINGDRA", 0),
    "Janine": ("JANINE", "POOL_JANINE", "GOLBAT", "CROBAT", "VENONAT", "VENOMOTH", 0),
}
# Elite Four only: label prefix -> (class, pool, ace, ace form, alt, alt form).
# Both aces need an explicit form because neither eeveelution is a species in
# this tree - Espeon and Umbreon are JOLTEON forms 1 and 2.
E4_MEMBERS = {
    "Will": ("WILL", "POOL_WILL", "XATU", POOL_FORM_ROLL, "JOLTEON", 1),
    "Karen": ("KAREN", "POOL_KAREN", "HOUNDOOM", POOL_FORM_ROLL, "JOLTEON", 2),
}
# Falkner's round 1 B and C are the Phase 2 worked examples, kept verbatim
# because five tests drive them by name and number. They do not follow the
# generated shape and are checked separately.
HAND_WRITTEN = {("Falkner", 2), ("Falkner", 3)}

_SYM_LINE = re.compile(r"^([0-9A-Fa-f]{2,4}):([0-9A-Fa-f]{4})\s+(\S+)$")


class Image:
    """A built ROM plus its symbol table, addressed by label."""

    def __init__(self, name):
        self.name = name
        self.rom = (REPO_ROOT / f"{name}.gbc").read_bytes()
        self.syms = {}
        for raw in (REPO_ROOT / f"{name}.sym").read_text(encoding="utf-8").splitlines():
            match = _SYM_LINE.match(raw.split(";")[0].strip())
            if match:
                bank, addr, label = match.groups()
                self.syms[label] = (int(bank, 16), int(addr, 16))

    def offset(self, label):
        bank, addr = self.syms[label]
        return addr if bank == 0 else bank * 0x4000 + (addr - 0x4000)

    def addr(self, label):
        return self.syms[label][1]

    def word(self, off):
        return self.rom[off] | (self.rom[off + 1] << 8)

    def spec_list(self, prefix):
        """(count byte, [pointer per wTrainerNo])."""
        base = self.offset(f"{prefix}Specs")
        count = self.rom[base]
        return count, [self.word(base + 1 + i * 2) for i in range(count)]

    def record(self, label):
        """(header 6-tuple, [(slot, ovr_flags, {bit: bytes})])."""
        off = self.offset(label)
        header = tuple(self.rom[off:off + 6])
        off += 6
        overrides = []
        while self.rom[off] != OVERRIDES_END:
            slot, flags = self.rom[off], self.rom[off + 1]
            off += 2
            fields = {}
            for bit, width in enumerate(OVERRIDE_FIELD_WIDTHS):
                if flags & (1 << bit):
                    fields[bit] = list(self.rom[off:off + width])
                    off += width
            overrides.append((slot, flags, fields))
        return header, overrides


def authored_rosters():
    """Team sizes and level envelopes per round, parsed from parties.asm.

    Both authored layouts have to be handled: TRAINERPARTY_LEVELS ($FF) is
    level/species pairs, TRAINERPARTY_FORMS ($FE) is level/species/form
    triples. Erika's roster is the $FE one, which is why this cannot assume
    pairs - and the $FE layout also spreads one team over several `db` lines
    with the layout byte alone on the first, so the body is flattened into one
    operand stream and walked, rather than parsed a line at a time.
    """
    text = (REPO_ROOT / "data/trainers/parties.asm").read_text(encoding="utf-8")
    out = {}
    for cls in ("Brock", "Misty", "LtSurge", "Erika", "Koga", "Blaine",
                "Sabrina", "Giovanni"):
        # ErikaData: carries trailing whitespace in the source, so neither the
        # anchor nor the lookahead may assume the colon ends the line.
        match = re.search(
            rf"^{cls}Data:[ \t]*\n(.*?)(?=\n[ \t]*[A-Za-z_0-9]+Data:[ \t]*\n)",
            text, re.S | re.M)
        assert match is not None, f"{cls}Data not found in parties.asm"
        body = match.group(1)
        tokens = []
        for raw in body.split("\n"):
            code = raw.split(";")[0].strip()
            if code.startswith("db"):
                tokens += [p.strip() for p in code[2:].split(",") if p.strip()]

        teams = []
        i = 0
        while i < len(tokens):
            layout = tokens[i]
            assert layout in ("$FF", "TRAINERPARTY_LEVELS",
                              "$FE", "TRAINERPARTY_FORMS"), (
                f"{cls}Data team {len(teams) + 1} starts with {layout!r}; gym "
                "leaders must use a per-mon-level layout")
            stride = 3 if layout in ("$FE", "TRAINERPARTY_FORMS") else 2
            i += 1
            levels = []
            while tokens[i] != "0":
                levels.append(int(tokens[i]))
                i += stride
            i += 1  # the terminator
            teams.append(levels)
        out[cls] = teams
    return out


class PartySpecCoverageContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.images = [Image(name) for name in ROMS]
        cls.pools = parse_rgbds_constants(REPO_ROOT / "data/trainers/pools.asm")
        cls.mixes = parse_rgbds_constants(REPO_ROOT / "data/trainers/party_specs.asm")
        cls.species = parse_rgbds_constants(
            REPO_ROOT / "constants/pokemon_constants.asm")
        # Raw class indexes, not OPP_ ids. Never recompute one from the other
        # with a literal offset - OPP_ID_OFFSET has already moved once.
        cls.classes = parse_trainer_class_indexes(
            REPO_ROOT / "constants/trainer_constants.asm")

    def test_every_character_covers_every_round_it_can_be_asked_for(self):
        """No wTrainerNo a leader can be handed may resolve to a `dw 0` hole.

        This is landmine 9 of PARTY_SPEC_SPEC.md and the reason Phase 3 has to
        land before Phase 7. A missing spec does not produce a missing battle:
        RogueBuildParty declines, control falls into the TrainerDataPointers
        lookup, and .SkipTrainer walks forward wTrainerNo - 1 terminators - off
        the end of a short class's data and into the NEXT class's. Measured:
        wTrainerNo 2 on a one-team class built a level-53 Bruno party.

        wTrainerNo 1 is the one deliberate hole, on every character, and it is
        safe precisely because .SkipTrainer does ZERO skips there and so lands
        on the class's own first authored team.
        """
        for image in self.images:
            for prefix, teams in (
                [(p, NUM_GYM_TEAMS) for p in GYM_LEADERS]
                + [(p, NUM_E4_TEAMS) for p in E4_MEMBERS]
            ):
                with self.subTest(rom=image.name, character=prefix):
                    count, pointers = image.spec_list(prefix)
                    self.assertEqual(
                        count, teams,
                        f"{prefix}Specs declares {count} teams; InitGymBattle / "
                        f"InitElite4Battle can ask for {teams}")
                    self.assertEqual(
                        pointers[0], 0,
                        f"{prefix} wTrainerNo 1 should be the authored-team hole")
                    for number, pointer in enumerate(pointers[1:], start=2):
                        self.assertEqual(
                            pointer, image.addr(f"{prefix}Spec{number}"),
                            f"{prefix} wTrainerNo {number} points at "
                            f"{pointer:04X}, not at {prefix}Spec{number}")

    def test_generated_records_match_the_round_and_variant_they_serve(self):
        """Every generated record's header and ace pin, decoded from the ROM.

        The round and variant are derived from the wTrainerNo the pointer list
        reaches the record through, NOT from the record's position in the file,
        so a record emitted for the wrong round fails here even though it
        assembles and links.
        """
        for image in self.images:
            for prefix, (_cls, pool, ace_e, ace_l, alt_e, alt_l, extra) \
                    in GYM_LEADERS.items():
                for number in range(2, NUM_GYM_TEAMS + 1):
                    if (prefix, number) in HAND_WRITTEN:
                        continue
                    round_no = (number - 1) // NUM_ROUND_VARIANTS + 1
                    variant = (number - 1) % NUM_ROUND_VARIANTS
                    mons, base, step = GYM_CURVE[round_no]
                    want = (mons, base, step, self.pools[pool],
                            self.mixes[GYM_MIX[round_no]],
                            BASE_FLAGS | (extra if round_no >= 7 else 0))
                    label = f"{prefix}Spec{number}"
                    with self.subTest(rom=image.name, spec=label):
                        header, overrides = image.record(label)
                        self.assertEqual(
                            header, want,
                            f"{label} serves round {round_no} variant "
                            f"{'ABC'[variant]}")
                        if variant == 1:
                            self.assertEqual(
                                overrides, [],
                                f"{label} is the B variant and must pin nothing")
                            continue
                        if variant == 0:
                            ace = ace_e if round_no <= 3 else ace_l
                        else:
                            ace = alt_e if round_no <= 3 else alt_l
                        self.assertEqual(len(overrides), 1)
                        slot, flags, fields = overrides[0]
                        self.assertEqual(
                            slot, mons - 1,
                            f"{label} must pin the LAST slot; BIT_PSPEC_ACE_LAST "
                            "gives that slot the strongest source")
                        self.assertEqual(flags, 1 << BIT_POVR_SPECIES)
                        self.assertEqual(
                            fields[BIT_POVR_SPECIES],
                            [self.species[ace], POOL_FORM_ROLL],
                            f"{label} should pin {ace}")

    def test_elite_four_records_use_the_four_tier_grid(self):
        """Twelve teams on the E4 grid, not 24 on the gym grid.

        InitElite4Battle derives its tier linearly from wBattleCount 86-89, so
        an E4-only class is asked for 1-12. Giving one 24 teams would leave half
        unreachable; giving it 8 rounds' worth of levels would put tier 1 at a
        gym leader's round-1 levels.
        """
        for image in self.images:
            for prefix, (_cls, pool, ace, ace_form, alt, alt_form) \
                    in E4_MEMBERS.items():
                for number in range(2, NUM_E4_TEAMS + 1):
                    tier = (number - 1) // NUM_ROUND_VARIANTS + 1
                    variant = (number - 1) % NUM_ROUND_VARIANTS
                    label = f"{prefix}Spec{number}"
                    with self.subTest(rom=image.name, spec=label):
                        header, overrides = image.record(label)
                        self.assertEqual(
                            header,
                            (5, 52 + tier, 2, self.pools[pool],
                             self.mixes["MIX_ELITE"], BASE_FLAGS),
                            f"{label} serves tier {tier}")
                        if variant == 1:
                            self.assertEqual(overrides, [])
                            continue
                        pinned, form = ((ace, ace_form) if variant == 0
                                        else (alt, alt_form))
                        self.assertEqual(len(overrides), 1)
                        slot, _flags, fields = overrides[0]
                        self.assertEqual(slot, 4)
                        self.assertEqual(fields[BIT_POVR_SPECIES],
                                         [self.species[pinned], form])

    def test_curve_tracks_the_authored_rosters(self):
        """The generated level curve is measured, not invented.

        All eight shipped Kanto rosters are identical round for round, which is
        what makes one shared curve correct. Asserting the generated curve
        against the authored data means a future edit to either has to justify
        itself against the other, instead of the curve silently drifting from
        the content it replaced.
        """
        rosters = authored_rosters()
        sizes = {}
        envelopes = {}
        for cls, teams in rosters.items():
            # GiovanniData carries 27: three past the 24 InitGymBattle can ask
            # for. They are unreachable through the round grid, so the curve
            # only describes the first 24.
            self.assertGreaterEqual(
                len(teams), NUM_GYM_TEAMS,
                f"{cls}Data holds {len(teams)} teams, fewer than the "
                f"{NUM_GYM_TEAMS} a gym leader can be asked for")
            for round_no in range(1, NUM_GYM_ROUNDS + 1):
                group = teams[(round_no - 1) * 3:round_no * 3]
                sizes.setdefault(round_no, set()).update(len(t) for t in group)
                for team in group:
                    envelopes.setdefault(round_no, set()).add(
                        (min(team), max(team)))

        for round_no, (mons, base, step) in GYM_CURVE.items():
            with self.subTest(round=round_no):
                self.assertEqual(
                    sizes[round_no], {mons},
                    f"round {round_no}: authored rosters carry "
                    f"{sorted(sizes[round_no])} mons, the spec curve says {mons}")
                self.assertEqual(
                    len(envelopes[round_no]), 1,
                    f"round {round_no} level envelopes diverge across the eight "
                    f"authored rosters: {sorted(envelopes[round_no])}")
                low, high = envelopes[round_no].pop()
                # The ACE is held to within one level because it is the fight's
                # difficulty peak. The base gets two, because base + slot * step
                # is linear and some authored rounds are not: round 8 spans
                # 42-50 over six mons, which needs a step of 1.6. Where the two
                # cannot both be met the ace wins and the low end gives way.
                self.assertLessEqual(
                    abs(base + (mons - 1) * step - high), 1,
                    f"round {round_no} ace level {base + (mons - 1) * step} vs "
                    f"authored {high}")
                self.assertLessEqual(
                    abs(base - low), 2,
                    f"round {round_no} base level {base} vs authored {low}")

    def test_allow_uber_is_confined_to_sabrina(self):
        """Only the one leader whose pool holds an uber may set the flag.

        RARITY_TIER_UBER in this tree is exactly {MEW, MEWTWO} and only
        SabrinaPool lists them, so the flag has no business anywhere else. It is
        checked from the ROM rather than the source because the flags byte is
        assembled from `GYM_SPEC_FLAGS | (\\7)` under an `IF _rnd >= 7`, and a
        mistake there would hand every leader an uber without changing a single
        visible argument.

        FalknerSpec3 is the documented exception: it is a test fixture for
        PartyGenPoolCandidateOk and FalknerPool no longer holds an uber at all.
        """
        for image in self.images:
            for prefix, entry in GYM_LEADERS.items():
                extra = entry[6]
                for number in range(2, NUM_GYM_TEAMS + 1):
                    if (prefix, number) in HAND_WRITTEN:
                        continue
                    round_no = (number - 1) // NUM_ROUND_VARIANTS + 1
                    header, _ = image.record(f"{prefix}Spec{number}")
                    expected = bool(extra & ALLOW_UBER) and round_no >= 7
                    with self.subTest(rom=image.name, spec=f"{prefix}Spec{number}"):
                        self.assertEqual(
                            bool(header[5] & ALLOW_UBER), expected,
                            f"{prefix}Spec{number} (round {round_no})")

    def test_every_authored_team_is_well_formed(self):
        """Every level/species pair in parties.asm actually is one.

        Phase 3 leaves wTrainerNo 1 as a hole on all 19 characters, so the
        authored rosters stay reachable and a malformed one stays a live bug.
        This caught a real one on its first run: KogaData's round 5 variant C
        was missing NIDOQUEEN's level byte. ReadTrainer stops on a 0 in the
        LEVEL position, so that team read a species id as a level, 0 as a
        species, and then kept walking into the FOLLOWING teams' bytes - the
        scan went from 285 teams to 294 once it was fixed, because the bad
        record had been swallowing the ones after it.

        Nothing else could see this. It assembles (every operand is a valid
        byte), it links, and assert_table_length counts pointers, not mons.
        """
        text = (REPO_ROOT / "data/trainers/parties.asm").read_text(encoding="utf-8")
        blocks = re.finditer(
            r"^([A-Za-z_0-9]+Data):[ \t]*\n(.*?)"
            r"(?=\n[ \t]*[A-Za-z_0-9]+Data:[ \t]*\n|\Z)",
            text, re.S | re.M)
        # BuildMiniBossTeam supplies levels at runtime from
        # trainer_difficulty_settings_miniboss, so these two carry species
        # markers with no level bytes at all. Documented in parties.asm.
        level_less = {"RivalMiniBossData", "GiovanniMiniBossData"}

        def is_level(token):
            return token.isdigit() and 0 < int(token) <= 100

        teams_seen = 0
        for block in blocks:
            label, body = block.group(1), block.group(2)
            if label in level_less:
                continue
            tokens = []
            for raw in body.split("\n"):
                code = raw.split(";")[0].strip()
                if code.startswith("db"):
                    tokens += [p.strip() for p in code[2:].split(",") if p.strip()]
            index = 0
            team = 0
            while index < len(tokens):
                team += 1
                teams_seen += 1
                layout = tokens[index]
                with self.subTest(data=label, team=team):
                    if layout in ("$FF", "TRAINERPARTY_LEVELS",
                                  "$FE", "TRAINERPARTY_FORMS"):
                        stride = 3 if layout in ("$FE", "TRAINERPARTY_FORMS") else 2
                        index += 1
                        while index < len(tokens) and tokens[index] != "0":
                            self.assertTrue(
                                is_level(tokens[index]),
                                f"{label} team {team}: expected a level, got "
                                f"{tokens[index]!r} - context "
                                f"{tokens[max(0, index - 5):index + 3]}")
                            self.assertFalse(
                                is_level(tokens[index + 1]),
                                f"{label} team {team}: expected a species after "
                                f"level {tokens[index]}, got {tokens[index + 1]!r}"
                                " - a level byte is missing or doubled")
                            index += stride
                    else:
                        # shared-level layout: db <level>, <species>..., 0
                        self.assertTrue(
                            is_level(layout),
                            f"{label} team {team} starts with {layout!r}, which "
                            "is neither a layout byte nor a level")
                        index += 1
                        while index < len(tokens) and tokens[index] != "0":
                            index += 1
                    index += 1  # the terminator
        self.assertGreater(teams_seen, 250,
                           "the roster scan stopped early, which is itself the "
                           "symptom a malformed team produces")

    def test_no_other_trainer_class_gained_a_spec_list(self):
        """PartySpecPointers is keyed by class constant, so prove it stayed so.

        The table is built by a FOR loop matching `n == BROCK` rather than 61
        positional rows precisely because a positional row at the wrong index is
        invisible to assert_table_length. This checks the result: exactly the 19
        intended classes carry a list and every other row is still `dw 0`, so a
        mistyped ELIF cannot quietly give a route trainer a gym leader's specs.
        """
        expected = {entry[0] for entry in GYM_LEADERS.values()}
        expected |= {entry[0] for entry in E4_MEMBERS.values()}
        self.assertEqual(len(expected), 19)
        by_index = {v: k for k, v in self.classes.items()}
        num_trainers = max(by_index)
        for image in self.images:
            base = image.offset("PartySpecPointers")
            for index in range(1, num_trainers + 1):
                name = by_index.get(index, f"class {index}")
                pointer = image.word(base + (index - 1) * 2)
                with self.subTest(rom=image.name, trainer=name):
                    if name in expected:
                        self.assertNotEqual(
                            pointer, 0, f"{name} should have a spec list")
                    else:
                        self.assertEqual(
                            pointer, 0,
                            f"{name} unexpectedly points at {pointer:04X}")


if __name__ == "__main__":
    unittest.main()
