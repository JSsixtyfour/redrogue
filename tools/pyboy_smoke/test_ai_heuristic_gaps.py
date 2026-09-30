"""AI_BACKLOG L5: closes declared gaps in ai_heuristic_manifest.json.

Each test pairs a positive/negative/boundary case against the exact condition
read from source (ai_redundant.asm, ai_smart.asm, ai_risky.asm, ai_threat.asm,
trainer_ai.asm, ai_plans.asm), the same style test_ai_checkpoint_a.py and
test_ai_checkpoint_b.py already use: load a single move (or a small moveset),
call the layer/routine directly, and read the score back from wBuffer (base
20; AIDiscourage adds, AIEncourage subtracts, saturating at 79/1).
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]


class _AIGapsBase(unittest.TestCase):
    """Shared constant tables and WRAM helpers for every class below."""

    def setUp(self):
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.effects = parse_rgbds_constants(ROOT / "constants/move_effect_constants.asm")
        self.battle = parse_rgbds_constants(ROOT / "constants/battle_constants.asm")
        self.types = parse_rgbds_constants(ROOT / "constants/type_constants.asm")
        self.ai = parse_rgbds_constants(ROOT / "constants/ai_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

    def tearDown(self):
        self.h.close()

    def mon(self, name, moves, level=50):
        return {"species": self.species[name], "level": level,
                "moves": [self.moves[m] for m in moves]}

    def word(self, label, value, offset=0):
        self.h.write8(label, value >> 8, offset=offset)
        self.h.write8(label, value & 255, offset=offset + 1)

    def boot(self, player, enemy, trainer="COOLTRAINER_M", tier=2):
        self.h.inject_fight2_spec(player, enemy,
                                  trainer_class=self.trainers[trainer], ai_tier=tier)
        self.h.boot_fight2(seed=1)


class _MoveLayerGapsBase(_AIGapsBase):
    """setUp used by the AI_REDUNDANT/AI_SMART/layer gap classes: a lone
    SNORLAX/SPLASH vs TAUROS/RECOVER pair, matching test_ai_checkpoint_a.py."""

    def setUp(self):
        super().setUp()
        self.boot([self.mon("SNORLAX", ["SPLASH"])],
                  [self.mon("TAUROS", ["RECOVER"])], tier=2)

    def prime_clean(self):
        """Neutral board: every stage neutral (7/BASE_STAT_LEVEL), every
        status/side-condition/disable cleared, Normal/Normal on both sides,
        no Bridge form selected. Mirrors test_ai_checkpoint_a.py's prime_haze
        and test_ai_checkpoint_b.py's select_plan board reset."""
        h = self.h
        h.park_before_hijack()
        for base in ("wPlayerMonAttackMod", "wEnemyMonAttackMod"):
            for i in range(8):
                h.write8(base, 7, offset=i)
        for label in ("wBattleMonStatus", "wEnemyMonStatus",
                      "wPlayerDisabledMove", "wEnemyDisabledMove",
                      "wPlayerBattleStatus1", "wPlayerBattleStatus2", "wPlayerBattleStatus3",
                      "wEnemyBattleStatus1", "wEnemyBattleStatus2", "wEnemyBattleStatus3"):
            h.write8(label, 0)
        h.write8("wBattleMonType1", self.types["NORMAL"])
        h.write8("wBattleMonType2", self.types["NORMAL"])
        h.write8("wEnemyMonType1", self.types["NORMAL"])
        h.write8("wEnemyMonType2", self.types["NORMAL"])
        for offset in range(4):
            h.write8("wBridgeSelectedEffects", 0, offset=offset)
        h.write8("hWhoseTurn", 1)
        h.write8("wLinkState", 0)
        h.write8("wAILastMoveNum", 0)
        h.write8("wAISameMoveCount", 0)
        h.write8("wEnemyMonLevel", 50)
        h.write8("wBattleMonLevel", 50)
        self.word("wEnemyMonHP", 200)
        self.word("wEnemyMonMaxHP", 200)
        self.word("wBattleMonHP", 200)
        self.word("wBattleMonMaxHP", 200)
        self.word("wEnemyMonSpeed", 100)
        self.word("wBattleMonSpeed", 90)
        h.write8("wPlayerSubstituteHP", 0)
        h.write8("wBuffer", 20)

    def load_moveset(self, moves):
        h = self.h
        for slot in range(4):
            h.write8("wEnemyMonMoves",
                     self.moves[moves[slot]] if slot < len(moves) else 0, offset=slot)

    def redundant_score(self, move, writes=None):
        """Score of a lone move from AILayerRedundant: 20 = legal, 79 = heavy
        (AI_REDUNDANT_HEAVY == AI_SATURATE)."""
        self.prime_clean()
        for label, value in (writes or {}).items():
            if isinstance(value, tuple):
                self.word(label, value[0])
            else:
                self.h.write8(label, value)
        self.load_moveset([move])
        self.h.write8("wBuffer", 20)
        self.h.call_routine("AILayerRedundant", limit=120)
        return self.h.read8("wBuffer")

    def smart_score(self, move, writes=None):
        """Score of a lone move from AI_SMART, read before the cross-cutting
        anti-spam/status-accuracy/fatigue rules run (same as
        test_ai_checkpoint_b.py's lone_smart_score)."""
        scores = []
        self.h.hook_flag("AISmartCrossCutting", action=lambda:
                         scores.append(self.h.read8("wBuffer")))
        self.prime_clean()
        for label, value in (writes or {}).items():
            if isinstance(value, tuple):
                self.word(label, value[0])
            else:
                self.h.write8(label, value)
        self.load_moveset([move])
        self.h.write8("wBuffer", 20)
        self.h.call_routine("AILayerSmart", limit=240)
        return scores[-1]


