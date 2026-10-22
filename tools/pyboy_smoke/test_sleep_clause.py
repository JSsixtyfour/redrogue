"""Sleep Clause (custom_functions/sleep_clause.asm), Smogon RBY's Sleep Clause Mod.

A side may not put a second opposing mon to sleep while one it already put to
sleep is still asleep. Rest neither sets nor is blocked by it. State is
wSleepClauseState: low nibble = the player's mon the enemy slept, high nibble =
the enemy's mon the player slept, each party slot + 1.

SleepEffect is probed to its first exit seam in a live FIGHT 2 battle (the
exits go on to animations/text that wait on VBlank, see test_paralyze_effect):
  PlayCurrentMoveAnimation2           the target fell asleep
  SleepClauseCheckAndClaim.blocked    "SLEEP CLAUSE prevents it!"
  SleepEffect.didntAffect             any other failure
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants
from test_item_descriptions import decode_tiles

ROOT = Path(__file__).resolve().parents[2]

PARTYMON_STRUCT_LENGTH = 0x2C
STATUS_OFFSET = 3              # MON_STATUS - MON_HP, ASSERTed in sleep_clause.asm
SLP_MASK = 0b111
USING_X_ACCURACY_MASK = 1 << 0  # wPlayer/EnemyBattleStatus2
CARRY = 1 << 4
NORMAL = 0x00
BIT_TEST_BATTLE_MASK = 1 << 0  # wStatusFlags7, constants/ram_constants.asm
SEAMS = (
    "PlayCurrentMoveAnimation2",
    "SleepClauseCheckAndClaim.blocked",
    "SleepEffect.didntAffect",
)


class SleepClauseTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        cls.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        cls.effects = parse_rgbds_constants(ROOT / "constants/move_effect_constants.asm")
        cls.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")

        def mon(name, move_names):
            return {"species": self.species[name], "level": 50,
                    "moves": [self.moves[m] for m in move_names]}

        team = [mon("PARASECT", ["SPORE", "REST"]), mon("SNORLAX", ["REST"]),
                mon("TAUROS", ["SPLASH"])]
        self.h.inject_fight2_spec(
            team, [dict(m) for m in team],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=1)
        self.h.boot_fight2(seed=1)
        self.player_active = self.h.read8("wPlayerMonNumber")
        self.enemy_active = self.h.read8("wEnemyMonPartyPos")
        self.assertLess(self.player_active, 3)
        self.assertLess(self.enemy_active, 3)
        self.player_bench = next(s for s in range(3) if s != self.player_active)
        self.enemy_bench = next(s for s in range(3) if s != self.enemy_active)

    def tearDown(self) -> None:
        self.h.close()

    # --- state helpers ---------------------------------------------------
    def party_hp(self, side: int, slot: int) -> int:
        label = "wPartyMon1HP" if side == 0 else "wEnemyMon1HP"
        return self.h.address(label) + slot * PARTYMON_STRUCT_LENGTH

    def set_benched(self, side: int, slot: int, *, hp: int, status: int) -> None:
        mem = self.h.pyboy.memory
        base = self.party_hp(side, slot)
        mem[base], mem[base + 1] = hp >> 8, hp & 0xFF
        mem[base + STATUS_OFFSET] = status

    def set_active(self, side: int, *, hp: int = 100, status: int = 0) -> None:
        prefix = "wBattleMon" if side == 0 else "wEnemyMon"
        self.h.write8(prefix + "HP", hp >> 8)
        self.h.write8(prefix + "HP", hp & 0xFF, offset=1)
        self.h.write8(prefix + "Status", status)

    @staticmethod
    def nibbles(player_holder: int | None, enemy_holder: int | None) -> int:
        low = 0 if player_holder is None else player_holder + 1
        high = 0 if enemy_holder is None else enemy_holder + 1
        return (high << 4) | low

    # --- SleepEffect probe ------------------------------------------------
    def run_sleep_move(self, attacker: int) -> dict[str, object]:
        """attacker 0 = the player uses Spore on the enemy, 1 = the reverse."""
        h = self.h
        h.park_before_hijack()
        h.write8("hWhoseTurn", attacker)
        user, target = ("wPlayer", "wEnemy") if attacker == 0 else ("wEnemy", "wPlayer")
        h.write8(user + "MoveNum", self.moves["SPORE"])
        h.write8(user + "MoveEffect", self.effects["SLEEP_EFFECT"])
        h.write8(user + "MoveType", NORMAL)
        h.write8(user + "MoveAccuracy", 255)
        h.write8(user + "BattleStatus2", USING_X_ACCURACY_MASK)  # deterministic hit
        h.write8(target + "BattleStatus2", 0)  # no Substitute
        target_status = "wEnemyMonStatus" if attacker == 0 else "wBattleMonStatus"

        captured: dict[str, object] = {}
        hooks = []

        def exit_hook(name):
            def callback(_context) -> None:
                if "exit" not in captured:
                    captured["exit"] = name
                    captured["status"] = h.read8(target_status)
                    captured["state"] = h.read8("wSleepClauseState")
            return callback

        for label in SEAMS:
            bank, address = h.symbols.get(label)
            h.pyboy.hook_register(bank, address, exit_hook(label), None)
            hooks.append((bank, address))
        try:
            h.probe_routine_until("SleepEffect", lambda: "exit" in captured, limit=240)
        finally:
            for bank, address in hooks:
                h.pyboy.hook_deregister(bank, address)
        return captured

    # --- tests: SleepEffect -----------------------------------------------
    def test_first_sleep_lands_and_records_the_target(self) -> None:
        self.h.write8("wSleepClauseState", 0)
        self.set_active(1)
        got = self.run_sleep_move(attacker=0)
        self.assertEqual(got["exit"], "PlayCurrentMoveAnimation2")
        self.assertNotEqual(got["status"] & SLP_MASK, 0)
        self.assertEqual(got["state"], self.nibbles(None, self.enemy_active))

    def test_second_sleep_is_blocked_while_the_first_sleeper_sleeps(self) -> None:
        self.set_benched(1, self.enemy_bench, hp=50, status=3)
        self.h.write8("wSleepClauseState", self.nibbles(None, self.enemy_bench))
        self.set_active(1)
        got = self.run_sleep_move(attacker=0)
        self.assertEqual(got["exit"], "SleepClauseCheckAndClaim.blocked")
        self.assertEqual(got["status"], 0)
        self.assertEqual(got["state"], self.nibbles(None, self.enemy_bench))

    def test_clause_lifts_once_the_sleeper_wakes(self) -> None:
        self.set_benched(1, self.enemy_bench, hp=50, status=0)
        self.h.write8("wSleepClauseState", self.nibbles(None, self.enemy_bench))
        self.set_active(1)
        got = self.run_sleep_move(attacker=0)
        self.assertEqual(got["exit"], "PlayCurrentMoveAnimation2")
        self.assertEqual(got["state"], self.nibbles(None, self.enemy_active))

    def test_clause_lifts_once_the_sleeper_faints(self) -> None:
        self.set_benched(1, self.enemy_bench, hp=0, status=3)
        self.h.write8("wSleepClauseState", self.nibbles(None, self.enemy_bench))
        self.set_active(1)
        got = self.run_sleep_move(attacker=0)
        self.assertEqual(got["exit"], "PlayCurrentMoveAnimation2")

    def test_enemy_is_bound_by_the_clause_too(self) -> None:
        self.set_benched(0, self.player_bench, hp=50, status=2)
        self.h.write8("wSleepClauseState", self.nibbles(self.player_bench, None))
        self.set_active(0)
        got = self.run_sleep_move(attacker=1)
        self.assertEqual(got["exit"], "SleepClauseCheckAndClaim.blocked")
        self.assertEqual(got["status"], 0)

    def test_sides_are_independent(self) -> None:
        # The player has slept an enemy mon; that must not stop the enemy.
        self.set_benched(1, self.enemy_bench, hp=50, status=3)
        self.h.write8("wSleepClauseState", self.nibbles(None, self.enemy_bench))
        self.set_active(0)
        got = self.run_sleep_move(attacker=1)
        self.assertEqual(got["exit"], "PlayCurrentMoveAnimation2")
        self.assertEqual(got["state"], self.nibbles(self.player_active, self.enemy_bench))

    def test_own_rest_sleep_does_not_count(self) -> None:
        # A self-Rested benched mon is asleep, but nothing recorded it.
        self.set_benched(1, self.enemy_bench, hp=50, status=2)
        self.h.write8("wSleepClauseState", 0)
        self.set_active(1)
        got = self.run_sleep_move(attacker=0)
        self.assertEqual(got["exit"], "PlayCurrentMoveAnimation2")

    # --- tests: Rest ------------------------------------------------------
    def run_rest_precheck(self, state: int) -> tuple[int, int]:
        h = self.h
        h.park_before_hijack()
        h.write8("hWhoseTurn", 0)
        h.write8("wSleepClauseState", state)
        h.call_routine("RestPrecheck")
        return h.last_call_registers["F"] & CARRY, h.read8("wSleepClauseState")

    def test_rest_is_never_blocked_and_releases_its_own_clause(self) -> None:
        carry, state = self.run_rest_precheck(self.nibbles(self.player_active, self.enemy_bench))
        self.assertEqual(carry, 0, "Sleep Clause must never block Rest")
        self.assertEqual(state, self.nibbles(None, self.enemy_bench))

    def test_rest_by_another_mon_keeps_the_clause(self) -> None:
        start = self.nibbles(self.player_bench, None)
        carry, state = self.run_rest_precheck(start)
        self.assertEqual(carry, 0)
        self.assertEqual(state, start)

    # --- tests: AI ----------------------------------------------------------
    def ai_sleep_blocked(self) -> bool:
        h = self.h
        h.park_before_hijack()
        h.write8("wPlayerBattleStatus2", 0)
        self.set_active(0)
        h.call_routine("AIPrimarySleepIsBlocked")
        return bool(h.last_call_registers["F"] & CARRY)

    def test_ai_sees_the_clause(self) -> None:
        self.set_benched(0, self.player_bench, hp=50, status=4)
        self.h.write8("wSleepClauseState", self.nibbles(self.player_bench, None))
        self.assertTrue(self.ai_sleep_blocked())

    def test_ai_is_free_without_the_clause(self) -> None:
        self.h.write8("wSleepClauseState", self.nibbles(None, self.enemy_bench))
        self.assertFalse(self.ai_sleep_blocked())

    # --- tests: move info box -------------------------------------------------
    def menu_power_row(self, state: int) -> str:
        """Open the real FIGHT menu (PrintMenuItem waits on frames, so it
        cannot be probed) with the cursor on Spore, and read the PWR row."""
        h = self.h
        self.assertEqual(h.read8("wBattleMonMoves"), self.moves["SPORE"])
        h.write8("wSleepClauseState", state)
        # FIGHT 2 is a TestBattle, and MoveSelectionMenu skips PrintMenuItem
        # in one (core.asm .battleselect). Drop the bit for this render only.
        h.write8("wStatusFlags7", h.read8("wStatusFlags7") & ~BIT_TEST_BATTLE_MASK & 0xFF)
        row: dict[str, str] = {}
        base = h.address("wTileMap") + 8 * 20 + 1

        def capture(_context) -> None:
            row.setdefault("text", decode_tiles(h.pyboy.memory[base:base + 9]))

        # Hook the branch both paths rejoin at, so a menu that never rendered
        # is a failure rather than a stale tilemap read.
        bank, address = h.symbols.get("PrintMenuItem.noPowerAccuracy")
        h.pyboy.hook_register(bank, address, capture, None)
        try:
            # A clears any intro text, then lands on FIGHT (the cursor's home);
            # stop the moment the move menu renders, before Spore is chosen.
            for _ in range(300):
                h.tap("a", 1)
                h.tick(8)
                if "text" in row:
                    break
            self.assertIn("text", row, "the move info box never rendered")
        finally:
            h.pyboy.hook_deregister(bank, address)
        return row["text"]

    def test_info_box_warns_when_the_clause_holds(self) -> None:
        self.set_benched(1, self.enemy_bench, hp=50, status=3)
        self.assertEqual(self.menu_power_row(self.nibbles(None, self.enemy_bench)), "SLEEP BAN")

    def test_info_box_is_normal_otherwise(self) -> None:
        self.assertTrue(self.menu_power_row(0).startswith("PWR"))


class SleepClauseAIFullFlowTest(unittest.TestCase):
    """Every AI tier must score a clause-blocked Spore below its attack.

    The player's benched mon is asleep from the enemy, so the enemy's Spore at
    the player's healthy lead would fail. AI_REDUNDANT runs at every tier and
    saturates it; the encourage paths (AI_SMART, class personality .sleep,
    AI_THREAT) must not pull it back under Tackle. The control run without the
    clause proves the instrumentation sees Spore scored normally.
    """

    def scores_for(self, tier: int, clause: bool) -> dict[str, object]:
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        try:
            h.inject_fight2_spec(
                [{"species": species["SNORLAX"], "level": 50, "moves": [moves["TACKLE"]]},
                 {"species": species["TAUROS"], "level": 50, "moves": [moves["TACKLE"]]}],
                [{"species": species["PARASECT"], "level": 50,
                  "moves": [moves["SPORE"], moves["TACKLE"]]}],
                trainer_class=trainers["COOLTRAINER_M"], ai_tier=tier)
            scores = h.hook_ai_scores()

            def apply_clause() -> None:
                if clause:
                    bench = h.address("wPartyMon1HP") + PARTYMON_STRUCT_LENGTH
                    h.pyboy.memory[bench + STATUS_OFFSET] = 3  # asleep, HP untouched
                    h.write8("wSleepClauseState", 2)           # slot 1 + 1

            # Hooked on AIPlanEnemyTurn, not applied after boot_fight2 returns:
            # turn 1's whole decision - the move scores this test reads via
            # scores[0] - is made INSIDE boot_fight2 (ai_turn_plan.asm's
            # pre-menu plan runs before boot_fight2's own first battle menu),
            # so a write made after boot would be one decision too late (the
            # move it should have blocked is already scored). Writing the
            # clause state BEFORE boot_fight2 instead does not work either:
            # boot_fight2's own party setup overwrites it (measured). The
            # hook runs after that setup and before the decision that reads it.
            h.hook_flag("AIPlanEnemyTurn", action=apply_clause)
            h.boot_fight2(seed=1)
            self.assertEqual(h.read8("wPlayerMonNumber"), 0)
            for _ in range(300):
                h.tap("a", 1)
                h.tick(8)
                if scores:
                    break
            self.assertTrue(scores, "the AI never scored a turn")
            self.assertEqual(scores[0]["tier"], tier)
            return scores[0]
        finally:
            h.close()

    def test_every_tier_avoids_a_blocked_sleep_move(self) -> None:
        for tier in range(4):
            with self.subTest(tier=tier):
                blocked = self.scores_for(tier, clause=True)["scores"]
                self.assertGreater(blocked[0], blocked[1],
                                   f"tier {tier} still prefers Spore under the clause")
                free = self.scores_for(tier, clause=False)["scores"]
                self.assertLess(free[0], blocked[0],
                                f"tier {tier}: the clause did not change Spore's score")


if __name__ == "__main__":
    unittest.main()
