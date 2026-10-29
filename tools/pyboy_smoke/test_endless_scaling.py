"""Endless mode checkpoint D: difficulty scales with RUN progress, not the
circuit-local battle count (ENDLESS_MODE_CHECKPOINT_D.md).

GetRunProgress = wBattleCount + depth * ENDLESS_CIRCUIT_SPAN (saturating), and
every difficulty reader goes through it. Shape holds at the last authored row;
levels grow by the solved EndlessLevelRows; rarity climbs by slot floors
(EndlessRosterClass). Depth 0 must be exactly the original run.

Every ROM test boots the lobby and runs inside isolated_routine_calls, which
restores the whole machine on exit.
"""
import re
import unittest
from collections import defaultdict

from routine_session import isolated_routine_calls
from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

SPAN = 72              # ENDLESS_CIRCUIT_SPAN
ROUND_BATTLES = 8
LAST_ROUND = 8
FIRST_ROUND = 9        # ENDLESS_FIRST_ROUND
SLACK = 10             # SET_LEVEL_SLACK_BELOW
MASTER, ULTRA, GREAT, POKE = 1, 2, 3, 4   # GetRandMon's inverted class encoding


def endless_rows() -> list[int]:
    text = (REPO_ROOT / "data/balance/endless_levels.asm").read_text()
    rows = []
    for m in re.finditer(r"^\s*db ([\d, ]+)", text, re.M):
        rows += [int(v) for v in m.group(1).split(",")]
    return rows