# ===========================================================================
# AI_REDUNDANT handlers (priority 1)
# ===========================================================================
class AIRedundantGapsTest(_MoveLayerGapsBase):
    def test_confusion_effect_already_confused_or_substitute_eliminated(self):
        # AIRedundant_ConfusionEffect: Substitute or already-confused target.
        self.assertEqual(self.redundant_score("CONFUSE_RAY"), 20)
        self.assertEqual(self.redundant_score(
            "CONFUSE_RAY", {"wPlayerBattleStatus1": 1 << self.battle["CONFUSED"]}), 79)
        self.assertEqual(self.redundant_score(
            "CONFUSE_RAY", {"wPlayerBattleStatus2": 1 << self.battle["HAS_SUBSTITUTE_UP"]}), 79)

    def test_disable_already_disabled_eliminated(self):
        self.assertEqual(self.redundant_score("DISABLE"), 20)
        self.assertEqual(self.redundant_score("DISABLE", {"wPlayerDisabledMove": 0x11}), 79)

    def test_focus_energy_already_active_eliminated(self):
        self.assertEqual(self.redundant_score("FOCUS_ENERGY"), 20)
        self.assertEqual(self.redundant_score(
            "FOCUS_ENERGY", {"wEnemyBattleStatus2": 1 << self.battle["GETTING_PUMPED"]}), 79)

    def test_heal_at_max_hp_eliminated_one_below_legal(self):
        # AIRedundant_Heal: eliminated only at exactly max HP.
        self.assertEqual(self.redundant_score(
            "RECOVER", {"wEnemyMonHP": (200,), "wEnemyMonMaxHP": (200,)}), 79)
        self.assertEqual(self.redundant_score(
            "RECOVER", {"wEnemyMonHP": (199,), "wEnemyMonMaxHP": (200,)}), 20)

    def test_leech_seed_grass_seeded_or_substitute_eliminated(self):
        self.assertEqual(self.redundant_score("LEECH_SEED"), 20)
        self.assertEqual(self.redundant_score(
            "LEECH_SEED", {"wBattleMonType1": self.types["GRASS"]}), 79)
        self.assertEqual(self.redundant_score(
            "LEECH_SEED", {"wBattleMonType2": self.types["GRASS"]}), 79)
        self.assertEqual(self.redundant_score(
            "LEECH_SEED", {"wPlayerBattleStatus2": 1 << self.battle["SEEDED"]}), 79)
        self.assertEqual(self.redundant_score(
            "LEECH_SEED", {"wPlayerBattleStatus2": 1 << self.battle["HAS_SUBSTITUTE_UP"]}), 79)

    def test_light_screen_already_up_eliminated(self):
        self.assertEqual(self.redundant_score("LIGHT_SCREEN"), 20)
        self.assertEqual(self.redundant_score(
            "LIGHT_SCREEN", {"wEnemyBattleStatus3": 1 << self.battle["HAS_LIGHT_SCREEN_UP"]}), 79)

    def test_mist_already_up_eliminated(self):
        self.assertEqual(self.redundant_score("MIST"), 20)
        self.assertEqual(self.redundant_score(
            "MIST", {"wEnemyBattleStatus2": 1 << self.battle["PROTECTED_BY_MIST"]}), 79)

    def test_ohko_needs_strictly_faster_equal_speed_eliminated(self):
        # AIRedundant_OHKO: slower or TIED auto-misses (eliminated); only
        # strictly faster keeps it legal.
        self.assertEqual(self.redundant_score(
            "HORN_DRILL", {"wEnemyMonSpeed": (100,), "wBattleMonSpeed": (150,)}), 79)
        self.assertEqual(self.redundant_score(
            "HORN_DRILL", {"wEnemyMonSpeed": (100,), "wBattleMonSpeed": (100,)}), 79)
        self.assertEqual(self.redundant_score(
            "HORN_DRILL", {"wEnemyMonSpeed": (150,), "wBattleMonSpeed": (100,)}), 20)

    def test_poison_blocked_target_eliminated(self):
        self.assertEqual(self.redundant_score("POISONPOWDER"), 20)
        self.assertEqual(self.redundant_score(
            "POISONPOWDER", {"wBattleMonStatus": 1 << self.battle["PAR"]}), 79)
        self.assertEqual(self.redundant_score(
            "POISONPOWDER", {"wBattleMonType1": self.types["POISON"]}), 79)
        self.assertEqual(self.redundant_score(
            "POISONPOWDER", {"wPlayerBattleStatus2": 1 << self.battle["HAS_SUBSTITUTE_UP"]}), 79)

    def test_poison_side_only_substitute_blocks_it(self):
        # AIRedundant_PoisonSide: a Substitute blocks the whole move (heavy);
        # a statused/Poison-type target only blocks the RIDER, not the hit
        # itself (Phase 3 Step 3) - the move stays legal.
        self.assertEqual(self.redundant_score("POISON_STING"), 20)
        self.assertEqual(self.redundant_score(
            "POISON_STING", {"wBattleMonStatus": 1 << self.battle["PAR"]}), 20)
        self.assertEqual(self.redundant_score(
            "POISON_STING", {"wPlayerBattleStatus2": 1 << self.battle["HAS_SUBSTITUTE_UP"]}), 79)

    def test_reflect_already_up_eliminated(self):
        self.assertEqual(self.redundant_score("REFLECT"), 20)
        self.assertEqual(self.redundant_score(
            "REFLECT", {"wEnemyBattleStatus3": 1 << self.battle["HAS_REFLECT_UP"]}), 79)

    def test_stat_down_at_floor_eliminated_above_floor_legal(self):
        # AIRedundant_StatDown (F17): floor is stage 1 (-6); the move targets
        # the PLAYER's stat (Growl lowers the target's Attack).
        self.assertEqual(self.redundant_score(
            "GROWL", {"wPlayerMonAttackMod": 1}), 79)  # exactly -6: boundary
        self.assertEqual(self.redundant_score(
            "GROWL", {"wPlayerMonAttackMod": 2}), 20)  # -5: still legal

    def test_stat_up_at_cap_eliminated(self):
        # AIRedundant_StatUp (F17): cap is stage 13 (+6); Sharpen raises the
        # USER's own Attack.
        self.assertEqual(self.redundant_score(
            "SHARPEN", {"wEnemyMonAttackMod": 13}), 79)  # exactly +6: boundary

    def test_sub_only_family_blocked_only_by_substitute(self):
        # AIRedundant_SubOnly covers flinch/confusion riders and drain.
        self.assertEqual(self.redundant_score("BITE"), 20)
        self.assertEqual(self.redundant_score(
            "BITE", {"wPlayerBattleStatus2": 1 << self.battle["HAS_SUBSTITUTE_UP"]}), 79)

    def test_substitute_quarter_hp_boundary_and_already_up(self):
        # AIRedundant_Substitute: eliminated at or below a quarter HP
        # (4*hp<=maxHP), or if already up. maxHP=100 makes the quarter exact.
        self.assertEqual(self.redundant_score(
            "SUBSTITUTE", {"wEnemyMonHP": (24,), "wEnemyMonMaxHP": (100,)}), 79)
        self.assertEqual(self.redundant_score(
            "SUBSTITUTE", {"wEnemyMonHP": (25,), "wEnemyMonMaxHP": (100,)}), 79)  # boundary
        self.assertEqual(self.redundant_score(
            "SUBSTITUTE", {"wEnemyMonHP": (26,), "wEnemyMonMaxHP": (100,)}), 20)
        self.assertEqual(self.redundant_score(
            "SUBSTITUTE", {"wEnemyMonHP": (200,), "wEnemyMonMaxHP": (200,),
                           "wEnemyBattleStatus2": 1 << self.battle["HAS_SUBSTITUTE_UP"]}), 79)

    def test_burn_freeze_para_side_substitute_is_heavy(self):
        # AIRedundant_BurnFreezeParaSide positive gap: a Substitute blocks the
        # WHOLE move (heavy). The rider-only-blocked negative is already
        # covered (test_ai_personality's blackbelt test).
        self.assertEqual(self.redundant_score(
            "FIRE_PUNCH", {"wPlayerBattleStatus2": 1 << self.battle["HAS_SUBSTITUTE_UP"]}), 79)

    def test_dream_eater_sleeping_target_is_legal(self):
        # AIRedundant_DreamEater negative gap: asleep target is left alone.
        self.assertEqual(self.redundant_score(
            "DREAM_EATER", {"wBattleMonStatus": 1}), 20)


