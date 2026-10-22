"""Explosion / Self-Destruct trade veto (AI_EXPLOSION_PP_SPEC_2026-10-21.md, Part A).

AIExplosionVetoMask decides; it runs at the end of AI_DAMAGE (so AI_PLAN and the
scarce-PP rule see only allowed KOs) and again in AIExplosionTradeVeto, just before
AIReliableKOWins, which sets the scores. A trainer at T1+ only blows itself up when
the trade is worth it:
  T1     enemy HP at or below 1/2
  T2/T3  enemy HP below 1/4, OR the player threatens a KO this turn, OR this slot
         reliably KOs and the player has no other live mon (the KO wins the battle)
  any    never into a Substitute
An unworthy slot scores AI_SCORE_MAX (79) and loses its reliable-KO bit. T0 is
untouched. The same ROM is A/B'd with the mask made to return 0 at once (the
PC-redirect hook below), which reproduces the pre-veto behaviour.

DreamEaterTest rides the same harness: AI_DAMAGE gives Dream Eater no kill into an
awake target or a Substitute, where MoveHitTest makes it miss.

Scores are read at AIEnemyTrainerChooseMoves.findMinimum (first hit): the veto
runs just past .loopFindMinimumEntries, so hook_ai_scores readers see pre-veto
scores. The pick is wBuffer after the call (move ids of the tied best slots).
"""
from __future__ import annotations

import io
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
BOOM = 3  # Explosion / Self-Destruct is slot 4 in every moveset below
MAX_SCORE = 79
LEVEL = 40

ENEMIES = {
    "GRAVELER": ["TACKLE", "ROCK_THROW", "DEFENSE_CURL", "SELFDESTRUCT"],
    "GOLEM": ["ROCK_SLIDE", "EARTHQUAKE", "DEFENSE_CURL", "EXPLOSION"],
    "GENGAR": ["DREAM_EATER", "NIGHT_SHADE", "HYPNOSIS", "CONFUSE_RAY"],
}
PLAYERS = {
    "SNORLAX": ("SNORLAX", 40, ["BODY_SLAM", "EARTHQUAKE"]),
    "SNORLAX60": ("SNORLAX", 60, ["BODY_SLAM", "EARTHQUAKE"]),  # out-levels the enemy: threatens a KO
}


