"""Balance Phase 3: the offline model (tools/balance/) agrees with the ROM.

The model predicts levels and money for a whole run from numbers parse.py reads
out of the source. Its predictions are only worth anything where the ROM does
the same arithmetic on the same numbers, so this file checks both halves:

STATIC. The tables the model parsed from .asm are the bytes the built ROMs
actually contain: trainer/mini-boss level blocks, the wild and boss level
tables, every class's prize-money row, the Amulet Coin percentages, and the
level header of every gym-leader and Elite Four spec record. A parse.py regex
that read the wrong column, or a table that moved away from the INCLUDE the
model assumes, fails here without booting anything.

RUNTIME. The routines that consume those tables produce what the model's own
functions produce: ReadTrainer (roster, leader, Elite Four and mini-boss paths)
for party size, every level and wAmountMoneyWon; GetRewardMonLevel,
PCGetWildLevel and PCGetBossLevel for their level. Expectations come from
calling model.py, never from re-deriving the formula here, so a wrong model is
what fails - a test that re-implemented the model would only prove itself.

Random rolls are handled by sampling the MODEL, not by trusting its ranges:
the set of levels model.roster_battle can produce over many seeds is the band,
and every level the ROM rolls must fall inside it.

HARNESS LIMIT: call_routine corrupts the machine after roughly ten invocations
per boot (project_call_routine_harness_limits), so every runtime test boots
once and stays at or under MAX_CALLS.
"""
from __future__ import annotations

import random
import re
import sys
import unittest

from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_party_spec_coverage import Image, ROMS
from test_smoke import HarnessTestCase, REPO_ROOT

sys.path.insert(0, str(REPO_ROOT / "tools" / "balance"))
import model  # noqa: E402
import parse  # noqa: E402

MAX_CALLS = 8
HARNESS_ROM = "pokeblue_debug"
NUM_ROUND_VARIANTS = 3
MODEL_SAMPLES = 300

# Falkner's round-1 B and C records are the Phase 2 worked examples, written by
# hand and pinned by test_party_specs.py. They do NOT follow GYM_R1_*: 3 mons,
# L13 step 1, where every other leader's round 1 is GYM_R1_MONS/BASE/STEP. The
# model uses the curve for every leader, so it is wrong for exactly these two
# teams. Falkner is Johto-only, so a Kanto run never meets them.
HAND_WRITTEN_SPECS = {("Falkner", 2), ("Falkner", 3)}


def _g() -> parse.GameData:
    return parse.load_all()


def _bcd(raw: list[int] | bytes) -> int:
    return int("".join(f"{b:02x}" for b in raw))


def _money_row(image: Image, classes: dict[str, int], name: str) -> bytes:
    """TrainerPicAndMoneyPointers row for a class: dw pic, db bank, bcd3 money."""
    off = image.offset("TrainerPicAndMoneyPointers") + (classes[name] - 1) * 6
    return bytes(image.rom[off + 3:off + 6])


def _map_ids() -> dict[str, int]:
    """map_const is a sequential const from const_def 0; source_constants does
    not know the macro, so count it here."""
    ids: dict[str, int] = {}
    for raw in (REPO_ROOT / "constants/map_constants.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*map_const\s+([A-Z0-9_]+)\s*,", raw)
        if m:
            ids[m.group(1)] = len(ids)
    return ids


def _classes() -> dict[str, int]:
    return parse_trainer_class_indexes(REPO_ROOT / "constants/trainer_constants.asm")


# =============================================================================
# Static: the model's parsed numbers are the ROM's bytes
# =============================================================================

class BalanceTablesMatchRomTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.g = _g()
        cls.images = [Image(name) for name in ROMS]
        cls.classes = _classes()

    def test_trainer_level_blocks(self):
        for image in self.images:
            for label, blocks in (("trainer_difficulty_settings", self.g.tables.route),
                                  ("trainer_difficulty_settings_gym", self.g.tables.gym)):
                base = image.offset(label)
                for i, b in enumerate(blocks):
                    with self.subTest(rom=image.name, table=label, round=i + 1):
                        self.assertEqual(
                            list(image.rom[base + i * 11:base + (i + 1) * 11]),
                            [b.level_range, b.min_level, *b.counts, b.final_bonus, *b.final_counts],
                        )

    def test_miniboss_level_rows(self):
        for image in self.images:
            base = image.offset("trainer_difficulty_settings_miniboss")
            for i, row in enumerate(self.g.tables.miniboss):
                with self.subTest(rom=image.name, round=i + 1):
                    self.assertEqual(
                        list(image.rom[base + i * 4:base + (i + 1) * 4]),
                        [row.level_range, row.min_level, row.base_class, row.rare_chance],
                    )

    def test_wild_and_boss_level_tables(self):
        for image in self.images:
            for label, table in (("PCWildLevelTable", self.g.tables.wild),
                                 ("PFacFakeWildLevelTable", self.g.tables.wild),
                                 ("PCBossLevelTable", self.g.tables.wild_boss)):
                base = image.offset(label)
                with self.subTest(rom=image.name, table=label):
                    self.assertEqual(list(image.rom[base:base + len(table)]), table)

    def test_every_money_row(self):
        """Every class the model prices, against TrainerPicAndMoneyPointers."""
        self.assertGreater(len(self.g.money), 40, "the model priced suspiciously few classes")
        for image in self.images:
            for name, amount in sorted(self.g.money.items()):
                with self.subTest(rom=image.name, trainer_class=name):
                    self.assertEqual(_bcd(_money_row(image, self.classes, name)), amount)

    def test_amulet_coin_percentages(self):
        for image in self.images:
            base = image.offset("ReadTrainer.AmuletCoinPctTable")
            with self.subTest(rom=image.name):
                self.assertEqual(tuple(image.rom[base:base + 3]), model.AMULET_COIN_PCT)

    def test_gym_leader_spec_headers(self):
        """n_mons, base level and step of every leader record, all 3 variants.

        The model builds every leader team from GYM_R<round>_*; the ROM builds
        it from whatever the record's header says. Header bytes 0-2."""
        k = self.g.knobs
        checked = 0
        for image in self.images:
            for leader in self.g.leaders:
                count, pointers = image.spec_list(leader.name)
                for t in range(1, count + 1):
                    if not pointers[t - 1] or (leader.name, t) in HAND_WRITTEN_SPECS:
                        continue
                    rnd = (t - 1) // NUM_ROUND_VARIANTS + 1
                    header, _ = image.record(f"{leader.name}Spec{t}")
                    with self.subTest(rom=image.name, leader=leader.name, wTrainerNo=t):
                        self.assertEqual(
                            header[:3],
                            (k[f"GYM_R{rnd}_MONS"], k[f"GYM_R{rnd}_BASE"], k[f"GYM_R{rnd}_STEP"]),
                        )
                    checked += 1
        self.assertGreater(checked, 3 * 17 * 20, "the record walk skipped most leaders")

    def test_hand_written_specs_are_still_the_only_exceptions(self):
        """If Falkner's round 1 is ever regenerated from the curve, drop the
        exemption above so the model's coverage claim widens with it."""
        k = self.g.knobs
        image = self.images[0]
        for name, t in sorted(HAND_WRITTEN_SPECS):
            header, _ = image.record(f"{name}Spec{t}")
            with self.subTest(spec=f"{name}Spec{t}"):
                self.assertNotEqual(header[:3], (k["GYM_R1_MONS"], k["GYM_R1_BASE"], k["GYM_R1_STEP"]))

    def test_elite_four_spec_headers(self):
        k = self.g.knobs
        for image in self.images:
            for member in self.g.e4:
                count, _ = image.spec_list(member.name)
                for t in range(1, count + 1):
                    tier = (t - 1) // NUM_ROUND_VARIANTS + 1
                    header, _ = image.record(f"{member.name}Spec{t}")
                    with self.subTest(rom=image.name, member=member.name, wTrainerNo=t):
                        self.assertEqual(
                            header[:3], (6, k["E4_BASE_LEVEL"] + tier, k["E4_LEVEL_STEP"]),
                        )


# =============================================================================
# Runtime: the ROM's routines produce what the model's functions produce
# =============================================================================