# ===========================================================================
# AI_SMART handlers (priority 2)
# ===========================================================================
class AISmartGapsTest(_MoveLayerGapsBase):
    def test_charge_dig_penalised_less_than_exposed_solarbeam(self):
        # AISmart_Charge/InvulnerableCharge: Dig (invulnerable) loses a turn
        # but dodges the hit (AI_NUDGE=1, 21); Solar Beam is fully exposed
        # (AI_STRONG=2, 22) - neither side is currently stalled.
        dig = self.smart_score("DIG")
        solarbeam = self.smart_score("SOLARBEAM")
        self.assertEqual((dig, solarbeam), (21, 22))
        self.assertLess(dig - 20, solarbeam - 20)

    def test_invulnerable_charge_boosted_back_when_stalling(self):
        # Fly (its own effect id, not shared via Charge's Dig branch).
        self.assertEqual(self.smart_score("FLY"), 21)
        self.assertEqual(self.smart_score(
            "FLY", {"wBattleMonStatus": 1 << self.battle["BRN"]}), 19)  # stalled

    def test_confusion_paralysed_encouraged_low_hp_discouraged(self):
        self.assertEqual(self.smart_score(
            "CONFUSE_RAY", {"wBattleMonStatus": 1 << self.battle["PAR"]}), 18)
        self.assertEqual(self.smart_score(
            "CONFUSE_RAY", {"wBattleMonHP": (50,), "wBattleMonMaxHP": (200,)}), 21)

    def test_confusion_side_bonus_unless_already_confused(self):
        self.assertEqual(self.smart_score("CONFUSION"), 19)
        self.assertEqual(self.smart_score(
            "CONFUSION", {"wPlayerBattleStatus1": 1 << self.battle["CONFUSED"]}), 20)

    def test_drain_hp_damaged_bonus_full_hp_none(self):
        self.assertEqual(self.smart_score(
            "ABSORB", {"wEnemyMonHP": (199,), "wEnemyMonMaxHP": (200,)}), 19)
        self.assertEqual(self.smart_score(
            "ABSORB", {"wEnemyMonHP": (200,), "wEnemyMonMaxHP": (200,)}), 20)

    def test_dream_eater_sleeping_encouraged_awake_left_to_redundant(self):
        self.assertEqual(self.smart_score("DREAM_EATER", {"wBattleMonStatus": 1}), 17)
        self.assertEqual(self.smart_score("DREAM_EATER"), 20)

    def test_evasion_worthwhile_while_stalled_discouraged_otherwise(self):
        self.assertEqual(self.smart_score("DOUBLE_TEAM"), 21)
        self.assertEqual(self.smart_score(
            "DOUBLE_TEAM", {"wBattleMonStatus": 1 << self.battle["BRN"]}), 18)

    def test_flinch_side_bonus_only_when_acting_first(self):
        # Bite is FLINCH_SIDE_EFFECT1 (10%, AI_NUDGE). Acting first requires
        # us faster (Bite is not Quick Attack/Counter).
        self.assertEqual(self.smart_score(
            "BITE", {"wEnemyMonSpeed": (200,), "wBattleMonSpeed": (100,)}), 19)
        self.assertEqual(self.smart_score(
            "BITE", {"wEnemyMonSpeed": (100,), "wBattleMonSpeed": (200,)}), 20)

    def test_heal_hp_bands(self):
        # AISmart_Heal: below quarter encourages, quarter-to-half is neutral,
        # at/above half discourages. maxHP=200 (quarter=50, half=100).
        self.assertEqual(self.smart_score("RECOVER", {"wEnemyMonHP": (40,)}), 18)
        self.assertEqual(self.smart_score("RECOVER", {"wEnemyMonHP": (70,)}), 20)
        self.assertEqual(self.smart_score("RECOVER", {"wEnemyMonHP": (150,)}), 22)

    def test_hyper_beam_healthy_encouraged_low_hp_discouraged(self):
        self.assertEqual(self.smart_score("HYPER_BEAM", {"wEnemyMonHP": (150,)}), 19)
        self.assertEqual(self.smart_score("HYPER_BEAM", {"wEnemyMonHP": (40,)}), 21)

    def test_ohko_level_gate(self):
        # AISmart_OHKO: our level must STRICTLY exceed the target's; equal
        # levels retain OHKO's normal chance (no extra penalty) per the
        # handler's own comment - only a strictly LOWER level is discouraged.
        self.assertEqual(self.smart_score(
            "HORN_DRILL", {"wEnemyMonLevel": 60, "wBattleMonLevel": 50}), 20)
        self.assertEqual(self.smart_score(
            "HORN_DRILL", {"wEnemyMonLevel": 50, "wBattleMonLevel": 50}), 20)  # boundary
        self.assertEqual(self.smart_score(
            "HORN_DRILL", {"wEnemyMonLevel": 40, "wBattleMonLevel": 50}), 30)

    def test_poison_healthy_toxic_encouraged_dying_target_no_bonus(self):
        self.assertEqual(self.smart_score(
            "TOXIC", {"wBattleMonHP": (200,), "wBattleMonMaxHP": (200,)}), 18)
        self.assertEqual(self.smart_score(
            "TOXIC", {"wBattleMonHP": (20,), "wBattleMonMaxHP": (200,)}), 20)

    def test_poison_side_bonus_when_it_can_land_none_when_blocked(self):
        self.assertEqual(self.smart_score("POISON_STING"), 19)
        self.assertEqual(self.smart_score(
            "POISON_STING", {"wBattleMonStatus": 1 << self.battle["PAR"]}), 20)

    def test_screen_healthy_allowed_damaged_discouraged(self):
        self.assertEqual(self.smart_score(
            "LIGHT_SCREEN", {"wEnemyMonHP": (200,), "wEnemyMonMaxHP": (200,)}), 20)
        self.assertEqual(self.smart_score(
            "LIGHT_SCREEN", {"wEnemyMonHP": (199,), "wEnemyMonMaxHP": (200,)}), 21)

    def test_sleep_with_dream_eater_in_moveset_encouraged_more(self):
        # Read the score BEFORE AISmartCrossCutting runs (as smart_score
        # does): Hypnosis is 60% accurate, exactly the status-accuracy
        # cross-cutting rule's threshold for a mild AI_NUDGE discourage, which
        # would otherwise add +1 to both branches here and mask the handler's
        # own effect.
        h = self.h
        scores = []
        h.hook_flag("AISmartCrossCutting", action=lambda: scores.append(h.read8("wBuffer")))
        self.prime_clean()
        self.load_moveset(["HYPNOSIS", "DREAM_EATER"])
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.call_routine("AILayerSmart", limit=240)
        # Two real moves means AISmartCrossCutting fires twice this call (once
        # per slot): scores[-2] is Hypnosis's (slot 0), scores[-1] Dream
        # Eater's own (slot 1, not under test here).
        with_dream_eater = scores[-2]

        self.prime_clean()
        self.load_moveset(["HYPNOSIS"])
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.call_routine("AILayerSmart", limit=240)
        without_dream_eater = scores[-1]

        self.assertEqual((with_dream_eater, without_dream_eater), (18, 20))

    def test_speed_up1_and_speed_down2_have_no_reachable_move(self):
        # AI_BACKLOG B2 gave SpeedDown2/SpeedUp1 their own entry labels
        # sharing SpeedDown1/SpeedUp2's body, but no Gen 1 move in this ROM
        # carries SPEED_DOWN2_EFFECT or SPEED_UP1_EFFECT (confirmed: neither
        # id appears anywhere in data/moves/moves.asm - only SPEED_DOWN1_EFFECT
        # (String Shot) and SPEED_UP2_EFFECT (Agility) are used). AILayerSmart's
        # dispatch table lookup keys on wEnemyMoveEffect immediately after
        # ReadMove repopulates it from real move data, with no hookable seam
        # between that write and the table read to inject a synthetic id, so
        # these two handlers are unreachable from any real battle and
        # untestable without an asm change (out of scope for a tests-only
        # session). Recorded as a permanent gap, not a TODO.
        for effect_name in ("SPEED_DOWN2_EFFECT", "SPEED_UP1_EFFECT"):
            effect_id = self.effects[effect_name]
            found = False
            for line in (ROOT / "data/moves/moves.asm").read_text().splitlines():
                if f", {effect_name},".replace(" ", "") in line.replace(" ", ""):
                    found = True
            self.assertFalse(found, f"{effect_name} is now reachable - un-gap it")

    def test_substitute_above_half_allowed_below_half_discouraged(self):
        self.assertEqual(self.smart_score(
            "SUBSTITUTE", {"wEnemyMonHP": (101,), "wEnemyMonMaxHP": (200,)}), 20)
        self.assertEqual(self.smart_score(
            "SUBSTITUTE", {"wEnemyMonHP": (100,), "wEnemyMonMaxHP": (200,)}), 20)  # exactly half
        self.assertEqual(self.smart_score(
            "SUBSTITUTE", {"wEnemyMonHP": (99,), "wEnemyMonMaxHP": (200,)}), 30)

    def test_trapping_untrapped_allowed_already_trapped_discouraged(self):
        self.assertEqual(self.smart_score("WRAP"), 20)
        self.assertEqual(self.smart_score(
            "WRAP", {"wPlayerBattleStatus1": 1 << self.battle["USING_TRAPPING_MOVE"]}), 21)

    def test_burn_freeze_para_side_blocked_by_type_or_status(self):
        # Boundary gap: the rider cannot land because the move's own type
        # matches one of the target's types (Gen 1's same-type-immunity rule,
        # AISmartParaSideBlocked) even though the target is otherwise
        # unstatused - no bonus at all, contrasted against the positive case
        # (a Normal target, already covered by test_ai_checkpoint_b's B1
        # tests) which does get the rider bonus.
        self.assertEqual(self.smart_score(
            "FIRE_PUNCH", {"wBattleMonType1": self.types["FIRE"]}), 20)

    def test_stat_down_side_blocked_by_substitute_gives_nothing(self):
        self.assertEqual(self.smart_score(
            "BUBBLE", {"wPlayerBattleStatus2": 1 << self.battle["HAS_SUBSTITUTE_UP"]}), 20)

    def test_super_fang_discourages_a_low_hp_target_not_encourages(self):
        # AISmart_SuperFang (Phase 3 Step 3 inversion): below half PLAYER HP
        # it now DISCOURAGES (cannot finish the target off), not encourages.
        self.assertEqual(self.smart_score(
            "SUPER_FANG", {"wBattleMonHP": (50,), "wBattleMonMaxHP": (200,)}), 22)
        self.assertEqual(self.smart_score(
            "SUPER_FANG", {"wBattleMonHP": (200,), "wBattleMonMaxHP": (200,)}), 20)

    def test_paralyze_nearly_dead_target_discouraged_already_faster_no_flip(self):
        self.assertEqual(self.smart_score(
            "THUNDER_WAVE", {"wBattleMonHP": (30,), "wBattleMonMaxHP": (200,)}), 21)
        self.assertEqual(self.smart_score(
            "THUNDER_WAVE", {"wEnemyMonSpeed": (200,), "wBattleMonSpeed": (100,)}), 20)

    def test_explode_hp_bands_low_hp_acceptable_no_substitute(self):
        # AISmart_Explode: AIEnemyHPAtMax checked FIRST (discourage), then
        # AIEnemyHPBelowQuarter (encourage); the band between is untouched.
        # No Substitute up in any of these - that negative is already fully
        # covered (test_low_hp_explosion_into_a_substitute_is_heavily_discouraged
        # / test_explosion_into_a_substitute_whatever_our_hp).
        self.assertEqual(self.smart_score(
            "EXPLOSION", {"wEnemyMonHP": (200,), "wEnemyMonMaxHP": (200,)}), 23)  # at max
        self.assertEqual(self.smart_score(
            "EXPLOSION", {"wEnemyMonHP": (100,), "wEnemyMonMaxHP": (200,)}), 20)  # mid band
        self.assertEqual(self.smart_score(
            "EXPLOSION", {"wEnemyMonHP": (40,), "wEnemyMonMaxHP": (200,)}), 18)  # below quarter