class EndlessLevelTableTest(unittest.TestCase):
    def test_rows_are_solved_monotone_and_complete(self) -> None:
        rows = endless_rows()
        self.assertEqual(len(rows), 255 // ROUND_BATTLES + 1 - FIRST_ROUND)
        self.assertTrue(any(rows), "still the all-zero placeholder")
        self.assertEqual(rows, sorted(rows), "a later round would get easier")


class MovesetCeilingTest(unittest.TestCase):
    """Checkpoint D 3.5: at level 100 a mon whose sets for a tier all stop
    lower falls back to a worse source. Every final-stage species that has
    ANY set on an Endless mix row's tier mask must have one reaching 100."""

    TIERS = {"TIER_NORMAL": 4, "TIER_HARD": 8, "TIER_ELITE": 16}
    MASKS = {"TRAINER_FINAL/GYM_LATE": 4 | 8, "ELITE": 8 | 16, "E4_SETS": 16}

    def test_final_stage_sets_reach_level_100(self) -> None:
        norm = lambda s: re.sub(r"[^A-Z0-9]", "", s.upper())
        sets, cur = defaultdict(list), None
        for line in (REPO_ROOT / "data/trainers/movesets.asm").read_text().splitlines():
            m = re.match(r"^Moveset_(\w+)::", line)
            if m:
                cur = norm(m.group(1))
                continue
            if line.startswith("MovesetFormIndex"):
                cur = None
            f = re.match(r"^\s*db ([^;]+)", line)
            if cur and f:
                parts = [p.strip() for p in f.group(1).split(",")]
                if len(parts) == 8:
                    mask = sum(self.TIERS.get(t.strip(), 0) for t in parts[4].split("|"))
                    sets[cur].append((mask, int(parts[7])))
        evolves, cur = set(), None
        for line in (REPO_ROOT / "data/pokemon/evos_moves.asm").read_text().splitlines():
            m = re.match(r"^(\w+)EvosMoves:", line)
            if m:
                cur = norm(m.group(1))
            elif cur and re.match(r"^\s*db EVOLVE_", line):
                evolves.add(cur)
        short = []
        for species, recs in sets.items():
            if species in evolves:
                continue
            for name, mk in self.MASKS.items():
                his = [hi for mask, hi in recs if mask & mk]
                if his and max(his) + SLACK < 100:
                    short.append(f"{species} {name} max {max(his)}")
        self.assertEqual(short, [])


class EndlessScalingTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        h = self.harness
        h.boot_to_lobby()
        self.session = isolated_routine_calls(h)
        self.session.__enter__()
        self.ram = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")
        self.rows = endless_rows()

    def tearDown(self) -> None:
        try:
            self.session.__exit__(None, None, None)
        finally:
            self.harness.close()

    def at(self, depth: int, count: int) -> None:
        self.harness.write8("wEndlessDepth", depth)
        self.harness.write8("wBattleCount", count)

    def regs(self) -> dict:
        return self.harness.last_call_registers

    @staticmethod
    def progress(depth: int, count: int) -> int:
        return min(255, count + depth * SPAN)

    # -- accessors ----------------------------------------------------

    def test_run_progress(self) -> None:
        h = self.harness
        for depth, count in [(0, 0), (0, 40), (0, 76), (1, 1), (1, 64), (2, 30), (3, 39), (3, 40), (3, 76), (9, 1)]:
            self.at(depth, count)
            h.call_routine("GetRunProgress")
            r = self.regs()
            self.assertEqual(r["A"], self.progress(depth, count), (depth, count))

    def test_round_step_clamps_the_round_not_the_count(self) -> None:
        """Clamping the count would make every Endless route trainer step 7, a
        final gym trainer (ENDLESS_MODE_CHECKPOINT_D.md section 9, finding 1)."""
        h = self.harness
        cases = [(0, 1), (0, 40), (0, 71), (1, 1), (1, 4), (1, 13), (2, 60), (3, 76)]
        for depth, count in cases:
            self.at(depth, count)
            h.call_routine("GetRunRoundStep")
            r = self.regs()
            p = self.progress(depth, count)
            self.assertEqual(r["B"], min(p // ROUND_BATTLES, LAST_ROUND), (depth, count))
            self.assertEqual(r["A"], p % ROUND_BATTLES, (depth, count))

    # -- levels -------------------------------------------------------

    def bonus_level(self, depth: int, count: int, level: int, label="EndlessLevelBonus") -> int:
        self.at(depth, count)
        self.harness.write8("wCurEnemyLevel", level)
        self.harness.call_routine(label)
        return self.harness.read8("wCurEnemyLevel")

    def test_level_bonus_follows_the_table(self) -> None:
        self.assertEqual(self.bonus_level(0, 70, 40), 40, "depth 0 must not change")
        for depth, count in [(1, 1), (1, 40), (2, 9), (3, 1), (3, 100)]:
            p = self.progress(depth, count)
            want = 40 + self.rows[p // ROUND_BATTLES - FIRST_ROUND]
            self.assertEqual(self.bonus_level(depth, count, 40), min(255, want), (depth, count))

    def test_funnels_cap_at_100(self) -> None:
        h = self.harness
        h.set_difficulty("HARD")
        for label in ("RogueApplyTrainerLevelModifiers", "RogueApplyWildLevelModifiers"):
            self.assertEqual(self.bonus_level(3, 40, 90, label), 100, label)
            self.assertEqual(self.bonus_level(0, 40, 37, label), 37, f"{label} depth 0")

    def test_reward_level_lifts_the_cap_in_endless(self) -> None:
        h = self.harness
        self.at(0, 60)
        h.call_routine("GetRewardMonLevel")
        base = h.read8("wCurEnemyLevel")
        self.assertLessEqual(base, 50)
        for depth, count in [(1, 1), (1, 60), (3, 40)]:
            self.at(depth, count)
            h.call_routine("GetRewardMonLevel")
            p = self.progress(depth, count)
            # Endless reads the last row uncapped: route 0x31 + 4/2 or gym 0x34 + 4/2.
            base = 51 if p % ROUND_BATTLES < 4 else 54
            want = min(100, base + self.rows[p // ROUND_BATTLES - FIRST_ROUND])
            self.assertEqual(h.read8("wCurEnemyLevel"), want, (depth, count))
            self.assertEqual(self.regs()["A"], want, "callers read the level from a")

    def test_leader_uses_round_8_teams(self) -> None:
        h = self.harness
        seen = set()
        for depth, count in [(1, 8), (1, 64), (2, 32), (3, 40)] * 4:
            self.at(depth, count)
            h.pyboy.register_file.D = 0x01
            h.call_routine("InitGymBattle")
            seen.add(h.read8("wTrainerNo"))
        self.assertTrue(seen <= {22, 23, 24}, seen)

    # -- rarity -------------------------------------------------------

    def roster_class(self, depth: int, round_: int, slot: int, cls: int) -> int:
        h = self.harness
        count = 1 if depth == 0 else round_ * ROUND_BATTLES + 1 - depth * SPAN
        self.at(depth, count)
        h.write8("wEnemyPartyCount", slot)
        h.pyboy.register_file.E = cls
        h.call_routine("EndlessRosterClass")
        return self.regs()["E"]

    def test_depth_0_rarity_untouched(self) -> None:
        for slot in range(6):
            self.assertEqual(self.roster_class(0, 0, slot, POKE), POKE)

    def test_master_floor_climbs_one_slot_a_round(self) -> None:
        # round 9 (s = 1) .. round 12 (s = 4): slots 5, 4, 3, 2 turn Master.
        for s in range(1, 5):
            for slot in range(2, 6):
                want = MASTER if slot + s >= 6 else ULTRA
                self.assertEqual(self.roster_class(1, LAST_ROUND + s, slot, ULTRA), want, (s, slot))

    def test_flex_slots_floor_at_ultra_then_flip(self) -> None:
        for slot in (0, 1):
            for cls in (POKE, GREAT, ULTRA):
                self.assertEqual(self.roster_class(1, 9, slot, cls), ULTRA, (slot, cls))
            self.assertEqual(self.roster_class(1, 9, slot, MASTER), MASTER, "never lowers")
            for s in (2, 3, 4):
                self.assertEqual(self.roster_class(1, LAST_ROUND + s, slot, ULTRA), ULTRA, s)
        seen = {self.roster_class(1, 13, i % 2, ULTRA) for i in range(40)}
        self.assertEqual(seen, {ULTRA, MASTER}, "round 13+: Ultra or Master")

    # -- witch --------------------------------------------------------

    def test_all_prizes_earned(self) -> None:
        h = self.harness
        full = (1 << self.ram["NUM_WITCH_PRIZES"]) - 1
        for earned, want_z in [(full, True), (full & ~1, False), (full & ~(1 << 9), False), (0, False)]:
            h.write8("wWitchPrizesEarned", earned & 0xFF)
            h.write8("wWitchPrizesEarned", earned >> 8, offset=1)
            h.call_routine("WitchAllPrizesEarned")
            self.assertEqual(bool(self.regs()["F"] & 0x80), want_z, hex(earned))


if __name__ == "__main__":
    unittest.main()