class PolicyBase(unittest.TestCase):
    ENEMY = "GOLEM"
    PLAYER = "SNORLAX"
    RESERVE = True
    LEVEL = LEVEL

    @classmethod
    def setUpClass(cls) -> None:
        cls.h = h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        cls.moves = mv = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        cls.battle = parse_rgbds_constants(ROOT / "constants/battle_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        cls.skip = False
        cls.pre = cls.post = cls.plan_ko = None
        h.register_hook("AIEnemyTrainerChooseMoves.findMinimum", cls._post_hook)
        h.register_hook("AIExplosionVetoMask", cls._veto_hook)
        h.register_hook("AILayerPlan", cls._plan_hook)
        player = PLAYERS[cls.PLAYER]
        party = [{"species": species[player[0]], "level": player[1],
                  "moves": [mv[m] for m in player[2]]}]
        if cls.RESERVE:  # a second live mon: a KO no longer ends the battle
            party.append({"species": species["RATTATA"], "level": 40, "moves": [mv["TACKLE"]]})
        h.inject_fight2_spec(
            party,
            [{"species": species[cls.ENEMY], "level": cls.LEVEL,
              "moves": [mv[m] for m in ENEMIES[cls.ENEMY]]}],
            trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)
        h.boot_fight2(seed=1)
        h.reveal_player_moves(0, [0, 1], clear=True)
        h.park_before_hijack()
        state = io.BytesIO()
        h.save_state(state)
        cls.state = state.getvalue()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.h.close()

    @classmethod
    def _post_hook(cls, _ctx) -> None:
        if cls.post is None:  # the loop revisits this label once per slot
            cls.post = cls.h.read_bytes("wBuffer", 4)

    @classmethod
    def _plan_hook(cls, _ctx) -> None:
        cls.plan_ko = cls.h.read8("wAIReliableKOFound")

    @classmethod
    def _veto_hook(cls, _ctx) -> None:
        if cls.skip:  # emulate `ret` with a = 0: nothing vetoed
            rf, mem = cls.h.pyboy.register_file, cls.h.pyboy.memory
            rf.A = 0
            rf.PC = mem[rf.SP] | mem[(rf.SP + 1) & 0xFFFF] << 8
            rf.SP = (rf.SP + 2) & 0xFFFF

    def _set_hp(self, cur: str, cap: str, frac) -> None:
        """frac: a fraction of max HP, or (hp, max_hp) to set both exactly."""
        h = self.h
        if isinstance(frac, tuple):
            value, cap_value = frac
            h.write8(cap, cap_value >> 8)
            h.write8(cap, cap_value & 0xFF, offset=1)
        else:
            value = max(1, int(((h.read8(cap) << 8) | h.read8(cap, offset=1)) * frac))
        h.write8(cur, value >> 8)
        h.write8(cur, value & 0xFF, offset=1)

    def run_board(self, tier, enemy_hp=1.0, player_hp=1.0, *, turn=2, skip=False,
                  pp=None, substitute=False, player_status=0):
        """-> (scores at findMinimum, KO mask, set of picked slots). self.plan_ko is
        wAIReliableKOFound as AI_PLAN saw it (None if the layer did not run)."""
        h = self.h
        type(self).skip = skip
        h.load_state(io.BytesIO(self.state))
        h.write8("wAILayer2Encouragement", turn)
        h.write8("wAIDebugTierOverride", tier + 1)
        h.write8("wAITier", 0)
        self._set_hp("wEnemyMonHP", "wEnemyMonMaxHP", enemy_hp)
        self._set_hp("wBattleMonHP", "wBattleMonMaxHP", player_hp)
        if substitute:
            h.write8("wPlayerBattleStatus2", 1 << self.battle["HAS_SUBSTITUTE_UP"])
            h.write8("wPlayerSubstituteHP", 40)
        h.write8("wBattleMonStatus", player_status)
        for slot, value in enumerate(pp or ()):
            h.write8("wEnemyMonPP", value, offset=slot)
        type(self).post = type(self).plan_ko = None
        h.call_routine("AIEnemyTrainerChooseMoves", limit=12000)
        picks = h.read_bytes("wBuffer", 4)
        return list(self.post), h.read8("wAIReliableKOFound"), {i for i in range(4) if picks[i]}


class GolemWithReserveTest(PolicyBase):
    """Fixtures 1, 4, 5, 8: Golem {Rock Slide, Earthquake, Defense Curl, Explosion} vs Snorlax + a reserve."""

    def test_1_full_hp_no_threat_is_vetoed(self) -> None:
        scores, ko, picks = self.run_board(3)
        self.assertEqual(scores[BOOM], MAX_SCORE)
        self.assertEqual(ko & (1 << BOOM), 0)
        self.assertNotIn(BOOM, picks)

    def test_1_without_the_veto_it_was_picked(self) -> None:
        scores, ko, picks = self.run_board(3, skip=True)
        self.assertLess(scores[BOOM], MAX_SCORE)
        self.assertEqual(picks, {BOOM})

    def test_1_t2_is_vetoed_too(self) -> None:
        scores, _, picks = self.run_board(2)
        self.assertEqual(scores[BOOM], MAX_SCORE)
        self.assertNotIn(BOOM, picks)

    def test_5_control_mid_hp_without_a_threat_is_vetoed(self) -> None:
        scores, _, picks = self.run_board(3, enemy_hp=0.6)
        self.assertEqual(scores[BOOM], MAX_SCORE)
        self.assertNotIn(BOOM, picks)

    def test_4_below_a_quarter_hp_still_explodes(self) -> None:
        scores, _, picks = self.run_board(3, enemy_hp=0.2)
        self.assertLess(scores[BOOM], MAX_SCORE)
        self.assertIn(BOOM, picks)

    def test_plan_sees_the_vetoed_explosion_as_no_ko(self) -> None:
        """2026-10-21 review: AI_PLAN withholds its push while a reliable KO stands, and
        it used to read the mask before the veto cleared Explosion's bit."""
        self.run_board(3)
        self.assertIsNotNone(self.plan_ko, "T3 runs AI_PLAN")
        self.assertEqual(self.plan_ko & (1 << BOOM), 0)
        self.run_board(3, skip=True)  # control: the bit is there to clear
        self.assertNotEqual(self.plan_ko & (1 << BOOM), 0)

    def test_8_substitute_blocks_it_even_at_low_hp(self) -> None:
        for tier in (1, 3):
            with self.subTest(tier=tier):
                scores, ko, _ = self.run_board(tier, enemy_hp=0.2, substitute=True)
                self.assertEqual(scores[BOOM], MAX_SCORE)
                self.assertEqual(ko & (1 << BOOM), 0)


class GolemThreatenedTest(PolicyBase):
    """Fixture 5: a level-60 Snorlax threatens a KO, so Explosion is allowed above 1/4 HP.
    (A full-HP Golem survives the hit, so the board is at 0.6 HP; the control in
    GolemWithReserveTest shows the same HP is vetoed without the threat.)"""
    PLAYER = "SNORLAX60"

    def test_5_threatened_explosion_is_allowed(self) -> None:
        for tier in (2, 3):
            with self.subTest(tier=tier):
                scores, _, _ = self.run_board(tier, enemy_hp=0.6)
                self.assertLess(scores[BOOM], MAX_SCORE)
                self.assertEqual(scores, self.run_board(tier, enemy_hp=0.6, skip=True)[0])


class GolemLastMonTest(PolicyBase):
    """Fixture 3: no reserve, so Explosion KOs the player's last mon and wins the battle."""
    RESERVE = False

    def test_3_battle_winning_ko_still_explodes(self) -> None:
        scores, ko, picks = self.run_board(3)
        self.assertLess(scores[BOOM], MAX_SCORE)
        self.assertIn(BOOM, picks)
        self.assertNotEqual(ko & (1 << BOOM), 0)


class GolemOnlyMoveTest(PolicyBase):
    def test_10_explosion_is_picked_when_it_is_the_only_slot_with_pp(self) -> None:
        scores, _, picks = self.run_board(3, pp=(0, 0, 0, 10))
        self.assertEqual(scores[BOOM], MAX_SCORE)  # vetoed...
        self.assertEqual(picks, {BOOM})  # ...but every other slot is DISABLED (80)


class GravelerTest(PolicyBase):
    """Fixtures 2, 6, 7: Graveler {Tackle, Rock Throw, Defense Curl, Self-Destruct}."""
    ENEMY = "GRAVELER"

    def test_2_non_lethal_self_destruct_at_mid_hp_is_not_picked(self) -> None:
        scores, _, picks = self.run_board(3, enemy_hp=0.6)
        self.assertEqual(scores[BOOM], MAX_SCORE)
        self.assertNotIn(BOOM, picks)

    def test_2_without_the_veto_it_was_picked(self) -> None:
        _, _, picks = self.run_board(3, enemy_hp=0.6, skip=True)
        self.assertIn(BOOM, picks)

    def test_6_t1_full_hp_is_vetoed_and_low_hp_is_not(self) -> None:
        scores, _, picks = self.run_board(1)
        self.assertEqual(scores[BOOM], MAX_SCORE)
        self.assertNotIn(BOOM, picks)
        scores, _, _ = self.run_board(1, enemy_hp=0.4)
        self.assertLess(scores[BOOM], MAX_SCORE)
        self.assertEqual(scores, self.run_board(1, enemy_hp=0.4, skip=True)[0])  # untouched

    def test_6_t1_exactly_half_hp_is_allowed(self) -> None:
        """At or below half: 100/200 explodes, 101/200 does not (2026-10-21 review: the
        guard used to be strictly below, so 100/200 was vetoed)."""
        scores, _, _ = self.run_board(1, enemy_hp=(100, 200))
        self.assertLess(scores[BOOM], MAX_SCORE)
        self.assertEqual(scores, self.run_board(1, enemy_hp=(100, 200), skip=True)[0])
        scores, _, _ = self.run_board(1, enemy_hp=(101, 200))
        self.assertEqual(scores[BOOM], MAX_SCORE)

    def test_7_t0_scores_are_bit_identical_to_the_veto_skipped_path(self) -> None:
        for enemy_hp in (1.0, 0.6, 0.2):
            with self.subTest(enemy_hp=enemy_hp):
                self.assertEqual(self.run_board(0, enemy_hp=enemy_hp),
                                 self.run_board(0, enemy_hp=enemy_hp, skip=True))


class DreamEaterTest(PolicyBase):
    """Gengar {Dream Eater, Night Shade, Hypnosis, Confuse Ray} vs Snorlax at 60 HP:
    Dream Eater kills a sleeper, Night Shade (50) does not. 2026-10-21 review: into an
    awake Snorlax Dream Eater was a reliable KO and the only pick, though it misses."""
    ENEMY = "GENGAR"
    LEVEL = 50
    SLEEP = 2  # turns left

    def test_asleep_target_is_a_ko_and_picked(self) -> None:  # control
        _, ko, picks = self.run_board(3, player_hp=(60, 180), player_status=self.SLEEP)
        self.assertNotEqual(ko & 1, 0)
        self.assertEqual(picks, {0})

    def test_awake_target_is_no_ko_and_not_picked(self) -> None:
        for tier in (2, 3):
            with self.subTest(tier=tier):
                _, ko, picks = self.run_board(tier, player_hp=(60, 180))
                self.assertEqual(ko & 1, 0)
                self.assertNotIn(0, picks)

    def test_substitute_is_no_ko_even_asleep(self) -> None:
        _, ko, picks = self.run_board(3, player_hp=(60, 180), player_status=self.SLEEP,
                                      substitute=True)
        self.assertEqual(ko & 1, 0)
        self.assertNotIn(0, picks)


class DoubleKOTest(unittest.TestCase):
    """Fixture 9: pins the source reading that an Explosion KOing the player's last mon wins
    the AI the battle. MainInBattleLoop (and ExecuteEnemyMove's fainted-player exit) go to
    HandlePlayerMonFainted, which blacks the player out before it ever looks at the enemy's
    HP, so a double KO ends in HandlePlayerBlackOut, never TrainerBattleVictory."""

    def test_double_ko_ends_in_a_blackout_not_a_victory(self) -> None:
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        try:
            species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
            mv = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
            trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
            h.inject_fight2_spec(
                [{"species": species["SNORLAX"], "level": 50, "moves": [mv["SPLASH"]]}],
                [{"species": species["GOLEM"], "level": 50, "moves": [mv["EXPLOSION"]]}],
                trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)
            order: list[str] = []
            for label in ("HandlePlayerBlackOut", "TrainerBattleVictory"):
                h.register_hook(label, lambda _ctx, label=label: order.append(label))

            def doom(_ctx) -> None:  # the player is at 1 HP when the AI decides
                h.write8("wKODefianceUsages", 0)
                for cur in ("wBattleMonHP", "wPartyMon1HP"):
                    h.write8(cur, 0)
                    h.write8(cur, 1, offset=1)
            h.register_hook("AIEnemyTrainerChooseMoves", doom)
            h.boot_fight2(seed=1)
            for _ in range(900):
                if order:
                    break
                h.tap("a", 1)
                h.tick(8)
            self.assertTrue(order, "the battle never reached a result")
            self.assertEqual(order[0], "HandlePlayerBlackOut")
        finally:
            h.close()


if __name__ == "__main__":
    unittest.main()
