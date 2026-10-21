"""B9 scarce-PP tiebreak (2026-10-21 AI review, Phase 4; hits-to-KO rule 2026-10-21).

AI_DAMAGE gives its highest-expected-damage slot one extra nudge. When that slot
has AI_SCARCE_PP (2) or less and is not a reliable KO, the nudge goes to the first
other slot with more PP that delivers this turn (no two-turn move), needs the SAME
number of hits to KO as the best (expected damage against the player's current HP,
capped at AI_SCARCE_MAX_HITS) and is a possible KO if the best is.
AILayerDamage is called alone; scores start at 20, lower is better. The per-slot
expected damage it works from is left at wBuffer + AI_BUF_SLOTDMG (2 bytes each,
big-endian) and the possible-KO mask at wBuffer + AI_BUF_POSSKO.

Premise, measured against a L50 Snorlax (227 HP) from a L50 Tauros: Double-Edge 137,
Body Slam 115, Headbutt 94, so Double-Edge is best, Body Slam is 0.84x of it and
Headbutt 0.69x.
"""
from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
FULL = 10
MAX_HITS = 8


def hits(dmg: int, hp: int) -> int:
    """Smallest n with n * dmg >= hp, or 0 when it takes more than MAX_HITS (or dmg is 0)."""
    for n in range(1, MAX_HITS + 1):
        if n * dmg >= hp:
            return n
    return 0


