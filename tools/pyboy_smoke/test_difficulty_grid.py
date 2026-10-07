"""Phase 5: the MovesetMixTable difficulty grid and its binding to wBattleCount.

Two halves, for two different failure modes.

The STATIC half decodes the grid and its lookup tables out of the built ROMs.
It exists because of the bug Phase 3 found the hard way: a mix row that no
shipping spec references is UNEXECUTED, and so is every branch only that row can
reach. MIX_ELITE hid a guaranteed infinite loop behind five passing tests for
exactly as long as nothing referenced it. Phase 5 adds five new rows, so
test_every_mix_row_is_reachable is the check that none of them is decoration.

The RUNTIME half proves the binding actually runs. wBattleCount -> round and
step -> kind and band -> a row of RosterMixByKindAndBand is four pieces of
arithmetic in assembly, all of which assemble fine when wrong, and the only
observation that settles it is the mix id the ROM hands RogueApplyMixToParty.
That is read off the CPU at the routine's entry rather than inferred from the
resulting party, because a moveset is a weighted random draw and two adjacent
rows can legitimately produce the same four moves.
"""
import unittest

from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_party_spec_coverage import Image, ROMS
from test_smoke import HarnessTestCase, REPO_ROOT

PARTY_LENGTH = 6
# Every kind is cut on the same four bands (gyms 1-2, 3-4, 5-6, 7-8): the
# GYM_BAND_ROUNDS cut the leader's species pools use.
NUM_BANDS = 4
GYM_BAND_ROUNDS = 2

# Column order inside a mix row, matching the `mix` macro in party_specs.asm.
QUOTA_COLUMNS = ("learnset", "learnset_full", "random", "random_tm",
                 "random_tm_only", "set")
TIER_MASK, RANK_ROW, TM_CAP = 6, 7, 8
FALLBACK = 13  # MIX_FALLBACK_OFFSET
MSRC_SET = QUOTA_COLUMNS.index("set")

# The plan's Phase 5 grid, as a model independent of the ROM. The static test
# checks the ROM's lookup table implements this; the runtime test checks the
# ROM's code reaches that table. Row 0 is the route trainer (step 0-4), row 1
# the final route trainer and the gym trainers (step 5-9).
ROSTER_GRID = (
    ("MIX_ROUTE_EARLY", "MIX_ROUTE_MID", "MIX_ROUTE_LATE", "MIX_ROUTE_FINAL"),
    ("MIX_TRAINER_EARLY", "MIX_TRAINER_MID", "MIX_TRAINER_LATE",
     "MIX_TRAINER_FINAL"),
)
GYM_BAND = ("MIX_GYM_EARLY", "MIX_GYM_MID", "MIX_GYM_LATE", "MIX_ELITE")

# The rank_row ladder the grid is meant to describe, per kind, by band. Each
# kind's ladder never falls; the leader's gyms 3-4 row stays on NORMAL on
# purpose (2026-10-05), sharing it with that band's trainers.
RANK_LADDER = {
    "route": ("RANK_ROW_BAD", "RANK_ROW_EASY", "RANK_ROW_NORMAL",
              "RANK_ROW_HARD"),
    "trainer": ("RANK_ROW_EASY", "RANK_ROW_NORMAL", "RANK_ROW_HARD",
                "RANK_ROW_HARD"),
    "leader": ("RANK_ROW_NORMAL", "RANK_ROW_NORMAL", "RANK_ROW_HARD",
               "RANK_ROW_ELITE"),
}

# Gym team size per round (GYM_R<n>_MONS), for the quota-fit check.
_BALANCE = parse_rgbds_constants(
    REPO_ROOT / "constants/balance_constants.asm",
    parse_rgbds_constants(REPO_ROOT / "constants/round_constants.asm"))
GYM_TEAM_SIZE = {r: _BALANCE[f"GYM_R{r}_MONS"] for r in range(1, 9)}


