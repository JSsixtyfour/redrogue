"""The balance model's moveset mirror (tools/balance/movesets.py) agrees with the ROM.

STATIC. The tables movesets.py parsed from source are the bytes in all three
built ROMs: MovesetMixTable (every column), MoveRankWeightTable, MoveRankByID
and MoveFlagsByID.

RUNTIME. ReadTrainer builds real parties; every enemy mon's four moves and its
wEnemyMoveOrigins byte are then explained by the mirror. The origin byte says
which path wrote the moves, exactly:

  0  vanilla WriteMonMoves  -> the moves equal movesets.vanilla_moves
  1  a generated roll       -> movesets.could_generate accepts them for some
                               generated source the mix row can deal
  2+ a curated set          -> one of movesets.set_records' passing records
                               (exact window or the widened one) with that
                               origin id carries exactly these moves

plus the rules that do not depend on the dice: no more set slots than the
row's set quota, and an ACE_LAST ace takes a set exactly when the mirror says
a record passes for it (and never on VERY EASY).

Expectations come from movesets.py's own functions, never re-derived here.
HARNESS LIMIT: at most MAX_CALLS ReadTrainer calls per boot.
"""
from __future__ import annotations

import io
import sys
import unittest

from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_party_spec_coverage import Image, ROMS
from test_smoke import HarnessTestCase, REPO_ROOT

sys.path.insert(0, str(REPO_ROOT / "tools" / "balance"))
import model  # noqa: E402
import movesets  # noqa: E402
import parse  # noqa: E402

MAX_CALLS = 8
HARNESS_ROM = "pokeblue_debug"
NUM_ROUND_VARIANTS = 3
FORM_MASK = 0x60      # MON_CATCH_RATE bits 5-6
ROUND = parse.load_round_constants()
R = ROUND["ROUND_BATTLES"]


class MovesetTablesMatchRomTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.d = movesets.load()
        cls.images = [Image(name) for name in ROMS]

    def test_mix_table(self):
        for image in self.images:
            base = image.offset("MovesetMixTable")
            for i, row in enumerate(self.d.mixes):
                with self.subTest(rom=image.name, row=row.name):
                    self.assertEqual(
                        list(image.rom[base + i * 14:base + (i + 1) * 14]),
                        [*row.quotas, row.tier_mask, row.rank_row, row.tm_cap,
                         row.require & 0xFF, row.require >> 8, row.forbid & 0xFF, row.forbid >> 8,
                         row.fallback])

    def test_rank_weights(self):
        for image in self.images:
            base = image.offset("MoveRankWeightTable")
            flat = [w for row in self.d.weights for w in row]
            with self.subTest(rom=image.name):
                self.assertEqual(list(image.rom[base:base + len(flat)]), flat)

    def test_difficulty_moveset_mods(self):
        """DifficultyMovesetMods rows, in stored DIFFICULTY_* order (model.DIFFICULTIES)."""
        for image in self.images:
            base = image.offset("DifficultyMovesetMods")
            for i, name in enumerate(model.DIFFICULTIES):
                with self.subTest(rom=image.name, difficulty=name):
                    self.assertEqual(list(image.rom[base + 4 * i:base + 4 * i + 4]),
                                     [v & 0xFF for v in self.d.diff_mods[name]])

    def test_tm_gate_table(self):
        for image in self.images:
            base = image.offset("TMGateLevelByRank")
            with self.subTest(rom=image.name):
                self.assertEqual(list(image.rom[base:base + len(self.d.tm_gate)]), self.d.tm_gate)

    def test_move_ranks_and_flags(self):
        ranks = list(self.d.rank.values())        # file order is move id order
        flags = list(self.d.flags.values())
        for image in self.images:
            with self.subTest(rom=image.name, table="MoveRankByID"):
                base = image.offset("MoveRankByID")
                self.assertEqual(list(image.rom[base:base + len(ranks)]), ranks)
            with self.subTest(rom=image.name, table="MoveFlagsByID"):
                base = image.offset("MoveFlagsByID")
                raw = image.rom[base:base + 2 * len(flags)]
                self.assertEqual([raw[2 * i] | raw[2 * i + 1] << 8 for i in range(len(flags))], flags)


