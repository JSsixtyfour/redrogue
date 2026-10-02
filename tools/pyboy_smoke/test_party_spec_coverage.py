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
BIT_ACE_LAST, BIT_NO_DUPES, BIT_ALLOW_UBER, BIT_NO_RIVAL_STARTER = 0, 1, 2, 3
BASE_FLAGS = (1 << BIT_ACE_LAST) | (1 << BIT_NO_DUPES)
ALLOW_UBER = 1 << BIT_ALLOW_UBER
NO_RIVAL_STARTER = 1 << BIT_NO_RIVAL_STARTER
# e4_team_spec (Trainer Revamp 2026-09-23): six mons, base E4_BASE_LEVEL + tier
# (read from balance_constants.asm below), step 2, ace pinned in the last slot,
# and NO wTrainerNo 1 hole.
E4_TEAM_SIZE = 6
POOL_FORM_BASE = 0
# ChampionsRoom.asm hands RIVAL3 wTrainerNo 1-5, all reaching Rival3Spec.
NUM_RIVAL3_TEAMS = 5
POOL_FORM_ROLL = 0xFF
OVERRIDES_END = 0xFF
# PartySpecOverrideFieldWidths, in bit order.
OVERRIDE_FIELD_WIDTHS = (2, 1, 1, 4, 1, 1, 1)
BIT_POVR_SPECIES = 0
BIT_POVR_POOL = 6
# PARTY_GEN_OFFTYPE_SLOT: the pseudo-slot whose pool override names the off-type pool.
OFFTYPE_SLOT = 0xFE
# party_specs.asm GYM_BAND_ROUNDS: gyms 1-2, 3-4, 5-6, 7-8.
GYM_BAND_ROUNDS = 2

# round -> (n_mons, base_level, level_step), read from the GYM_Rn_* knobs in
# constants/balance_constants.asm. Until 2026-09-28 these were literals measured
# from the authored parties.asm rosters; curve D (BALANCE_PHASE5_PLAN.md D) is a
# deliberate departure from those levels, so the knobs are now the source.
_BALANCE = parse_rgbds_constants(
    REPO_ROOT / "constants/balance_constants.asm",
    parse_rgbds_constants(REPO_ROOT / "constants/round_constants.asm"))
GYM_CURVE = {
    r: (_BALANCE[f"GYM_R{r}_MONS"], _BALANCE[f"GYM_R{r}_BASE"], _BALANCE[f"GYM_R{r}_STEP"])
    for r in range(1, 9)
}
E4_BASE_LEVEL = _BALANCE["E4_BASE_LEVEL"]
GYM_MIX = {1: "MIX_GYM_EARLY", 2: "MIX_GYM_EARLY", 3: "MIX_GYM_LATE",
           4: "MIX_GYM_LATE", 5: "MIX_GYM_LATE", 6: "MIX_ELITE",
           7: "MIX_ELITE", 8: "MIX_ELITE"}

# label prefix -> (trainer class, extra flags from round 7). Since the banded
# design (BALANCE_PHASE5_PLAN.md F, 2026-09-29) a leader's pools and aces are
# not spec arguments: each round's record names POOL_BAND_<prefix>_Fod/Ace/Off
# <band> from data/trainers/gym_band_pools.asm.
GYM_LEADERS = {
    "Falkner": ("FALKNER", 0), "Brock": ("BROCK", 0), "Misty": ("MISTY", 0),
    "LtSurge": ("LT_SURGE", 0), "Erika": ("ERIKA", 0), "Koga": ("KOGA", 0),
    "Blaine": ("BLAINE", 0), "Sabrina": ("SABRINA", 0), "Giovanni": ("GIOVANNI", 0),
    "Bugsy": ("BUGSY", 0), "Whitney": ("WHITNEY", 0), "Morty": ("MORTY", 0),
    "Chuck": ("CHUCK", 0), "Jasmine": ("JASMINE", 0), "Pryce": ("PRYCE", 0),
    "Clair": ("CLAIR", 0), "Janine": ("JANINE", 0),
}


