"""AI_THREAT's paralysis bonus reads the enemy's best hit THIS turn.

AIIsDisablingStatus encourages Thunder Wave (PARALYZE_EFFECT) on a threatened,
acting-first T3 mon only when no move it can use this turn is expected to take
40% of the player's current HP. AI_DAMAGE's best-damage record ranks a two-turn
move at half its hit, which is right for ranking but wrong here: Solar Beam deals
nothing this turn, so a mon whose only real attack is Solar Beam has no hit and
should still paralyse (AI_REVIEW_OPUS_HANDOFF_2026-11-21, section 1).

Each test runs the real AILayerDamage (it fills the per-slot damage the check
reads) and then AILayerThreat, and reads the Thunder Wave score on both sides of
AI_THREAT. AI_STRONG (2) is the bonus. The KO threat is forced through
wAIPlayerKOCache, the one-decision cache AIPlayerWouldKO answers from.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]


class AIParalysisThresholdTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.battle = parse_rgbds_constants(ROOT / "constants/battle_constants.asm")
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

    def read_word(self, label, offset=0):
        hi, lo = self.h.read_bytes(label, 2, offset=offset)
        return hi << 8 | lo

    def boot(self, player, enemy):
        self.h.inject_fight2_spec([player], [enemy],
                                  trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3)
        self.h.boot_fight2(seed=1)
        self.h.reveal_player_moves(0, [0], clear=True)

    def run_layers(self, moves, *, player_hp=100, pp=None, disabled=0, substitute=0,
                   slot_damage=None):
        """Score `moves` (slot 0 is the status move under test) through AI_DAMAGE
        then AI_THREAT. Returns (score after DAMAGE, score after THREAT, info).
        slot_damage, if given, overwrites AI_BUF_SLOTDMG between the layers."""
        h = self.h
        h.park_before_hijack()
        h.call_routine("AIClearDecisionCaches", limit=60)
        self.word("wBattleMonHP", player_hp)
        self.word("wBattleMonMaxHP", max(player_hp, 100))
        self.word("wEnemyMonHP", 10)
        self.word("wEnemyMonMaxHP", 200)
        self.word("wEnemyMonSpeed", 200)  # acts first: the bonus is reachable
        self.word("wBattleMonSpeed", 50)
        for label in ("wBattleMonStatus", "wEnemyMonStatus", "wPlayerBattleStatus1",
                      "wPlayerBattleStatus3", "wEnemyBattleStatus1", "wEnemyBattleStatus2",
                      "wEnemyBattleStatus3"):
            h.write8(label, 0)
        sub_bit = 1 << self.battle["HAS_SUBSTITUTE_UP"]
        h.write8("wPlayerBattleStatus2", sub_bit if substitute else 0)
        h.write8("wPlayerSubstituteHP", substitute)
        h.write8("wEnemyDisabledMove", disabled)
        for slot in range(4):
            h.write8("wEnemyMonMoves",
                     self.moves[moves[slot]] if slot < len(moves) else 0, offset=slot)
            h.write8("wEnemyMonPP", 15 if pp is None else pp[slot], offset=slot)
            h.write8("wBuffer", 20, offset=slot)
        h.write8("wAIPlayerKOCache", self.ai["AI_KO_CACHE_YES"])
        h.call_routine("AILayerDamage", limit=480)
        info = {
            "bestdmg": self.read_word("wBuffer", self.ai["AI_BUF_BESTDMG"]),
            "slotdmg": [self.read_word("wBuffer", self.ai["AI_BUF_SLOTDMG"] + 2 * s)
                        for s in range(4)],
        }
        if slot_damage is not None:
            for slot, value in enumerate(slot_damage):
                self.word("wBuffer", value, offset=self.ai["AI_BUF_SLOTDMG"] + 2 * slot)
        before = h.read8("wBuffer")
        h.write8("wAIPlayerKOCache", self.ai["AI_KO_CACHE_YES"])
        # In play both layers run inside one decision, so AI_THREAT sees the
        # estimate cache AI_DAMAGE filled (the Explosion check reads it). Each
        # call_routine is a fresh decision and empties that cache at entry, so
        # put AI_DAMAGE's estimates back as AI_THREAT starts.
        cache = h.read_bytes("wAIEnemyEstimateCache", 8)

        def restore(_context):
            for offset, value in enumerate(cache):
                h.write8("wAIEnemyEstimateCache", value, offset=offset)

        h.register_hook("AILayerThreat", restore)
        try:
            h.call_routine("AILayerThreat", limit=480)
        finally:
            h.unregister_hook("AILayerThreat", restore)
        after = h.read8("wBuffer")
        return before, after, info

    def bonus(self, before, after):
        return before - after

    def test_solar_beam_is_no_hit_this_turn(self):
        # Electabuzz's Solar Beam into a slow Water type: its half-ranked
        # expected hit clears 40% of 100 HP, but it deals nothing this turn.
        self.boot(self.mon("SLOWBRO", ["TACKLE"], level=20),
                  self.mon("ELECTABUZZ", ["THUNDER_WAVE", "SOLARBEAM"], level=60))
        before, after, info = self.run_layers(["THUNDER_WAVE", "SOLARBEAM"])
        # Precondition: the old input (best-damage record) says "real hit".
        self.assertGreaterEqual(5 * info["bestdmg"], 2 * 100, info)
        self.assertEqual(info["slotdmg"][1], 0, info)  # two-turn: 0 this turn
        self.assertEqual(self.bonus(before, after), self.ai["AI_STRONG"], info)

    def test_threshold_boundary_39_keeps_bonus_40_withholds(self):
        self.boot(self.mon("SLOWBRO", ["TACKLE"], level=20),
                  self.mon("ELECTABUZZ", ["THUNDER_WAVE", "SOLARBEAM", "TACKLE"], level=60))
        moves = ["THUNDER_WAVE", "SOLARBEAM", "TACKLE"]
        for value, expected in ((39, self.ai["AI_STRONG"]), (40, 0)):
            before, after, info = self.run_layers(moves, slot_damage=[0, 0, value, 0])
            with self.subTest(immediate=value):
                self.assertEqual(self.bonus(before, after), expected, info)

    def test_legal_explosion_counts_as_a_hit(self):
        self.boot(self.mon("SLOWBRO", ["TACKLE"], level=20),
                  self.mon("ELECTRODE", ["THUNDER_WAVE", "EXPLOSION"], level=60))
        before, after, info = self.run_layers(["THUNDER_WAVE", "EXPLOSION"])
        self.assertEqual(info["slotdmg"][1], 0, info)  # PP-conservation zero
        self.assertEqual(self.bonus(before, after), 0, info)

    def test_explosion_into_a_substitute_is_no_hit(self):
        # Behind a Substitute the trade policy vetoes every blast.
        self.boot(self.mon("SLOWBRO", ["TACKLE"], level=20),
                  self.mon("ELECTRODE", ["THUNDER_WAVE", "EXPLOSION"], level=60))
        before, after, info = self.run_layers(["THUNDER_WAVE", "EXPLOSION"], substitute=30)
        self.assertEqual(self.bonus(before, after), self.ai["AI_STRONG"], info)

    def test_explosion_out_of_pp_is_no_hit(self):
        self.boot(self.mon("SLOWBRO", ["TACKLE"], level=20),
                  self.mon("ELECTRODE", ["THUNDER_WAVE", "EXPLOSION"], level=60))
        before, after, info = self.run_layers(["THUNDER_WAVE", "EXPLOSION"], pp=[15, 0, 0, 0])
        self.assertEqual(self.bonus(before, after), self.ai["AI_STRONG"], info)

    def test_attack_at_zero_pp_is_no_hit(self):
        self.boot(self.mon("OCTILLERY", ["TACKLE"], level=40),
                  self.mon("ELECTABUZZ", ["THUNDER_WAVE", "THUNDERPUNCH"], level=60))
        before, after, info = self.run_layers(["THUNDER_WAVE", "THUNDERPUNCH"], pp=[15, 0, 0, 0])
        self.assertEqual(self.bonus(before, after), self.ai["AI_STRONG"], info)

    def test_disabled_attack_is_no_hit(self):
        self.boot(self.mon("OCTILLERY", ["TACKLE"], level=40),
                  self.mon("ELECTABUZZ", ["THUNDER_WAVE", "THUNDERPUNCH"], level=60))
        # high nybble = disabled slot 1-4, low nybble = turns left
        before, after, info = self.run_layers(["THUNDER_WAVE", "THUNDERPUNCH"], disabled=0x23)
        self.assertEqual(self.bonus(before, after), self.ai["AI_STRONG"], info)

    def test_strong_thunderpunch_still_withholds_the_bonus(self):
        # The original Everdrive position's shape: a ThunderPunch worth well
        # over 40% of Octillery's HP keeps Electabuzz attacking.
        self.boot(self.mon("OCTILLERY", ["TACKLE"], level=40),
                  self.mon("ELECTABUZZ", ["THUNDER_WAVE", "THUNDERPUNCH"], level=60))
        before, after, info = self.run_layers(["THUNDER_WAVE", "THUNDERPUNCH"], player_hp=72)
        self.assertGreaterEqual(5 * info["slotdmg"][1], 2 * 72, info)
        self.assertEqual(self.bonus(before, after), 0, info)

    def test_full_decision_solar_beam_user_paralyses(self):
        # The same board through one real decision (AIEnemyTrainerChooseMoves,
        # every T3 layer, the KO threat computed for real): the per-slot damage
        # the check reads must still be AI_DAMAGE's when AI_THREAT runs.
        h = self.h
        self.boot(self.mon("SLOWBRO", ["TACKLE"], level=20),
                  self.mon("ELECTABUZZ", ["THUNDER_WAVE", "SOLARBEAM"], level=60))
        seen = {}

        def at_threat(_context):
            seen["threat_in"] = h.read8("wBuffer")

        def at_check(_context):
            seen["slotdmg"] = [self.read_word("wBuffer", self.ai["AI_BUF_SLOTDMG"] + 2 * s)
                               for s in range(4)]
            seen["bestdmg"] = self.read_word("wBuffer", self.ai["AI_BUF_BESTDMG"])

        def at_plan(_context):
            seen.setdefault("threat_out", h.read8("wBuffer"))

        h.park_before_hijack()
        h.write8("wAILayer2Encouragement", 2)
        self.word("wEnemyMonHP", 1)  # the player's Tackle KOs: AI_THREAT is live
        for slot in range(4):
            h.write8("wEnemyMonPP", 15 if slot < 2 else 0, offset=slot)
        hooks = (("AILayerThreat", at_threat), ("AIImmediateHitUnder40Pct", at_check),
                 ("AILayerPlan", at_plan))
        for label, callback in hooks:
            h.register_hook(label, callback)
        try:
            h.call_routine("AIEnemyTrainerChooseMoves", limit=12000)
        finally:
            for label, callback in hooks:
                h.unregister_hook(label, callback)
        hp = self.read_word("wBattleMonHP")
        self.assertIn("slotdmg", seen, seen)  # the paralysis check ran
        self.assertEqual(seen["slotdmg"][1], 0, seen)
        self.assertGreaterEqual(5 * seen["bestdmg"], 2 * hp, seen)  # old input: "a hit"
        self.assertEqual(seen["threat_in"] - seen["threat_out"], self.ai["AI_STRONG"], seen)

    def test_full_decision_threatened_blaster_explodes(self):
        # A mon about to be KO'd with Thunder Wave and Explosion trades itself: the
        # blast must win the whole decision, not just keep Thunder Wave from a bonus.
        # Closest measured margin (2026-11-21): Voltorb into a bulky Snorlax, where the
        # blast is NOT a KO and Thunder Wave still gets THREAT's -2; Explosion wins on
        # AI_SMART's -2 and the plan's -3 (final 14 vs 18).
        h = self.h
        self.boot(self.mon("SNORLAX", ["TACKLE"], level=60),
                  self.mon("VOLTORB", ["THUNDER_WAVE", "EXPLOSION"], level=30))
        records = h.hook_ai_scores()
        h.park_before_hijack()
        h.write8("wAILayer2Encouragement", 2)
        self.word("wEnemyMonHP", 1)  # the player's Tackle KOs: AI_THREAT is live
        h.call_routine("AIEnemyTrainerChooseMoves", limit=12000)
        record = records[-1]
        self.assertEqual(record["eligible_slots"], [1], record["scores"])

    def test_sleep_is_encouraged_whatever_the_hit(self):
        # Control: SLEEP_EFFECT never consults the 40% check.
        self.boot(self.mon("OCTILLERY", ["TACKLE"], level=40),
                  self.mon("ELECTABUZZ", ["HYPNOSIS", "THUNDERPUNCH"], level=60))
        before, after, info = self.run_layers(["HYPNOSIS", "THUNDERPUNCH"], player_hp=72)
        self.assertEqual(self.bonus(before, after), self.ai["AI_STRONG"], info)


if __name__ == "__main__":
    unittest.main()
