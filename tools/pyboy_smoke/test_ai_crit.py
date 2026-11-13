"""AI review CP2 (2026-11-12): crit-certain moves are estimated as crits.

engine/battle/ai/ai_crit.asm. A damaging move whose CalcCritRate threshold is at
least AI_CRIT_CERTAIN ($C0) goes through the engine's own crit path: unmodified
stats on both sides (stages and screens ignored), doubled level. Plan:
AI_REVIEW_PLAN_2026-11-12.md.
"""

from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

MOVE_LENGTH = 6
NEUTRAL_STAGE = 7


class CritCertainEstimateTest(unittest.TestCase):
    harness: RedRogueHarness | None = None
    booted = False

    def setUp(self) -> None:
        self.booted = False
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.species = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")
        self.moves = parse_rgbds_constants(REPO_ROOT / "constants" / "move_constants.asm")
        self.trainers = parse_trainer_constants(REPO_ROOT / "constants" / "trainer_constants.asm")
        self.rom = (REPO_ROOT / "pokeblue_debug.gbc").read_bytes()

    def tearDown(self) -> None:
        if self.harness is not None:
            self.harness.close()

    def mon(self, species: str, moves: list[str], level: int = 50) -> dict[str, object]:
        return {"species": self.species[species], "level": level,
                "moves": [self.moves[name] for name in moves]}

    def boot(self, player: dict[str, object], enemy: list[dict[str, object]]) -> RedRogueHarness:
        h = self.harness
        assert h is not None
        h.inject_fight2_spec([player], enemy, trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3)
        h.boot_fight2(seed=1)
        self.booted = True
        return h

    def word(self, label: str) -> int:
        assert self.harness is not None
        return int.from_bytes(bytes(self.harness.read_bytes(label, 2)), "big")

    def write_word(self, label: str, value: int) -> None:
        assert self.harness is not None
        self.harness.write8(label, value >> 8)
        self.harness.write8(label, value & 0xFF, offset=1)

    def load_player_move(self, move: str) -> None:
        """The move's 6-byte record from the ROM's Moves table into wPlayerMove*."""
        h = self.harness
        assert h is not None
        bank, address = h.symbols.get("Moves")
        start = bank * 0x4000 + address - 0x4000 + (self.moves[move] - 1) * MOVE_LENGTH
        for offset, value in enumerate(self.rom[start:start + MOVE_LENGTH]):
            h.write8("wPlayerMoveNum", value, offset=offset)

    def estimate(self, move: str, routine: str = "AIEstimatePlayerMoveDamage") -> tuple[int, bool]:
        """(the estimate, whether the crit path ran) for the player's `move`."""
        h = self.harness
        assert h is not None
        self.load_player_move(move)
        crit = h.hook_flag("AIEstimatePlayerDamageCrit")
        before = crit["count"]
        h.call_routine(routine)
        return self.word("wAIDamageEstimate"), crit["count"] > before

    def set_enemy_defense_stage(self, stage: int) -> None:
        """Defense stage +stage on the enemy, with the stat scaled the engine's way
        for +2 (x2): enough for the ordinary path to see it."""
        h = self.harness
        assert h is not None
        h.write8("wEnemyMonDefenseMod", NEUTRAL_STAGE + stage)
        self.write_word("wEnemyMonDefense", self.word("wEnemyMonUnmodifiedDefense") * (2 if stage == 2 else 1))

    def test_slash_from_a_fast_mon_is_estimated_as_a_crit_that_ignores_defense_stages(self) -> None:
        self.boot(self.mon("PERSIAN", ["SLASH", "STRENGTH"]), [self.mon("SNORLAX", ["TACKLE"])])
        plain, _ = self.estimate("SLASH", routine="AIEstimatePlayerDamage")  # the old, non-crit number
        crit, ran = self.estimate("SLASH")
        self.assertTrue(ran, "Persian's Slash (base Speed 115) must take the crit path")
        self.assertGreaterEqual(crit * 10, plain * 17, (plain, crit))  # a crit is ~1.8-2x here
        self.set_enemy_defense_stage(2)
        boosted, ran = self.estimate("SLASH")
        self.assertTrue(ran)
        self.assertEqual(boosted, crit, "a crit ignores the defender's Defense stage")

    def test_an_ordinary_move_is_unchanged_and_still_sees_the_stage(self) -> None:
        self.boot(self.mon("PERSIAN", ["SLASH", "STRENGTH"]), [self.mon("SNORLAX", ["TACKLE"])])
        old, _ = self.estimate("STRENGTH", routine="AIEstimatePlayerDamage")
        new, ran = self.estimate("STRENGTH")
        self.assertFalse(ran, "Strength's crit chance is ~22%: not crit-certain")
        self.assertEqual(new, old)
        self.set_enemy_defense_stage(2)
        boosted, _ = self.estimate("STRENGTH")
        self.assertLess(boosted, new)

    # --- FU1 part 2 (2026-11-13): the player's crit is the larger of the two --
    def boost_player_attack_6(self) -> None:
        h = self.harness
        assert h is not None
        h.write8("wPlayerMonAttackMod", NEUTRAL_STAGE + 6)
        self.write_word("wBattleMonAttack", min(999, self.word("wPlayerMonUnmodifiedAttack") * 4))

    def drop_enemy_defense_6(self) -> None:
        h = self.harness
        assert h is not None
        h.write8("wEnemyMonDefenseMod", NEUTRAL_STAGE - 6)
        self.write_word("wEnemyMonDefense", max(1, self.word("wEnemyMonUnmodifiedDefense") // 4))

    def wrapped(self, move: str) -> tuple[int, bool, int]:
        """(AIEstimatePlayerMoveDamage's estimate, its carry, normal estimates it ran)."""
        h = self.harness
        assert h is not None
        self.load_player_move(move)
        normal = h.hook_flag("AIEstimatePlayerDamage")
        before = normal["count"]
        carry = h.call_routine("AIEstimatePlayerMoveDamage",
                               capture=lambda hh: bool(hh.pyboy.register_file.F & 0x10))
        return self.word("wAIDamageEstimate"), carry, normal["count"] - before

    def test_boosted_players_slash_counts_its_normal_hit_when_larger(self) -> None:
        self.boot(self.mon("PERSIAN", ["SLASH"]), [self.mon("SNORLAX", ["TACKLE"])])
        crit, carry, normals = self.wrapped("SLASH")
        self.assertEqual((carry, normals), (True, 0), "neutral: the crit alone, no normal estimate")
        self.boost_player_attack_6()
        plain, _ = self.estimate("SLASH", routine="AIEstimatePlayerDamage")
        self.assertGreater(plain, crit, (plain, crit))
        value, carry, normals = self.wrapped("SLASH")
        self.assertEqual((value, carry, normals), (plain, False, 1))

    def test_lowered_enemy_defense_counts_the_players_normal_hit(self) -> None:
        self.boot(self.mon("PERSIAN", ["SLASH"]), [self.mon("SNORLAX", ["TACKLE"])])
        crit, _, _ = self.wrapped("SLASH")
        self.drop_enemy_defense_6()
        plain, _ = self.estimate("SLASH", routine="AIEstimatePlayerDamage")
        value, carry, normals = self.wrapped("SLASH")
        self.assertEqual(normals, 1)
        self.assertEqual((value, carry), (max(plain, crit), crit >= plain), (plain, crit))
        self.assertGreater(plain, crit, (plain, crit))

    def test_screen_handler_buckets_a_boosted_players_normal_hit_as_physical(self) -> None:
        self.boot(self.mon("PERSIAN", ["SLASH"]), [self.mon("SNORLAX", ["TACKLE"])])
        self.boost_player_attack_6()
        plain, _ = self.estimate("SLASH", routine="AIEstimatePlayerDamage")
        self.assertEqual(self.screen_buckets("SLASH"), (plain, 0, 0))

    def test_crit_estimate_puts_back_what_the_crit_path_clobbers(self) -> None:
        h = self.boot(self.mon("PERSIAN", ["SLASH"]), [self.mon("SNORLAX", ["TACKLE"])])
        sentinels = {"wCurSpecies": 0x5A, "wCurEnemyLevel": 0x3C,
                     "wFormContextSpecies": 0x21, "wFormContextForm": 0x02}
        for label, value in sentinels.items():
            h.write8(label, value)
        _, ran = self.estimate("SLASH")
        self.assertTrue(ran)
        for label, value in sentinels.items():
            self.assertEqual(h.read8(label), value, label)

    # --- consumers of the crit estimate ---------------------------------------
    AI_KO_CACHE_NO = 1
    AI_KO_CACHE_YES = 2
    AI_BUF_BESTPARTYSLOT = 19
    AI_BUF_POSSKO = 18
    AI_BUF_SCREEN_HITS = 20

    def set_enemy_hp(self, hp: int) -> None:
        self.write_word("wEnemyMonHP", hp)

    def would_ko(self, move: str, hp_offset_from_plain: int) -> int:
        """wAIPlayerKOCache after AIPlayerWouldKO with the enemy at the move's
        non-crit estimate + hp_offset_from_plain HP (player's only believed move)."""
        h = self.harness
        assert h is not None
        h.reveal_player_moves(0, [0], clear=True)
        plain, _ = self.estimate(move, routine="AIEstimatePlayerDamage")
        self.set_enemy_hp(plain + hp_offset_from_plain)
        h.write8("wAIPlayerKOCache", 0)
        h.write8("wAIReliableKOFound", 0)
        h.call_routine("AIPlayerWouldKO", limit=600)
        return h.read8("wAIPlayerKOCache")

    def test_ko_check_flips_on_the_crit_alone(self) -> None:
        # HP one above the plain max roll: a non-crit Slash cannot KO, a crit can.
        self.boot(self.mon("PERSIAN", ["SLASH"]), [self.mon("SNORLAX", ["TACKLE"])])
        self.assertEqual(self.would_ko("SLASH", 1), self.AI_KO_CACHE_YES)

    def test_ko_check_control_ordinary_move_does_not_flip(self) -> None:
        self.boot(self.mon("PERSIAN", ["STRENGTH"]), [self.mon("SNORLAX", ["TACKLE"])])
        self.assertEqual(self.would_ko("STRENGTH", 1), self.AI_KO_CACHE_NO)

    def reserve_delivery(self, scan_setup=None) -> tuple[int, list[int]]:
        """(B4's delivery for reserve slot 1, wEnemyMon bytes after the scan)."""
        h = self.harness
        assert h is not None
        h.reveal_player_moves(0, [0], clear=True)
        rf = h.pyboy.register_file
        seen: list[int] = []
        h.register_hook("_AIBestReserveThreatScan.storeHalf",
                        lambda _ctx: seen.append((rf.D << 8) | rf.E))
        if scan_setup is not None:
            scan_setup()
        h.write8("wBuffer", 1, offset=self.AI_BUF_BESTPARTYSLOT)
        h.call_routine("AIBestReserveSurvivesThreat", limit=2000)
        self.assertTrue(seen, "the reserve scan never reached storeHalf")
        return seen[-1], h.read_bytes("wEnemyMonSpecies", 0x30)

    def test_reserve_scan_uses_the_reserves_own_identity_and_restores_everything(self) -> None:
        h = self.boot(self.mon("PERSIAN", ["SLASH"]),
                      [self.mon("SNORLAX", ["TACKLE"]), self.mon("GOLEM", ["TACKLE"])])
        before = h.read_bytes("wEnemyMonSpecies", 0x30)
        status3 = h.read8("wEnemyBattleStatus3")
        delivery, after = self.reserve_delivery()
        self.assertEqual(after, before, "the active mon's bytes must be put back")
        self.assertEqual(h.read8("wEnemyBattleStatus3"), status3)
        # Stage Golem by hand and estimate: a single-hit move delivers exactly one hit.
        for src, dst, length in (("wEnemyMon2Species", "wEnemyMonSpecies", 1),
                                 ("wEnemyMon2CatchRate", "wEnemyMonCatchRate", 1),
                                 ("wEnemyMon2Type1", "wEnemyMonType1", 2),
                                 ("wEnemyMon2DVs", "wEnemyMonDVs", 2),
                                 ("wEnemyMon2Level", "wEnemyMonLevel", 1),
                                 ("wEnemyMon2Defense", "wEnemyMonDefense", 2),
                                 ("wEnemyMon2Special", "wEnemyMonSpecial", 2)):
            for i, value in enumerate(h.read_bytes(src, length)):
                h.write8(dst, value, offset=i)
        hit, ran = self.estimate("SLASH")
        self.assertTrue(ran)
        self.assertEqual(delivery, hit, "the reserve's delivery must be the crit on the RESERVE's stats")

    def test_reserve_scan_with_transformed_active_mon_restores_the_bit(self) -> None:
        h = self.boot(self.mon("PERSIAN", ["SLASH"]),
                      [self.mon("SNORLAX", ["TACKLE"]), self.mon("GOLEM", ["TACKLE"])])
        plain_delivery, _ = self.reserve_delivery()
        TRANSFORMED = 3

        def make_transformed() -> None:
            h.write8("wEnemyBattleStatus3", h.read8("wEnemyBattleStatus3") | (1 << TRANSFORMED))

        h2_delivery, _ = self.reserve_delivery(make_transformed)
        self.assertEqual(h2_delivery, plain_delivery)
        self.assertTrue(h.read8("wEnemyBattleStatus3") >> TRANSFORMED & 1)

    def screen_buckets(self, move: str) -> tuple[int, int, int]:
        h = self.harness
        assert h is not None
        h.reveal_player_moves(0, [0], clear=True)
        h.call_routine("AIPlayerBestHitByCategory", limit=600)
        words = h.read_bytes("wBuffer", 6, offset=self.AI_BUF_SCREEN_HITS)
        return tuple((words[i] << 8) | words[i + 1] for i in (0, 2, 4))  # physical, special, fixed

    def test_screen_handler_buckets_a_crit_as_fixed_and_an_ordinary_hit_as_physical(self) -> None:
        self.boot(self.mon("PERSIAN", ["SLASH"]), [self.mon("SNORLAX", ["TACKLE"])])
        crit, ran = self.estimate("SLASH")
        self.assertTrue(ran)
        physical, special, fixed = self.screen_buckets("SLASH")
        self.assertEqual((physical, special), (0, 0))
        self.assertEqual(fixed, crit)

    def test_screen_handler_control_ordinary_move_stays_physical(self) -> None:
        self.boot(self.mon("PERSIAN", ["STRENGTH"]), [self.mon("SNORLAX", ["TACKLE"])])
        plain, _ = self.estimate("STRENGTH", routine="AIEstimatePlayerDamage")
        physical, special, fixed = self.screen_buckets("STRENGTH")
        self.assertEqual((physical, special, fixed), (plain, 0, 0))

    def own_move_ko_ceiling(self, move: str, setup=None, reliable: bool = False) -> int:
        """Largest player HP at which the enemy's slot-0 `move` is a possible KO
        (AI_BUF_POSSKO bit 0; with `reliable`, wAIReliableKOFound bit 0), found by
        bisection over reloaded boards. `setup`
        runs on each reloaded board before the decision."""
        import io
        if self.booted:  # one boot_fight2 per harness
            self.harness.close()
            self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        h = self.boot(self.mon("SNORLAX", ["TACKLE"]), [self.mon("PERSIAN", [move, "SPLASH"])])
        h.park_before_hijack()
        state = io.BytesIO()
        h.save_state(state)
        blob = state.getvalue()
        masks: list[int] = []
        h.register_hook("AILayerDamage.applyBest", lambda _ctx: masks.append(
            h.read8("wAIReliableKOFound") if reliable else h.read8("wBuffer", self.AI_BUF_POSSKO)))

        def possible_ko(hp: int) -> bool:
            h.load_state(io.BytesIO(blob))
            h.write8("wAIDebugTierOverride", 4)
            h.write8("wAITier", 0)
            h.write8("wAILayer2Encouragement", 2)
            self.write_word("wBattleMonHP", hp)
            if setup is not None:
                setup()
            masks.clear()
            h.call_routine("AIEnemyTrainerChooseMoves", limit=12000)
            self.assertTrue(masks, "AI_DAMAGE never reached applyBest")
            return bool(masks[-1] & 1)

        lo, hi = 1, self.word("wBattleMonMaxHP")
        self.assertTrue(possible_ko(lo))
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if possible_ko(mid):
                lo = mid
            else:
                hi = mid - 1
        return lo

    def test_own_slash_is_a_possible_ko_at_its_crit_not_its_plain_damage(self) -> None:
        # Slash (power 70) and Strength (power 80) are both Normal STAB from Persian.
        # Plain, Slash would be 7/8 of Strength; as a crit it is ~1.67x its plain damage
        # (measured: Slash 102 vs Strength 70 HP), so ~1.46x Strength.
        strength = self.own_move_ko_ceiling("STRENGTH")
        slash = self.own_move_ko_ceiling("SLASH")
        self.assertGreaterEqual(slash * 80, strength * 105, (slash, strength))  # >= 1.5 x plain Slash

    # --- FU1 (2026-11-13): a crit can be WEAKER than the normal hit -----------
    # A Gen 1 crit ignores stat stages, so from +6 Attack a crit-certain Slash
    # crits for far less than it hits normally. Its possible KO must still see
    # the normal hit. AI_REVIEW_FOLLOWUP_PLAN_2026-11-13.md, FU1.
    def boost_enemy_attack_6(self) -> None:
        h = self.harness
        assert h is not None
        h.write8("wEnemyMonAttackMod", NEUTRAL_STAGE + 6)
        self.write_word("wEnemyMonAttack", min(999, self.word("wEnemyMonUnmodifiedAttack") * 4))

    def test_own_boosted_slash_keeps_its_normal_hit_as_a_possible_ko(self) -> None:
        # Neither move's normal hit is a crit; Strength (80) is not crit-certain, so its
        # ceiling is its boosted normal hit, and Slash (70)'s is about 70/80 of that.
        strength = self.own_move_ko_ceiling("STRENGTH", self.boost_enemy_attack_6)
        slash = self.own_move_ko_ceiling("SLASH", self.boost_enemy_attack_6)
        self.assertGreaterEqual(slash * 80, strength * 68, (slash, strength))

    def test_own_boosted_slash_is_reliable_only_where_its_crit_kos_too(self) -> None:
        # The crit is the likely outcome, so a reliable KO needs it: Slash's reliable
        # ceiling at +6 drops to its crit's minimum roll (unboosted crit max is 102),
        # far below its possible ceiling. Strength at +6 is the control: no crit
        # path, its reliable ceiling stays its normal minimum roll.
        slash_possible = self.own_move_ko_ceiling("SLASH", self.boost_enemy_attack_6)
        slash_reliable = self.own_move_ko_ceiling("SLASH", self.boost_enemy_attack_6, reliable=True)
        strength_possible = self.own_move_ko_ceiling("STRENGTH", self.boost_enemy_attack_6)
        strength_reliable = self.own_move_ko_ceiling("STRENGTH", self.boost_enemy_attack_6, reliable=True)
        self.assertLessEqual(slash_reliable, 102, (slash_reliable, slash_possible))
        self.assertGreater(slash_possible, slash_reliable * 3 // 2, (slash_reliable, slash_possible))
        self.assertGreaterEqual(strength_reliable * 100, strength_possible * 80, (strength_reliable, strength_possible))

    def test_unboosted_slash_reliable_ko_is_its_normal_minimum(self) -> None:
        # Unboosted, the crit is the bigger hit: reliable stays where the normal
        # minimum roll KOs (the crit's minimum is larger), as before FU1.
        slash = self.own_move_ko_ceiling("SLASH", reliable=True)
        strength = self.own_move_ko_ceiling("STRENGTH", reliable=True)
        self.assertGreaterEqual(slash * 80, strength * 68, (slash, strength))
        self.assertLessEqual(slash * 80, strength * 72, (slash, strength))

    def test_boosted_slash_leaves_the_estimate_cache_non_crit(self) -> None:
        # The crit estimates are uncached: at applyBest the cached slot-0 one-hit max
        # is still the boosted normal hit, above the crit's 102 (valid bit masked off).
        h = self.boot(self.mon("SNORLAX", ["TACKLE"]), [self.mon("PERSIAN", ["SLASH", "SPLASH"])])
        h.park_before_hijack()
        h.write8("wAIDebugTierOverride", 4)
        h.write8("wAITier", 0)
        h.write8("wAILayer2Encouragement", 2)
        self.write_word("wBattleMonHP", 150)
        self.boost_enemy_attack_6()
        seen: list[int] = []
        h.register_hook("AILayerDamage.applyBest", lambda _ctx: seen.append(
            int.from_bytes(bytes(h.read_bytes("wAIEnemyEstimateCache", 2)), "big") & 0x7FFF))
        h.call_routine("AIEnemyTrainerChooseMoves", limit=12000)
        self.assertTrue(seen, "AI_DAMAGE never reached applyBest")
        self.assertGreater(seen[-1], 150, seen)

    def test_focus_energy_alone_does_not_make_an_ordinary_move_crit_certain(self) -> None:
        # CalcCritRate: Focus Energy is x8 on base Speed / 2, then the ordinary move
        # halves it back: Persian (base 115) caps at 255 / 2 = 127, about 50%.
        h = self.boot(self.mon("PERSIAN", ["TACKLE"]), [self.mon("SNORLAX", ["TACKLE"])])
        h.write8("wPlayerBattleStatus2", 1 << 2)  # GETTING_PUMPED
        _, ran = self.estimate("TACKLE")
        self.assertFalse(ran, "Tackle under Focus Energy tops out at 127/256: not crit-certain")

    def test_focus_energy_turns_a_slow_attackers_high_crit_move_certain(self) -> None:
        # Snorlax (base Speed 30), Slash: 15 x 8 = 120 without Focus Energy (no);
        # with it 15 x 8 x 8 caps at 255 (yes).
        h = self.boot(self.mon("SNORLAX", ["SLASH"]), [self.mon("PERSIAN", ["TACKLE"])])
        _, ran = self.estimate("SLASH")
        self.assertFalse(ran, "Snorlax Slash without Focus Energy: 120 < 192")
        h.write8("wPlayerBattleStatus2", 1 << 2)
        _, ran = self.estimate("SLASH")
        self.assertTrue(ran, "Snorlax Slash under Focus Energy caps at 255")

    def test_fixed_damage_never_takes_the_crit_path(self) -> None:
        h = self.boot(self.mon("PERSIAN", ["SEISMIC_TOSS"]), [self.mon("SNORLAX", ["TACKLE"])])
        h.write8("wPlayerBattleStatus2", 1 << 2)
        _, ran = self.estimate("SEISMIC_TOSS")
        self.assertFalse(ran)

    # --- CP9 (2026-11-13): AIMoveCritCertain's prefilter ----------------------
    # An ordinary move tops out at 127 before the bonuses, so CalcCritRate is
    # skipped unless the move is high-crit, the player has a Captain crit pick,
    # or the attacker is a special form. These boards check that the skip never
    # changes an answer.
    WITCH_CRIT_BIT = 4  # PRIZE_CRIT_BOOST - 1 in wWitchPrizesEarned
    BIT_SPECIAL_FORM = 3  # custom_functions/func_special_form.asm, in MON_CATCH_RATE
    CATCH_RATE = 7  # MON_CATCH_RATE in the battle struct

    def lookups(self, move: str) -> tuple[bool, int]:
        """(crit path ran, CalcCritRate calls) for the player's `move`."""
        h = self.harness
        assert h is not None
        calls = h.hook_flag("CalcCritRate")
        before = calls["count"]
        _, ran = self.estimate(move)
        return ran, calls["count"] - before

    def bridge(self, witch: bool, captain: bool) -> None:
        h = self.harness
        assert h is not None
        prizes = h.read8("wWitchPrizesEarned") & ~(1 << self.WITCH_CRIT_BIT)
        h.write8("wWitchPrizesEarned", prizes | (int(witch) << self.WITCH_CRIT_BIT))
        for offset in range(4):
            h.write8("wBridgeSelectedEffects", 0, offset=offset)
        if captain:
            h.write8("wBridgeSelectedEffects", h.read8("wPlayerMonNumber") + 1)
            h.write8("wBridgeSelectedEffects", 1, offset=1)  # BRIDGE_SELECTED_EFFECT_CRITICAL_RATE

    def test_prefilter_skips_the_lookup_for_an_ordinary_move(self) -> None:
        self.boot(self.mon("PERSIAN", ["STRENGTH", "SLASH"]), [self.mon("SNORLAX", ["TACKLE"])])
        self.bridge(witch=False, captain=False)
        self.assertEqual(self.lookups("STRENGTH"), (False, 0))
        ran, calls = self.lookups("SLASH")
        self.assertTrue(ran)
        self.assertGreater(calls, 0, "a high-crit move still takes the exact lookup")

    def test_bridge_bonuses_can_make_an_ordinary_move_certain(self) -> None:
        # Measured: Persian's ordinary Strength threshold is 57 (base Speed / 2);
        # Captain makes it 121, both bonuses 135. Under Focus Energy it caps at 127
        # (the most an ordinary move can have): Witch x1.25 then 158 (no, and no
        # lookup is needed), Captain +64 then 191 (looked up, no), both 222 (yes).
        h = self.boot(self.mon("PERSIAN", ["STRENGTH"]), [self.mon("SNORLAX", ["TACKLE"])])
        h.write8("wPlayerBattleStatus2", 1 << 2)  # GETTING_PUMPED
        self.bridge(witch=True, captain=False)
        self.assertEqual(self.lookups("STRENGTH"), (False, 0))
        self.bridge(witch=False, captain=True)
        ran, calls = self.lookups("STRENGTH")
        self.assertEqual((ran, calls > 0), (False, True))
        self.bridge(witch=True, captain=True)
        ran, calls = self.lookups("STRENGTH")
        self.assertEqual((ran, calls > 0), (True, True))

    def test_an_always_crit_form_is_still_looked_up(self) -> None:
        h = self.boot(self.mon("FARFETCHD", ["PECK"]), [self.mon("SNORLAX", ["TACKLE"])])
        self.bridge(witch=False, captain=False)
        rate = h.read8("wBattleMon", self.CATCH_RATE)
        h.write8("wBattleMon", rate & ~(1 << self.BIT_SPECIAL_FORM), offset=self.CATCH_RATE)
        self.assertEqual(self.lookups("PECK"), (False, 0))
        h.write8("wBattleMon", rate | (1 << self.BIT_SPECIAL_FORM), offset=self.CATCH_RATE)
        ran, calls = self.lookups("PECK")
        self.assertEqual((ran, calls > 0), (True, True))

    # --- CP8 cut (2026-11-13, FU4): the setup gate no longer weighs crit risk --
    SG_HURTS = 1 << 5  # AI_SG_HURTS_BIT
    SETUPGATE = 29  # AI_BUF_SETUPGATE

    def plain_and_crit(self, move: str) -> tuple[int, int]:
        h = self.harness
        assert h is not None
        plain, _ = self.estimate(move, routine="AIEstimatePlayerDamage")
        self.load_player_move(move)
        h.call_routine("AIEstimatePlayerDamageCrit")
        return plain, self.word("wAIDamageEstimate")

    def extra_hit(self, hp: int, faster: bool) -> int:
        """AISetupExtraHitHurts' gate byte with our HP = hp and the given speed order."""
        h = self.harness
        assert h is not None
        self.write_word("wEnemyMonHP", hp)
        self.write_word("wEnemyMonSpeed", 300 if faster else 5)
        self.write_word("wBattleMonSpeed", 100)
        h.write8("wBuffer", 0, offset=self.SETUPGATE)
        h.write8("wAIPlayerKOCache", 0)
        h.call_routine("AISetupExtraHitHurts")
        return h.read8("wBuffer", self.SETUPGATE)

    def test_a_crit_only_ko_no_longer_withholds_setup(self) -> None:
        # Persian (base Speed 115): Strength crits at 57/256 (22%), a crit that KOs
        # where the plain hit does not. CP8 withheld setup here; on identical inputs
        # that changed 1 pick in 2,949 decisions, so it was cut. The bit stays clear,
        # and so does bit 7 (CP8's AI_SG_CRIT_BIT, now free).
        h = self.boot(self.mon("PERSIAN", ["STRENGTH"]), [self.mon("SNORLAX", ["TACKLE"])])
        h.reveal_player_moves(0, [0], clear=True)
        self.write_word("wEnemyMonMaxHP", 999)
        plain, crit = self.plain_and_crit("STRENGTH")
        self.assertGreater(crit, plain + 1, (plain, crit))
        gate = self.extra_hit(crit, faster=True)
        self.assertEqual(gate & (self.SG_HURTS | 0x80), 0, (plain, crit, gate))
        gate = self.extra_hit(plain, faster=True)  # control: the plain hit KOs
        self.assertEqual(gate & self.SG_HURTS, self.SG_HURTS, (plain, crit, gate))

    def test_slow_attackers_high_crit_move_stays_ordinary(self) -> None:
        self.boot(self.mon("SNORLAX", ["SLASH"]), [self.mon("PERSIAN", ["TACKLE"])])
        _, ran = self.estimate("SLASH")
        self.assertFalse(ran, "Snorlax Slash: 15 x 8 = 120 < 192")


if __name__ == "__main__":
    unittest.main()