def band_pool_labels():
    """POOL_BAND name -> the BandPool_ label its TrainerPoolTable row must point
    at, following `band_same` aliases to the pool that owns the bytes."""
    text = (REPO_ROOT / "data/trainers/gym_band_pools.asm").read_text(encoding="utf-8")
    out = {}
    for raw in text.splitlines():
        code = raw.split(";")[0].strip()
        m = re.match(r"band_pool\s+(\w+)$", code)
        if m:
            out[m.group(1)] = f"BandPool_{m.group(1)}"
        m = re.match(r"band_same\s+(\w+),\s*(\w+)$", code)
        if m:
            out[m.group(1)] = out[m.group(2)]
    return out


# Elite Four only: label prefix -> (class, pool, ace, ace form, alt, alt form).
# Both aces need an explicit form because neither eeveelution is a species in
# this tree - Espeon and Umbreon are JOLTEON forms 1 and 2.
E4_MEMBERS = {
    "Will": ("WILL", "POOL_WILL", "XATU", POOL_FORM_ROLL, "JOLTEON", 1),
    "Karen": ("KAREN", "POOL_KAREN", "HOUNDOOM", POOL_FORM_ROLL, "JOLTEON", 2),
    # KOGA_E4 is a SEPARATE class from the gym KOGA above, and belongs here
    # rather than in the gym registry. The two roles need different grids: the
    # gym Koga is 24 records indexed by ROUND, the Elite Four grid is 12 on
    # four tiers. Sharing one class made an Elite Four Koga field his gym
    # rounds 1-4, roughly level 15 against a level 55 party. His aces are plain
    # species, so unlike Will and Karen neither needs a form index.
    # Since the Trainer Revamp he draws his own POOL_KOGA_E4 (Articuno is
    # E4-only, Beedrill gym-only) and his C ace is Galarian Weezing.
    "KogaE4": ("KOGA_E4", "POOL_KOGA_E4", "CROBAT", 0, "WEEZING", 1),
    # The Kanto four had no spec list at all until the Trainer Revamp, so every
    # tier fielded one authored team. LANCE's list also serves Champion Lance.
    "Lorelei": ("LORELEI", "POOL_LORELEI", "LAPRAS", 0, "CLOYSTER", 0),
    "Bruno": ("BRUNO", "POOL_BRUNO", "MACHAMP", 0, "HITMONTOP", 0),
    "Agatha": ("AGATHA", "POOL_AGATHA", "GENGAR", 0, "MAROWAK", 1),
    "Lance": ("LANCE", "POOL_LANCE", "DRAGONITE", 0, "KINGDRA", 0),
}
# Falkner's round 1 B and C are the Phase 2 worked examples, kept verbatim
# because five tests drive them by name and number. They do not follow the
# generated shape and are checked separately.
HAND_WRITTEN = {("Falkner", 2), ("Falkner", 3)}

