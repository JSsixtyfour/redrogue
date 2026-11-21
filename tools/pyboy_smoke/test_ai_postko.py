"""Free-replacement decisions through the real ROM selector, not score mirrors."""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]


class PostKOTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, Path(__file__).parent / "artifacts")
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

    def tearDown(self):
        self.h.close()

    def mon(self, species, moves):
        return dict(species=self.species[species], level=50,
                    moves=[self.moves[m] for m in moves])

    def word(self, label, value):
        self.h.write8(label, value >> 8)
        self.h.write8(label, value & 255, offset=1)

    def boot(self, reserves=None, tier=3, active=None):
        reserves = reserves or [self.mon("MAGMORTAR", ["THUNDERBOLT"]),
                                self.mon("SLOWBRO", ["THUNDERBOLT"])]
        self.h.inject_fight2_spec(
            [self.mon("STARMIE", ["SURF", "PSYCHIC_M", "THUNDERBOLT", "ICE_BEAM"])],
            [active or self.mon("RATTATA", ["TACKLE"]), *reserves],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=tier)
        self.h.boot_fight2(seed=1)
        self.h.write8("wAITurnPlan", 0)
        self.h.write8("wAISeenPlayerMoveMask", 15)
        self.word("wBattleMonHP", 200)
        for stat in ("Attack", "Defense", "Speed", "Special"):
            self.word("wBattleMon" + stat, 100)
            self.word("wPlayerMonUnmodified" + stat, 100)
        for slot in range(2, len(reserves) + 2):
            for stat in ("HP", "MaxHP", "Attack", "Defense", "Special"):
                self.word(f"wEnemyMon{slot}" + stat, 100)
            self.word(f"wEnemyMon{slot}Speed", 50)
        self.word("wEnemyMonHP", 0)
        self.word("wEnemyMon1HP", 0)

    def select(self):
        self.h.call_routine("AISelectSendOut")
        return self.h.read8("hWhichPokemon")

    def test_starmie_type_tie_prefers_surviving_reply_at_t2_and_t3(self):
        self.boot(tier=2)
        # Both reserves are 2x weak to one revealed attack. Fire falls to Surf;
        # Slowbro survives Thunderbolt and can answer with its own Thunderbolt.
        self.assertEqual(self.select(), 2)
        self.h.write8("wAIDebugTierOverride", 4)
        self.h.write8("wAITier", 0)
        self.assertEqual(self.select(), 2)

    def finish_board(self, reserves, specials):
        """Starmie at 10 HP, so a faster reserve's Thunderbolt is a reliable finish."""
        self.boot(reserves)
        self.word("wBattleMonHP", 10)
        for slot, special in enumerate(specials, start=2):
            self.word(f"wEnemyMon{slot}Speed", 150)
            self.word(f"wEnemyMon{slot}Special", special)
        return self.h.hook_flag("AIPostKOReply")

    def test_finish_leader_prunes_reserves_with_a_worse_legacy_score(self):
        # C0 cut 4 (2026-11-17). Electrode's worst believed hit is 1x, Charizard's 2x
        # (Surf, Thunderbolt), so Electrode is enumerated first; once it finishes,
        # Charizard cannot win on the legacy score and is never staged.
        replies = self.finish_board([self.mon("ELECTRODE", ["THUNDERBOLT"]),
                                     self.mon("CHARIZARD", ["FLAMETHROWER"])], [300, 300])
        self.assertEqual(self.select(), 1)
        self.assertEqual(replies["count"], 1, "the worse-scored reserve was pruned")

    def test_finish_leader_still_scans_an_equal_score_that_can_win_on_damage(self):
        # Same species and legacy score: a same-tier, same-score candidate can still win
        # on damage, so the prune must stage it. (Here both finish a 10-HP Starmie and
        # the expected damage both read 9, capped at the target's HP as measured, so the
        # exact tie keeps the earlier slot.)
        replies = self.finish_board([self.mon("ELECTRODE", ["THUNDERBOLT"]),
                                     self.mon("ELECTRODE", ["THUNDERBOLT"])], [150, 400])
        self.assertEqual(self.select(), 1)
        self.assertEqual(replies["count"], 2, "the equal-score reserve was still staged")

    def test_lower_tier_keeps_legacy_type_tie(self):
        self.boot(tier=1)
        self.assertEqual(self.select(), 1)

    def test_surviving_equal_types_compare_usable_coverage(self):
        self.boot([self.mon("SLOWBRO", ["TACKLE"]),
                   self.mon("SLOWBRO", ["THUNDERBOLT"])])
        self.assertEqual(self.select(), 2)
        self.h.write8("wEnemyMon3PP", 0)
        self.assertEqual(self.select(), 1)

    def test_comfortable_survivor_beats_a_stronger_reply_that_barely_survives(self):
        # Both survive Starmie's Thunderbolt and have equal legacy scores. The
        # first takes most of its HP and hits harder; the bulky second keeps the
        # B5 margin (slower than the player: 3x the hit stays below its HP).
        self.boot([self.mon("SLOWBRO", ["THUNDERBOLT"]),
                   self.mon("SLOWBRO", ["TACKLE"])])
        self.word("wEnemyMon3Special", 400)
        self.assertEqual(self.select(), 2)
        self.word("wEnemyMon3Special", 100)  # control: no margin either side
        self.assertEqual(self.select(), 1)  # same tier: damage decides again

    def test_legacy_score_outranks_damage_within_a_tier(self):
        # Both bulky Slowbro keep the margin. The poisoned one (+10 legacy) hits
        # far harder, but extra damage short of a KO does not buy a worse mon.
        self.boot([self.mon("SLOWBRO", ["TACKLE"]),
                   self.mon("SLOWBRO", ["THUNDERBOLT"])])
        for slot in (2, 3):
            self.word(f"wEnemyMon{slot}Special", 400)
        self.word("wBattleMonHP", 900)  # 400-Special Thunderbolt must not be a FINISH
        self.h.write8("wEnemyMon3Status", 1 << 3)  # poison
        self.assertEqual(self.select(), 1)
        self.h.write8("wEnemyMon3Status", 0)  # control: equal scores
        self.assertEqual(self.select(), 2)  # damage breaks the tie

    def test_faster_fragile_finisher_then_paralysis_reverses_choice(self):
        self.boot([self.mon("ELECTRODE", ["THUNDERBOLT"]),
                   self.mon("SLOWBRO", ["THUNDERBOLT"])])
        self.word("wBattleMonHP", 40)
        self.word("wEnemyMon2HP", 1)
        self.word("wEnemyMon2Speed", 200)
        self.assertEqual(self.select(), 1)
        self.h.write8("wEnemyMon2Status", 1 << 6)
        self.assertEqual(self.select(), 2)

    def test_sleep_and_fainted_reserves_do_not_win(self):
        self.boot([self.mon("SLOWBRO", ["THUNDERBOLT"]),
                   self.mon("SLOWBRO", ["TACKLE"])])
        self.h.write8("wEnemyMon2Status", 3)
        self.assertEqual(self.select(), 2)
        self.word("wEnemyMon3HP", 0)
        self.assertEqual(self.select(), 1)  # legal best-of-bad-set fallback

    def test_unrevealed_coverage_and_selected_move_do_not_leak(self):
        self.boot()
        self.h.write8("wAISeenPlayerMoveMask", 1)  # only Surf was revealed
        first = self.select()
        self.h.write8("wBattleMonMoves", self.moves["EXPLOSION"], offset=2)
        self.h.write8("wPlayerSelectedMove", self.moves["EXPLOSION"])
        self.assertEqual(self.select(), first)

    def test_staging_restores_battle_state_and_caches(self):
        self.boot()
        for label, value in (("wEnemyBattleStatus1", 0x80),
                             ("wEnemyBattleStatus2", 0x10),
                             ("wEnemyBattleStatus3", 0x10),
                             ("wEnemyMonAccuracyMod", 11),
                             ("hWhoseTurn", 1), ("wAIPlayerKOCache", 2)):
            self.h.write8(label, value)
        blocks = {"wEnemyMon": 29, "wEnemyMoveNum": 6,
                  "wEnemyBattleStatus1": 3, "wEnemyMonStatMods": 8,
                  "wEnemyMonUnmodifiedLevel": 11, "wBattleMon": 29,
                  "wPlayerMoveNum": 6, "hWhoseTurn": 1,
                  "wAIPlayerKOCache": 1, "wAIPlayerKOMaxDamage": 2,
                  "wAIEnemyEstimateCache": 8, "wEnemyMon1": 44 * 3,
                  "wCurSpecies": 1, "wCurEnemyLevel": 1,
                  "wFormContextSpecies": 2}
        before = {k: self.h.read_bytes(k, n) for k, n in blocks.items()}
        # call_routine clears decision caches before entering the ROM. Plant
        # their sentinels at entry so this tests the selector, not the harness.
        def seed_caches(_):
            for label in ("wAIPlayerKOMaxDamage", "wAIEnemyEstimateCache"):
                for offset, value in enumerate(before[label]):
                    self.h.write8(label, value, offset=offset)
        self.h.register_hook("AISelectSendOut", seed_caches)
        self.assertEqual(self.select(), 2)
        for label, expected in before.items():
            self.assertEqual(self.h.read_bytes(label, len(expected)), expected, label)

    def test_planned_switch_and_opening_keep_their_choice(self):
        self.boot()
        self.h.write8("wAITurnPlan", 0x10 | 2)  # armed, party slot 1
        self.assertEqual(self.select(), 1)
        self.h.write8("wAITurnPlan", 0)
        self.h.write8("wEnemyMonPartyPos", 0xff)
        self.assertEqual(self.select(), 1)  # first living, not the better counter

    def test_real_sendout_loads_selected_reserve(self):
        self.boot()
        events = self.h.hook_enemy_send_out()
        self.h.probe_routine_until("EnemySendOutFirstMon.next",
                                  lambda: bool(events) and
                                  self.h.read8("wEnemyMonPartyPos") == 2 and
                                  self.h.read8("wEnemyMonSpecies") == self.species["SLOWBRO"],
                                  limit=12000)
        self.assertEqual(events[-1]["selected_slot"], 2, events)
        self.assertEqual(events[-1]["ranked_slot"], 2, events)

    def test_double_ko_keeps_legacy_order(self):
        self.boot()
        self.word("wBattleMonHP", 0)
        self.assertEqual(self.select(), 1)

    def test_move_order_does_not_replace_a_stronger_reply_with_a_weaker_one(self):
        self.boot([self.mon("SLOWBRO", ["THUNDERBOLT", "TACKLE"]),
                   self.mon("SLOWBRO", ["TACKLE", "THUNDERBOLT"])])
        self.assertEqual(self.select(), 1)  # equal best attacks retain party order

    def test_crit_lookup_publishes_each_reserves_own_identity(self):
        self.boot([self.mon("PERSIAN", ["SLASH"]),
                   self.mon("FARFETCHD", ["SLASH"])])
        # Special Farfetch'd always crits. The fainted Rattata's identity/form
        # context must not be used for either reserve's crit calculation.
        self.h.write8("wEnemyMon3CatchRate", self.h.read8("wEnemyMon3CatchRate") | 8)
        seen = []
        pending = [False]
        def begin(_):
            pending[0] = bool(self.h.read8("hWhoseTurn"))
        def capture(_):
            if pending[0]:
                pending[0] = False
                seen.append((self.h.read8("wEnemyMonSpecies"),
                             self.h.read8("wCurSpecies"),
                             self.h.read8("wFormContextSpecies")))
        # GetMonHeader consumes/clears form context. Observe its input, not
        # CalcCritRate's later threshold branch where that context is spent.
        self.h.register_hook("CalcCritRate.handleAttacker", begin)
        self.h.register_hook("GetMonHeader", capture)
        self.select()
        self.assertEqual({row[0] for row in seen},
                         {self.species["PERSIAN"], self.species["FARFETCHD"]})
        for staged, species, context in seen:
            self.assertEqual((species, context), (staged, staged))

    def test_single_living_reserve_skips_the_scan(self):
        self.boot()
        self.word("wEnemyMon2HP", 0)  # only slot 2 is left: there is no choice
        estimates = []
        self.h.register_hook("AIEstimateDamage", lambda _: estimates.append(1))
        self.assertEqual(self.select(), 2)
        self.assertEqual(estimates, [])

    # --- E4 near tie (AI_T4_REGRET_PLAN, 2026-11-20) -----------------------------------
    # A VOLUNTARY target tied on tier and legacy score is a uniform pick; a FAINT send-out
    # keeps the damage order (re-measured on the built ROM: mixing cost +0.0050 of party
    # HP per send-out there, switch targets +0.0009 within noise).
    def voluntary_board(self, count):
        """Charizard out (Surf and Thunderbolt are 2x: legacy 40), `count` identical
        Rattata behind it (all 1x: 20, so each beats the active mon)."""
        self.boot([self.mon("RATTATA", ["TACKLE"]) for _ in range(count)],
                  active=self.mon("CHARIZARD", ["FLAMETHROWER"]))
        self.word("wEnemyMonHP", 100)
        self.word("wEnemyMon1HP", 100)

    def voluntary_pick(self):
        self.h.write8("wBuffer", 1, offset=19)  # AI_BUF_BESTPARTYSLOT: the fallback
        got = {}
        self.h.call_routine("AIRankVoluntaryTarget",
                            capture=lambda hh: got.update(slot=hh.read8("wBuffer", offset=19)))
        return got["slot"]

    def test_voluntary_near_tie_reaches_every_tied_reserve(self):
        # The reservoir (k-th tie leads with chance 1/k) must reach the last slot too.
        self.voluntary_board(5)
        self.assertEqual({self.voluntary_pick() for _ in range(40)}, {1, 2, 3, 4, 5})

    def test_faint_send_out_tie_keeps_the_damage_order(self):
        # Same five reserves after a faint: no mixing, the earliest equal candidate.
        self.boot([self.mon("RATTATA", ["TACKLE"]) for _ in range(5)])
        self.assertEqual({self.select() for _ in range(12)}, {1})

    def test_six_mon_scan_has_bounded_latency_and_stack_use(self):
        self.boot([self.mon("SLOWBRO", ["SURF", "THUNDERBOLT", "PSYCHIC_M", "ICE_BEAM"])
                   for _ in range(5)])
        samples = []
        start = []
        end = []
        self.h.register_hook("AIRankPostKOSendOut", lambda _: start.append(self.h.pyboy._cycles()))
        self.h.register_hook("AISelectSendOut.commit", lambda _: end.append(self.h.pyboy._cycles()))
        for label in ("AIEstimateDamage", "AIEstimatePlayerMoveDamage",
                      "CalculateDamage", "GetEnemyMonStat", "CalcCritRate"):
            self.h.register_hook(label, lambda _: samples.append(self.h.pyboy.register_file.SP))
        self.assertEqual(self.select(), 1)
        cycles = end[-1] - start[-1]
        self.assertLess(cycles, 2_000_000)  # less than half a second at DMG speed
        self.assertGreaterEqual(min(samples), self.h.address("wStack") - 255)
        print(f"post-KO five-reserve/four-move scan: {cycles} cycles, sampled min SP=${min(samples):04x}")


if __name__ == "__main__":
    unittest.main()