# ===========================================================================
# Item routines (priority 3)
# ===========================================================================
class AIItemGapsTest(_AIGapsBase):
    """ONE boot per test method: boot_fight2 is not reentrant (see
    project_boot_to_lobby_not_reentrant), so every probe helper below is
    called at most once per test - never looped or called twice on the same
    harness instance, even though test_ai_roster.py's near-identical helpers
    superficially look reusable."""

    def probe_use_futile(self, routine, ai_tier, player, enemy, reveal=None):
        self.boot([player], [enemy], tier=ai_tier)
        if reveal is not None:
            self.h.reveal_player_moves(0, reveal, clear=True)
        self.h.write8("wEnemyMonHP", 0, offset=0)
        self.h.write8("wEnemyMonHP", 1, offset=1)
        self.h.call_routine("AIGetTier")
        use = self.h.hook_flag(f"{routine}.use")
        futile = self.h.hook_flag(f"{routine}.futile")
        self.h.probe_routine_until(routine, lambda: bool(use["count"] or futile["count"]))
        return "use" if use["count"] else "futile"

    def test_hyper_potion_skipped_when_futile(self):
        self.assertEqual(self.probe_use_futile(
            "AIUseHyperPotion", 2,
            self.mon("MEWTWO", ["PSYCHIC_M"]), self.mon("RATTATA", ["TACKLE"])), "futile")

    def test_hyper_potion_used_when_it_helps(self):
        self.assertEqual(self.probe_use_futile(
            "AIUseHyperPotion", 2,
            self.mon("SNORLAX", ["SPLASH"]), self.mon("RATTATA", ["TACKLE"]),
            reveal=[0]), "use")

    def test_super_potion_skipped_when_futile(self):
        self.assertEqual(self.probe_use_futile(
            "AIUseSuperPotion", 2,
            self.mon("MEWTWO", ["PSYCHIC_M"]), self.mon("RATTATA", ["TACKLE"])), "futile")

    def test_super_potion_used_when_it_helps(self):
        self.assertEqual(self.probe_use_futile(
            "AIUseSuperPotion", 2,
            self.mon("SNORLAX", ["SPLASH"]), self.mon("RATTATA", ["TACKLE"]),
            reveal=[0]), "use")

    def probe_stat_gate(self, routine, ai_tier, attack_mod, prime_lethal):
        self.boot([self.mon("PIKACHU", ["THUNDERBOLT"])],
                  [self.mon("SNORLAX", ["SPLASH"])], tier=ai_tier)
        self.h.write8("wEnemyMonDefenseMod" if routine == "AIUseXDefend" else
                      "wEnemyMonSpeedMod", attack_mod)
        if prime_lethal:
            max_hi, max_lo = self.h.read_bytes("wEnemyMonMaxHP", 2)
            max_hp = (max_hi << 8) | max_lo
            value = max(1, max_hp * 1 // 20)
            self.h.write8("wEnemyMonHP", value >> 8, offset=0)
            self.h.write8("wEnemyMonHP", value & 0xFF, offset=1)
        self.h.call_routine("AIGetTier")
        proceed = self.h.hook_flag("AIIncreaseStat.proceed")
        maxed = self.h.hook_flag("AIIncreaseStat.maxedOut")
        would_die = self.h.hook_flag("AIIncreaseStat.wouldDie")
        self.h.probe_routine_until(
            routine, lambda: bool(proceed["count"] or maxed["count"] or would_die["count"]))
        if proceed["count"]:
            return "proceed"
        if maxed["count"]:
            return "maxed"
        return "would_die"

    def test_x_defend_idempotence_skips_a_capped_stat(self):
        self.assertEqual(self.probe_stat_gate("AIUseXDefend", 2, 13, False), "maxed")

    def test_x_defend_ko_gate_skips_setup_when_player_would_kill(self):
        self.assertEqual(self.probe_stat_gate("AIUseXDefend", 2, 7, True), "would_die")

    def test_x_defend_normal_case_proceeds(self):
        self.assertEqual(self.probe_stat_gate("AIUseXDefend", 2, 7, False), "proceed")

    def test_x_speed_idempotence_skips_a_capped_stat(self):
        self.assertEqual(self.probe_stat_gate("AIUseXSpeed", 2, 13, False), "maxed")

    def test_x_speed_ko_gate_skips_setup_when_player_would_kill(self):
        self.assertEqual(self.probe_stat_gate("AIUseXSpeed", 2, 7, True), "would_die")

    def test_x_speed_normal_case_proceeds(self):
        self.assertEqual(self.probe_stat_gate("AIUseXSpeed", 2, 7, False), "proceed")

    def test_guard_spec_reaches_the_unconditional_mist_set(self):
        # AIUseGuardSpec has no internal payoff gate (unlike the heal/X
        # items) and no seam before the bit write to probe either: its very
        # first instruction is `call AIPlayRestoringSFX`, which is exactly
        # what every OTHER item routine's `.use` label sits BEFORE (see
        # AIUsePotion) - here there is no such label, so reaching the actual
        # `set PROTECTED_BY_MIST` byte means first running
        # PlaySoundWaitForCurrent, which (confirmed by this probe timing out
        # at its limit rather than completing) blocks on real sound-channel/
        # VBlank timing this harness's hijacked, interrupt-disabled context
        # cannot supply - the same class of routine the module docstring
        # already flags as unreachable by call_routine/probe_routine_until.
        # What IS provable this way: the routine is genuinely DISPATCHED
        # (entry reached), and from there the mist bit follows
        # UNCONDITIONALLY per source - `set PROTECTED_BY_MIST, [hl]` has no
        # preceding branch of any kind, unlike AIUsePotion's `.use`/`.futile`
        # split - so reaching entry is equivalent proof for this routine.
        self.boot([self.mon("PIKACHU", ["THUNDERBOLT"])],
                  [self.mon("SNORLAX", ["SPLASH"])], trainer="GIOVANNI", tier=2)
        self.h.write8("wEnemyBattleStatus2", 0)
        self.h.write8("wAICount", 1)
        self.h.call_routine("AIGetTier")
        entry = self.h.hook_flag("AIUseGuardSpec")
        self.h.probe_routine_until("AIUseGuardSpec", lambda: entry["count"] > 0, limit=120)
        self.assertGreater(entry["count"], 0)

    def test_guard_spec_not_used_when_no_item_uses_remain(self):
        # "Not used twice": once wAICount is spent, TrainerAI's own shared
        # dispatch gate (`ld a,[wAICount] / and a / ret z`) refuses to reach
        # ANY item routine again this turn, GuardSpec included.
        self.boot([self.mon("PIKACHU", ["THUNDERBOLT"])],
                  [self.mon("SNORLAX", ["SPLASH"])], trainer="GIOVANNI", tier=0)
        self.h.write8("wEnemyBattleStatus2", 0)
        self.h.write8("wAICount", 0)
        self.h.park_before_hijack()
        self.h.call_routine("TrainerAI", limit=2000)
        mist_bit = 1 << self.battle["PROTECTED_BY_MIST"]
        self.assertEqual(self.h.read8("wEnemyBattleStatus2") & mist_bit, 0)


# ===========================================================================
# Threat decision (priority 4): custom mons per test, so this class does NOT
# auto-boot in setUp (each test calls self.boot() itself, matching
# test_ai_full_flow.py's pattern) rather than re-booting on top of a fixture
# setUp already established.
# ===========================================================================
class AIThreatDecisionGapsTest(_AIGapsBase):
    def test_heal_would_still_die_rest_survives_recover_does_not(self):
        # AIHealWouldStillDie via AILayerThreat's .checkHeal branch: proves
        # positive (still dies -> discouraged), negative (survives -> left
        # alone) and the Rest-vs-Recover cap boundary in one setup. maxHP=40,
        # HP=1: Recover heals to 21 (half), Rest heals to 40 (full). The
        # player's SEISMIC_TOSS is a fixed hit for exactly the user's level
        # (30) - between the two post-heal totals.
        h = self.h
        self.boot([self.mon("RATTATA", ["SEISMIC_TOSS"], level=30)],
                  [self.mon("TAUROS", ["RECOVER"])], tier=2)
        self.h.reveal_player_moves(0, [0], clear=True)
        for move, expected in (("RECOVER", 30), ("REST", 20)):
            h.park_before_hijack()
            self.word("wEnemyMonMaxHP", 40)
            self.word("wEnemyMonHP", 1)
            h.write8("wEnemyMonMoves", self.moves[move])
            for slot in range(1, 4):
                h.write8("wEnemyMonMoves", 0, offset=slot)
            for slot in range(4):
                h.write8("wBuffer", 20, offset=slot)
            h.write8("wAIPlayerKOCache", self.ai["AI_KO_CACHE_EMPTY"])
            h.call_routine("AILayerThreat", limit=480)
            with self.subTest(move=move):
                self.assertEqual(h.read8("wBuffer"), expected)

    def test_layer_risky_nudges_a_high_crit_move_when_losing(self):
        # AILayerRisky positive: player threatens a KO, enemy's only move is
        # a high-crit-rate move (Karate Chop) that is not itself a guaranteed
        # win (player HP kept high) -> nudged.
        h = self.h
        self.boot([self.mon("RATTATA", ["TACKLE"], level=60)],
                  [self.mon("TAUROS", ["KARATE_CHOP"])], tier=2)
        h.reveal_player_moves(0, [0], clear=True)
        h.park_before_hijack()
        self.word("wEnemyMonHP", 1)
        self.word("wEnemyMonMaxHP", 200)
        self.word("wBattleMonHP", 999)
        self.word("wBattleMonMaxHP", 999)
        h.write8("wEnemyMonMoves", self.moves["KARATE_CHOP"])
        for slot in range(1, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.write8("wAIPlayerKOCache", self.ai["AI_KO_CACHE_EMPTY"])
        h.call_routine("AILayerRisky", limit=480)
        self.assertEqual(h.read8("wBuffer"), 19)

    def test_layer_risky_silent_with_a_guaranteed_win_of_our_own(self):
        # Negative: even under a KO threat, if the moveset ALSO holds an
        # already-guaranteed win (faster + reliable kill), RISKY returns
        # before its loop and touches nothing.
        h = self.h
        self.boot([self.mon("RATTATA", ["TACKLE"], level=60)],
                  [self.mon("TAUROS", ["TACKLE", "KARATE_CHOP"])], tier=2)
        h.reveal_player_moves(0, [0], clear=True)
        h.park_before_hijack()
        self.word("wEnemyMonHP", 1)
        self.word("wEnemyMonMaxHP", 200)
        self.word("wBattleMonHP", 1)
        self.word("wBattleMonMaxHP", 200)
        self.word("wEnemyMonSpeed", 200)
        self.word("wBattleMonSpeed", 100)
        h.write8("wEnemyMonMoves", self.moves["TACKLE"])
        h.write8("wEnemyMonMoves", self.moves["KARATE_CHOP"], offset=1)
        for slot in range(2, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.write8("wAIPlayerKOCache", self.ai["AI_KO_CACHE_EMPTY"])
        h.call_routine("AILayerRisky", limit=480)
        self.assertEqual(list(h.read_bytes("wBuffer", 4)), [20, 20, 20, 20])

    def test_layer_risky_graded_ladder_ohko_outranks_ordinary_risky(self):
        # Boundary (F15): OHKO gets AI_STRONG(2)=>18, an ordinary powerful-
        # but-unreliable/high-crit move only AI_NUDGE(1)=>19. Player HP kept
        # high so neither move is itself a "guaranteed win" that would
        # silence the whole layer (OHKO's own damage estimate is always 0 by
        # design, so it never trips that scan regardless).
        h = self.h
        self.boot([self.mon("RATTATA", ["TACKLE"], level=60)],
                  [self.mon("TAUROS", ["HORN_DRILL", "KARATE_CHOP"])], tier=2)
        h.reveal_player_moves(0, [0], clear=True)
        h.park_before_hijack()
        self.word("wEnemyMonHP", 1)
        self.word("wEnemyMonMaxHP", 200)
        self.word("wBattleMonHP", 999)
        self.word("wBattleMonMaxHP", 999)
        h.write8("wEnemyMonMoves", self.moves["HORN_DRILL"])
        h.write8("wEnemyMonMoves", self.moves["KARATE_CHOP"], offset=1)
        for slot in range(2, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.write8("wAIPlayerKOCache", self.ai["AI_KO_CACHE_EMPTY"])
        h.call_routine("AILayerRisky", limit=480)
        horn_drill, karate_chop = h.read8("wBuffer"), h.read8("wBuffer", 1)
        self.assertEqual((horn_drill, karate_chop), (18, 19))

    def threat_layer_score(self, moves, writes=None):
        h = self.h
        self.boot([self.mon("RATTATA", ["TACKLE"], level=60)],
                  [self.mon("TAUROS", moves)], tier=2)
        h.reveal_player_moves(0, [0], clear=True)
        h.park_before_hijack()
        self.word("wEnemyMonHP", 1)
        self.word("wEnemyMonMaxHP", 200)
        self.word("wBattleMonHP", 5)
        self.word("wBattleMonMaxHP", 200)
        self.word("wEnemyMonSpeed", 90)
        self.word("wBattleMonSpeed", 100)
        for label, value in (writes or {}).items():
            if isinstance(value, tuple):
                self.word(label, value[0])
            else:
                h.write8(label, value)
        for slot in range(4):
            h.write8("wEnemyMonMoves",
                     self.moves[moves[slot]] if slot < len(moves) else 0, offset=slot)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.write8("wAIPlayerKOCache", self.ai["AI_KO_CACHE_EMPTY"])
        h.call_routine("AILayerThreat", limit=480)
        return list(h.read_bytes("wBuffer", 4))

    def test_layer_threat_discourages_investment_encourages_priority_kill(self):
        # Positive: under a KO threat, FOCUS_ENERGY (investment) is heavily
        # discouraged; QUICK_ATTACK, which beats raw Speed's "we lose the
        # race" verdict (enemy 90 < player 100) and reaches a 5-HP player
        # (max roll), is encouraged as the priority-kill rescue.
        scores = self.threat_layer_score(["FOCUS_ENERGY", "QUICK_ATTACK"])
        self.assertEqual(scores[:2], [30, 18])

    def test_layer_threat_silent_with_no_ko_threat(self):
        # Negative: player's only move is SPLASH (0 power) - no threat, so
        # AIPlayerWouldKO is false and the layer returns before touching
        # anything, including an investment move that would otherwise be hit
        # hard.
        h = self.h
        self.boot([self.mon("SNORLAX", ["SPLASH"])],
                  [self.mon("TAUROS", ["FOCUS_ENERGY"])], tier=2)
        h.park_before_hijack()
        self.word("wEnemyMonHP", 200)
        self.word("wEnemyMonMaxHP", 200)
        h.write8("wEnemyMonMoves", self.moves["FOCUS_ENERGY"])
        for slot in range(1, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.write8("wAIPlayerKOCache", self.ai["AI_KO_CACHE_EMPTY"])
        h.call_routine("AILayerThreat", limit=480)
        self.assertEqual(list(h.read_bytes("wBuffer", 4)), [20, 20, 20, 20])

    def test_layer_threat_disabling_status_bonus_when_acting_first(self):
        # Boundary: Hypnosis (SLEEP_EFFECT, a disabling status per
        # AIIsDisablingStatus) only earns the encouragement if the enemy acts
        # FIRST with it (AIEnemyActsFirstWith, which falls back to raw Speed
        # for a non-priority move like Hypnosis). One boot per test method
        # (boot_fight2 is not reentrant): the "acts second" half is its own
        # test right below.
        scores = self.threat_layer_score(
            ["HYPNOSIS"], {"wEnemyMonSpeed": (200,), "wBattleMonSpeed": (100,)})
        self.assertEqual(scores[0], 18)

    def test_layer_threat_disabling_status_no_bonus_when_acting_second(self):
        scores = self.threat_layer_score(
            ["HYPNOSIS"], {"wEnemyMonSpeed": (90,), "wBattleMonSpeed": (100,)})
        self.assertEqual(scores[0], 20)


# ===========================================================================
# Remaining vanilla-derived scoring layers (priority 5): default single-mon
# boot from _MoveLayerGapsBase, same as the AI_REDUNDANT/AI_SMART classes.
# ===========================================================================
class AILayerGapsTest(_MoveLayerGapsBase):
    def test_move_choice_modification1_status_move_into_statused_target(self):
        # AIMoveChoiceModification1 (AI_BASIC): discourages a pure status move
        # only when the player already has a status; silent on a healthy one.
        h = self.h
        self.prime_clean()
        h.write8("wBattleMonStatus", 1 << self.battle["PAR"])
        self.load_moveset(["HYPNOSIS"])
        h.write8("wBuffer", 20)
        h.call_routine("AIMoveChoiceModification1", limit=120)
        statused = h.read8("wBuffer")

        self.prime_clean()
        self.load_moveset(["HYPNOSIS"])
        h.write8("wBuffer", 20)
        h.call_routine("AIMoveChoiceModification1", limit=120)
        healthy = h.read8("wBuffer")

        self.assertEqual((statused, healthy), (30, 20))

    def test_move_choice_modification2_no_encouragement_after_first_turn(self):
        # AIMoveChoiceModification2 (AI_SETUP) negative gap: fires only on the
        # send-out's first action (wAILayer2Encouragement == 0).
        h = self.h
        self.prime_clean()
        h.write8("wAILayer2Encouragement", 1)
        self.load_moveset(["SWORDS_DANCE"])
        h.write8("wBuffer", 20)
        h.call_routine("AIMoveChoiceModification2", limit=120)
        self.assertEqual(h.read8("wBuffer"), 20)

    def test_move_choice_modification3_effectiveness_scoring(self):
        # AIMoveChoiceModification3 (AI_TYPES): super-effective is encouraged;
        # a resisted move is discouraged only while a better damaging option
        # exists (boundary: the last damaging option is left alone).
        h = self.h
        self.prime_clean()
        h.write8("wBattleMonType1", self.types["WATER"])
        h.write8("wBattleMonType2", self.types["WATER"])
        self.load_moveset(["THUNDERBOLT"])
        h.write8("wBuffer", 20)
        h.call_routine("AIMoveChoiceModification3", limit=120)
        super_effective = h.read8("wBuffer")

        self.prime_clean()
        h.write8("wBattleMonType1", self.types["WATER"])
        h.write8("wBattleMonType2", self.types["WATER"])
        self.load_moveset(["WATER_GUN", "TACKLE"])
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.call_routine("AIMoveChoiceModification3", limit=120)
        resisted_with_alternative = h.read8("wBuffer")

        self.prime_clean()
        h.write8("wBattleMonType1", self.types["WATER"])
        h.write8("wBattleMonType2", self.types["WATER"])
        self.load_moveset(["WATER_GUN"])
        h.write8("wBuffer", 20)
        h.call_routine("AIMoveChoiceModification3", limit=120)
        resisted_last_option = h.read8("wBuffer")

        self.assertEqual(
            (super_effective, resisted_with_alternative, resisted_last_option),
            (19, 21, 20))


# ===========================================================================
# Plans (priority 6)
# ===========================================================================
class AIPlanGapsTest(_AIGapsBase):
    def setUp(self):
        super().setUp()
        # Slot 1 (TACKLE) stays unrevealed for every test except OhkoFish,
        # which reveals it to force a genuine AIPlayerWouldKO threat - every
        # other plan's fitness gate wants that to be FALSE, and an unrevealed
        # real move falls back to the same Normal-type guess SPLASH alone
        # would give (both mons here are Normal-type), so adding the slot
        # does not change any other test's board.
        self.boot([self.mon("SNORLAX", ["SPLASH", "TACKLE"])],
                  [self.mon("TAUROS", ["TACKLE"])], tier=2)

    def select_plan(self, moves, player_types=None, enemy_speed=200, player_speed=100,
                    enemy_hp=(200, 200), writes=None, attack_mod=7, special_mod=7):
        h = self.h
        h.park_before_hijack()
        for slot in range(4):
            move = self.moves[moves[slot]] if slot < len(moves) else 0
            h.write8("wEnemyMonMoves", move, offset=slot)
        h.call_routine("AIClassifyMoveset", limit=240)

        types = player_types or (self.types["NORMAL"], self.types["NORMAL"])
        h.write8("wBattleMonType1", types[0])
        h.write8("wBattleMonType2", types[1])
        h.write8("wEnemyMonAttackMod", attack_mod)
        h.write8("wEnemyMonAttackMod", special_mod, offset=3)  # Special mod
        self.word_word("wEnemyMonSpeed", enemy_speed)
        self.word_word("wBattleMonSpeed", player_speed)
        self.word_word("wEnemyMonHP", enemy_hp[0])
        self.word_word("wEnemyMonMaxHP", enemy_hp[1])
        for label in (
            "wBattleMonStatus", "wPlayerBattleStatus1", "wPlayerBattleStatus2",
            "wPlayerBattleStatus3", "wEnemyBattleStatus1", "wEnemyBattleStatus2",
            "wEnemyBattleStatus3", "wEnemyDisabledMove", "wAIPlan", "wAIPlanStep",
        ):
            h.write8(label, 0)
        h.write8("hWhoseTurn", 1)
        h.write8("wLinkState", 0)
        h.write8("wPlayerMonNumber", 0)
        for offset in range(4):
            h.write8("wBridgeSelectedEffects", 0, offset=offset)
        for label, value in (writes or {}).items():
            if isinstance(value, tuple):
                self.word_word(label, value[0])
            else:
                h.write8(label, value)
        h.call_routine("AIPlanSelect", limit=480)
        return h.read8("wAIPlan")

    def word_word(self, label, value):
        self.h.write8(label, value >> 8)
        self.h.write8(label, value & 255, offset=1)

    def test_bruiser_qualifies_when_nothing_else_does_never_outranks_a_real_plan(self):
        # Positive: only a plain damaging move -> no other plan's required
        # class mask is satisfied -> Bruiser (id 1) is the sole qualifier.
        self.assertEqual(self.select_plan(["TACKLE"]), self.ai["AI_PLAN_BRUISER"])
        # Negative: the same board but with a real plan's moveset qualifies
        # for something other than Bruiser.
        self.assertEqual(self.select_plan(["WRAP"]), self.ai["AI_PLAN_WRAP_LOCK"])

    def test_amnesia_rest_qualifies_stops_when_pointless(self):
        self.assertEqual(
            self.select_plan(["AMNESIA", "RECOVER"]), self.ai["AI_PLAN_AMNESIA_REST"])
        # Negative: Special mod already at the Gen 1 cap -> fitness returns 0,
        # and no other plan's class mask is satisfied, so Bruiser wins.
        self.assertEqual(
            self.select_plan(["AMNESIA", "RECOVER"], special_mod=13),
            self.ai["AI_PLAN_BRUISER"])

    def test_amnesia_alone_qualifies_with_the_boost(self):
        self.assertEqual(self.select_plan(["AMNESIA"]), self.ai["AI_PLAN_AMNESIA"])

    def test_chansey_stall_qualifies_against_a_paralysable_target(self):
        self.assertEqual(
            self.select_plan(["THUNDER_WAVE", "RECOVER"]), self.ai["AI_PLAN_CHANSEY_STALL"])

    def test_toxic_stall_qualifies_against_a_poisonable_target(self):
        self.assertEqual(
            self.select_plan(["TOXIC", "RECOVER"]), self.ai["AI_PLAN_TOXIC_STALL"])

    def test_agility_wrap_qualifies_with_both_moves_and_room_to_work(self):
        self.assertEqual(
            self.select_plan(["AGILITY", "WRAP"]), self.ai["AI_PLAN_AGILITY_WRAP"])

    def test_sub_stall_qualifies_with_substitute_and_a_rider(self):
        self.assertEqual(
            self.select_plan(["SUBSTITUTE", "RECOVER"], enemy_hp=(999, 999)),
            self.ai["AI_PLAN_SUB_STALL_REC"])
        self.assertEqual(
            self.select_plan(["SUBSTITUTE", "TOXIC"], enemy_hp=(999, 999)),
            self.ai["AI_PLAN_SUB_STALL_PSN"])

    def test_sub_stall_does_not_run_when_enemy_is_already_low(self):
        # AIFit_SubStall refuses when the ENEMY's own HP is already below
        # half. maxHP 999 keeps the sub (maxHP/4) out of the guessed attack's
        # reach, isolating this gate from AISubWouldSurvive's.
        self.assertNotEqual(
            self.select_plan(["SUBSTITUTE", "RECOVER"], enemy_hp=(400, 999)),
            self.ai["AI_PLAN_SUB_STALL_REC"])

    def test_sub_plans_do_not_run_when_the_sub_would_not_survive(self):
        # Sub HP = 200/4 = 50, inside the guessed Normal attack's reach, so
        # AISubWouldSurvive is false. Regression: the exit after that farcall
        # was a bare `ret nc`, returning the farcall's leftover a as fitness,
        # and the plan was selected anyway (fixed 2026-09-30, L5).
        self.assertNotEqual(
            self.select_plan(["SUBSTITUTE", "RECOVER"], enemy_hp=(200, 200)),
            self.ai["AI_PLAN_SUB_STALL_REC"])
        self.assertNotEqual(
            self.select_plan(["SUBSTITUTE", "SWORDS_DANCE"], enemy_hp=(200, 200)),
            self.ai["AI_PLAN_SUB_SETUP"])

    def test_sub_setup_qualifies_with_a_boost_no_boost_class_does_not_run(self):
        self.assertEqual(
            self.select_plan(["SUBSTITUTE", "SWORDS_DANCE"], enemy_hp=(999, 999)),
            self.ai["AI_PLAN_SUB_SETUP"])
        # Negative: Substitute + Recover has no boost class, so SubSetup's
        # fitness returns 0 and SubStall (which DOES want that pairing) wins.
        self.assertEqual(
            self.select_plan(["SUBSTITUTE", "RECOVER"], enemy_hp=(999, 999)),
            self.ai["AI_PLAN_SUB_STALL_REC"])

    def test_bomb_trade_qualifies_when_favourable_not_into_a_substitute(self):
        # Favourable: our own HP is below a quarter, so the trade is coming
        # regardless (AIFit_BombTrade's .worthIt path).
        self.assertEqual(
            self.select_plan(["EXPLOSION"], enemy_hp=(40, 200)), self.ai["AI_PLAN_BOMB_TRADE"])
        # Negative: the player has a Substitute up - the trade is a straight
        # loss (ExplodeEffect zeroes the user's HP unconditionally here).
        self.assertNotEqual(
            self.select_plan(["EXPLOSION"], enemy_hp=(40, 200),
                             writes={"wPlayerBattleStatus2":
                                     1 << self.battle["HAS_SUBSTITUTE_UP"]}),
            self.ai["AI_PLAN_BOMB_TRADE"])

    def test_ohko_fish_runs_only_when_losing_and_faster(self):
        # AIFit_OhkoFish unconditionally requires AIPlayerWouldKO, with no
        # alternate path (unlike BombTrade's HP-below-quarter bypass), so
        # this needs a REVEALED, real damaging player move, not the type
        # guess an unrevealed slot would fall back to.
        #
        # Negative: slower means the OHKO auto-misses, so the plan must not
        # run. Regression: the exits after AIPlayerWouldKO/AIEnemyIsFaster were
        # bare `ret nc`s returning the farcall's leftover a as fitness, and
        # the plan was selected when slower too (fixed 2026-09-30, L5).
        self.h.reveal_player_moves(0, [1], clear=True)
        self.assertEqual(
            self.select_plan(["HORN_DRILL"], enemy_hp=(1, 200), enemy_speed=200,
                             player_speed=100), self.ai["AI_PLAN_OHKO_FISH"])
        self.assertNotEqual(
            self.select_plan(["HORN_DRILL"], enemy_hp=(1, 200), enemy_speed=100,
                             player_speed=200), self.ai["AI_PLAN_OHKO_FISH"])

    def test_swords_dance_qualifies_stops_boosting_when_sufficient(self):
        self.assertEqual(
            self.select_plan(["SWORDS_DANCE", "TACKLE"]), self.ai["AI_PLAN_SWORDS_DANCE"])
        # Negative (execute-level): once Attack is at AI_STAT_MOD_STOP (+4,
        # stage 11) AIRun_SwordsDance issues no directive at all, even though
        # the plan is still SELECTED (fitness only caps at stage 13). Observe
        # this through AILayerPlan, which applies the directive to wBuffer.
        h = self.h
        h.park_before_hijack()
        h.write8("wEnemyMonMoves", self.moves["SWORDS_DANCE"])
        h.write8("wEnemyMonMoves", self.moves["TACKLE"], offset=1)
        for slot in range(2, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.write8("wBattleMonType1", self.types["NORMAL"])
        h.write8("wBattleMonType2", self.types["NORMAL"])
        h.write8("wEnemyMonAttackMod", 11)  # AI_STAT_MOD_STOP
        self.word_word("wEnemyMonSpeed", 200)
        self.word_word("wBattleMonSpeed", 100)
        self.word_word("wEnemyMonHP", 200)
        self.word_word("wEnemyMonMaxHP", 200)
        for label in (
            "wBattleMonStatus", "wPlayerBattleStatus1", "wPlayerBattleStatus2",
            "wPlayerBattleStatus3", "wEnemyBattleStatus1", "wEnemyBattleStatus2",
            "wEnemyBattleStatus3", "wEnemyDisabledMove", "wAIPlan", "wAIPlanStep",
            "wTrainerClass",
        ):
            h.write8(label, self.trainers["COOLTRAINER_M"] if label == "wTrainerClass" else 0)
        h.write8("hWhoseTurn", 1)
        h.write8("wLinkState", 0)
        h.write8("wPlayerMonNumber", 0)
        for offset in range(4):
            h.write8("wBridgeSelectedEffects", 0, offset=offset)
        h.call_routine("AILayerPlan", limit=600)
        self.assertEqual(list(h.read_bytes("wBuffer", 4)), [20, 20, 20, 20])


if __name__ == "__main__":
    unittest.main()