def roster_team_sizes():
    """{round index: (smallest route team, smallest gym-trainer-row team)}.

    From data/balance/trainer_levels.asm: nine 11-byte blocks for the route
    table, then nine for the gym trainers. Bytes 2-5 are the normal class
    counts, 7-10 the final trainer's. A normal team of
    ROSTER_VARY_MIN_SIZE..ROSTER_FULL_SIZE-1 mons may field one fewer
    (GetRandRoster's .maybeShrink); a final trainer never does. The gym-trainer
    mix row also covers the final ROUTE trainer, so its smallest team is taken
    over that one, the normal gym trainers and the final gym trainer.
    """
    values = []
    text = (REPO_ROOT / "data/balance/trainer_levels.asm").read_text()
    for raw in text.splitlines():
        code = raw.split(";", 1)[0].strip()
        if code.startswith("db "):
            values.append(int(code[3:].strip(), 0))

    def block(index):
        cells = values[index * 11:(index + 1) * 11]
        normal, final = sum(cells[2:6]), sum(cells[7:11])
        if _BALANCE["ROSTER_VARY_MIN_SIZE"] <= normal < _BALANCE["ROSTER_FULL_SIZE"]:
            normal -= 1
        return normal, final

    rounds = len(values) // 22
    sizes = {}
    for index in range(rounds):
        route_normal, route_final = block(index)
        gym_normal, gym_final = block(rounds + index)
        sizes[index] = (route_normal, min(route_final, gym_normal, gym_final))
    return sizes


# Every row the grid model above knows about. Asserted to be the COMPLETE set,
# so a new mix row cannot be added to the ROM without this model growing with
# it - which is the only way the reachability check below stays honest.
ALL_MIX_NAMES = sum((list(row) for row in ROSTER_GRID), []) \
    + list(GYM_BAND) + ["MIX_E4_SETS", "MIX_GAMBLER"]

# `DEF NUM_MOVESET_MIXES EQU const_value` does not survive parse_rgbds_constants
# (const_value is an rgbds builtin, not a name it has seen), so these two sizes
# are the ones this file reads out of the source rather than hard-coding.
SIZE_CONSTANTS = ("MIX_ENTRY_SIZE", "MIX_ONLY_SPEC_SIZE", "MIX_FALLBACK_OFFSET")


def _constants():
    """Every constant these tests name, from the files that define them."""
    values = parse_rgbds_constants(REPO_ROOT / "data/trainers/party_specs.asm")
    values.update(
        parse_rgbds_constants(REPO_ROOT / "constants/party_spec_constants.asm")
    )
    return values


def _mix_ids(values):
    return {
        name: value for name, value in values.items()
        if name.startswith("MIX_") and name not in SIZE_CONSTANTS
    }


# The round shape (constants/round_constants.asm), so the positions below
# follow ROUTE_BATTLES / GYM_TRAINER_BATTLES instead of assuming 10 per round.
ROUND = parse_rgbds_constants(REPO_ROOT / "constants/round_constants.asm")
R = ROUND["ROUND_BATTLES"]


def at(round_index, step):
    """The wBattleCount of `step` within round `round_index`."""
    return round_index * R + step


def expected_round_and_step(battle_count):
    """GetRandRoster's own arithmetic, in Python: clamp, then divide by the round size."""
    clamped = min(battle_count, ROUND["LAST_ROUND_BATTLECOUNT"])
    return clamped // R, clamped % R


def strongest_source(row):
    """The highest MSRC_* a decoded mix row can hand a slot (quota or fallback)."""
    named = [i for i, q in enumerate(row[:len(QUOTA_COLUMNS)]) if q]
    return max(named + [row[FALLBACK]])


