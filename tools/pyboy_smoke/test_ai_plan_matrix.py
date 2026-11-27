"""Every AI strategy plan, chosen and executed from an exact battle state.

The nightly autoplay suites reach several plans on only one or two nights in
26 (AmnesiaRest, ToxicStall, ChanseyStall, OhkoFish, measured 2026-11-27), so
a regression in one would go unseen. Each case below sets a moveset and the
state its fitness routine reads, runs the classifier and the once-per-turn
selector, and checks both the plan chosen and the directive it issues. The
execute-only branches (a plan already running when its fitness would refuse
it) are called directly.

Expected plans follow from the fitness constants in ai_plans.asm: a case
names the winner, and the losers it must beat are noted beside it.
"""
from pathlib import Path
import re
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]

SLOW, FAST = 50, 300  # enemy speeds either side of the player's 150
PLAYER_SPEED = 150


class AIPlanMatrixTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        cls.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        cls.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        cls.battle = parse_rgbds_constants(ROOT / "constants/battle_constants.asm")
        cls.ai = parse_rgbds_constants(ROOT / "constants/ai_constants.asm")
        # parse_rgbds_constants does not evaluate `1 << n`
        cls.classes = {name: 1 << int(bit) for name, bit in re.findall(
            r"^DEF AICLASS_(\w+)\s+EQU 1 << (\d+)", (ROOT / "constants/ai_constants.asm").read_text(), re.M)}
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

        def mon(name, moves):
            return {"species": cls.species[name], "level": 50,
                    "moves": [cls.moves[move] for move in moves]}

        cls.h.inject_fight2_spec([mon("SNORLAX", ["SPLASH"])], [mon("TAUROS", ["TACKLE"])],
                                 trainer_class=trainers["COOLTRAINER_M"], ai_tier=2)
        cls.h.boot_fight2(seed=1)

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def word(self, label, value):
        self.h.write8(label, value >> 8)
        self.h.write8(label, value & 255, offset=1)

    def cls_mask(self, *names):
        mask = 0
        for name in names:
            mask |= self.classes[name]
        return mask

    def stage(self, moves, *, enemy_speed=SLOW, enemy_hp=None, player_moves=("SPLASH",),
              player_status=0, enemy_sub=False, attack_mod=7, special_mod=7):
        """Write every field a plan's fitness or execute routine reads."""
        h = self.h
        h.park_before_hijack()
        for slot in range(4):
            h.write8("wEnemyMonMoves", self.moves[moves[slot]] if slot < len(moves) else 0, offset=slot)
            h.write8("wEnemyMonPP", 10 if slot < len(moves) else 0, offset=slot)
            h.write8("wBattleMonMoves",
                     self.moves[player_moves[slot]] if slot < len(player_moves) else 0, offset=slot)
        h.write8("wEnemyDisabledMove", 0)
        # Party slot 0 has revealed all four slots, so the AI believes exactly
        # player_moves. Unrevealed slots would be guessed as a STAB move of the
        # player's type (AIGetPlayerMoveN), which can break a Substitute.
        h.write8("wAISeenPlayerMoveMask", 0x0F)
        self.word("wEnemyMonSpeed", enemy_speed)
        self.word("wBattleMonSpeed", PLAYER_SPEED)
        max_hp = 160
        self.word("wEnemyMonMaxHP", max_hp)
        self.word("wEnemyMonHP", max_hp if enemy_hp is None else enemy_hp)
        h.write8("wBattleMonStatus", player_status)
        h.write8("wPlayerBattleStatus2", 0)
        h.write8("wEnemyBattleStatus1", 0)
        h.write8("wEnemyBattleStatus2", (1 << self.battle["HAS_SUBSTITUTE_UP"]) if enemy_sub else 0)
        h.write8("wEnemyMonAttackMod", attack_mod)
        h.write8("wEnemyMonAttackMod", special_mod, offset=3)
        h.write8("wPlayerMonNumber", 0)
        h.write8("wAIPlan", 0)
        h.write8("wAIPlanStep", 0)
        # A real decision starts here. call_routine empties the estimate and KO
        # caches itself; this also empties the setup mask and gate in wBuffer.
        h.call_routine("AIClearDecisionCaches", limit=240)
        h.park_before_hijack()
        h.call_routine("AIClassifyMoveset", limit=240)

    def directive(self, label):
        """Run a routine returning de = class mask, l = magnitude; read both at its return."""
        rf = self.h.pyboy.register_file
        self.h.park_before_hijack()
        return self.h.call_routine(label, limit=2000,
                                   capture=lambda hh: ((rf.D << 8) | rf.E, rf.HL & 0xFF))

    def select(self):
        mask, magnitude = self.directive("AIPlanSelectAndExecute")
        return self.h.read8("wAIPlan"), mask, magnitude

    def assertPlan(self, expected, classes, *, magnitude="AI_VERY_STRONG"):
        plan, mask, strength = self.select()
        self.assertEqual(plan, self.ai[f"AI_PLAN_{expected}"], f"plan {plan}")
        if magnitude is None:
            self.assertEqual(strength, 0)
        else:
            self.assertEqual((mask, strength), (self.cls_mask(*classes), self.ai[magnitude]))

    # --- selection: one case per plan --------------------------------------
    def test_selection_matrix(self):
        cases = [
            # (name, moves, stage kwargs, plan, directive classes, magnitude)
            ("fallback", ["TACKLE"], {}, "BRUISER", (), None),
            # slower: AgilityWrap 40+20 beats WrapLock (needs the enemy faster)
            ("agility wrap", ["AGILITY", "WRAP"], {}, "AGILITY_WRAP", ("BOOST_SPD",), "AI_VERY_STRONG"),
            ("wrap lock", ["WRAP"], {"enemy_speed": FAST}, "WRAP_LOCK", ("TRAP",), "AI_VERY_STRONG"),
            ("sleep lead", ["HYPNOSIS", "TACKLE"], {}, "SLEEP_LEAD", ("SLEEP",), "AI_VERY_STRONG"),
            # AmnesiaRest 60 beats Amnesia 45
            ("amnesia rest", ["AMNESIA", "REST"], {}, "AMNESIA_REST", ("BOOST_SPC",), "AI_VERY_STRONG"),
            ("amnesia rest heals", ["AMNESIA", "REST"], {"enemy_hp": 70}, "AMNESIA_REST",
             ("RECOVERY",), "AI_VERY_STRONG"),
            ("amnesia", ["AMNESIA", "TACKLE"], {}, "AMNESIA", ("BOOST_SPC",), "AI_VERY_STRONG"),
            ("amnesia past +4", ["AMNESIA", "TACKLE"], {"special_mod": 11}, "AMNESIA", (), None),
            ("toxic stall", ["TOXIC", "RECOVER"], {}, "TOXIC_STALL", ("POISON",), "AI_VERY_STRONG"),
            # no damaging move, so ParaSweep (paralyze + damage) does not qualify
            ("chansey stall", ["THUNDER_WAVE", "SOFTBOILED"], {}, "CHANSEY_STALL",
             ("PARALYZE",), "AI_VERY_STRONG"),
            ("para sweep", ["THUNDER_WAVE", "BODY_SLAM"], {}, "PARA_SWEEP", ("PARALYZE",), "AI_VERY_STRONG"),
            ("sub stall", ["SUBSTITUTE", "RECOVER"], {}, "SUB_STALL_REC", ("SUB",), "AI_VERY_STRONG"),
            ("sub stall heals behind it", ["SUBSTITUTE", "RECOVER"], {"enemy_sub": True}, "SUB_STALL_REC",
             ("RECOVERY",), "AI_VERY_STRONG"),
            ("sub poison", ["SUBSTITUTE", "TOXIC"], {"enemy_sub": True}, "SUB_STALL_PSN",
             ("POISON",), "AI_VERY_STRONG"),
            # SubSetup 55+10 beats SwordsDance 35
            ("sub setup", ["SUBSTITUTE", "SWORDS_DANCE"], {}, "SUB_SETUP", ("SUB",), "AI_VERY_STRONG"),
            ("sub setup boosts behind it", ["SUBSTITUTE", "SWORDS_DANCE"], {"enemy_sub": True}, "SUB_SETUP",
             ("BOOST_SPD", "BOOST_ATK", "BOOST_SPC", "BOOST_DEF"), "AI_VERY_STRONG"),
            # under a quarter HP the trade is worth it without a player KO threat
            ("bomb trade", ["EXPLOSION"], {"enemy_hp": 30}, "BOMB_TRADE", ("EXPLODE",), "AI_VERY_STRONG"),
            ("full-HP explosion holds", ["EXPLOSION"], {}, "BRUISER", (), None),
            # losing position (the player KOs a 5 HP enemy) and faster, so Fissure can land
            ("ohko fish", ["FISSURE"], {"enemy_speed": FAST, "enemy_hp": 5, "player_moves": ("BODY_SLAM",)},
             "OHKO_FISH", ("OHKO",), "AI_STRONG"),
            ("ohko slower misses", ["FISSURE"], {"enemy_hp": 5, "player_moves": ("BODY_SLAM",)},
             "BRUISER", (), None),
            ("swords dance", ["SWORDS_DANCE", "TACKLE"], {}, "SWORDS_DANCE", ("BOOST_ATK",), "AI_VERY_STRONG"),
            ("swords dance past +4", ["SWORDS_DANCE", "TACKLE"], {"attack_mod": 11}, "SWORDS_DANCE", (), None),
        ]
        for name, moves, kwargs, plan, classes, magnitude in cases:
            with self.subTest(name):
                self.stage(moves, **kwargs)
                self.assertPlan(plan, classes, magnitude=magnitude)

    # --- execute-only branches: the plan is running, its fitness now refuses --
    def test_stall_plans_heal_once_the_status_has_landed(self):
        poisoned, paralyzed = 1 << 3, 1 << 6
        for name, moves, status, label in [
                ("toxic", ["TOXIC", "RECOVER"], poisoned, "AIRun_ToxicStall"),
                ("chansey", ["THUNDER_WAVE", "SOFTBOILED"], paralyzed, "AIRun_ChanseyStall")]:
            with self.subTest(name, hp="below half"):
                self.stage(moves, player_status=status, enemy_hp=70)
                self.assertEqual(self.directive(label),
                                 (self.cls_mask("RECOVERY"), self.ai["AI_VERY_STRONG"]))
            with self.subTest(name, hp="healthy"):
                self.stage(moves, player_status=status)
                self.assertEqual(self.directive(label)[1], 0)

    def test_status_plans_stop_once_the_status_has_landed(self):
        asleep = 2
        for label, moves in [("AIRun_SleepLead", ["HYPNOSIS", "TACKLE"]),
                             ("AIRun_ParaSweep", ["THUNDER_WAVE", "BODY_SLAM"])]:
            with self.subTest(label):
                self.stage(moves, player_status=asleep)
                self.assertEqual(self.directive(label)[1], 0)

    def test_agility_wrap_traps_once_faster(self):
        self.stage(["AGILITY", "WRAP"], enemy_speed=FAST)
        self.assertEqual(self.directive("AIRun_AgilityWrap"),
                         (self.cls_mask("TRAP"), self.ai["AI_VERY_STRONG"]))


if __name__ == "__main__":
    unittest.main()
