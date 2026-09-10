"""Runtime checks for the Phase 2 party spec system (RogueBuildParty).

A clean link proves nothing here: this is ~800 lines of new hand-written
assembly full of hl/bc juggling across farcalls, in a project whose most
repeated bug class is exactly that. These tests drive the real routine in the
real ROM and read the resulting enemy party out of WRAM.

The specs under test are in data/trainers/party_specs.asm:

  FALKNER wTrainerNo 1  a `dw 0` hole - no spec, so the Phase 1 authored
                        placeholder team still serves this round
          wTrainerNo 2  3 mons, base level 13 step +1, POOL_FALKNER,
                        MIX_GYM_EARLY, NO_DUPES | ACE_LAST, and a slot 2
                        override pinning PIDGEOT at level 17 with four
                        explicit moves
          wTrainerNo 3  the same pool and mix with ALLOW_UBER and no overrides

⚠ HARNESS LIMIT, MEASURED, NOT GUESSED. `call_routine("ReadTrainer")` cannot be
invoked more than roughly ten times per boot: somewhere between build 10 and
build 40 the machine corrupts - SP ends up in echo RAM and WRAM fills with the
$39/$00 pair Bankswitch pushes. It is NOT caused by this feature. The control
experiment is BROCK, which has no party spec at all and therefore runs the
original authored path: it dies at build 16 just the same. So the loops below
are capped at 8 builds, and anything needing more statistical power than that is
asserted deterministically instead - see test_uber_filter_reads_the_spec_flag,
which drives the filter predicate directly rather than sampling draws.
"""
from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_smoke import HarnessTestCase, REPO_ROOT

# Keep well under the harness's repeated-invocation ceiling described above.
MAX_BUILDS = 8

# FalknerPool's Kanto run, in data/trainers/pools.asm order. Only this run is
# eligible on a fresh save: RogueGetActiveGroupMask enables Johto only after a
# champion win, so the Johto entries must be unreachable here.
FALKNER_KANTO_RUN = [
    "PIDGEY", "PIDGEOTTO", "PIDGEOT", "SPEAROW", "FEAROW", "DODUO", "DODRIO",
    "ZUBAT", "GOLBAT", "FARFETCHD", "AERODACTYL", "ARTICUNO", "MEWTWO",
]
FALKNER_JOHTO_RUN = [
    "HOOTHOOT", "NOCTOWL", "CROBAT", "MURKROW", "SKARMORY", "YANMA", "GLIGAR",
]
ACE_MOVES = ["WING_ATTACK", "SAND_ATTACK", "QUICK_ATTACK", "AGILITY"]