def expected_band(round_index):
    """Round index r is fought on the way to gym r + 1; its band is that gym's."""
    return min(round_index // GYM_BAND_ROUNDS, NUM_BANDS - 1)


def expected_roster_mix(battle_count):
    """The mix row name wBattleCount should select for a roster trainer.

    The route/trainer line falls at step 5, one earlier than GetRandRoster's
    own route/gym LEVEL table split at step 6. That is deliberate: step 5 is
    the final route trainer, which the plan's grid groups with the gym
    trainers, and which already gets BIT_ROGUE_FINAL_TRAINER's level bonus.
    """
    round_index, step = expected_round_and_step(battle_count)
    kind = 0 if step < ROUND["FINAL_ROUTE_STEP"] else 1
    return ROSTER_GRID[kind][expected_band(round_index)]


class DifficultyGridContractTest(unittest.TestCase):
    """Static decode of the grid from all three built ROMs."""

    @classmethod
    def setUpClass(cls):
        cls.images = [Image(name) for name in ROMS]
        cls.const = _constants()
        cls.mix_ids = _mix_ids(cls.const)
        cls.num_mixes = max(cls.mix_ids.values()) + 1
        cls.entry_size = cls.const["MIX_ENTRY_SIZE"]
        cls.spec_size = cls.const["MIX_ONLY_SPEC_SIZE"]

    def test_the_grid_model_names_every_row_the_rom_has(self):
        """The ids are contiguous and this file knows all of them.

        Everything below indexes the ROM by a name from ALL_MIX_NAMES, so a
        row added to party_specs.asm and wired to nothing would otherwise be
        invisible here - the exact hole test_every_mix_row_is_reachable exists
        to close.
        """
        self.assertEqual(len(self.mix_ids), self.num_mixes,
                         f"mix ids are not contiguous: {sorted(self.mix_ids.items())}")
        self.assertEqual(sorted(self.mix_ids), sorted(ALL_MIX_NAMES))

    def mix_rows(self, image):
        base = image.offset("MovesetMixTable")
        return [
            list(image.rom[base + i * self.entry_size:
                           base + (i + 1) * self.entry_size])
            for i in range(self.num_mixes)
        ]

    def referenced_mix_ids(self, image):
        """Every mix id any shipping spec record or lookup table can select.

        Walks PartySpecPointers for all NUM_TRAINERS classes, follows each
        non-null spec list and reads the mix byte out of every non-hole record,
        then adds the two Phase 5 lookup tables. Deliberately derived from the
        ROM rather than from the source macros: the macros are what would be
        wrong.
        """
        classes = parse_trainer_class_indexes(
            REPO_ROOT / "constants/trainer_constants.asm"
        )
        num_trainers = max(classes.values())
        seen = set()
        table = image.offset("PartySpecPointers")
        for index in range(num_trainers):
            list_addr = image.word(table + index * 2)
            if not list_addr:
                continue
            list_off = image.offset("PartySpecPointers") \
                + (list_addr - image.addr("PartySpecPointers"))
            count = image.rom[list_off]
            for i in range(count):
                record_addr = image.word(list_off + 1 + i * 2)
                if not record_addr:
                    continue  # a `dw 0` hole: the authored path serves it
                record_off = list_off + (record_addr - (list_addr))
                seen.add(image.rom[record_off + 4])  # header byte 4 = mix id
        roster = image.offset("RosterMixByKindAndBand")
        seen.update(image.rom[roster:roster + 2 * NUM_BANDS])
        gym = image.offset("GymMixByBand")
        seen.update(image.rom[gym:gym + NUM_BANDS])
        # MIX_GAMBLER is an immediate in RogueRosterMixId (party roster Phase
        # 6): ld a, [wTrainerClass] / cp GAMBLER / ld a, MIX_GAMBLER / ret z.
        # Read out of the code itself, and the opcodes around it checked, so a
        # reshuffled prologue fails here instead of reading a stray byte.
        code = image.offset("RogueRosterMixId")
        if image.rom[code] == 0xFA and image.rom[code + 3] == 0xFE                 and image.rom[code + 5] == 0x3E and image.rom[code + 7] == 0xC8:
            seen.add(image.rom[code + 6])
        return seen

    def test_every_mix_row_is_reachable(self):
        """No row is decoration.

        Phase 3's infinite loop lived in a branch only MIX_ELITE could reach,
        and stayed invisible while nothing referenced MIX_ELITE. Five new rows
        landed in Phase 5 and MIX_GYM_MID after it; this is what says each of
        them is real content and not a row someone meant to wire up later.
        """
        for image in self.images:
            with self.subTest(rom=image.name):
                reachable = self.referenced_mix_ids(image)
                missing = sorted(set(range(self.num_mixes)) - reachable)
                self.assertEqual(
                    missing, [],
                    f"mix rows {missing} are referenced by nothing, so neither "
                    "they nor any branch only they reach is ever executed",
                )
                # Guards the walk itself. A pointer-arithmetic slip would read
                # mix ids out of unrelated bytes, which passes the check above
                # by accident while proving nothing; real ids are all in range.
                stray = sorted(i for i in reachable if i >= self.num_mixes)
                self.assertEqual(
                    stray, [],
                    f"the spec-record walk produced mix ids {stray}, which are "
                    "past the end of MovesetMixTable - it is decoding the wrong "
                    "bytes",
                )

    def test_roster_lookup_table_matches_the_grid(self):
        for image in self.images:
            base = image.offset("RosterMixByKindAndBand")
            for kind, row in enumerate(ROSTER_GRID):
                for band, name in enumerate(row):
                    with self.subTest(rom=image.name, kind=kind, band=band):
                        self.assertEqual(
                            image.rom[base + kind * NUM_BANDS + band],
                            self.const[name],
                        )

    def test_gym_band_table_matches_the_grid(self):
        for image in self.images:
            base = image.offset("GymMixByBand")
            for band, name in enumerate(GYM_BAND):
                with self.subTest(rom=image.name, band=band):
                    self.assertEqual(image.rom[base + band], self.const[name])

    def test_mix_only_pseudo_specs_name_their_own_row(self):
        """MixOnlySpecs[m] must carry mix id m and nothing else.

        Generated by a FOR loop, so the interesting failure is not a typo but
        an off-by-one against MIX_ONLY_SPEC_SIZE, which would hand
        RogueApplyMixToParty a pointer into the middle of the previous record -
        assembling clean and mixing every roster under the wrong row.
        """
        for image in self.images:
            base = image.offset("MixOnlySpecs")
            for mix in range(self.num_mixes):
                off = base + mix * self.spec_size
                with self.subTest(rom=image.name, mix=mix):
                    self.assertEqual(
                        list(image.rom[off:off + self.spec_size]),
                        [0, 0, 0, 0, mix, 0, 0xFF],
                        "a mix-only pseudo-spec is n_mons, base, step, pool, "
                        "mix, flags, then an immediate override terminator",
                    )

    def test_fallback_is_a_rollable_source_below_set(self):
        """The fallback column is also MSRC_SET's own fallback.

        A fallback of MSRC_SET would send a set-less slot straight back to the
        set path; anything at or past MSRC_EXPLICIT has no roll behind it.
        """
        for image in self.images:
            for mix, row in enumerate(self.mix_rows(image)):
                with self.subTest(rom=image.name, mix=mix):
                    self.assertLess(row[FALLBACK], MSRC_SET)

    def test_gym_rows_fit_every_team_in_their_band(self):
        """A gym row never asks for more units than its rounds have mons.

        The ROM asserts this at build time too (gym_round_spec); checked here
        against the decoded table so a hand-edited row or a GYM_R<n>_MONS
        retune that slips past the assert still fails loudly.
        """
        for image in self.images:
            rows = self.mix_rows(image)
            for round_no, size in GYM_TEAM_SIZE.items():
                band = (round_no - 1) // GYM_BAND_ROUNDS
                row = rows[self.const[GYM_BAND[band]]]
                with self.subTest(rom=image.name, round=round_no):
                    self.assertLessEqual(
                        sum(row[:self.const["NUM_MSRC_QUOTAS"]]), size)

    def test_roster_rows_fit_the_smallest_team_in_their_band(self):
        """No roster unit depends on the team reaching some size.

        A row is "these units, then the fallback": if its quotas add up past
        the smallest team its band fields, some battles silently lose units.
        Route rows are checked against normal route teams (which may shrink by
        one), trainer rows against every team that fields the gym-trainer row.
        """
        sizes = roster_team_sizes()
        for image in self.images:
            rows = self.mix_rows(image)
            for band in range(NUM_BANDS):
                rounds = [r for r in sizes if expected_band(r) == band]
                smallest_route = min(sizes[r][0] for r in rounds)
                smallest_trainer = min(sizes[r][1] for r in rounds)
                for kind, smallest in ((0, smallest_route), (1, smallest_trainer)):
                    name = ROSTER_GRID[kind][band]
                    with self.subTest(rom=image.name, row=name):
                        total = sum(rows[self.const[name]][:self.const["NUM_MSRC_QUOTAS"]])
                        self.assertLessEqual(
                            total, smallest,
                            f"{name} deals {total} units but its band fields "
                            f"teams of {smallest}")

    def test_quotas_never_exceed_a_full_party(self):
        """An over-full mix silently drops its weakest units.

        PartyGenAssignSources deals quotas strongest first and drops a unit
        that finds no free slot, so a row summing past PARTY_LENGTH does not
        fail - it just means its weakest columns never apply, which is a tuning
        bug that reads as a random one.
        """
        for image in self.images:
            for mix, row in enumerate(self.mix_rows(image)):
                with self.subTest(rom=image.name, mix=mix):
                    quotas = row[:self.const["NUM_MSRC_QUOTAS"]]
                    total = sum(quotas)
                    self.assertLessEqual(
                        total, PARTY_LENGTH,
                        f"mix {mix} quotas sum to {total}: "
                        f"{dict(zip(QUOTA_COLUMNS, quotas))}",
                    )

    def test_rank_row_ladder_rises_with_band_and_with_kind(self):
        """The whole point of the grid: harder later, and harder per kind.

        Checked as a property rather than row by row, so a future retune can
        change any individual weight but cannot accidentally make a round-8
        route trainer roll from a softer table than a round-1 one.
        """
        names = {"route": ROSTER_GRID[0], "trainer": ROSTER_GRID[1],
                 "leader": GYM_BAND}
        for image in self.images:
            rows = self.mix_rows(image)
            for kind, ladder in RANK_LADDER.items():
                with self.subTest(rom=image.name, kind=kind, ladder=True):
                    ranks = [self.const[name] for name in ladder]
                    self.assertEqual(ranks, sorted(ranks),
                                     f"the {kind} ladder falls somewhere")
                for band, expected in enumerate(ladder):
                    mix = self.const[names[kind][band]]
                    with self.subTest(rom=image.name, kind=kind, band=band):
                        self.assertEqual(
                            rows[mix][RANK_ROW], self.const[expected],
                            f"{names[kind][band]} should use {expected}",
                        )
            # And the cross-kind claims, at every band: route <= trainer <=
            # leader, and a route is no softer than the previous band's gym
            # trainers.
            for band in range(NUM_BANDS):
                route_row = rows[self.const[ROSTER_GRID[0][band]]]
                trainer_row = rows[self.const[ROSTER_GRID[1][band]]]
                route, trainer = route_row[RANK_ROW], trainer_row[RANK_ROW]
                leader = rows[self.const[GYM_BAND[band]]][RANK_ROW]
                with self.subTest(rom=image.name, band=band):
                    self.assertLessEqual(route, trainer)
                    self.assertLessEqual(trainer, leader)
                    self.assertLessEqual(route, leader)
                    if band:
                        previous = rows[self.const[ROSTER_GRID[1][band - 1]]][RANK_ROW]
                        self.assertGreaterEqual(
                            route, previous,
                            "a route should be no softer than the gym "
                            "trainers of the band before it")
                    if route == trainer:
                        self.assertGreater(
                            strongest_source(trainer_row),
                            strongest_source(route_row),
                            "where route and gym trainer share a rank_row the "
                            "gym trainer must name a stronger source")

    def test_a_curated_set_quota_always_carries_a_tier_mask(self):
        """A nonzero MSRC_SET quota with a zero set_tier_mask can never match.

        PartyGenApplySetMoveset ANDs a record's tier against the mask, so mask 0
        rejects every record and the slot silently degrades to its fallback. The
        row would look like it curates and never would.
        """
        for image in self.images:
            for mix, row in enumerate(self.mix_rows(image)):
                if row[QUOTA_COLUMNS.index("set")] == 0:
                    continue
                with self.subTest(rom=image.name, mix=mix):
                    self.assertNotEqual(
                        row[TIER_MASK], 0,
                        f"mix {mix} asks for {row[QUOTA_COLUMNS.index('set')]} "
                        "curated sets but its tier mask matches no record",
                    )

    def test_tm_cap_is_nonzero_wherever_random_tm_is_used(self):
        # Covers the fallback column too: a row whose fallback is random+TM
        # rolls it on every slot no quota reaches.
        """MSRC_RANDOM_TM with tm_cap 0 is MSRC_RANDOM with extra steps.

        Not fatal - the union still contains every level-learnable move that is
        also a TM - but it means the row cannot reach a single TM-ONLY move,
        which is the whole reason to name that source.
        """
        for image in self.images:
            for mix, row in enumerate(self.mix_rows(image)):
                rtm = QUOTA_COLUMNS.index("random_tm")
                if row[rtm] == 0 and row[FALLBACK] != rtm:
                    continue
                with self.subTest(rom=image.name, mix=mix):
                    self.assertGreater(row[TM_CAP], 0)


class DifficultyGridBindingSmokeTest(HarnessTestCase):
    """The runtime half: wBattleCount really does pick the row.

    ⚠ HARNESS LIMIT. ReadTrainer cannot be driven more than roughly ten times
    per boot (see the module note in test_party_specs.py), so the grid is
    sampled three cells at a time across three tests rather than swept.

    YOUNGSTER is the trainer class throughout. Its wTrainerNo 1 team is the
    shared `db 14, SPEAROW, 0` block at data/trainers/parties.asm - a plain
    same-level team, so its first byte is not TRAINERPARTY_LEVELS and ReadTrainer
    hands it to GetRandRoster. That is the path Phase 5 hooks.
    """

    def _boot(self):
        """Boot once and arm the entry hook ONCE.

        register_hook appends to a per-address callback list rather than
        replacing, so arming it inside the per-build helper would leave every
        earlier build's callback live and firing.
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        self.seen = []
        h.register_hook(
            "RogueApplyMixToParty",
            lambda _ctx: self.seen.append(h.pyboy.register_file.A),
        )
        self.classes = parse_trainer_class_indexes(
            REPO_ROOT / "constants/trainer_constants.asm"
        )

    def _selected_mix(self, battle_count, trainer_class="YOUNGSTER",
                      trainer_no=1):
        """Run ReadTrainer at this wBattleCount; return the mix id chosen.

        Read two independent ways, and both are asserted, because they fail
        differently: the hook sees what RogueRosterMixId returned, while
        wPartyGenSpecPtr shows which MixOnlySpecs record that id resolved to.
        A broken lookup stride would agree with the first and not the second.
        """
        h = self.harness
        assert h is not None
        self.seen.clear()
        h.write8("wBattleCount", battle_count)
        h.write8("wTrainerClass", self.classes[trainer_class])
        h.write8("wTrainerNo", trainer_no)
        h.call_routine("ReadTrainer", limit=60000)

        self.assertEqual(
            len(self.seen), 1,
            f"RogueApplyMixToParty ran {len(self.seen)} times at wBattleCount "
            f"{battle_count}; the roster hook should fire exactly once",
        )
        pointer = h.read8("wPartyGenSpecPtr") | (
            h.read8("wPartyGenSpecPtr", offset=1) << 8
        )
        delta = pointer - h.address("MixOnlySpecs")
        spec_size = _constants()["MIX_ONLY_SPEC_SIZE"]
        self.assertEqual(
            delta % spec_size, 0,
            f"wPartyGenSpecPtr landed {delta} bytes into MixOnlySpecs, which is "
            "not a record boundary",
        )
        self.assertEqual(delta // spec_size, self.seen[0])
        return self.seen[0]

    def _check(self, battle_counts):
        self._boot()
        const = _constants()
        for battle_count in battle_counts:
            expected = expected_roster_mix(battle_count)
            with self.subTest(battle_count=battle_count):
                self.assertEqual(
                    self._selected_mix(battle_count), const[expected],
                    f"wBattleCount {battle_count} should select {expected}",
                )

    def test_route_trainers_walk_the_route_column(self):
        """Steps 0-4 of an early, a middle and a late round."""
        self._check([0, at(2, 3), at(6, 3)])

    def test_gym_trainers_walk_the_trainer_column(self):
        """Step 5 is the final route trainer and belongs to this column too."""
        self._check([ROUND["FINAL_ROUTE_STEP"], at(2, ROUND["FINAL_GYM_TRAINER_STEP"] - 1),
                     at(6, ROUND["FINAL_GYM_TRAINER_STEP"])])

    def test_band_edges_and_the_round_clamp(self):
        """The values most likely to be off by one.

        19 is the last battle of round index 1 (still band 0), 20 the first of
        round index 2 (band 1), 40 the first of band 2, 60 the first of band 3,
        and 95 is past the clamp GetRandRoster applies at 90 - without it the
        round index would run to 9 and past the last band.
        """
        self._check([at(2, 0) - 1, at(2, 0), at(4, 0), at(6, 0),
                     ROUND["LAST_ROUND_BATTLECOUNT"] + 6])

    def test_gambler_fields_its_forced_sets(self):
        """Gambler's Paradise: every gambler mon carries one of ITS forced sets.

        Party roster Phase 6 (2026-10-07) moved the sets out of a private table
        (GamblerMonMovesets / OverrideGamblerMoves) into the curated corpus as
        TIER_GAMBLER records, and the gambler onto the grid with its own row:
        RogueRosterMixId returns MIX_GAMBLER, whose six set units cover every
        slot. The sets are keyed on the species FIELDED, so an evolved pool
        entry (Dragonair at 55+, Onix at 38+) must find its evolution's row.

        This is the plan's "the fallback never fires" check: a slot that found
        no TIER_GAMBLER record would take MIX_GAMBLER's MSRC_RANDOM_TM fallback
        and miss every row of the table. Two rounds, so both stages of an
        evolving entry get a chance to appear; the Sets table is read from the
        doc, the same source tools/gen_movesets.py builds the corpus from.
        """
        import sys
        sys.path.insert(0, str(REPO_ROOT / "tools"))
        import gen_party_roster
        species_ids = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
        move_ids = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        sets = {}
        for species, moves in gen_party_roster.load_gambler_sets():
            sets.setdefault(species_ids[species], []).append(
                sorted(move_ids[m] for m in moves))
        self._boot()
        h = self.harness
        assert h is not None
        mix = _constants()["MIX_GAMBLER"]
        fielded = 0
        for battle_count in (at(4, 1), at(8, 3)):
            with self.subTest(battle_count=battle_count):
                self.seen.clear()
                h.write8("wBattleCount", battle_count)
                h.write8("wTrainerClass", self.classes["GAMBLER"])
                h.write8("wTrainerNo", 1)
                h.call_routine("ReadTrainer", limit=60000)
                self.assertEqual(self.seen, [mix], "a gambler must take MIX_GAMBLER")
                count = h.read8("wEnemyPartyCount")
                self.assertGreater(count, 0)
                for slot in range(count):
                    species = h.read8("wEnemyPartySpecies", offset=slot)
                    # PARTYMON_STRUCT_LENGTH 0x2C, MON_MOVES at offset 8
                    moves = sorted(h.read8("wEnemyMons", offset=slot * 0x2C + 8 + i)
                                   for i in range(4))
                    self.assertIn(species, sets, f"slot {slot}: species {species} has no gambler set")
                    self.assertIn(moves, sets[species],
                                  f"slot {slot}: species {species} fielded {moves}, not a gambler set")
                    fielded += 1
        self.assertGreater(fielded, 2)

    def test_mini_boss_takes_the_gym_leader_row_for_its_round(self):
        """"Mini-boss / rival matches the gym leader of the same round."

        Since party roster Phase 4 (2026-10-07) a mini-boss builds from its own
        party spec (miniboss_records, party_specs.asm), so the row is that
        record's mix byte and the mix-only hook must NOT fire. The record is
        picked by the ROUND (PartyGenSpecIndex), never by wTrainerNo: the
        stage hands Giovanni a set of 1-3 and Victory Road hands the rival 1,
        so set 2 here must still land on the round's record.
        """
        self._boot()
        h = self.harness
        assert h is not None
        const = _constants()
        rom = h.rom_path.read_bytes()
        # wBattleCount / ROUND_BATTLES is the 0-based round, fought on the way
        # to that gym, so it takes that gym's band: one cell per band, plus
        # the clamp past gym 8 (round 9, Victory Road).
        for battle_count, expected in ((5, "MIX_GYM_EARLY"),
                                       (25, "MIX_GYM_MID"),
                                       (45, "MIX_GYM_LATE"),
                                       (65, "MIX_ELITE"),
                                       (85, "MIX_ELITE")):
            tier = min(battle_count, ROUND["LAST_ROUND_BATTLECOUNT"]) // ROUND["ROUND_BATTLES"] + 1
            with self.subTest(battle_count=battle_count):
                self.seen.clear()
                h.write8("wBattleCount", battle_count)
                h.write8("wTrainerClass", self.classes["GIOVANNI_MINIBOSS"])
                h.write8("wTrainerNo", 2)
                h.call_routine("ReadTrainer", limit=60000)
                self.assertEqual(self.seen, [], "a spec'd mini-boss should not take the mix-only path")
                pointer = h.read8("wPartyGenSpecPtr") | (h.read8("wPartyGenSpecPtr", offset=1) << 8)
                bank, record = h.symbols.get(f"GiovanniMiniBossSpec{tier}")
                self.assertEqual(pointer, record, f"wBattleCount {battle_count} should build round {tier}'s record")
                mix = rom[bank * 0x4000 + record - 0x4000 + 4]  # party_spec byte 4 = mix id
                self.assertEqual(
                    mix, const[expected],
                    f"a mini-boss at wBattleCount {battle_count} should use "
                    f"{expected}, the gym leader row for that round",
                )

    def test_a_late_roster_mon_does_not_keep_its_vanilla_moveset(self):
        """The end-to-end claim, not just the row selection.

        A route trainer in the last band draws under MIX_ROUTE_FINAL, which
        rolls MSRC_RANDOM_TM and MSRC_RANDOM on three slots - so at least one
        mon must differ from what AddPartyMon's WriteMonMoves alone produced.
        Compared against the same build at wBattleCount 0, whose row is pure
        MSRC_LEARNSET and therefore IS the vanilla result.

        Sampled, not proved: a rank-weighted draw can legitimately reproduce
        the level-up four. Several mons over several builds cannot all do so.
        """
        self._boot()
        vanilla = []
        mixed = []
        for _ in range(3):
            self._selected_mix(0)
            vanilla.append(self._party_moves())
        for _ in range(3):
            self._selected_mix(63)
            mixed.append(self._party_moves())
        self.assertNotEqual(
            vanilla, mixed,
            "a round-7 route trainer produced exactly the same movesets as a "
            "round-1 one; the mix is being selected but not applied",
        )

    def _party_moves(self):
        h = self.harness
        assert h is not None
        count = h.read8("wEnemyPartyCount")
        return [
            (h.read8("wEnemyMon1", offset=slot * 44),
             tuple(h.read_bytes("wEnemyMon1Moves", 4, offset=slot * 44)))
            for slot in range(min(count, PARTY_LENGTH))
        ]