class ScarcePPBase(unittest.TestCase):
    PLAYER = ("SNORLAX", 50)
    ENEMY = ("TAUROS", 50)
    MOVES: tuple[str, ...] = ()

    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.ai = parse_rgbds_constants(ROOT / "constants/ai_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.tracked: dict[int, int] = {}
        self.at_apply: list[int] | None = None
        self.h.register_hook("AILayerDamage.trackBest", self._track)
        self.h.register_hook("AILayerDamage.applyBest", self._apply)
        self.h.inject_fight2_spec(
            [{"species": species[self.PLAYER[0]], "level": self.PLAYER[1], "moves": [self.moves["SPLASH"]]}],
            [{"species": species[self.ENEMY[0]], "level": self.ENEMY[1],
              "moves": [self.moves[m] for m in self.MOVES]}],
            trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)
        self.h.boot_fight2(seed=1)

    def tearDown(self) -> None:
        self.h.close()

    def _track(self, _ctx) -> None:  # wAIDamageEstimate is this slot's scaled expected damage here
        e = self.h.read8("wAIDamageEstimate") << 8 | self.h.read8("wAIDamageEstimate", offset=1)
        self.tracked[self.h.read8("wBuffer", offset=self.ai["AI_BUF_CURSLOT"])] = e

    def _apply(self, _ctx) -> None:
        raw = self.h.read_bytes("wBuffer", 8, offset=self.ai["AI_BUF_SLOTDMG"])
        self.at_apply = [raw[2 * s] << 8 | raw[2 * s + 1] for s in range(4)]

    def damage(self, pp=(FULL,) * 4, *, player_hp=None):
        """(scores, per-slot expected damage, possible-KO mask) after AI_DAMAGE alone."""
        h = self.h
        h.park_before_hijack()
        if player_hp is not None:
            h.write8("wBattleMonHP", player_hp >> 8)
            h.write8("wBattleMonHP", player_hp & 0xFF, offset=1)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
            h.write8("wEnemyMonPP", pp[slot], offset=slot)
        h.write8("wEnemyDisabledMove", 0)
        h.write8("wAIReliableKOFound", 0)
        h.call_routine("AILayerDamage", limit=900)
        raw = h.read_bytes("wBuffer", 8, offset=self.ai["AI_BUF_SLOTDMG"])
        dmg = [raw[2 * s] << 8 | raw[2 * s + 1] for s in range(4)]
        return list(h.read_bytes("wBuffer", 4)), dmg, h.read8("wBuffer", self.ai["AI_BUF_POSSKO"])

    def hp_for(self, hp: int):
        """Scores at full PP and with the best slot (0) scarce, at player HP `hp`."""
        return self.damage(player_hp=hp), self.damage(pp=(1, FULL, FULL, FULL), player_hp=hp)


class ScarcePPTest(ScarcePPBase):
    MOVES = ("DOUBLE_EDGE", "BODY_SLAM", "HEADBUTT", "GROWL")

    def test_premise_double_edge_is_best(self) -> None:
        scores, dmg, mask = self.damage()
        self.assertEqual(scores[0] + 1, scores[1])  # the best-damage nudge
        self.assertEqual(dmg[3], 0)  # a status move stores nothing
        self.assertEqual(max(dmg), dmg[0])
        self.assertEqual(mask, 0)

    def test_stored_damage_survives_to_apply_best(self) -> None:
        """Nothing between the first .trackBest and .applyBest touches +20..27."""
        _, dmg, _ = self.damage()
        self.assertEqual(self.at_apply, dmg)
        self.assertEqual(self.at_apply, [self.tracked[s] for s in range(3)] + [0])

    def test_scarce_best_hands_the_nudge_to_a_same_hits_move(self) -> None:
        # Fixture 3 (B9 still works): at 227 HP Double-Edge and Body Slam both 2HKO.
        full, dmg, _ = self.damage()
        self.assertEqual(hits(dmg[0], 227), hits(dmg[1], 227))
        scarce, *_ = self.damage(pp=(2, FULL, FULL, FULL))
        self.assertEqual(scarce, [full[0] + 1, full[1] - 1, full[2], full[3]])

    def test_three_pp_is_not_scarce(self) -> None:
        self.assertEqual(self.damage(pp=(3, FULL, FULL, FULL)), self.damage())

    def test_headbutt_needs_more_hits_so_a_scarce_body_slam_pair_keeps_the_nudge(self) -> None:
        # Body Slam also scarce: Headbutt (94, a 3HKO against 227) is the only other
        # attacker and needs a hit more than Double-Edge, so the nudge stays.
        full, dmg, _ = self.damage()
        self.assertGreater(hits(dmg[2], 227), hits(dmg[0], 227))
        got, *_ = self.damage(pp=(2, 2, FULL, FULL))
        self.assertEqual(got, full)  # the nudge stayed on slot 0

    def test_a_dead_slot_never_takes_it(self) -> None:
        both = self.damage(pp=(FULL, 0, FULL, FULL))[0]
        self.assertEqual(self.damage(pp=(2, 0, FULL, FULL))[0], both)

    def test_a_reliable_ko_keeps_its_nudge(self) -> None:
        kill, *_ = self.damage(player_hp=1)
        self.assertEqual(self.damage(pp=(2, FULL, FULL, FULL), player_hp=1)[0], kill)

    def test_fixture4_same_tier_stand_in_that_needs_a_hit_more_is_refused(self) -> None:
        """Best 3HKO, Body Slam (0.84x) 4HKO: the shipped tier rule moved the nudge."""
        _, dmg, _ = self.damage()
        hp = 3 * dmg[0]
        (full, d, _), (scarce, *_rest) = self.hp_for(hp)
        self.assertEqual((hits(d[0], hp), hits(d[1], hp)), (3, 4))
        self.assertEqual(scarce, full)  # the nudge stayed on the best slot

    def test_fixture6_best_needing_more_than_eight_hits_keeps_the_nudge(self) -> None:
        _, dmg, _ = self.damage()
        hp = dmg[0] * (MAX_HITS + 1) - 5
        (full, d, _), (scarce, *_rest) = self.hp_for(hp)
        self.assertEqual(hits(d[0], hp), 0)  # more than eight
        self.assertEqual(scarce, full)


class ScarcePPLowerRatioTest(ScarcePPBase):
    """Fixture 5: a stand-in at ~0.69x that still 2HKOs as the best does takes the nudge."""
    MOVES = ("DOUBLE_EDGE", "HEADBUTT", "GROWL", "SPLASH")

    def test_stand_in_that_keeps_the_hit_count_takes_it(self) -> None:
        _, dmg, _ = self.damage()
        hp = dmg[1] * 2 - 20
        (full, d, _), (scarce, *_rest) = self.hp_for(hp)
        self.assertEqual((hits(d[0], hp), hits(d[1], hp)), (2, 2))
        self.assertLess(d[1] / d[0], 0.75)
        self.assertEqual(scarce, [full[0] + 1, full[1] - 1, full[2], full[3]])


class ScarcePPChargeTest(ScarcePPBase):
    """Fixture 1: a two-turn move never stands in. Ice Beam (best, 1 PP) + Solar Beam."""
    PLAYER = ("SNORLAX", 50)
    ENEMY = ("VENUSAUR", 50)
    MOVES = ("ICE_BEAM", "SOLARBEAM", "GROWL", "SPLASH")

    def test_charge_move_stores_zero_and_does_not_take_the_nudge(self) -> None:
        full, dmg, _ = self.damage()
        self.assertGreater(dmg[0], 0)
        self.assertEqual(dmg[1], 0)  # Solar Beam is two-turn
        scarce, *_ = self.damage(pp=(1, FULL, FULL, FULL))
        self.assertEqual(scarce, full)  # the nudge stays on Ice Beam


class ScarcePPPossibleKOTest(ScarcePPBase):
    """Fixture 2: a best move that can kill keeps its nudge against a half-HP move."""
    MOVES = ("DOUBLE_EDGE", "BODY_SLAM", "GROWL", "SPLASH")

    def test_possible_ko_best_is_not_replaced_by_a_non_ko(self) -> None:
        _, dmg, _ = self.damage()
        found = None
        for hp in range(dmg[0] * 2, 0, -1):
            _, d, mask = self.damage(player_hp=hp)
            if mask & 1 and not mask & 2 and hits(d[0], hp) == hits(d[1], hp):
                found = hp
                break
        self.assertIsNotNone(found, "no HP gives a possible-KO best and a same-hits non-KO stand-in")
        full, *_ = self.damage(player_hp=found)
        scarce, *_ = self.damage(pp=(1, FULL, FULL, FULL), player_hp=found)
        self.assertEqual(scarce, full)  # shipped: the nudge moved to Body Slam


if __name__ == "__main__":
    unittest.main()
