"""Multi-turn, full-flow AI fixtures (AI_BACKLOG L1 part 2 and L3).

Unlike the call_routine unit fixtures, these drive real battle turns through
the menus: SelectEnemyMove -> TrainerAI -> ExecuteEnemyMove, with hooks that
only prime state (HP, revealed moves) and record what happened. They catch
contracts that hold per call but break across turns: history that records a
move that never ran, a switch that ping-pongs, a plan that keeps pushing a
move after it landed.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
TRAINER_ITEMS = bool(parse_rgbds_constants(ROOT / "constants/ai_constants.asm")["AI_TRAINER_ITEMS"])


class AIFullFlowTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.battle = parse_rgbds_constants(ROOT / "constants/battle_constants.asm")
        self.ai = parse_rgbds_constants(ROOT / "constants/ai_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.executed_bit = 1 << self.ai["AI_MOVE_EXECUTED_BIT"]

    def tearDown(self):
        self.h.close()

    def mon(self, name, moves, level=50):
        return {"species": self.species[name], "level": level,
                "moves": [self.moves[m] for m in moves]}

    def word(self, label, value, offset=0):
        self.h.write8(label, value >> 8, offset=offset)
        self.h.write8(label, value & 255, offset=offset + 1)

    def boot(self, player, enemy, trainer="JUGGLER", tier=2):
        self.h.inject_fight2_spec(player, enemy,
                                  trainer_class=self.trainers[trainer], ai_tier=tier)
        self.h.boot_fight2(seed=1)

    def drive_turns(self, stop, limit=2400):
        """Always FIGHT, always the player's move slot 0."""
        h = self.h
        h.hook_flag("DisplayBattleMenu", action=lambda:
                    h.write8("wBattleAndStartSavedMenuItem", 0))
        for _ in range(limit):
            if stop():
                return True
            h.tap("a", 1)
            h.tick(8)
        return stop()

    def no_items(self):
        # Items are not under test; an item turn would also skip execution.
        self.h.hook_flag("TrainerAI", action=lambda: self.h.write8("wAICount", 0))

    def history(self):
        h = self.h
        return (h.read8("wAILastMoveNum"), h.read8("wAISameMoveCount"),
                h.read8("wAILastMovePower"))

    # --- L1 part 2: the history records EXECUTED moves -----------------------
    def test_execution_hook_records_once_per_decision(self):
        # Unit contract of AITrackExecutedEnemyMove. The first call after a
        # decision wins: Metronome/Mirror Move re-enter EnemyCanExecuteMove
        # with wEnemySelectedMove overwritten by the called move.
        h = self.h
        self.boot([self.mon("SNORLAX", ["SPLASH"])], [self.mon("TAUROS", ["TACKLE"])])
        metronome, bolt = self.moves["METRONOME"], self.moves["THUNDERBOLT"]
        h.park_before_hijack()
        h.write8("wAILastMoveNum", 0)
        h.write8("wAISameMoveCount", 3)
        h.write8("wAILastMovePower", 0)
        h.call_routine("AITrackLastMove", limit=120)  # open a decision
        h.write8("wEnemySelectedMove", metronome)
        h.write8("wEnemyMovePower", 0)
        h.call_routine("AITrackExecutedEnemyMove", limit=120)
        first = self.history()
        h.write8("wEnemySelectedMove", bolt)  # the move Metronome called
        h.write8("wEnemyMovePower", 95)
        h.call_routine("AITrackExecutedEnemyMove", limit=120)
        self.assertEqual(first, (metronome, self.executed_bit, 0))
        self.assertEqual(self.history(), first)

        # Next decision, same move again: the streak grows by exactly one.
        h.call_routine("AITrackLastMove", limit=120)
        self.assertEqual(h.read8("wAISameMoveCount"), 0)  # flag cleared for scoring
        h.write8("wEnemySelectedMove", metronome)
        h.write8("wEnemyMovePower", 0)
        h.call_routine("AITrackExecutedEnemyMove", limit=120)
        self.assertEqual(self.history(), (metronome, self.executed_bit | 1, 0))

    def test_streak_saturates_below_the_executed_flag(self):
        h = self.h
        self.boot([self.mon("SNORLAX", ["SPLASH"])], [self.mon("TAUROS", ["TACKLE"])])
        tackle = self.moves["TACKLE"]
        cap = self.executed_bit - 1
        h.park_before_hijack()
        h.write8("wAILastMoveNum", tackle)
        h.write8("wAISameMoveCount", cap)
        h.write8("wEnemySelectedMove", tackle)
        h.write8("wEnemyMovePower", 40)
        h.call_routine("AITrackExecutedEnemyMove", limit=120)
        self.assertEqual(self.history(), (tackle, self.executed_bit | cap, 40))
        h.call_routine("AITrackLastMove", limit=120)
        self.assertEqual(h.read8("wAISameMoveCount"), cap)

    def test_flinched_turn_does_not_extend_the_streak(self):
        # Real turns. Tauros (faster) Tackles every turn except the second,
        # where it flinches. Before L1 part 2 the decision-time tracker counted
        # the flinched SELECTION, reading a streak of 2 at the fourth decision.
        h = self.h
        self.boot([self.mon("SNORLAX", ["SPLASH"])], [self.mon("TAUROS", ["TACKLE"])],
                  trainer="COOLTRAINER_M")
        self.no_items()
        tackle = self.moves["TACKLE"]
        decisions, executions = [], []

        def at_decision():
            decisions.append(self.history())

        def at_execute():
            executions.append(h.read8("wEnemySelectedMove"))
            if len(executions) == 2:
                h.write8("wEnemyBattleStatus1",
                         h.read8("wEnemyBattleStatus1") | (1 << self.battle["FLINCHED"]))

        h.hook_flag("AIEnemyTrainerChooseMoves", action=at_decision)
        h.hook_flag("ExecuteEnemyMove", action=at_execute)
        self.assertTrue(self.drive_turns(lambda: len(decisions) >= 4),
                        f"decisions={decisions}")
        print(f"\nL1 flinch decisions={decisions} executions={executions}")
        nums = [d[0] for d in decisions[:4]]
        streaks = [d[1] & (self.executed_bit - 1) for d in decisions[:4]]
        # Decision 1 sees the lead send-out's fresh-mon sentinel.
        self.assertEqual(nums, [self.ai["AI_LAST_MOVE_FRESH_MON"], tackle, tackle, tackle])
        self.assertEqual(streaks, [0, 0, 0, 1])
        self.assertNotEqual(decisions[1][2], 0)  # Tackle's power, from execution

    # --- L3: switching across real turns ------------------------------------
    def test_surviving_switch_in_happens_once_and_holds(self):
        # Slowpoke is kept in Thunderbolt's KO range and Thunderbolt is known,
        # so the AI switches to Geodude (immune: B4 says it survives). Geodude
        # must then stay, and start with a fresh move history.
        h = self.h
        self.boot([self.mon("ELECTRODE", ["SPLASH", "THUNDERBOLT"])],
                  [self.mon("SLOWPOKE", ["TACKLE"]), self.mon("GEODUDE", ["TACKLE"])])
        active, switches, first_geodude = [], [], []

        def at_trainer_ai():
            h.write8("wAICount", 0)
            h.reveal_player_moves(0, [1])
            pos = h.read8("wEnemyMonPartyPos")
            active.append(pos)
            if pos == 0:
                # Just above a quarter: below it, B5 would sacrifice Slowpoke.
                max_hp = int.from_bytes(bytes(h.read_bytes("wEnemyMonMaxHP", 2)), "big")
                self.word("wEnemyMonHP", max_hp // 4 + 1)

        def at_decision():
            if h.read8("wEnemyMonPartyPos") == 1 and not first_geodude:
                first_geodude.append(h.read8("wAILastMoveNum"))

        h.hook_flag("TrainerAI", action=at_trainer_ai)
        h.hook_flag("AIEnemyTrainerChooseMoves", action=at_decision)
        h.hook_flag("SwitchEnemyMon", action=lambda:
                    switches.append(h.read8("wEnemyMonPartyPos")))
        self.assertTrue(self.drive_turns(lambda: len(active) >= 5), f"active={active}")
        print(f"\nL3 survive active={active} switched-from={switches} "
              f"geodude-first-history={first_geodude}")
        self.assertEqual(switches, [0])
        self.assertEqual(active[:5], [0, 1, 1, 1, 1])
        self.assertEqual(first_geodude, [self.ai["AI_LAST_MOVE_FRESH_MON"]])

    def test_switch_in_that_would_be_koed_is_refused_every_turn(self):
        # Same threat, but Geodude sits at 1 HP and the player's Tackle is known
        # too. The ranking still prefers Geodude (Thunderbolt immunity), so the
        # B4 survival gate is what keeps Slowpoke in - on every turn, not once.
        h = self.h
        self.boot([self.mon("ELECTRODE", ["SPLASH", "THUNDERBOLT", "TACKLE"])],
                  [self.mon("SLOWPOKE", ["TACKLE"]), self.mon("GEODUDE", ["TACKLE"])])
        active, switches = [], []

        def at_trainer_ai():
            h.write8("wAICount", 0)
            h.reveal_player_moves(0, [1, 2])
            self.word("wEnemyMon2HP", 1)
            active.append(h.read8("wEnemyMonPartyPos"))
            self.word("wEnemyMonHP", 2)

        h.hook_flag("TrainerAI", action=at_trainer_ai)
        gate = h.hook_flag("AIBestReserveSurvivesThreat")
        h.hook_flag("SwitchEnemyMon", action=lambda:
                    switches.append(h.read8("wEnemyMonPartyPos")))
        self.assertTrue(self.drive_turns(lambda: len(active) >= 4), f"active={active}")
        print(f"\nL3 refuse active={active} switched-from={switches} gate={gate['count']}")
        self.assertEqual(switches, [])
        self.assertGreaterEqual(gate["count"], 3)

    def test_sacrificed_mon_hands_a_free_entry_to_the_reserve(self):
        # B5 across real turns. Pikachu (faster) sits at 2 HP facing a known
        # Body Slam; Geodude would survive a switch-in. Before B5 the AI switched
        # and Geodude ate the Body Slam. Now Pikachu stays and attacks, faints,
        # and Geodude comes in after the faint untouched.
        h = self.h
        self.boot([self.mon("SNORLAX", ["BODY_SLAM"])],
                  [self.mon("PIKACHU", ["THUNDERSHOCK"]), self.mon("GEODUDE", ["TACKLE"])])
        switches, geodude_first = [], []

        def at_trainer_ai():
            h.write8("wAICount", 0)
            h.reveal_player_moves(0, [0])
            if h.read8("wEnemyMonPartyPos") == 0:
                self.word("wEnemyMonHP", 2)

        def at_decision():
            if h.read8("wEnemyMonPartyPos") == 1 and not geodude_first:
                geodude_first.append((self.read_hp("wEnemyMonHP"), self.read_hp("wEnemyMonMaxHP")))

        h.hook_flag("TrainerAI", action=at_trainer_ai)
        h.hook_flag("AIEnemyTrainerChooseMoves", action=at_decision)
        h.hook_flag("SwitchEnemyMon", action=lambda:
                    switches.append(h.read8("wEnemyMonPartyPos")))
        self.assertTrue(self.drive_turns(lambda: bool(geodude_first)),
                        f"switches={switches}")
        print(f"\nB5 flow switched-from={switches} geodude-at-first-decision={geodude_first}")
        self.assertEqual(switches, [])
        hp, max_hp = geodude_first[0]
        self.assertEqual(hp, max_hp)

    # --- B6 first slice: items never trade away a won exchange ----------------
    def brock_first_decision(self, player_hp):
        """Brock (T2) with a lone poisoned Onix: his handler uses Full Heal on
        any status, with no random roll. Returns (Full Heal used, no-item exit)
        at the first TrainerAI decision."""
        h = self.h
        self.boot([self.mon("SNORLAX", ["SPLASH"])], [self.mon("ONIX", ["TACKLE"])],
                  trainer="BROCK")
        state = {"decisions": 0}

        def at_trainer_ai():
            state["decisions"] += 1
            if state["decisions"] == 1:
                h.write8("wAICount", 1)
                h.write8("wEnemyMonStatus", 1 << 3)  # PSN: Onix can still act
                if player_hp is not None:
                    self.word("wBattleMonHP", player_hp)

        h.hook_flag("TrainerAI", action=at_trainer_ai)
        heal = h.hook_flag("AIUseFullHeal")
        no_item = h.hook_flag("TrainerAI.noItem")
        self.assertTrue(self.drive_turns(lambda: heal["count"] + no_item["count"] > 0))
        return heal["count"], no_item["count"]

    # Both B6 tests need trainer items on: with AI_TRAINER_ITEMS 0 the veto
    # is not assembled, and "no item" would pass for the wrong reason.
    @unittest.skipUnless(TRAINER_ITEMS, "AI_TRAINER_ITEMS is 0: the B6 item veto is not assembled")
    def test_item_is_vetoed_when_the_selected_move_wins(self):
        # The selected Tackle reliably finishes a 1-HP player at this action
        # point, so spending the turn on Full Heal would throw the win away.
        self.assertEqual(self.brock_first_decision(1), (0, 1))

    @unittest.skipUnless(TRAINER_ITEMS, "AI_TRAINER_ITEMS is 0: trainers never use items")
    def test_item_is_used_when_no_win_is_on_the_board(self):
        self.assertEqual(self.brock_first_decision(None), (1, 0))

    @unittest.skipIf(TRAINER_ITEMS, "AI_TRAINER_ITEMS is 1: trainers use items")
    def test_no_item_when_trainer_items_are_off(self):
        # Player feedback #8 (2026-10-09). Brock's handler used Full Heal on any
        # status with no roll, so a poisoned lone Onix with no win on the board
        # is the case most sure to use an item if any path still could.
        self.assertEqual(self.brock_first_decision(None), (0, 1))

    # --- FOLLOWUPS #48: TrainerAI reuses move selection's caches when exact ----
    def ko_cache_at_trainer_ai(self, player, enemy, reveal=(1,), prime_hp=True,
                               force_stale=False):
        """(entry, final, cycles) for the first TrainerAI: wAIPlayerKOCache as
        AIPlayerWouldKO is entered inside it (0 = empty, so it scans), the
        answer it holds when TrainerAI hands over, and TrainerAI's cycles.
        The player always uses slot 0. force_stale corrupts the state key at
        TrainerAI entry, so the same turn is re-decided with nothing reused."""
        h = self.h
        self.boot([player], enemy, tier=3)
        self.no_items()
        state = {"in": False, "entry": None, "final": None, "start": 0, "cycles": None,
                 "selected": None, "max": None}
        self.last_state = state

        def at_decision():
            h.reveal_player_moves(0, list(reveal))
            # Primed BEFORE move selection, so both decisions see one board.
            if prime_hp is True:
                self.word("wEnemyMonHP", self.read_hp("wEnemyMonMaxHP") // 4 + 1)
            elif prime_hp:
                self.word("wEnemyMonHP", prime_hp)

        def enter():
            if state["cycles"] is None:
                state["in"], state["start"] = True, h.cycle_count()
                # Move selection's answer and scan maximum, before TrainerAI
                # revalidates or clears them.
                state["selected"] = h.read8("wAIPlayerKOCache")
                state["max"] = self.read_hp("wAIPlayerKOMaxDamage")
                if force_stale:
                    for key in ("wAIThreatStateKey", "wAIEstimateStateKey"):
                        h.write8(key, h.read8(key) ^ 1)

        def leave():
            if state["in"]:
                state["in"], state["cycles"] = False, h.cycle_count() - state["start"]
                state["final"] = h.read8("wAIPlayerKOCache")

        def would_ko():
            if state["in"] and state["entry"] is None:
                state["entry"] = h.read8("wAIPlayerKOCache")

        h.hook_flag("AIEnemyTrainerChooseMoves", action=at_decision)
        h.hook_flag("TrainerAI", action=enter)
        h.hook_flag("ExecuteEnemyMove", action=leave)
        h.hook_flag("SwitchEnemyMon", action=leave)
        h.hook_flag("AIPlayerWouldKO", action=would_ko)
        self.assertTrue(self.drive_turns(lambda: state["cycles"] is not None))
        return state["entry"], state["final"], state["cycles"]

    def test_enemy_first_trainer_ai_reuses_the_ko_answer(self):
        # Electrode outspeeds Snorlax: nothing happens between move selection and
        # TrainerAI, so move selection's KO answer (YES here) is still exact.
        entry, _, cycles = self.ko_cache_at_trainer_ai(
            self.mon("SNORLAX", ["SPLASH", "BODY_SLAM"]),
            [self.mon("ELECTRODE", ["TACKLE", "THUNDERBOLT"]), self.mon("GEODUDE", ["TACKLE"])])
        print(f"\n#48 enemy-first TrainerAI KO cache={entry} cycles={cycles}")
        self.assertEqual(entry, self.ai["AI_KO_CACHE_YES"])

    def test_player_first_new_reveal_forces_a_rescan(self):
        # Electrode (player) moves first and its Splash is revealed by being
        # used: the believed moveset changed, so the answer must be rescanned.
        entry, _, cycles = self.ko_cache_at_trainer_ai(
            self.mon("ELECTRODE", ["SPLASH", "THUNDERBOLT"]),
            [self.mon("SLOWPOKE", ["TACKLE", "WATER_GUN"]), self.mon("GEODUDE", ["TACKLE"])])
        print(f"\n#48 player-first new reveal: KO cache={entry} cycles={cycles}")
        self.assertEqual(entry, self.ai["AI_KO_CACHE_EMPTY"])

    def assert_reused_and_exact(self, tag, player, enemy, **kw):
        reused = self.ko_cache_at_trainer_ai(player, enemy, **kw)
        selected = self.last_state["selected"]
        self.h.close()
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        fresh = self.ko_cache_at_trainer_ai(player, enemy, force_stale=True, **kw)
        print(f"\n#48 {tag}: reused entry={reused[0]} final={reused[1]} "
              f"cycles={reused[2]}; fresh final={fresh[1]} cycles={fresh[2]}")
        self.assertNotEqual(reused[0], self.ai["AI_KO_CACHE_EMPTY"])
        self.assertEqual(fresh[0], self.ai["AI_KO_CACHE_EMPTY"])
        self.assertEqual(reused[1], fresh[1])
        self.assertLess(reused[2], fresh[2])
        self.last_state["selected"] = selected
        return reused[1]

    def test_player_first_unchanged_board_reuses_the_ko_answer(self):
        # Splash already revealed: the player's move changes nothing the
        # estimates read, so the answer is re-derived, not rescanned, and
        # matches a full rescan of the same turn.
        final = self.assert_reused_and_exact(
            "player-first Splash, KO range",
            self.mon("ELECTRODE", ["SPLASH", "THUNDERBOLT"]),
            [self.mon("SLOWPOKE", ["TACKLE", "WATER_GUN"]), self.mon("GEODUDE", ["TACKLE"])],
            reveal=(0, 1))
        self.assertEqual(final, self.ai["AI_KO_CACHE_YES"])

    def test_player_first_hit_rederives_against_the_lower_hp(self):
        # The player's revealed attack lands first: only our HP changed, which
        # the key leaves out, so the answer is re-derived for the new HP.
        self.assert_reused_and_exact(
            "player-first hit",
            self.mon("ELECTRODE", ["THUNDERBOLT", "TACKLE"]),
            [self.mon("SNORLAX", ["TACKLE", "BODY_SLAM"]), self.mon("GEODUDE", ["TACKLE"])],
            reveal=(0, 1), prime_hp=False)

    def test_player_first_hit_into_ko_range_flips_the_answer(self):
        # SonicBoom deals exactly 20. Our HP is primed 10 above the scan's
        # maximum M, so move selection says NO; after the hit HP = M - 10 and the
        # re-derived answer must be YES without a rescan.
        player = self.mon("ELECTRODE", ["SONICBOOM", "THUNDERBOLT"])
        enemy = [self.mon("SNORLAX", ["TACKLE", "BODY_SLAM"]), self.mon("GEODUDE", ["TACKLE"])]
        self.ko_cache_at_trainer_ai(player, enemy, reveal=(0, 1), prime_hp=False)
        flags = self.last_state["max"]
        valid = 1 << (8 + self.ai["AI_KO_MAX_VALID_BIT"])
        self.assertTrue(flags & valid)
        m = flags & 0x1FFF
        self.h.close()
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        final = self.assert_reused_and_exact("player-first hit into KO range", player, enemy,
                                             reveal=(0, 1), prime_hp=m + 10)
        print(f"  M={m} selected={self.last_state['selected']}")
        self.assertEqual(self.last_state["selected"], self.ai["AI_KO_CACHE_NO"])
        self.assertEqual(final, self.ai["AI_KO_CACHE_YES"])

    def test_player_first_defense_drop_forces_a_rescan(self):
        # Tail Whip lowers our Defense, an input to the player's damage on us:
        # the KO answer may not be reused.
        entry, _, _ = self.ko_cache_at_trainer_ai(
            self.mon("ELECTRODE", ["TAIL_WHIP", "TACKLE"]),
            [self.mon("SLOWPOKE", ["TACKLE", "WATER_GUN"]), self.mon("GEODUDE", ["TACKLE"])],
            reveal=(0, 1))
        self.assertEqual(entry, self.ai["AI_KO_CACHE_EMPTY"])

    def test_player_first_attack_drop_keeps_the_ko_answer(self):
        # Growl lowers only OUR Attack, which the player's damage on us does not
        # read: the KO answer is still reused (our estimates are not).
        self.assert_reused_and_exact(
            "player-first Growl",
            self.mon("ELECTRODE", ["GROWL", "THUNDERBOLT"]),
            [self.mon("SLOWPOKE", ["TACKLE", "WATER_GUN"]), self.mon("GEODUDE", ["TACKLE"])],
            reveal=(0, 1))

    def read_hp(self, label):
        return int.from_bytes(bytes(self.h.read_bytes(label, 2)), "big")

    # --- L3: a T3 plan across real turns ------------------------------------
    def test_para_sweep_paralyses_then_attacks(self):
        # Raichu is slower than Aerodactyl until paralysis quarters its Speed,
        # so ParaSweep fits with the flip bonus. Turn 1 must be Thunder Wave;
        # once it lands the plan goes quiet and Thunderbolt follows.
        #
        # Level 62 keeps Thunderbolt out of kill range (measured: half-HP tier,
        # final scores TW 13 / TB 14, a strict win). At level 50 Thunderbolt is a
        # reliable KO and ties Thunder Wave at 13, and the AI must take a kill
        # over a plan (FOLLOWUPS #55), so that board tests something else.
        h = self.h
        self.boot([self.mon("AERODACTYL", ["SPLASH"], level=62)],
                  [self.mon("RAICHU", ["THUNDER_WAVE", "THUNDERBOLT"])],
                  trainer="COOLTRAINER_M", tier=3)
        self.no_items()
        executed = []
        h.hook_flag("ExecuteEnemyMove", action=lambda: executed.append(
            (h.read8("wEnemySelectedMove"), h.read8("wBattleMonStatus"))))
        self.assertTrue(self.drive_turns(lambda: len(executed) >= 2), f"executed={executed}")
        print(f"\nL3 para-sweep executed={executed}")
        self.assertEqual([m for m, _ in executed[:2]],
                         [self.moves["THUNDER_WAVE"], self.moves["THUNDERBOLT"]])
        self.assertNotEqual(executed[1][1], 0)  # the second move saw a paralysed target

    def test_reliable_kill_outranks_the_para_sweep_plan(self):
        # FOLLOWUPS #55. At level 50 Thunderbolt reliably KOs Aerodactyl
        # (measured 147 -> 0), and Thunder Wave's SMART 3 + PLAN 3 used to tie
        # that kill at 13, leaving it to the RNG. A plan must never steer past a
        # reliable kill: PLAN issues nothing, and Thunderbolt wins on score.
        h = self.h
        self.boot([self.mon("AERODACTYL", ["SPLASH"])],
                  [self.mon("RAICHU", ["THUNDER_WAVE", "THUNDERBOLT"])],
                  trainer="COOLTRAINER_M", tier=3)
        self.no_items()
        decisions = h.hook_ai_scores()
        executed = []
        h.hook_flag("ExecuteEnemyMove", action=lambda: executed.append(
            h.read8("wEnemySelectedMove")))
        self.assertTrue(self.drive_turns(lambda: len(executed) >= 1), f"executed={executed}")
        first = decisions[0]
        print(f"\nL3 kill-over-plan scores={first['scores']} executed={executed}")
        plan = [t for t in first["layer_trace"] if t["layer"] == "PLAN"]
        self.assertEqual([t["delta"] for t in plan], [[0, 0, 0, 0]])
        self.assertLess(first["scores"][1], first["scores"][0])  # TB strictly below TW
        self.assertEqual(executed[0], self.moves["THUNDERBOLT"])

    def test_two_turn_kill_is_capped_at_the_unreliable_tier(self):
        # Solar Beam KOs Golem (4x), but only on turn 2: turn 1 charges and
        # hands the player a free hit. Before 2026-10-08 AI_DAMAGE scored it
        # AI_KILL_FIRST (-10) and AI_SMART's +2 charge penalty was noise. Now it
        # reaches the kill branch, is capped at AI_STRONG, sets no
        # wAIReliableKOFound, and the half-HP Vine Whip wins. Since Solar Beam
        # also ranks at half (#61), the best-damage nudge is Vine Whip's: 19 vs 16.
        h = self.h
        self.boot([self.mon("GOLEM", ["SPLASH"])],
                  [self.mon("VENUSAUR", ["SOLARBEAM", "VINE_WHIP"])],
                  trainer="COOLTRAINER_M", tier=3)
        self.no_items()
        kill_branch, flag = [], []
        h.hook_flag("AILayerDamage.kill", action=lambda: kill_branch.append(1))
        h.hook_flag("AILayerPlan", action=lambda: flag.append(h.read8("wAIReliableKOFound")))
        decisions = h.hook_ai_scores()
        executed = []
        h.hook_flag("ExecuteEnemyMove", action=lambda: executed.append(
            h.read8("wEnemySelectedMove")))
        self.assertTrue(self.drive_turns(lambda: len(executed) >= 1), f"executed={executed}")
        first = decisions[0]
        damage = [t["delta"] for t in first["layer_trace"] if t["layer"] == "DAMAGE"]
        print(f"\nL3 two-turn kill scores={first['scores']} damage={damage} executed={executed}")
        self.assertTrue(kill_branch)  # Solar Beam really is in KO range
        self.assertGreater(damage[0][0], -self.ai["AI_KILL"])  # ...and capped below it
        self.assertEqual(flag[:1], [0])
        self.assertEqual(executed[0], self.moves["VINE_WHIP"])

    def test_attack_that_can_ko_beats_a_pointless_speed_boost(self):
        # FOLLOWUPS #61 (benchmark seed 17): an already-faster Pidgeot vs a
        # 47-HP Golbat chose Agility (18) over a Take Down that could KO (19).
        # AI_SETUP's blanket -2 drowned out B2's "already faster" +1, and the
        # best-damage nudge went to Sky Attack (two turns ranked as one). Now
        # AI_SETUP skips speed boosts when already faster, Sky Attack ranks at
        # half, and Take Down takes the nudge and wins outright.
        h = self.h
        self.boot([self.mon("GOLBAT", ["SPLASH"], level=45)],
                  [self.mon("PIDGEOT", ["TAKE_DOWN", "AGILITY", "SKY_ATTACK", "MIRROR_MOVE"])],
                  trainer="COOLTRAINER_M", tier=3)
        self.no_items()
        primed = []

        def prime():
            if not primed:
                primed.append(1)
                self.word("wBattleMonHP", 47)

        h.hook_flag("AIEnemyTrainerChooseMoves", action=prime)
        decisions = h.hook_ai_scores()
        executed = []
        h.hook_flag("ExecuteEnemyMove", action=lambda: executed.append(
            h.read8("wEnemySelectedMove")))
        self.assertTrue(self.drive_turns(lambda: len(executed) >= 1), f"executed={executed}")
        first = decisions[0]
        layers = {t["layer"]: t["delta"] for t in first["layer_trace"]}
        print(f"\nL3 speed-boost scores={first['scores']} setup={layers.get('SETUP')} "
              f"damage={layers.get('DAMAGE')} executed={executed}")
        self.assertEqual(layers["SETUP"][1], 0)  # no blanket encourage for Agility
        take_down = first["scores"][0]
        self.assertTrue(all(take_down < s for s in first["scores"][1:]), first["scores"])
        self.assertEqual(executed[0], self.moves["TAKE_DOWN"])


if __name__ == "__main__":
    unittest.main()
