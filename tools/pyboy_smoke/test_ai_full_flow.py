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

    def boot(self, player, enemy, trainer="JUGGLER", tier=2, before_boot=None):
        """before_boot, if given, runs after the fixture is injected but
        before boot_fight2 - the only place to register a hook (hook_flag,
        hook_ai_scores, ...) that must see turn 1's decision: that decision
        is made (and, since 2026-10-22, a T2+ voluntary switch is executed)
        INSIDE boot_fight2 itself (ai_turn_plan.asm AIPlanEnemyTurn runs before
        boot_fight2's own first battle menu), before any hook registered
        after boot_fight2 returns can ever see it."""
        self.h.inject_fight2_spec(player, enemy,
                                  trainer_class=self.trainers[trainer], ai_tier=tier)
        if before_boot is not None:
            before_boot()
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
        #
        # Both hooks registered in before_boot: decision 1's fresh-mon sentinel
        # (AI_LAST_MOVE_FRESH_MON) is only ever visible at the VERY FIRST
        # AIEnemyTrainerChooseMoves call, which now happens silently inside
        # boot_fight2 (ai_turn_plan.asm's pre-menu plan); a hook registered
        # after boot never sees it; decisions[0] would read the SECOND
        # decision's already-Tackle value instead (measured: nums=[33,33,33,33]).
        h = self.h
        tackle = self.moves["TACKLE"]
        decisions, executions = [], []

        def at_decision():
            decisions.append(self.history())

        def at_execute():
            executions.append(h.read8("wEnemySelectedMove"))
            if len(executions) == 2:
                h.write8("wEnemyBattleStatus1",
                         h.read8("wEnemyBattleStatus1") | (1 << self.battle["FLINCHED"]))

        def before_boot():
            h.hook_flag("AIEnemyTrainerChooseMoves", action=at_decision)
            h.hook_flag("ExecuteEnemyMove", action=at_execute)

        self.boot([self.mon("SNORLAX", ["SPLASH"])], [self.mon("TAUROS", ["TACKLE"])],
                  trainer="COOLTRAINER_M", before_boot=before_boot)
        self.no_items()
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
        #
        # Priming hooked on AIPlanEnemyTurn, in before_boot, not on TrainerAI:
        # the switch (and the move, and the replacement) is decided THERE, once
        # per turn, before that turn's menu - including turn 1's, made silently
        # inside boot_fight2 itself. A TrainerAI-hooked prime (as this used to
        # read) arrives one commit too late for the decision it is meant to
        # steer; this fixture happened to still pass before, because a level 50
        # Slowpoke's full (unprimed) HP is ALSO already within a critical
        # Thunderbolt's reach (the same latent trap the CGB switch-speed
        # fixture hit - measured there, not re-measured here), so the switch
        # still landed on commit 1 regardless, for the wrong reason.
        h = self.h
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

        def before_boot():
            h.hook_flag("AIPlanEnemyTurn", action=at_trainer_ai)
            h.hook_flag("AIEnemyTrainerChooseMoves", action=at_decision)

        self.boot([self.mon("ELECTRODE", ["SPLASH", "THUNDERBOLT"])],
                  [self.mon("SLOWPOKE", ["TACKLE"]), self.mon("GEODUDE", ["TACKLE"])],
                  before_boot=before_boot)
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
        #
        # Priming hooked on AIPlanEnemyTurn (see test_surviving_switch_in_
        # happens_once_and_holds's note just above): a TrainerAI-hooked prime
        # (as this used to read) arrives after the switch for that turn is
        # already decided, so the decision never saw Geodude's simulated 1 HP
        # at all - measured: a level 50 Slowpoke's full HP is ALSO already
        # within Thunderbolt's reach, so with the OLD hook point the switch
        # fired on commit 1 regardless of this fixture's own "Geodude would
        # also die" setup, a real (fixture-timing) regression this rewrite
        # fixes rather than merely re-baselines.
        h = self.h
        active, switches = [], []

        def at_trainer_ai():
            h.write8("wAICount", 0)
            h.reveal_player_moves(0, [1, 2])
            self.word("wEnemyMon2HP", 1)
            active.append(h.read8("wEnemyMonPartyPos"))
            self.word("wEnemyMonHP", 2)

        def before_boot():
            h.hook_flag("AIPlanEnemyTurn", action=at_trainer_ai)

        self.boot([self.mon("ELECTRODE", ["SPLASH", "THUNDERBOLT", "TACKLE"])],
                  [self.mon("SLOWPOKE", ["TACKLE"]), self.mon("GEODUDE", ["TACKLE"])],
                  before_boot=before_boot)
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
        #
        # Priming hooked on AIPlanEnemyTurn (see test_surviving_switch_in_
        # happens_once_and_holds's note above): a TrainerAI-hooked prime (as
        # this used to read) arrives after the switch-vs-sacrifice decision is
        # already made. Measured: Body Slam is Normal-type and Snorlax's own
        # type-guess STAB, believed even unrevealed, so a FULL-HP Pikachu is
        # already within its reach too (the same latent trap as the other two
        # tests touched by this note) - with the OLD hook point the AI
        # switched into Geodude regardless of this fixture's simulated 2 HP, a
        # real (fixture-timing) regression this rewrite fixes.
        h = self.h
        switches, geodude_first = [], []

        def at_trainer_ai():
            h.write8("wAICount", 0)
            h.reveal_player_moves(0, [0])
            if h.read8("wEnemyMonPartyPos") == 0:
                self.word("wEnemyMonHP", 2)

        def at_decision():
            if h.read8("wEnemyMonPartyPos") == 1 and not geodude_first:
                geodude_first.append((self.read_hp("wEnemyMonHP"), self.read_hp("wEnemyMonMaxHP")))

        def before_boot():
            h.hook_flag("AIPlanEnemyTurn", action=at_trainer_ai)
            h.hook_flag("AIEnemyTrainerChooseMoves", action=at_decision)

        self.boot([self.mon("SNORLAX", ["BODY_SLAM"])],
                  [self.mon("PIKACHU", ["THUNDERSHOCK"]), self.mon("GEODUDE", ["TACKLE"])],
                  before_boot=before_boot)
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
        # Not assembled with trainer items off: nothing can reach it, so 0.
        heal = h.hook_flag("AIUseFullHeal") if TRAINER_ITEMS else {"count": 0}
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

    # --- FOLLOWUPS #48, direct (2026-10-22 rewrite) ----------------------------
    # The real-battle framing above no longer applies: TrainerAI runs at commit
    # (ai_turn_plan.asm AICommitEnemyTurn), BEFORE either side's move executes,
    # for both turn orders - there is no more "enemy-first" (nothing changed)
    # vs "player-first" (the player's hit landed first) distinction, since
    # neither side's move ever lands before TrainerAI any more. The only thing
    # that CAN change between move selection (the planner, before the menu) and
    # TrainerAI's revalidation (at commit, after the menu) is the player's menu
    # ACTION itself - a switch, an item, or TURN REWIND - never a landed attack.
    # These test AIRevalidateDecisionCaches directly against that board.
    #
    # call_routine cannot be used for AIRevalidateDecisionCaches itself: its own
    # "fresh decision" precondition (every real decision clears the one-hit
    # estimate cache, FOLLOWUPS #48) zeroes wAIPlayerKOMaxDamage before the
    # routine's first instruction runs, destroying the exact value it is
    # supposed to read back (measured: a direct call_routine always observed
    # wAIPlayerKOCache as EMPTY, regardless of what move selection had computed
    # moments before). probe_routine_until does not touch WRAM, only the
    # hijacked registers/stack, so it is used instead; wAIPlayerKOCache is read
    # from the HOOKED register snapshot (A, the value about to be stored), not
    # from WRAM - a hook fires BEFORE the label's own instruction runs, so
    # reading WRAM at .store would still see the entry-time EMPTY the routine
    # itself writes before deciding anything.
    def revalidate(self, change=None):
        """Runs one real decision (AIEnemyTrainerChooseMoves), optionally
        applies `change` to simulate the player's menu action, then probes
        AIRevalidateDecisionCaches. Returns (path, cache): path is "store" (a
        fast re-derive or reuse - cache is the resulting AI_KO_CACHE_* answer)
        or "threatStale" (rescan deferred to the next reader; cache is None)."""
        h = self.h
        h.call_routine("AIEnemyTrainerChooseMoves", limit=6000)
        if change is not None:
            change()
        h.park_before_hijack()
        result = {}
        h.register_hook("AIRevalidateDecisionCaches.store", lambda _ctx:
                        result.update(path="store", cache=h.pyboy.register_file.A))
        h.register_hook("AIRevalidateDecisionCaches.threatStale", lambda _ctx:
                        result.setdefault("path", "threatStale"))
        h.probe_routine_until("AIRevalidateDecisionCaches",
                              lambda: "path" in result, limit=2000)
        return result.get("path"), result.get("cache")

    def test_unchanged_board_reuses_the_ko_answer(self):
        # Nothing simulates a menu action: the keys still match, M is still
        # valid, so the answer comes back through the fast path unchanged.
        self.boot([self.mon("SNORLAX", ["SPLASH", "BODY_SLAM"])],
                  [self.mon("ELECTRODE", ["TACKLE", "THUNDERBOLT"]), self.mon("GEODUDE", ["TACKLE"])],
                  tier=3)
        self.h.reveal_player_moves(0, [0, 1], clear=True)
        before = self.h.read8("wAIPlayerKOCache")
        path, cache = self.revalidate()
        print(f"\n#48 unchanged: before={before} path={path} cache={cache}")
        self.assertEqual(path, "store")
        self.assertEqual(cache, before)

    def test_hp_only_change_rederives_without_a_rescan(self):
        # Our own HP is deliberately left OUT of both state keys (TURN REWIND
        # and a heal both change only it), so a drop re-derives fast against
        # wAIPlayerKOMaxDamage rather than forcing a full rescan. Level 70
        # Slowpoke's full HP is safely out of a critical Thunderbolt's reach
        # (measured: a level 50 Slowpoke's full HP was already within it,
        # mirroring the CGB switch-speed fixture's same trap), so the baseline
        # answer is NO and the drop is a genuine NO -> YES flip, not a
        # coincidental match.
        self.boot([self.mon("ELECTRODE", ["SPLASH", "THUNDERBOLT"])],
                  [self.mon("SLOWPOKE", ["TACKLE", "WATER_GUN"], level=70),
                   self.mon("GEODUDE", ["TACKLE"])],
                  tier=3)
        self.h.reveal_player_moves(0, [0, 1], clear=True)
        before = self.h.read8("wAIPlayerKOCache")

        def drop_into_ko_range():
            self.word("wEnemyMonHP", self.read_hp("wEnemyMonMaxHP") // 4 + 1)

        path, cache = self.revalidate(drop_into_ko_range)
        print(f"\n#48 HP-only drop: before={before} path={path} cache={cache}")
        self.assertEqual(before, self.ai["AI_KO_CACHE_NO"])  # premise: safe at full HP
        self.assertEqual(path, "store")
        self.assertEqual(cache, self.ai["AI_KO_CACHE_YES"])

    def test_defense_drop_forces_a_rescan(self):
        # Our Defense is an input to the player's damage on us (the threat
        # key), so a drop (Screech, Tail Whip) invalidates the cached answer.
        self.boot([self.mon("ELECTRODE", ["SPLASH", "THUNDERBOLT"])],
                  [self.mon("SLOWPOKE", ["TACKLE", "WATER_GUN"]), self.mon("GEODUDE", ["TACKLE"])],
                  tier=3)
        self.h.reveal_player_moves(0, [0, 1], clear=True)
        path, cache = self.revalidate(
            lambda: self.h.write8("wEnemyMonDefense", self.h.read8("wEnemyMonDefense") ^ 1))
        print(f"\n#48 Defense drop: path={path} cache={cache}")
        self.assertEqual(path, "threatStale")
        self.assertIsNone(cache)

    def test_attack_drop_keeps_the_ko_answer(self):
        # Growl lowers only OUR Attack, which the player's damage on us does
        # not read (our own damage OUTPUT estimates do, a separate key): the
        # KO answer is still reused.
        self.boot([self.mon("ELECTRODE", ["SPLASH", "THUNDERBOLT"])],
                  [self.mon("SLOWPOKE", ["TACKLE", "WATER_GUN"]), self.mon("GEODUDE", ["TACKLE"])],
                  tier=3)
        self.h.reveal_player_moves(0, [0, 1], clear=True)
        before = self.h.read8("wAIPlayerKOCache")
        path, cache = self.revalidate(
            lambda: self.h.write8("wEnemyMonAttack", self.h.read8("wEnemyMonAttack") ^ 1))
        print(f"\n#48 Attack drop: before={before} path={path} cache={cache}")
        self.assertEqual(path, "store")
        self.assertEqual(cache, before)

    def test_new_reveal_forces_a_rescan(self):
        # A newly revealed player move slot changes the believed moveset
        # (wAISeenPlayerMoveMask, part of the threat key): the cache cannot
        # be trusted and is cleared for the next reader to rescan.
        self.boot([self.mon("ELECTRODE", ["SPLASH", "THUNDERBOLT", "TACKLE"])],
                  [self.mon("SLOWPOKE", ["TACKLE", "WATER_GUN"]), self.mon("GEODUDE", ["TACKLE"])],
                  tier=3)
        self.h.reveal_player_moves(0, [0, 1], clear=True)
        path, cache = self.revalidate(lambda: self.h.reveal_player_moves(0, [2]))
        print(f"\n#48 new reveal: path={path} cache={cache}")
        self.assertEqual(path, "threatStale")
        self.assertIsNone(cache)

    def test_player_switch_forces_a_rescan(self):
        # wPlayerMonNumber is itself part of both state keys: a party switch
        # (via the battle menu) is always a cache miss, whatever the new mon's
        # stats turn out to be.
        self.boot([self.mon("ELECTRODE", ["SPLASH", "THUNDERBOLT"])],
                  [self.mon("SLOWPOKE", ["TACKLE", "WATER_GUN"]), self.mon("GEODUDE", ["TACKLE"])],
                  tier=3)
        self.h.reveal_player_moves(0, [0, 1], clear=True)
        path, cache = self.revalidate(lambda: self.h.write8("wPlayerMonNumber", 1))
        print(f"\n#48 player switch: path={path} cache={cache}")
        self.assertEqual(path, "threatStale")
        self.assertIsNone(cache)

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
        #
        # hook_ai_scores() is registered in before_boot: turn 1's decision is
        # made INSIDE boot_fight2 (ai_turn_plan.asm's pre-menu plan), so a hook
        # registered after boot never sees it, and decisions[0] below would be
        # an IndexError (drive_turns's own stop condition - one execution - is
        # satisfied by turn 1 before a second decision ever runs).
        h = self.h
        container = {}
        def before_boot():
            container["decisions"] = h.hook_ai_scores()
        self.boot([self.mon("AERODACTYL", ["SPLASH"])],
                  [self.mon("RAICHU", ["THUNDER_WAVE", "THUNDERBOLT"])],
                  trainer="COOLTRAINER_M", tier=3, before_boot=before_boot)
        self.no_items()
        decisions = container["decisions"]
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
        # All three hooks below are registered in before_boot: turn 1's
        # decision happens INSIDE boot_fight2 (see the previous test's note),
        # before a hook registered after boot could ever see it.
        h = self.h
        kill_branch, flag = [], []
        container = {}
        def before_boot():
            h.hook_flag("AILayerDamage.kill", action=lambda: kill_branch.append(1))
            h.hook_flag("AILayerPlan", action=lambda: flag.append(h.read8("wAIReliableKOFound")))
            container["decisions"] = h.hook_ai_scores()
        self.boot([self.mon("GOLEM", ["SPLASH"])],
                  [self.mon("VENUSAUR", ["SOLARBEAM", "VINE_WHIP"])],
                  trainer="COOLTRAINER_M", tier=3, before_boot=before_boot)
        self.no_items()
        decisions = container["decisions"]
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
        # prime and hook_ai_scores() both registered in before_boot: turn 1's
        # decision - the one `prime` needs to catch - happens INSIDE
        # boot_fight2 (see test_reliable_kill_outranks_the_para_sweep_plan's
        # note), before a hook registered after boot could ever see it.
        h = self.h
        primed = []
        container = {}

        def prime():
            if not primed:
                primed.append(1)
                self.word("wBattleMonHP", 47)

        def before_boot():
            h.hook_flag("AIEnemyTrainerChooseMoves", action=prime)
            container["decisions"] = h.hook_ai_scores()

        self.boot([self.mon("GOLBAT", ["SPLASH"], level=45)],
                  [self.mon("PIDGEOT", ["TAKE_DOWN", "AGILITY", "SKY_ATTACK", "MIRROR_MOVE"])],
                  trainer="COOLTRAINER_M", tier=3, before_boot=before_boot)
        self.no_items()
        decisions = container["decisions"]
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