class BalanceModelMatchesRomSmokeTest(HarnessTestCase):
    @classmethod
    def setUpClass(cls):
        cls.g = _g()
        cls.classes = _classes()
        cls.image = Image(HARNESS_ROM)
        cls.ram = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")
        cls.maps = _map_ids()

    def setUp(self) -> None:
        super().setUp()
        self.calls = 0

    # --- machine setup -------------------------------------------------------

    def _boot(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)

    def _call(self, routine: str, limit: int = 12000) -> None:
        self.calls += 1
        self.assertLessEqual(self.calls, MAX_CALLS, "past the harness's per-boot call ceiling")
        self.harness.call_routine(routine, limit=limit)

    def _neutral_state(self, difficulty: str, battle_count: int) -> None:
        """Everything outside the model's scope switched off: no witch level
        bonus, no link battle, the requested difficulty, the requested count."""
        h = self.harness
        mask = self.ram["DIFFICULTY_MASK"]
        h.write8("wOptions2", (h.read8("wOptions2") & ~mask & 0xFF)
                 | model.DIFFICULTIES.index(difficulty))
        h.write8("wRogueFlagsBitfield",
                 h.read8("wRogueFlagsBitfield") & ~(1 << self.ram["BIT_WITCH_ACCEPTED"]) & 0xFF)
        h.write8("wLinkState", 0)
        h.write8("wBattleCount", battle_count)

    def _read_trainer(self, trainer_class: str, trainer_no: int, battle_count: int,
                      difficulty: str = "normal") -> tuple[list[int], int]:
        """Build one enemy party; return (levels, money won)."""
        h = self.harness
        self._neutral_state(difficulty, battle_count)
        h.write8("wTrainerClass", self.classes[trainer_class])
        h.write8("wTrainerNo", trainer_no)
        # GetTrainerInformation's job, done from the ROM row the static test
        # checks, so this stays one call_routine per battle.
        for i, byte in enumerate(_money_row(self.image, self.classes, trainer_class)):
            h.write8("wTrainerBaseMoney", byte, i)
        self._call("ReadTrainer", limit=60000)

        count = h.read8("wEnemyPartyCount")
        stride = h.address("wEnemyMon2") - h.address("wEnemyMon1")
        levels = [h.read8("wEnemyMon1Level", offset=slot * stride) for slot in range(count)]
        money = _bcd(h.read_bytes("wAmountMoneyWon", 3))
        return levels, money

    def _assert_money(self, battle: model.Battle, rom_levels: list[int], rom_money: int) -> None:
        """model.money_for over the ROM's own last level (the roll is random)."""
        priced = model.Battle(battle.kind, battle.count,
                              [("?", lv) for lv in rom_levels], True, battle.money_base)
        self.assertEqual(rom_money, model.money_for(self.g, priced, 0),
                         f"money: ROM paid {rom_money} for last level {rom_levels[-1]}")

    def _model_band(self, build) -> tuple[set[int], set[int]]:
        """(possible party sizes, possible levels) over MODEL_SAMPLES seeds."""
        sizes, levels = set(), set()
        for seed in range(MODEL_SAMPLES):
            b = build(random.Random(seed))
            sizes.add(len(b.mons))
            levels.update(lv for _, lv in b.mons)
        return sizes, levels

    # --- roster trainers (GetRandRoster) --------------------------------------

    def _check_rosters(self, counts: list[int]) -> None:
        self._boot()
        cfg = model.Config()
        for count in counts:
            with self.subTest(wBattleCount=count):
                sizes, band = self._model_band(
                    lambda rng: model.roster_battle(self.g, cfg, count, rng))
                levels, money = self._read_trainer("YOUNGSTER", 1, count)
                self.assertIn(len(levels), sizes, "party size")
                self.assertTrue(set(levels) <= band,
                                f"ROM levels {levels} outside model band {sorted(band)}")
                self._assert_money(model.roster_battle(self.g, cfg, count, random.Random(0)),
                                   levels, money)

    def test_early_rosters(self):
        """Route trainers, the final route trainer (5), a gym trainer, the final
        gym trainer (9), across rounds 1-3."""
        self._check_rosters([1, 5, 7, 9, 16, 29])

    def test_late_rosters(self):
        """Rounds 5-9, including the clamp at 89."""
        self._check_rosters([45, 55, 62, 79, 89, 95])

    # --- gym leaders and the Elite Four (RogueBuildParty) ---------------------

    def _check_spec(self, trainer_class: str, trainer_no: int, count: int, battle: model.Battle,
                    difficulty: str = "normal") -> None:
        levels, money = self._read_trainer(trainer_class, trainer_no, count, difficulty)
        self.assertEqual(levels, [lv for _, lv in battle.mons], "levels")
        self._assert_money(battle, levels, money)

    def test_leader_levels_every_round(self):
        """Brock, variant B (no pinned ace), rounds 1-8. Levels are
        deterministic on this path, so they are compared exactly."""
        self._boot()
        leader = next(l for l in self.g.leaders if l.name == "Brock")
        cfg = model.Config()
        for rnd in range(1, 9):
            with self.subTest(round=rnd):
                battle = model.leader_battle(self.g, cfg, leader, rnd, random.Random(1))
                self._check_spec("BROCK", (rnd - 1) * NUM_ROUND_VARIANTS + 2, 10 * rnd, battle)

    def test_difficulty_modes(self):
        """RogueApplyDifficulty's rounding, all five modes, on a round-6 team
        (L37-43) where 10% and 20% both truncate."""
        self._boot()
        leader = next(l for l in self.g.leaders if l.name == "Brock")
        for difficulty in model.DIFFICULTIES:
            with self.subTest(difficulty=difficulty):
                battle = model.leader_battle(self.g, model.Config(difficulty=difficulty), leader, 6,
                                             random.Random(1))
                self._check_spec("BROCK", 5 * NUM_ROUND_VARIANTS + 2, 60, battle, difficulty)

    def test_elite_four_tiers(self):
        """Lorelei, tiers 1-4 at wBattleCount 86-89."""
        self._boot()
        member = next(m for m in self.g.e4 if m.name == "Lorelei")
        cfg = model.Config()
        for tier in range(1, 5):
            count = 85 + tier
            with self.subTest(tier=tier):
                battle = model.e4_battle(self.g, cfg, member, count, random.Random(1))
                self._check_spec("LORELEI", (tier - 1) * NUM_ROUND_VARIANTS + 2, count, battle)

    def test_miniboss_levels(self):
        self._boot()
        cfg = model.Config()
        for count in (5, 35, 65, 85):
            with self.subTest(wBattleCount=count):
                sizes, band = self._model_band(
                    lambda rng: model.miniboss_battle(self.g, cfg, "GIOVANNI", count, "CHARMANDER", rng))
                levels, money = self._read_trainer("GIOVANNI_MINIBOSS", 1, count)
                self.assertIn(len(levels), sizes, "party size")
                self.assertTrue(set(levels) <= band,
                                f"ROM levels {levels} outside model band {sorted(band)}")
                self._assert_money(
                    model.miniboss_battle(self.g, cfg, "GIOVANNI", count, "CHARMANDER", random.Random(0)),
                    levels, money)

    # --- reward / wild / boss levels ------------------------------------------

    def _level_after(self, routine: str, count: int) -> int:
        self._neutral_state("normal", count)
        self.harness.write8("wCurEnemyLevel", 0)
        self._call(routine)
        return self.harness.read8("wCurEnemyLevel")

    def test_reward_and_boss_levels(self):
        """GetRewardMonLevel's stage caller (any map but the lobby, Reward Room
        and Oak's Lab) and PCGetBossLevel, both deterministic."""
        self._boot()
        h = self.harness
        saved_map = h.read8("hCurMap")
        h.write8("hCurMap", self.maps["ROUTE_1"])
        try:
            for count in (0, 15, 45, 89):
                with self.subTest(routine="GetRewardMonLevel", wBattleCount=count):
                    self.assertEqual(self._level_after("GetRewardMonLevel", count),
                                     model.reward_level(self.g, count))
                with self.subTest(routine="PCGetBossLevel", wBattleCount=count):
                    battle = model.wild_boss_battle(self.g, model.Config(), count, random.Random(0))
                    self.assertEqual(self._level_after("PCGetBossLevel", count), battle.mons[0][1])
        finally:
            h.write8("hCurMap", saved_map)

    def test_wild_levels(self):
        self._boot()
        cfg = model.Config()
        for count in (0, 25, 55, 89, 95, 120):
            with self.subTest(wBattleCount=count):
                _, band = self._model_band(lambda rng: model.wild_battle(self.g, cfg, count, rng))
                self.assertIn(self._level_after("PCGetWildLevel", count), band)


if __name__ == "__main__":
    unittest.main()