class MovesetMirrorMatchesRomSmokeTest(HarnessTestCase):
    @classmethod
    def setUpClass(cls):
        cls.g = parse.load_all()
        cls.d = movesets.load()
        cls.classes = parse_trainer_class_indexes(REPO_ROOT / "constants/trainer_constants.asm")
        cls.ram = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")
        moves = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        cls.move_name = {v: k for k, v in moves.items() if k.isupper() and not k.startswith("NUM_")}
        cls.move_name[0] = "NO_MOVE"
        cls.species_of = {}
        for name, sp in cls.g.species.items():
            cls.species_of.setdefault((sp.internal_id, sp.form), name)

    def setUp(self) -> None:
        super().setUp()
        self.calls = 0

    def _boot(self) -> None:
        self.harness.boot_fight2(seed=1)

    def _build(self, trainer_class: str, trainer_no: int, count: int, difficulty: str = "hard"):
        """ReadTrainer; returns [(model species, level, moves, origin)] per slot."""
        h = self.harness
        self.calls += 1
        self.assertLessEqual(self.calls, MAX_CALLS, "past the harness's per-boot call ceiling")
        mask = self.ram["DIFFICULTY_MASK"]
        h.write8("wOptions2", (h.read8("wOptions2") & ~mask & 0xFF) | model.DIFFICULTIES.index(difficulty))
        h.write8("wRogueFlagsBitfield",
                 h.read8("wRogueFlagsBitfield") & ~(1 << self.ram["BIT_WITCH_ACCEPTED"]) & 0xFF)
        h.write8("wLinkState", 0)
        h.write8("wBattleCount", count)
        h.write8("wTrainerClass", self.classes[trainer_class])
        h.write8("wTrainerNo", trainer_no)
        h.call_routine("ReadTrainer", limit=60000)
        stride = h.address("wEnemyMon2") - h.address("wEnemyMon1")
        out = []
        for slot in range(h.read8("wEnemyPartyCount")):
            sid = h.read8("wEnemyMon1", offset=slot * stride)
            form = (h.read8("wEnemyMon1CatchRate", offset=slot * stride) & FORM_MASK) >> 5
            name = self.species_of.get((sid, form)) or self.species_of[(sid, 0)]
            moves = [self.move_name[m] for m in h.read_bytes("wEnemyMon1Moves", 4, offset=slot * stride) if m]
            out.append((name, h.read8("wEnemyMon1Level", offset=slot * stride), moves,
                        h.read8("wEnemyMoveOrigins", offset=slot)))
        return out

    def _check(self, mix_id: int, party, ace_last: bool, difficulty: str = "hard") -> None:
        d = self.d
        mix = d.mixes[mix_id]
        rolled, gate_shift = movesets.for_difficulty(d, mix, difficulty)
        set_pct = d.diff_mods[difficulty][0]
        generated = [s for s in range(len(mix.quotas)) if (mix.quotas[s] or s == mix.fallback)
                     and s not in (movesets.MSRC["LEARNSET"], movesets.MSRC["SET"])]
        if mix.quotas[movesets.MSRC["SET"]] and mix.fallback not in generated:
            generated.append(mix.fallback)
        sets = 0
        for slot, (name, level, moves, origin) in enumerate(party):
            sp = self.g.species[name]
            key = (sp.base_species, sp.form)
            mon = d.mons[key]
            where = f"slot {slot} {name} L{level} {moves} origin {origin} (mix {mix.name})"
            passing = (movesets.set_records(d, key, level, mix.tier_mask, 0)
                       or movesets.set_records(d, key, level, mix.tier_mask, d.slack))
            if origin >= 2:
                sets += 1
                self.assertTrue(any([m for m in r.moves if m != "NO_MOVE"] == moves and r.origin == origin
                                    for r in passing), f"no passing set record explains {where}")
            elif origin == 1:
                self.assertTrue(any(movesets.could_generate(d, rolled, mon, level, s, moves, gate_shift)
                                    for s in generated),
                                f"no generated source of the row explains {where}")
            else:
                self.assertEqual(moves, movesets.vanilla_moves(mon, level), f"vanilla moves: {where}")
            # The ace's set is certain only at a 100% set chance, impossible at 0%
            # or with no passing record; in between either outcome is legal.
            if ace_last and slot == len(party) - 1 and mix.quotas[movesets.MSRC["SET"]]:
                if not passing or set_pct == 0:
                    self.assertLess(origin, 2, f"ace took a set the mirror rules out: {where}")
                elif set_pct == 100:
                    self.assertGreaterEqual(origin, 2, f"ace skipped a set it must take: {where}")
        self.assertLessEqual(sets, mix.quotas[movesets.MSRC["SET"]], "more set slots than the set quota")
        if set_pct == 0:
            self.assertEqual(sets, 0, f"{difficulty} (0% set chance) fielded a curated set")

    def _select(self, species: str, level: int, mask: int) -> list[str] | None:
        """PartyGenApplySetMovesetMask on one hand-written mon; None = no match."""
        h = self.harness
        self.calls += 1
        self.assertLessEqual(self.calls, MAX_CALLS, "past the harness's per-boot call ceiling")
        h.park_before_hijack()
        h.write8("wEnemyPartyCount", 1)
        h.write8("wPartyGenSlot", 0)
        h.write8("wEnemyMon1", self.g.species[species].internal_id)
        h.write8("wEnemyMon1CatchRate", 0)
        h.write8("wCurEnemyLevel", level)
        for i in range(4):
            h.write8("wEnemyMon1Moves", 0xEE, offset=i)
        verdict = []
        h.register_hook("PartyGenApplySetMovesetMask.noMatch", lambda ctx: verdict.append("none"))
        h.pyboy.register_file.E = mask
        h.call_routine("PartyGenApplySetMovesetMask", limit=4000)
        if verdict:
            return None
        return [self.move_name[m] for m in h.read_bytes("wEnemyMon1Moves", 4) if m]

    def _set_cases(self):
        """(label, species, level, mask) for each branch of the set filter, found
        in the data rather than named, so they survive a catalog edit."""
        d = self.d
        hard, normal = d.consts["TIER_HARD"], d.consts["TIER_NORMAL"]
        cases = {}
        for (sp, form), recs in sorted(d.sets.items()):
            if form or sp not in self.g.species:
                continue
            for r in recs:
                for mask in (normal, hard):
                    if not r.tier & mask or r.hi + 3 > 100:
                        continue
                    lv = r.hi + 3
                    if "widened" not in cases and not movesets.set_records(d, (sp, 0), lv, mask, 0) \
                            and movesets.set_records(d, (sp, 0), lv, mask, d.slack):
                        cases["widened"] = (sp, lv, mask)
                    if "exact" not in cases and movesets.set_records(d, (sp, 0), r.lo, mask, 0):
                        cases["exact"] = (sp, r.lo, mask)
                bad = d.consts["TIER_BAD"]
                if "masked out" not in cases and not movesets.set_records(d, (sp, 0), r.lo, bad, d.slack):
                    cases["masked out"] = (sp, r.lo, bad)
        self.assertEqual(sorted(cases), ["exact", "masked out", "widened"], "the data lost a filter branch")
        return cases

    def test_set_filter_branches(self):
        """Exact window, the widened window and a mask that excludes every record."""
        self._boot()
        for label, (species, level, mask) in self._set_cases().items():
            with self.subTest(case=label, species=species, level=level, mask=mask):
                key = (species, 0)
                want = (movesets.set_records(self.d, key, level, mask, 0)
                        or movesets.set_records(self.d, key, level, mask, self.d.slack))
                got = self._select(species, level, mask)
                if not want:
                    self.assertIsNone(got, "the ROM found a set the mirror rules out")
                else:
                    self.assertIn(got, [[m for m in r.moves if m != "NO_MOVE"] for r in want])

    def _probe(self, label: str, at: str, registers: dict[str, int]) -> int:
        """Run `label` from a direct jump with `registers` set and return `a` the
        moment execution reaches `at`, then restore the machine (test_ai_fairplay's
        call_a_preserving pattern: call_routine's trampoline destroys a and e)."""
        h = self.harness
        h.park_before_hijack()
        baseline = io.BytesIO()
        h.save_state(baseline)
        bank, address = h.symbols.get(label)
        at_bank, at_address = h.symbols.get(at)
        result: dict[str, int] = {}
        h.pyboy.hook_register(at_bank, at_address, lambda _c: result.setdefault("a", h.pyboy.register_file.A), None)
        try:
            sp = (h.pyboy.register_file.SP - 2) & 0xFFFF
            h.pyboy.memory[sp], h.pyboy.memory[sp + 1] = 0xFF, 0x3F   # return sentinel $3FFF
            h.pyboy.register_file.SP = sp
            h.pyboy.memory[0x2000] = bank
            h.write8("hLoadedROMBank", bank)
            for name, value in registers.items():
                setattr(h.pyboy.register_file, name, value)
            h.pyboy.register_file.PC = address
            h.wait_until(lambda: "a" in result, at, limit=300)
        finally:
            h.pyboy.hook_deregister(at_bank, at_address)
            h.load_state(baseline)
        return result["a"]

    def test_difficulty_reaches_the_readers(self):
        """PartyGenRankWeight, PartyGenTMCapReached and PartyGenTMGated read the
        difficulty's row: the effective rank_row, tm_cap and gate equal
        movesets.for_difficulty's, for every difficulty, on ELITE and ROUTE_EARLY."""
        self._boot()
        h = self.harness
        moves = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        mask = self.ram["DIFFICULTY_MASK"]
        pseudo = h.address("MixOnlySpecs")
        for row in ("ELITE", "ROUTE_EARLY"):
            mix_id = self.d.mix_id[row]
            for difficulty in model.DIFFICULTIES:
                with self.subTest(row=row, difficulty=difficulty):
                    want, shift = movesets.for_difficulty(self.d, self.d.mixes[mix_id], difficulty)
                    h.write8("wOptions2", (h.read8("wOptions2") & ~mask & 0xFF)
                             | model.DIFFICULTIES.index(difficulty))
                    ptr = pseudo + mix_id * self.d.consts["MIX_ONLY_SPEC_SIZE"]
                    h.write8("wPartyGenSpecPtr", ptr & 0xFF)
                    h.write8("wPartyGenSpecPtr", ptr >> 8, offset=1)
                    self.assertEqual(self._probe("PartyGenRankWeight", "PartyGenRankWeight.rowShifted",
                                                 {"A": 5}), want.rank_row, "effective rank_row")
                    self.assertEqual(self._probe("PartyGenTMCapReached", "PartyGenTMCapReached.capShifted",
                                                 {}), want.tm_cap, "effective tm_cap")
                    self.assertEqual(self._probe("PartyGenTMGated", "PartyGenTMGated.noOverflow",
                                                 {"E": moves["BLIZZARD"]}),
                                     self.d.tm_gate[self.d.rank["BLIZZARD"]] + shift, "effective S gate")

    def _mix(self, kind: str, count: int, spec_round: int = 0) -> int:
        return movesets.mix_for(self.d, self.g, model.Battle(kind, count, [], True, spec_round=spec_round))

    def test_leaders_every_round(self):
        """Brock, rounds 1-8: GYM_EARLY through ELITE, ace on the strongest source.
        VERY HARD (the table as written, 100% set chance) so the ace rule is exact."""
        self._boot()
        for rnd in range(1, 9):
            with self.subTest(round=rnd):
                party = self._build("BROCK", (rnd - 1) * NUM_ROUND_VARIANTS + 2, rnd * R, "very_hard")
                self._check(self._mix("leader", rnd * R, rnd), party, ace_last=True, difficulty="very_hard")

    def test_elite_four(self):
        """Lorelei and Agatha (MIX_E4_SETS: every slot a set, fallback random+TM)."""
        self._boot()
        for member in ("LORELEI", "AGATHA"):
            for tier in (1, 2, 3, 4):
                count = ROUND["E4_FIRST_BATTLECOUNT"] - 1 + tier
                with self.subTest(member=member, tier=tier):
                    party = self._build(member, (tier - 1) * NUM_ROUND_VARIANTS + 1, count, "very_hard")
                    self._check(self._mix("e4", count, tier), party, ace_last=True, difficulty="very_hard")

    def test_rosters_every_band(self):
        """Route and trainer rows in all four bands, and the Victory Road clamp."""
        self._boot()
        fr, g1, fg = ROUND["FINAL_ROUTE_STEP"], ROUND["FIRST_GYM_STEP"], ROUND["FINAL_GYM_TRAINER_STEP"]
        for count in (1, 2 * R + 1, 2 * R + g1, 4 * R + 2, 4 * R + fg, 7 * R + 1, 7 * R + fr,
                      ROUND["LAST_ROUND_BATTLECOUNT"]):
            with self.subTest(wBattleCount=count):
                party = self._build("YOUNGSTER", 1, count)
                self._check(self._mix("route", count), party, ace_last=False)

    def test_mini_bosses_and_very_easy(self):
        """GIOVANNI_MINIBOSS (gym row of its round) on NORMAL (move preference -1,
        tm_cap -1, gate +3), then VERY EASY on gym 8 and the E4."""
        self._boot()
        for count in (5, 35, 65, 85):
            with self.subTest(wBattleCount=count):
                party = self._build("GIOVANNI_MINIBOSS", 2, count, "normal")
                tier = model.round_of(self.g, count) + 1
                self._check(self._mix("miniboss", count, tier), party, ace_last=True, difficulty="normal")
        for trainer, no, count, kind, spec_round in (
                ("BROCK", 23, 8 * R, "leader", 8), ("LORELEI", 10, ROUND["E4_FIRST_BATTLECOUNT"] + 3, "e4", 4)):
            with self.subTest(very_easy=trainer):
                party = self._build(trainer, no, count, "very_easy")
                self._check(self._mix(kind, count, spec_round), party, ace_last=True, difficulty="very_easy")


if __name__ == "__main__":
    unittest.main()