class PartySpecSmokeTest(HarnessTestCase):
    def _build(self, trainer_no):
        """Run ReadTrainer for FALKNER at this wTrainerNo; return (count, species)."""
        h = self.harness
        assert h is not None
        classes = parse_trainer_class_indexes(
            REPO_ROOT / "constants/trainer_constants.asm"
        )
        h.write8("wTrainerClass", classes["FALKNER"])
        h.write8("wTrainerNo", trainer_no)
        h.call_routine("ReadTrainer", limit=4000)
        count = h.read8("wEnemyPartyCount")
        return count, h.read_bytes("wEnemyPartySpecies", count + 1)

    def _build_many(self, n=MAX_BUILDS, trainer_no=2):
        """Build the same spec n times after ONE boot.

        Each ReadTrainer call advances the RNG on its own, so repeated builds
        sample different draws. See the harness-limit note at module level for
        why n is small.
        """
        assert n <= MAX_BUILDS, "see the harness-limit note at module level"
        return [self._build(trainer_no) for _ in range(n)]

    def test_spec_and_authored_team_coexist_on_one_class(self):
        """A `dw 0` hole keeps the authored path for that round only.

        This is the migration property: without it, converting one round of a
        class to a spec would force converting all 24 at once.
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        species = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")

        # wTrainerNo 1: the hole. Must still be the Phase 1 authored placeholder.
        count, party = self._build(1)
        self.assertEqual(count, 3)
        self.assertEqual(
            party,
            [species[s] for s in ("PIDGEOTTO", "HOOTHOOT", "NOCTOWL")] + [0xFF],
        )

        # wTrainerNo 2: the spec. Three mons, and the ace is the pinned PIDGEOT.
        count, party = self._build(2)
        self.assertEqual(count, 3)
        self.assertEqual(party[2], species["PIDGEOT"])
        self.assertEqual(party[3], 0xFF)

    def test_pool_rolls_stay_inside_the_active_group_run(self):
        """Slots without an override roll only from the pool's Kanto run.

        The three-run layout is indexed by "total the ACTIVE runs, roll inside
        that total, then walk the runs advancing the list offset past inactive
        ones too". Conflating those two would return a Johto species on a fresh
        save, where Johto is locked until a champion win.
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        species = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
        kanto = {species[s] for s in FALKNER_KANTO_RUN}
        johto = {species[s] for s in FALKNER_JOHTO_RUN}

        seen = set()
        for build, (count, party) in enumerate(self._build_many()):
            self.assertEqual(count, 3)
            for slot in (0, 1):
                self.assertIn(
                    party[slot], kanto,
                    f"build {build} slot {slot} rolled {party[slot]}, which is "
                    "not in the pool's Kanto run",
                )
                self.assertNotIn(party[slot], johto)
                seen.add(party[slot])

        # A stuck roller that always returned entry 0 would satisfy every
        # assertion above, so require the draw to actually move around.
        self.assertGreater(
            len(seen), 2,
            f"only {len(seen)} distinct species across {MAX_BUILDS} builds; the "
            "pool draw looks stuck rather than random",
        )

    def test_no_dupes_flag_is_honoured(self):
        """NO_DUPES must also see species PINNED by a not-yet-built slot.

        Slots build in order, so when slots 0 and 1 roll, the party is still
        empty and the pinned PIDGEOT ace does not exist yet. A dupe check that
        only looked at wEnemyPartySpecies would let slot 0 roll PIDGEOT and
        produce a team with two of them - which is exactly what this test caught
        on its first run.
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        for build, (count, party) in enumerate(self._build_many()):
            rolled = party[:count]
            self.assertEqual(
                len(set(rolled)), len(rolled),
                f"build {build} produced {rolled}, a duplicate species despite "
                "BIT_PSPEC_NO_DUPES",
            )

    def test_explicit_slot_moves_are_written_with_correct_pp(self):
        """The ace's four moves come from the override, each with real PP.

        PP matters as much as the move ids: WriteMonMoves already set PP for the
        moves IT chose, so an override that rewrites the moves and not the PP
        leaves a mon holding Agility on Wing Attack's PP - or 0 PP in a slot the
        vanilla walk had left empty.
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        moves = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        self._build(2)

        # The ace is slot 2. The struct stride comes from the built symbol table
        # rather than a hardcoded 44, so it cannot rot if the party struct ever
        # changes width.
        stride = h.address("wEnemyMon2") - h.address("wEnemyMon1")
        self.assertEqual(
            h.read_bytes("wEnemyMon1Moves", 4, offset=2 * stride),
            [moves[m] for m in ACE_MOVES],
        )
        for move, pp in zip(ACE_MOVES, h.read_bytes("wEnemyMon1PP", 4, offset=2 * stride)):
            with self.subTest(move=move):
                self.assertGreater(
                    pp, 0,
                    f"{move} was written with 0 PP; the override rewrote the "
                    "move ids without rewriting PP",
                )

    def test_uber_filter_reads_the_spec_flag(self):
        """BIT_PSPEC_ALLOW_UBER, tested deterministically and in both directions.

        Sampling draws cannot test this within the harness's ~10-invocation
        ceiling: MEWTWO is 1 of 13 eligible pool entries, so 8 builds would flake
        outright. So the filter predicate is driven directly instead -
        PartyGenPoolCandidateOk reads wCurPartySpecies plus the spec at
        wPartyGenSpecPtr and answers in the carry flag.

        The verdict is observed by hooking the routine's own .accept and .reject
        labels rather than by reading the carry flag afterwards. That is not a
        stylistic choice: call_routine's return trampoline RESTORES every saved
        register including F (harness.py, `for name, value in
        saved_registers.items()`), so a callee's flags are discarded by design
        and a post-call carry read silently reports the CALLER's flags. A first
        attempt did exactly that and reported "rejected" for all three cases.

        Three cases, which together pin the behaviour down:
          MEWTWO  + FalknerSpec2 (no flag)   -> rejected
          MEWTWO  + FalknerSpec3 (flag set)  -> accepted
          ARTICUNO+ FalknerSpec2 (no flag)   -> accepted, because it is
                    KantoUltraball, NOT KantoUber. Measured in
                    engine/pokemon/rarity.asm: RARITY_TIER_UBER in this tree is
                    exactly {MEW, MEWTWO}, so the legendary BIRDS are not
                    covered. That is why the flag is not called ALLOW_LEGEND -
                    see its note in constants/party_spec_constants.asm - and
                    this case fails if anyone later widens it to match the
                    friendlier name.

        A filter that always rejected and one that always accepted each satisfy
        some of these, so all three are needed.
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        species = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")

        verdict = []
        h.register_hook("PartyGenPoolCandidateOk.accept",
                        lambda ctx: verdict.append(True))
        h.register_hook("PartyGenPoolCandidateOk.reject",
                        lambda ctx: verdict.append(False))

        for spec_label, mon, expected in (
            ("FalknerSpec2", "MEWTWO", False),
            ("FalknerSpec3", "MEWTWO", True),
            ("FalknerSpec2", "ARTICUNO", True),
        ):
            with self.subTest(spec=spec_label, mon=mon):
                verdict.clear()
                spec_addr = h.address(spec_label)
                h.write8("wPartyGenSpecPtr", spec_addr & 0xFF)
                h.write8("wPartyGenSpecPtr", spec_addr >> 8, offset=1)
                # Slot 0, so PartyGenFindOverrideForSlot finds nothing on either
                # spec and only the flag-driven filters run.
                h.write8("wPartyGenSlot", 0)
                h.write8("wEnemyPartyCount", 0)
                h.write8("wCurPartySpecies", species[mon])
                h.call_routine("PartyGenPoolCandidateOk", limit=600)
                self.assertEqual(
                    len(verdict), 1,
                    f"expected exactly one verdict, got {verdict}",
                )
                self.assertEqual(
                    verdict[0], expected,
                    f"{mon} with {spec_label} was "
                    f"{'accepted' if verdict[0] else 'rejected'}; expected "
                    f"{'accepted' if expected else 'rejected'}",
                )
