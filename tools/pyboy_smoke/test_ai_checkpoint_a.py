"""Runtime regression fixtures for AI review R0, R2, and R3."""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]


class AICheckpointATest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        def mon(name, moves):
            return {"species": self.species[name], "level": 50,
                    "moves": [self.moves[m] for m in moves]}
        self.h.inject_fight2_spec(
            [mon("SNORLAX", ["SPLASH"])],
            [mon("TAUROS", ["SONICBOOM", "RECOVER"])],
            trainer_class=trainers["COOLTRAINER_M"], ai_tier=2)
        self.h.boot_fight2(seed=1)

    def tearDown(self):
        self.h.close()

    def word(self, label, value):
        self.h.write8(label, value >> 8)
        self.h.write8(label, value & 255, offset=1)

    def estimate(self, name, player=False, crit=False):
        h = self.h
        h.park_before_hijack()
        bank, address = h.symbols.get("Moves")
        offset = bank * 0x4000 + address - 0x4000 + (self.moves[name] - 1) * 6
        data = (ROOT / "pokeblue_debug.gbc").read_bytes()[offset:offset + 6]
        for index, value in enumerate(data):
            h.write8("wPlayerMoveNum" if player else "wEnemyMoveNum", value, offset=index)
        h.call_routine("AIEstimatePlayerDamage" if player else "AIEstimateDamage", limit=120)
        if crit:
            h.park_before_hijack()
            h.call_routine("AIScaleDamageForCrit", limit=120)
        return int.from_bytes(bytes(h.read_bytes("wAIDamageEstimate", 2)), "big")

    def test_fixed_damage_never_receives_crit_bonus_including_focus_energy(self):
        h = self.h
        for focused in (0, 1 << 2):
            h.write8("wEnemyBattleStatus2", focused)
            for name, expected in (("SONICBOOM", 20), ("DRAGON_RAGE", 40),
                                   ("SEISMIC_TOSS", 50), ("NIGHT_SHADE", 50)):
                with self.subTest(move=name, focused=focused):
                    self.assertEqual(self.estimate(name), expected)
                    self.assertEqual(self.estimate(name, crit=True), expected)
                    self.assertEqual(self.estimate(name, player=True), expected)
        raw = self.estimate("TACKLE")
        self.assertGreater(self.estimate("TACKLE", crit=True), raw)

    def test_super_fang_boundary_and_crit_exclusion_both_directions(self):
        for hp in (1, 2, 3, 255, 256):
            self.word("wBattleMonHP", hp)
            self.word("wEnemyMonHP", hp)
            expected = max(1, hp // 2)
            with self.subTest(hp=hp):
                self.assertEqual(self.estimate("SUPER_FANG", crit=True), expected)
                self.assertEqual(self.estimate("SUPER_FANG", player=True), expected)

    def test_disabled_finisher_cannot_hide_legal_recover(self):
        h = self.h
        for tier in range(4):
            for disabled_slot in (0, 1):
                h.park_before_hijack()
                h.write8("wAITier", tier + 1)
                h.write8("wEnemyMonMoves", self.moves["SONICBOOM"], offset=disabled_slot)
                h.write8("wEnemyMonMoves", self.moves["RECOVER"], offset=1 - disabled_slot)
                h.write8("wEnemyDisabledMove", ((disabled_slot + 1) << 4) | 1)
                self.word("wBattleMonHP", 10)
                for i, value in enumerate(h.read_bytes("wEnemyMonMaxHP", 2)):
                    h.write8("wEnemyMonHP", value, offset=i)
                h.call_routine("SelectEnemyMove", limit=120)
                self.assertEqual(h.read8("wEnemySelectedMove"), self.moves["RECOVER"])

    def test_only_move_disabled_uses_struggle(self):
        h = self.h
        h.write8("wEnemyMonMoves", 0, offset=1)
        h.write8("wEnemyDisabledMove", 0x11)
        h.call_routine("SelectEnemyMove", limit=120)
        self.assertEqual(h.read8("wEnemySelectedMove"), self.moves["STRUGGLE"])

    def prime_haze(self):
        h = self.h
        h.park_before_hijack()
        for base in ("wPlayerMonAttackMod", "wEnemyMonAttackMod"):
            for i in range(8):
                h.write8(base, 7, offset=i)
        for label in ("wBattleMonStatus", "wEnemyMonStatus", "wPlayerDisabledMove", "wEnemyDisabledMove",
                      "wPlayerBattleStatus1", "wPlayerBattleStatus2", "wPlayerBattleStatus3",
                      "wEnemyBattleStatus1", "wEnemyBattleStatus2", "wEnemyBattleStatus3"):
            h.write8(label, 0)
        h.write8("wEnemyMonMoves", self.moves["HAZE"])
        for i in range(1, 4):
            h.write8("wEnemyMonMoves", 0, offset=i)
        h.write8("wBuffer", 20)

    def test_smart_haze_distinguishes_neutral_from_beneficial_stage_reset(self):
        scores = []
        # Capture the effect-specific result before evasion affects the shared
        # status-accuracy heuristic. Those are separate scoring decisions.
        self.h.hook_flag("AISmartCrossCutting", action=lambda:
                         scores.append(self.h.read8("wBuffer")))
        for label, stage in (("wPlayerMonAttackMod", 6),
                             ("wPlayerMonEvasionMod", 9),
                             ("wEnemyMonAttackMod", 5)):
            self.prime_haze()
            self.h.write8("wAILastMoveNum", 0)
            self.h.write8("wAISameMoveCount", 0)
            self.h.write8(label, stage)
            self.h.call_routine("AILayerSmart", limit=120)
        self.assertGreater(scores[0], scores[1])
        self.assertGreater(scores[0], scores[2])

    def test_smart_haze_scores_the_whole_trade(self):
        # Review F7 (2026-09-29): enemy Haze also cures the PLAYER's major
        # status, so a paralysis we inflicted is a cost, not a free reset.
        # SMART score from 20, read before the cross-cutting rules run:
        # 22 = discouraged, 19 = mild encourage, 18 = strong encourage.
        scores = []
        self.h.hook_flag("AISmartCrossCutting", action=lambda:
                         scores.append(self.h.read8("wBuffer")))
        cases = [
            ("player paralyzed, nothing else", {"wBattleMonStatus": 1 << 6}, 22),
            ("player +2 Attack, +1 Speed", {"wPlayerMonAttackMod": 9,
                                            "wPlayerMonSpeedMod": 8}, 18),
            ("player +2 Attack but paralyzed", {"wPlayerMonAttackMod": 9,
                                                "wBattleMonStatus": 1 << 6}, 22),
            ("player Reflect only", {"wPlayerBattleStatus3": 4}, 19),
        ]
        for _label, writes, _expected in cases:
            self.prime_haze()
            self.h.write8("wAILastMoveNum", 0)
            self.h.write8("wAISameMoveCount", 0)
            for label, value in writes.items():
                self.h.write8(label, value)
            self.h.call_routine("AILayerSmart", limit=120)
        self.assertEqual(scores, [expected for _l, _w, expected in cases],
                         [label for label, _w, _e in cases])

    def test_haze_noop_and_all_six_non_neutral_stage_contracts(self):
        self.prime_haze()
        self.h.call_routine("AILayerRedundant", limit=120)
        self.assertEqual(self.h.read8("wBuffer"), 79)
        for base in ("wPlayerMonAttackMod", "wEnemyMonAttackMod"):
            for slot in range(6):
                for stage in (1, 6, 8, 13):
                    self.prime_haze()
                    self.h.write8(base, stage, offset=slot)
                    self.h.call_routine("AILayerRedundant", limit=120)
                    self.assertEqual(self.h.read8("wBuffer"), 20, (base, slot, stage))

    def test_haze_recognizes_only_states_the_real_effect_clears(self):
        states = {"wBattleMonStatus": [1, 8, 16, 32, 64],
                  "wPlayerDisabledMove": [0x11], "wEnemyDisabledMove": [0x11],
                  "wPlayerBattleStatus1": [128], "wEnemyBattleStatus1": [128],
                  "wPlayerBattleStatus2": [1, 2, 4, 128],
                  "wEnemyBattleStatus2": [1, 2, 4, 128],
                  "wPlayerBattleStatus3": [1, 2, 4], "wEnemyBattleStatus3": [1, 2, 4]}
        for label, values in states.items():
            for value in values:
                self.prime_haze()
                self.h.write8(label, value)
                self.h.call_routine("AILayerRedundant", limit=120)
                self.assertEqual(self.h.read8("wBuffer"), 20, (label, value))
        self.prime_haze()
        self.h.write8("wEnemyMonStatus", 32)  # enemy Haze does not cure its user
        self.h.call_routine("AILayerRedundant", limit=120)
        self.assertEqual(self.h.read8("wBuffer"), 79)


if __name__ == "__main__":
    unittest.main()