# Phase 7f: procedural stage-event characters (PROCEDURAL_WILD_AREA_PLAN.md).
# A separate set, not folded into GYM_LEADERS/E4_MEMBERS above: those two
# dicts drive the byte-for-byte gym_team_spec/e4_team_spec shape checks
# elsewhere in this file, and the stage-event classes use a different macro
# (stage_event_team_spec, data/trainers/party_specs.asm) with no round/variant
# grid and no ace pin, so they would fail those checks for having the wrong
# shape rather than for a real defect. Only test_no_other_trainer_class_...
# below needs to know these five now carry a spec list.
STAGE_EVENT_CLASSES = {
    "JESSIE_JAMES", "PSYCHIC_TR", "BURGLAR", "NURSE_JOY", "OFFICER_JENNY",
}

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

    def pool_list_addr(self, pool_id):
        """The species-list address TrainerPoolTable row `pool_id` points at."""
        row = self.offset("TrainerPoolTable") + pool_id * 5
        return self.word(row + 3)

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
                # Nobody has a wTrainerNo 1 hole any more: the Elite Four lost
                # theirs 2026-09-23, the gym leaders 2026-09-29.
                has_hole = False
                with self.subTest(rom=image.name, character=prefix):
                    count, pointers = image.spec_list(prefix)
                    self.assertEqual(
                        count, teams,
                        f"{prefix}Specs declares {count} teams; InitGymBattle / "
                        f"InitElite4Battle can ask for {teams}")
                    if has_hole:
                        self.assertEqual(
                            pointers[0], 0,
                            f"{prefix} wTrainerNo 1 should be the authored-team hole")
                    for number, pointer in enumerate(
                            pointers[1:] if has_hole else pointers,
                            start=2 if has_hole else 1):
                        # Gym leaders: every variant of a round shares that
                        # round's record (banded design).
                        if prefix in GYM_LEADERS:
                            want = f"{prefix}Round{(number - 1) // NUM_ROUND_VARIANTS + 1}"
                        else:
                            want = f"{prefix}Spec{number}"
                        self.assertEqual(
                            pointer, image.addr(want),
                            f"{prefix} wTrainerNo {number} points at "
                            f"{pointer:04X}, not at {want}")

    def test_generated_records_match_the_round_and_variant_they_serve(self):
        """Every banded round record's header and pool overrides, from the ROM.

        Header: the round's curve, the band's FODDER pool, the round's mix.
        Overrides: the last slot draws from the band's ACE pool, and from band 2
        the PARTY_GEN_OFFTYPE_SLOT pseudo-slot names its OFF-TYPE pool. Each pool
        id is followed through TrainerPoolTable to the BandPool_ label it must
        reach, so an id emitted for the wrong leader or band fails here even
        though it assembles and links.
        """
        labels = band_pool_labels()
        for image in self.images:
            for prefix, (_cls, extra) in GYM_LEADERS.items():
                for round_no in range(1, NUM_GYM_ROUNDS + 1):
                    band = (round_no - 1) // GYM_BAND_ROUNDS + 1
                    mons, base, step = GYM_CURVE[round_no]
                    label = f"{prefix}Round{round_no}"
                    with self.subTest(rom=image.name, spec=label):
                        header, overrides = image.record(label)
                        self.assertEqual(
                            header[:3] + header[4:],
                            (mons, base, step, self.mixes[GYM_MIX[round_no]],
                             BASE_FLAGS | (extra if round_no >= 7 else 0)),
                            f"{label} serves round {round_no}")
                        self.assertEqual(
                            image.pool_list_addr(header[3]),
                            image.addr(labels[f"{prefix}_Fod{band}"]),
                            f"{label}'s own pool is not {prefix}_Fod{band}")
                        want_slots = [mons - 1] + ([OFFTYPE_SLOT] if band >= 2 else [])
                        self.assertEqual([o[0] for o in overrides], want_slots)
                        for (slot, flags, fields), kind in zip(overrides, ("Ace", "Off")):
                            self.assertEqual(flags, 1 << BIT_POVR_POOL)
                            self.assertEqual(
                                image.pool_list_addr(fields[BIT_POVR_POOL][0]),
                                image.addr(labels[f"{prefix}_{kind}{band}"]),
                                f"{label} slot {slot:02X} is not {prefix}_{kind}{band}")

    def test_elite_four_records_use_the_four_tier_grid(self):
        """Twelve teams on the E4 grid, not 24 on the gym grid.

        InitElite4Battle derives its tier linearly from wBattleCount 86-89, so
        an E4-only class is asked for 1-12. Giving one 24 teams would leave half
        unreachable; giving it 8 rounds' worth of levels would put tier 1 at a
        gym leader's round-1 levels.

        All four tiers share MIX_E4_SETS, the Phase 5 "sets only, ELITE mask"
        row - the one place in the grid where the row does NOT vary with the
        round, because the four tiers are within three levels of each other and
        the ladder lives in the levels instead.
        """
        for image in self.images:
            for prefix, (_cls, pool, ace, ace_form, alt, alt_form) \
                    in E4_MEMBERS.items():
                for number in range(1, NUM_E4_TEAMS + 1):
                    tier = (number - 1) // NUM_ROUND_VARIANTS + 1
                    variant = (number - 1) % NUM_ROUND_VARIANTS
                    label = f"{prefix}Spec{number}"
                    with self.subTest(rom=image.name, spec=label):
                        header, overrides = image.record(label)
                        self.assertEqual(
                            header,
                            (E4_TEAM_SIZE, E4_BASE_LEVEL + tier, 2, self.pools[pool],
                             self.mixes["MIX_E4_SETS"], BASE_FLAGS),
                            f"{label} serves tier {tier}")
                        if variant == 1:
                            self.assertEqual(overrides, [])
                            continue
                        pinned, form = ((ace, ace_form) if variant == 0
                                        else (alt, alt_form))
                        self.assertEqual(len(overrides), 1)
                        slot, _flags, fields = overrides[0]
                        self.assertEqual(slot, E4_TEAM_SIZE - 1)
                        self.assertEqual(fields[BIT_POVR_SPECIES],
                                         [self.species[pinned], form])

    def test_rival3_champion_record(self):
        """All five Champion-rival numbers reach one pool-rolled record.

        Six mons at 60-65, and the last slot pins RIVAL_STARTER_PLACEHOLDER,
        which PartyGenBuildSlot resolves to his own selected starter. The
        NO_RIVAL_STARTER flag is what keeps the other five slots off that line;
        without it the pool's CHARMANDER could stand next to his Charizard.
        """
        for image in self.images:
            with self.subTest(rom=image.name):
                count, pointers = image.spec_list("Rival3")
                self.assertEqual(count, NUM_RIVAL3_TEAMS)
                self.assertEqual(set(pointers), {image.addr("Rival3Spec")})
                header, overrides = image.record("Rival3Spec")
                self.assertEqual(
                    header,
                    (6, _BALANCE["CHAMPION_BASE_LEVEL"], _BALANCE["CHAMPION_LEVEL_STEP"],
                     self.pools["POOL_RIVAL3"],
                     self.mixes["MIX_E4_SETS"], BASE_FLAGS | NO_RIVAL_STARTER))
                self.assertEqual(len(overrides), 1)
                slot, flags, fields = overrides[0]
                self.assertEqual(slot, 5)
                self.assertEqual(flags, 1 << BIT_POVR_SPECIES)
                self.assertEqual(
                    fields[BIT_POVR_SPECIES],
                    [self.species["RIVAL_STARTER_PLACEHOLDER"], POOL_FORM_BASE])

    def test_curve_tracks_the_authored_rosters(self):
        """The generated team sizes still match the authored rosters.

        All eight shipped Kanto rosters are identical round for round, which is
        what made one shared curve correct. The LEVEL half of this check is
        retired (2026-09-28): curve D raised the leader levels on purpose
        (BALANCE_PHASE5_PLAN.md D), so the authored level envelopes no longer
        describe the game. Team sizes did not change and are still held.
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
                # Level envelope vs the authored rosters: retired with curve D
                # (see the docstring). The knobs are the source of the levels.

    def test_no_gym_round_allows_ubers(self):
        """No gym leader's round record sets BIT_PSPEC_ALLOW_UBER.

        RARITY_TIER_UBER is exactly {MEW, MEWTWO}, and since the banded design
        no gym pool lists either. Checked from the ROM because the flags byte is
        assembled from `GYM_SPEC_FLAGS | (\\3)` under an `IF _rnd >= 7`, and a
        mistake there would hand every leader an uber without changing a single
        visible argument. FalknerSpec3 is a test fixture and stays exempt.
        """
        for image in self.images:
            for prefix in GYM_LEADERS:
                for round_no in range(1, NUM_GYM_ROUNDS + 1):
                    header, _ = image.record(f"{prefix}Round{round_no}")
                    with self.subTest(rom=image.name, spec=f"{prefix}Round{round_no}"):
                        self.assertFalse(header[5] & ALLOW_UBER)

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
        # trainer_difficulty_settings_miniboss, so these three carry species
        # markers with no level bytes at all. Documented in parties.asm.
        level_less = {"RivalMiniBossData", "GiovanniMiniBossData",
                      "KarateMiniBossData"}

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
        invisible to assert_table_length. This checks the result: exactly the 20
        intended classes carry a list and every other row is still `dw 0`, so a
        mistyped ELIF cannot quietly give a route trainer a gym leader's specs.

        17 gym leaders + 7 Elite Four + RIVAL3 + 5 Phase 7f stage-event
        characters. The Trainer Revamp added LORELEI, BRUNO, AGATHA, LANCE and
        RIVAL3 (25 -> 30).
        Was 19 before KOGA_E4, the Phase 7 class that carries the Elite Four
        Koga's party grid so it is not the gym Koga's 24-round one, and 20
        before Phase 7f gave JESSIE_JAMES, PSYCHIC_TR, BURGLAR, NURSE_JOY and
        OFFICER_JENNY their own 9-row stage_event_team_spec lists. Raise this
        only alongside a deliberate new entry in GYM_LEADERS, E4_MEMBERS or
        STAGE_EVENT_CLASSES above.
        """
        expected = {entry[0] for entry in GYM_LEADERS.values()}
        expected |= {entry[0] for entry in E4_MEMBERS.values()}
        expected |= STAGE_EVENT_CLASSES
        expected |= {"RIVAL3"}
        self.assertEqual(len(expected), 30)
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
