from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import (
    parse_rgbds_constants,
    parse_trainer_constants,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"


class AISelectSendOutTest(unittest.TestCase):
    harness: RedRogueHarness | None = None

    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.species = parse_rgbds_constants(
            REPO_ROOT / "constants" / "pokemon_constants.asm"
        )
        self.moves = parse_rgbds_constants(
            REPO_ROOT / "constants" / "move_constants.asm"
        )
        self.trainers = parse_trainer_constants(
            REPO_ROOT / "constants" / "trainer_constants.asm"
        )

    def tearDown(self) -> None:
        if self.harness is not None:
            self.harness.close()

    def mon(self, species: str) -> dict[str, object]:
        return {
            "species": self.species[species],
            "level": 50,
            "moves": [self.moves["TACKLE"]],
        }

    def boot_fixture(self, player: str, enemy: list[str]) -> None:
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [self.mon(player)],
            [self.mon(species) for species in enemy],
            trainer_class=self.trainers["COOLTRAINER_M"],
            ai_tier=3,
        )
        self.harness.boot_fight2(seed=1)

    def call_selector_with_sentinels(self) -> tuple[int, int]:
        assert self.harness is not None
        sentinels = self.harness.plant_sentinels(
            {
                "wEnemyMonType1": 0xA1,
                "wEnemyMonType2": 0xB2,
                "wPlayerMoveType": 0xC3,
            }
        )

        self.harness.call_routine("AISelectSendOut")
        self.harness.assert_sentinels(sentinels)

        return (
            self.harness.read8("hWhichPokemon"),
            self.harness.read8("wBuffer", 18),
        )

    def test_excludes_active_mon_and_restores_borrowed_state(self) -> None:
        # All three matchups are neutral. If the current mon were not excluded,
        # the deterministic earliest-tie rule would incorrectly return slot 0.
        self.boot_fixture("SNORLAX", ["PIKACHU", "RATTATA", "PIDGEY"])
        assert self.harness is not None
        self.harness.write8("wEnemyMonPartyPos", 0)

        selected, multiplier = self.call_selector_with_sentinels()

        self.assertEqual(selected, 1)
        self.assertEqual(multiplier, 20)

    def test_send_out_marks_the_move_history_fresh(self) -> None:
        # Codex follow-up L1: a replacement must not inherit the previous mon's
        # anti-spam / fatigue history. AI_LAST_MOVE_FRESH_MON is $fe.
        self.boot_fixture("SNORLAX", ["PIKACHU", "RATTATA", "PIDGEY"])
        assert self.harness is not None
        self.harness.write8("wEnemyMonPartyPos", 0)
        self.harness.write8("wAILastMoveNum", 0x21)
        self.call_selector_with_sentinels()
        self.assertEqual(self.harness.read8("wAILastMoveNum"), 0xFE)

    def test_skips_fainted_best_counter(self) -> None:
        self.boot_fixture("SNORLAX", ["PIKACHU", "RATTATA", "PIDGEY"])
        assert self.harness is not None
        self.harness.write8("wEnemyMonPartyPos", 0)
        self.harness.write8("wEnemyMon2HP", 0)
        self.harness.write8("wEnemyMon2HP", 0, offset=1)

        selected, multiplier = self.call_selector_with_sentinels()

        self.assertEqual(selected, 2)
        self.assertEqual(multiplier, 20)

    def test_equal_matchups_choose_the_earliest_living_slot(self) -> None:
        self.boot_fixture("SNORLAX", ["PIKACHU", "RATTATA", "PIDGEY"])
        assert self.harness is not None
        self.harness.write8("wEnemyMonPartyPos", 0)

        selected, multiplier = self.call_selector_with_sentinels()

        self.assertEqual(selected, 1)
        self.assertEqual(multiplier, 20)

    def test_ready_reserve_outranks_frozen_equal_matchup(self) -> None:
        self.boot_fixture("SNORLAX", ["PIKACHU", "RATTATA", "PIDGEY"])
        assert self.harness is not None
        self.harness.write8("wEnemyMonPartyPos", 0)
        self.harness.write8("wEnemyMon2Status", 1 << 5)

        selected, score = self.call_selector_with_sentinels()

        self.assertEqual(selected, 2)
        self.assertEqual(score, 20)

    def test_ready_reserve_outranks_sleeping_equal_matchup(self) -> None:
        self.boot_fixture("SNORLAX", ["PIKACHU", "RATTATA", "PIDGEY"])
        assert self.harness is not None
        self.harness.write8("wEnemyMonPartyPos", 0)
        self.harness.write8("wEnemyMon2Status", 3)

        selected, score = self.call_selector_with_sentinels()

        self.assertEqual(selected, 2)
        self.assertEqual(score, 20)

    def test_statused_reserve_remains_best_of_bad_set_fallback(self) -> None:
        self.boot_fixture("SNORLAX", ["PIKACHU", "RATTATA", "PIDGEY"])
        assert self.harness is not None
        self.harness.write8("wEnemyMonPartyPos", 0)
        self.harness.write8("wEnemyMon2Status", 1 << 5)
        self.harness.write8("wEnemyMon3HP", 0)
        self.harness.write8("wEnemyMon3HP", 0, offset=1)

        selected, score = self.call_selector_with_sentinels()

        self.assertEqual(selected, 1)
        self.assertEqual(score, 60)

    def test_enemy_send_out_full_flow_uses_effectiveness_ranking(self) -> None:
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [self.mon("BLASTOISE")],
            [self.mon("CHARIZARD"), self.mon("GEODUDE"), self.mon("GENGAR")],
            trainer_class=self.trainers["COOLTRAINER_M"],
            ai_tier=3,
        )
        send_outs = self.harness.hook_enemy_send_out()

        self.harness.boot_fight2(seed=1)

        # The trainer's opening mon is chosen before the player's battle-mon
        # block is loaded, so it cannot prove matchup-aware replacement. Start
        # a real later EnemySendOut with the player type now authoritative.
        #
        # 2026-09-01: that same fact is now handled in the engine rather than
        # only worked around here. AISelectSendOut takes the FIRST LIVING mon on
        # the opening send-out (wEnemyMonPartyPos is $ff only at that moment) and
        # scores candidates only for later replacements, because ranking the lead
        # against the player's team is information a trainer does not have - and
        # it was reading a stale wBattleMonType1 from the PREVIOUS battle anyway.
        # See pending_contracts.json:phase4-opening-sendout-player-type-context.
        # So previous_slot below is now 0 (party order) rather than 2 (the old
        # scored pick). The assertions this test actually exists for -
        # ranked_slot and selected_slot on a real replacement - are unchanged.
        #
        # Faint ONLY the active mon. This used to also faint party slot 2,
        # which worked when the scored opening pick happened to make slot 2
        # active - with party-order leads that instead leaves a single eligible
        # candidate and proves nothing about ranking. Against BLASTOISE (Water)
        # the remaining two candidates are genuinely different: GEODUDE
        # (Rock/Ground, 4x = 80) and GENGAR (Ghost/Poison, 1x = 20), and lower
        # is better, so a correct ranking must choose GENGAR.
        send_outs.clear()
        self.harness.write8("wEnemyMonHP", 0)
        self.harness.write8("wEnemyMonHP", 0, offset=1)
        self.harness.probe_routine_until(
            "EnemySendOutFirstMon.next",
            lambda: bool(send_outs),
            limit=12000,
        )

        self.assertTrue(send_outs)
        first = send_outs[0]
        self.assertEqual(first["previous_slot"], 0)
        self.assertEqual(first["best_score"], 20, first)
        self.assertEqual(first["ranked_slot"], 2)
        self.assertEqual(first["selected_slot"], 2)


class AIShouldSwitchTest(unittest.TestCase):
    """AI_OVERHAUL_PLAN.md follow-up F18: Phase 4's other half.

    AIShouldSwitch is reached in real play only through the vanilla per-class
    item AI's own probability rolls (JugglerAI 25%, CooltrainerFAI's
    conditional-then-25%), which makes it both probabilistic to reach and
    trainer-class-dependent through the normal battle flow - unsuitable for a
    deterministic ai_scenarios.json fixture. Called directly via call_routine
    instead, mirroring AISelectSendOutTest's own established pattern above.

    AIShouldSwitch cannot return its carry result through call_routine (that
    helper restores every saved register including F on return - see
    PYBOY_HARNESS_REFERENCE.md). Its two exits are hooked directly instead:
    .stay and .switch are at DIFFERENT addresses (.vanilla shares .switch's
    address, since the T0/T1 early-out and every emergency trigger use the
    identical unconditional scf/ret tail), so which hook fires is the result.
    """

    harness: RedRogueHarness | None = None

    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.species = parse_rgbds_constants(
            REPO_ROOT / "constants" / "pokemon_constants.asm"
        )
        self.moves = parse_rgbds_constants(
            REPO_ROOT / "constants" / "move_constants.asm"
        )
        self.trainers = parse_trainer_constants(
            REPO_ROOT / "constants" / "trainer_constants.asm"
        )
        self.ai = parse_rgbds_constants(REPO_ROOT / "constants" / "ai_constants.asm")

    def tearDown(self) -> None:
        if self.harness is not None:
            self.harness.close()

    def call_ai_should_switch(self) -> None:
        """call_routine("AIShouldSwitch") for a decision computed fresh
        against the board as THIS test left it. boot_fight2 now makes turn
        1's whole decision silently before its own first menu appears
        (ai_turn_plan.asm, 2026-10-22), so wAIPlayerKOCache/wAIReliableKOFound
        may still hold that decision's answer for the board as it was before
        this test primed it; AIShouldSwitch's trigger 2 (AIPlayerWouldKO)
        would otherwise reuse that stale answer instead of recomputing one
        for the board this test actually set up. call_routine's own "fresh
        decision" precondition only resets the damage-estimate span
        (wAIEnemyEstimateCache/wAIPlayerKOMaxDamage, FOLLOWUPS #48) - it is
        deliberately NOT a global reset of these two, since other tests
        (test_ai_checkpoint_b, test_ai_reliable_ko_wins) prime a specific
        wAIPlayerKOCache/wAIReliableKOFound value and need call_routine to
        leave it alone."""
        assert self.harness is not None
        for label in ("wAIPlayerKOCache", "wAIReliableKOFound"):
            self.harness.write8(label, 0)
        self.harness.call_routine("AIShouldSwitch")

    def mon(self, species: str, moves: list[str] | None = None) -> dict[str, object]:
        return {
            "species": self.species[species],
            "level": 50,
            "moves": [self.moves[name] for name in (moves or ["TACKLE"])],
        }

    def call_should_switch(
        self,
        player: dict[str, object],
        enemy: list[dict[str, object]],
        ai_tier: int,
        prime: dict[str, int] | None = None,
        reveal: list[int] | None = None,
        post_boot=None,
    ) -> bool:
        """Returns True if AIShouldSwitch chose to switch, False if it stayed.

        reveal: player move slots already shown this battle. Every tier is fair
        play, so an unrevealed slot 0 reads as a visible-type guess.
        """
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [player], enemy,
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=ai_tier,
        )
        self.harness.boot_fight2(seed=1)
        self.harness.write8("wEnemyMonPartyPos", 0)
        if prime:
            for label, value in prime.items():
                self.harness.write8(label, value)
        if reveal is not None:
            self.harness.reveal_player_moves(0, reveal, clear=True)
        if post_boot is not None:
            post_boot(self.harness)
        switch = self.harness.hook_flag("AIShouldSwitch.switch")
        stay = self.harness.hook_flag("AIShouldSwitch.stay")
        self.call_ai_should_switch()
        self.assertEqual(switch["count"] + stay["count"], 1, "exactly one exit must fire")
        return bool(switch["count"])

    def prime_lethal_hp(self) -> None:
        """Primes the ACTIVE enemy mon into the range AIPlayerWouldKO reports true.

        Just ABOVE a quarter HP: below it, B5 (AISacrificeBeatsSwitch) keeps a
        low-value mon in on purpose, which is not what these fixtures test.
        """
        assert self.harness is not None
        max_hi, max_lo = self.harness.read_bytes("wEnemyMonMaxHP", 2)
        max_hp = (max_hi << 8) | max_lo
        value = max(1, max_hp // 4 + 1)
        self.harness.write8("wEnemyMonHP", value >> 8, offset=0)
        self.harness.write8("wEnemyMonHP", value & 0xFF, offset=1)

    def prime_both_sides_lethal(self) -> None:
        """Put both active mons in ordinary-hit finishing range."""
        assert self.harness is not None
        self.prime_lethal_hp()
        max_hi, max_lo = self.harness.read_bytes("wBattleMonMaxHP", 2)
        max_hp = (max_hi << 8) | max_lo
        value = max(1, max_hp * 1 // 20)
        self.harness.write8("wBattleMonHP", value >> 8, offset=0)
        self.harness.write8("wBattleMonHP", value & 0xFF, offset=1)

    def call_lethal_exchange(self, enemy_move: str, *, disabled: bool = False) -> bool:
        """Return AIShouldSwitch's choice when either active mon can finish."""
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [self.mon("SNORLAX", ["BODY_SLAM"])],
            # Geodude resists Body Slam and survives it, so the B4 survival gate
            # does not mask the veto logic these tests are about.
            [self.mon("ELECTRODE", [enemy_move]), self.mon("GEODUDE")],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=2,
        )
        self.harness.boot_fight2(seed=1)
        self.harness.write8("wEnemyMonPartyPos", 0)
        self.harness.write8("wEnemySelectedMove", self.moves[enemy_move])
        self.harness.write8("wEnemyMoveListIndex", 0)
        self.prime_both_sides_lethal()
        if disabled:
            self.harness.write8("wEnemyDisabledMove", 0x11)
        switch = self.harness.hook_flag("AIShouldSwitch.switch")
        stay = self.harness.hook_flag("AIShouldSwitch.stay")
        self.call_ai_should_switch()
        self.assertEqual(switch["count"] + stay["count"], 1)
        return bool(switch["count"])

    def test_reliable_first_ko_vetoes_emergency_switch(self) -> None:
        self.assertFalse(self.call_lethal_exchange("TACKLE"))

    def test_unreliable_ko_does_not_veto_emergency_switch(self) -> None:
        self.assertTrue(self.call_lethal_exchange("FIRE_BLAST"))

    def test_disabled_ko_does_not_veto_emergency_switch(self) -> None:
        self.assertTrue(self.call_lethal_exchange("TACKLE", disabled=True))

    def test_charge_turn_damage_does_not_veto_emergency_switch(self) -> None:
        self.assertTrue(self.call_lethal_exchange("SOLARBEAM"))

    def test_zero_power_fixed_damage_can_veto_emergency_switch(self) -> None:
        self.assertFalse(self.call_lethal_exchange("NIGHT_SHADE"))

    def test_unselected_finisher_does_not_veto_emergency_switch(self) -> None:
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [self.mon("SNORLAX", ["BODY_SLAM"])],
            [self.mon("ELECTRODE", ["SPLASH", "TACKLE"]), self.mon("GEODUDE")],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=2,
        )
        self.harness.boot_fight2(seed=1)
        self.harness.write8("wEnemyMonPartyPos", 0)
        self.harness.write8("wEnemySelectedMove", self.moves["SPLASH"])
        self.harness.write8("wEnemyMoveListIndex", 0)
        self.prime_both_sides_lethal()
        switch = self.harness.hook_flag("AIShouldSwitch.switch")
        stay = self.harness.hook_flag("AIShouldSwitch.stay")
        self.call_ai_should_switch()
        self.assertEqual((switch["count"], stay["count"]), (1, 0))

    def slower_selected_finisher(self, enemy_status: int = 0, *, move: str = "TACKLE",
                                 player_status1: int = 0,
                                 safe_from_player: bool = False) -> tuple[int, int]:
        """Slower Slowpoke with `move` selected; the reserve is Geodude (immune
        to Thunderbolt), so B4's survival gate and B5's sacrifice rule never
        mask the vetoes under test.

        safe_from_player=False (default): both sides in ordinary-hit finishing
        range (prime_both_sides_lethal). The known threat is Thunderbolt, super
        effective, so the player's believed moveset also reliably KOs us.
        safe_from_player=True: only OUR finisher is lethal. The enemy mon
        (Slowpoke)'s HP is set to a synthetic 999 - the documented ceiling a
        believed delivery never exceeds (ai_constants.asm's AIPlayerKOMaxDamage
        comment) - rather than its real max HP: a full-HP Slowpoke is still
        within a critical, max-roll Thunderbolt's reach (measured: the KO scan
        reported "yes" at 160/160), since this emergency check is a POSSIBLE
        delivery, not AIMoveIsReliableKO's 90%-confidence bar.
        """
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [self.mon("ELECTRODE", ["THUNDERBOLT"])],
            [self.mon("SLOWPOKE", [move]), self.mon("GEODUDE")],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=2,
        )
        self.harness.boot_fight2(seed=1)
        self.harness.write8("wEnemyMonPartyPos", 0)
        self.harness.write8("wEnemySelectedMove", self.moves[move])
        self.harness.write8("wEnemyMoveListIndex", 0)
        self.harness.write8("wEnemyMonStatus", enemy_status)
        self.harness.write8("wPlayerBattleStatus1", player_status1)
        self.harness.reveal_player_moves(0, [0], clear=True)
        if safe_from_player:
            self.harness.write8("wEnemyMonHP", 999 >> 8, offset=0)
            self.harness.write8("wEnemyMonHP", 999 & 0xFF, offset=1)
            max_hi, max_lo = self.harness.read_bytes("wBattleMonMaxHP", 2)
            max_hp = (max_hi << 8) | max_lo
            value = max(1, max_hp * 1 // 20)
            self.harness.write8("wBattleMonHP", value >> 8, offset=0)
            self.harness.write8("wBattleMonHP", value & 0xFF, offset=1)
        else:
            self.prime_both_sides_lethal()
        switch = self.harness.hook_flag("AIShouldSwitch.switch")
        stay = self.harness.hook_flag("AIShouldSwitch.stay")
        self.call_ai_should_switch()
        return switch["count"], stay["count"]

    def test_slower_selected_ko_now_switches_when_the_player_also_kos(self) -> None:
        # 2026-10-22: the enemy's switch is now decided and executed BEFORE
        # either side's move (Gen 2 timing, ai_turn_plan.asm), so a slower
        # mon's own finisher no longer "lands first" - the switch pre-empts it
        # entirely. AIEnemyHasReliableFirstKO's veto now requires acting first
        # OR the player's believed moveset being unable to KO us; here Slowpoke
        # is slower AND Thunderbolt (believed) can finish it, so the veto does
        # not hold and the emergency trigger switches. This inverts the
        # pre-2026-10-22 rule (TrainerAI used to run at the enemy's action
        # point, after the player had already acted, so staying to land a
        # survived hit was always correct - probe_ai_review_phase0 F1).
        self.assertEqual(self.slower_selected_finisher(), (1, 0))

    def test_slower_selected_ko_still_vetoes_when_the_player_cannot_ko_back(self) -> None:
        # Companion case for the inverted rule above: slower, but the player's
        # believed moveset cannot reach us this turn, so there is no race to
        # lose by staying - the veto holds exactly as it always did.
        self.assertEqual(
            self.slower_selected_finisher(safe_from_player=True), (0, 1))

    # Codex follow-up R1: the player's state at the enemy's action point.
    # wPlayerBattleStatus1 bit 5 = USING_TRAPPING_MOVE, bit 6 = INVULNERABLE.
    def test_newly_landed_trap_voids_the_winning_action_veto(self) -> None:
        # A Wrap that landed first means our finisher cannot be used this turn;
        # trapped and slower, the trap trigger then switches.
        self.assertEqual(self.slower_selected_finisher(player_status1=1 << 5), (1, 0))

    def test_invulnerable_target_voids_the_veto_except_for_swift(self) -> None:
        self.assertEqual(self.slower_selected_finisher(player_status1=1 << 6), (1, 0))

    def test_swift_now_switches_against_an_invulnerable_target(self) -> None:
        # 2026-10-22: Swift still reaches an invulnerable (Fly/Dig) target, so
        # the reliable-KO check passes as before, but Slowpoke is slower and
        # the player's believed Thunderbolt can also KO us (prime_both_sides_
        # lethal, the fixture's default) - same inversion as the plain-Tackle
        # case above: the switch pre-empts our finisher, so it fires instead
        # of staying.
        self.assertEqual(
            self.slower_selected_finisher(move="SWIFT", player_status1=1 << 6), (1, 0))

    def test_swift_still_vetoes_when_the_player_cannot_ko_back(self) -> None:
        # Companion case, mirroring test_slower_selected_ko_still_vetoes_
        # when_the_player_cannot_ko_back: Swift still reaches the invulnerable
        # target, and with no race to lose (the player can't KO us this
        # turn), the veto holds exactly as it always did.
        self.assertEqual(
            self.slower_selected_finisher(move="SWIFT", player_status1=1 << 6,
                                          safe_from_player=True), (0, 1))

    def test_paralyzed_finisher_does_not_veto_emergency_switch(self) -> None:
        # 25% full paralysis puts the KO below the 90% reliability bar.
        self.assertEqual(self.slower_selected_finisher(enemy_status=1 << 6), (1, 0))

    def test_emergency_player_would_ko_forces_switch(self) -> None:
        # T2 deliberately, not T3: this is the highest-priority DETERMINISTIC
        # trigger and must fire before the T3-only probabilistic generic case
        # is even reachable, so proving it at T2 (where that generic case does
        # not exist at all) isolates it cleanly. Uses prime_lethal_hp rather
        # than call_should_switch's plain prime dict, since the lethal HP
        # value depends on the mon's real max HP.
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [self.mon("SNORLAX", ["BODY_SLAM"])],
            [self.mon("PIKACHU"), self.mon("GEODUDE")],  # a reserve that survives (B4)
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=2,
        )
        self.harness.boot_fight2(seed=1)
        self.harness.write8("wEnemyMonPartyPos", 0)
        self.prime_lethal_hp()
        switch = self.harness.hook_flag("AIShouldSwitch.switch")
        stay = self.harness.hook_flag("AIShouldSwitch.stay")
        self.call_ai_should_switch()
        self.assertEqual((switch["count"], stay["count"]), (1, 0))

    # --- AI_BACKLOG B5: sacrifice instead of an expensive emergency switch ------
    def reserve_hit(self, h) -> int:
        """Body Slam's one-hit maximum into party slot 1, via the estimator."""
        saved = {label: h.read_bytes(label, 2)
                 for label in ("wEnemyMonType1", "wEnemyMonDefense", "wEnemyMonSpecial")}
        for live, party in (("wEnemyMonType1", "wEnemyMon2Type1"),
                            ("wEnemyMonDefense", "wEnemyMon2Defense"),
                            ("wEnemyMonSpecial", "wEnemyMon2Special")):
            for offset, value in enumerate(h.read_bytes(party, 2)):
                h.write8(live, value, offset=offset)
        bank, address = h.symbols.get("Moves")
        rom = (REPO_ROOT / "pokeblue_debug.gbc").read_bytes()
        start = bank * 0x4000 + address - 0x4000 + (self.moves["BODY_SLAM"] - 1) * 6
        for offset, value in enumerate(rom[start:start + 6]):
            h.write8("wPlayerMoveNum", value, offset=offset)
        h.call_routine("AIEstimatePlayerDamage")
        hit = int.from_bytes(bytes(h.read_bytes("wAIDamageEstimate", 2)), "big")
        for label, values in saved.items():
            for offset, value in enumerate(values):
                h.write8(label, value, offset=offset)
        return hit

    def sacrifice_case(self, reserve: str, reserve_hp=None, *, low_active=False):
        """(switched, sacrifice-gate calls, hit, reserve HP, reserve max HP)."""
        info = {}

        def post_boot(h):
            self.prime_lethal_hp()
            if low_active:
                max_hp = int.from_bytes(bytes(h.read_bytes("wEnemyMonMaxHP", 2)), "big")
                h.write8("wEnemyMonHP", 0)
                h.write8("wEnemyMonHP", max(1, max_hp // 20), offset=1)
            info["max"] = int.from_bytes(bytes(h.read_bytes("wEnemyMon2MaxHP", 2)), "big")
            info["hit"] = self.reserve_hit(h)
            if reserve_hp is not None:
                info["hp"] = reserve_hp(info["hit"])
                h.write8("wEnemyMon2HP", info["hp"] >> 8)
                h.write8("wEnemyMon2HP", info["hp"] & 255, offset=1)
            info["gate"] = h.hook_flag("AISacrificeBeatsSwitch")

        switched = self.call_should_switch(
            self.mon("SNORLAX", ["BODY_SLAM"]), [self.mon("PIKACHU"), self.mon(reserve)],
            ai_tier=2, reveal=[0], post_boot=post_boot)
        return (switched, info["gate"]["count"], info["hit"], info.get("hp"), info["max"])

    def test_low_value_active_is_sacrificed_for_a_free_entry(self) -> None:
        # B5: Pikachu at 1/20 HP faces the KO; Geodude would survive the switch,
        # but saving a nearly spent mon is worth less than a free entry.
        switched, gate, *_ = self.sacrifice_case("GEODUDE", low_active=True)
        self.assertEqual((switched, gate), (False, 1))

    def test_reserve_that_would_lose_half_is_not_spent_on_a_switch(self) -> None:
        # B5: Wigglytuff survives Body Slam but loses at least half its HP to it,
        # so the switch spends most of the answer. HP = 2 x hit: the hit takes
        # exactly half (the boundary), it survives, and it is still at least
        # half its max (no ranking HP penalty), so the sacrifice gate - not the
        # ranking or B4 - is what decides. Measured: hit 91, max HP 216.
        switched, gate, hit, hp, max_hp = self.sacrifice_case(
            "WIGGLYTUFF", lambda hit: 2 * hit)
        self.assertGreaterEqual(2 * hp, max_hp, f"hit {hit}, hp {hp}/{max_hp}")
        self.assertEqual((switched, gate), (False, 1))

    # --- E2 voluntary target (AI_T4_REGRET_PLAN, 2026-11-17) ----------------------
    # Paired replays measured T3's KO-threat switches losing +0.158 of party HP per
    # switch to a better TARGET: the pick was the legacy defence-only ranking. T3 now
    # re-ranks the reserves that beat the active mon with the post-KO tiers, each
    # after paying the entry hit (AIRankVoluntaryTarget).
    def voluntary_target(self, ai_tier: int, machamp_hp: int | None = None) -> tuple[bool, int]:
        def board(h) -> None:
            if machamp_hp is not None:
                h.write8("wEnemyMon3HP", machamp_hp >> 8)
                h.write8("wEnemyMon3HP", machamp_hp & 0xFF, offset=1)
            self.prime_lethal_hp()  # the KO-threat trigger, above B5's quarter-HP sacrifice
            h.write8("wBattleMonHP", 0)
            # Measured: Karate Chop's expected damage 44, Geodude's Tackle 22. At 30 HP the
            # Chop is a reliable KO (FINISH) and Tackle is not; at 45 both were
            # SURVIVE_REPLY and the lower legacy score (Geodude) rightly won the tie.
            h.write8("wBattleMonHP", 30, offset=1)

        switched = self.call_should_switch(
            self.mon("SNORLAX", ["BODY_SLAM"]),
            # Electrode's Growl cannot trip the "we KO first" veto. Geodude resists Body
            # Slam (the legacy pick); Machamp is faster and finishes with Karate Chop.
            [self.mon("ELECTRODE", ["GROWL"]), self.mon("GEODUDE", ["TACKLE"]),
             self.mon("MACHAMP", ["KARATE_CHOP"])],
            ai_tier=ai_tier, reveal=[0], post_boot=board,
        )
        return switched, self.harness.read8("wBuffer", offset=19)  # AI_BUF_BESTPARTYSLOT

    def test_t3_voluntary_switch_picks_the_reserve_that_finishes(self) -> None:
        self.assertEqual(self.voluntary_target(3), (True, 2))

    def test_t3_voluntary_switch_never_picks_a_reserve_the_entry_hit_kos(self) -> None:
        # The same finisher at 5 HP dies to Body Slam on the way in: Geodude again.
        self.assertEqual(self.voluntary_target(3, machamp_hp=5), (True, 1))

    def test_t2_voluntary_switch_keeps_the_defensive_pick(self) -> None:
        # Negative control on the same board: T2 is not re-ranked.
        self.assertEqual(self.voluntary_target(2), (True, 1))

    # --- B17 stalemate breaker (AI_T4_REGRET_PLAN, 2026-11-17) ------------------------
    # Seed 288: a Weezing whose only attacks are self-KO trades the Explosion veto
    # refuses looped Amnesia/Haze ~30 turns at +0.22 of party HP per turn. Through
    # the real turn plan (boot_fight2 makes turn 1's decision), because the trigger
    # reads the damage estimates AI_DAMAGE leaves for that decision.
    def stalemate_plan(self, weezing_moves: list[str], ai_tier: int = 3) -> int:
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            # Two Ekans: the veto lets a trade through against the LAST mon.
            [dict(self.mon("EKANS", ["POISON_STING", "LEER"]), level=10),
             dict(self.mon("EKANS", ["POISON_STING", "LEER"]), level=10)],
            [dict(self.mon("WEEZING", weezing_moves), level=60),
             dict(self.mon("CLEFABLE", ["BODY_SLAM"]), level=58)],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=ai_tier,
        )
        self.harness.boot_fight2(seed=1)
        return self.harness.read8("wAITurnPlan")

    def test_stalemate_switches_to_a_reserve_that_can_reply(self) -> None:
        plan = self.stalemate_plan(["AMNESIA", "SELFDESTRUCT", "HAZE", "EXPLOSION"])
        self.assertTrue(plan >> 6 & 1, f"switch bit, plan {plan:#04x}")
        self.assertEqual(plan & 0b111, 2, "slot 1 (Clefable) + 1")

    def test_stalemate_t2_switches_too(self) -> None:
        plan = self.stalemate_plan(["AMNESIA", "SELFDESTRUCT", "HAZE", "EXPLOSION"], ai_tier=2)
        self.assertTrue(plan >> 6 & 1, f"plan {plan:#04x}")

    def test_trapped_enemy_scans_slots_without_reading_sentinel_move(self) -> None:
        h = self.harness
        scans, reads = [], []
        h.hook_flag("AIPlanEnemyTurn", action=lambda: h.write8("wPlayerBattleStatus1", 1 << 5))
        h.hook_flag("AIActiveCanDoNothing.scan",
                    action=lambda: scans.append(h.read8("wEnemySelectedMove")))
        h.hook_flag("AIActiveCanDoNothing.moveByte",
                    action=lambda: reads.append(h.pyboy.register_file.B))
        self.stalemate_plan(["AMNESIA", "SELFDESTRUCT", "HAZE", "EXPLOSION"])
        self.assertIn(0xff, scans)
        self.assertNotIn(0xff, reads)

    def test_a_chosen_status_move_is_not_a_stalemate(self) -> None:
        # A status user keeps its status move: Thunder Wave on a healthy Ekans is
        # progress, unlike seed 288's Amnesia/Haze loop.
        plan = self.stalemate_plan(["THUNDER_WAVE", "SELFDESTRUCT", "HAZE", "EXPLOSION"])
        self.assertEqual(self.harness.read8("wEnemySelectedMove"), self.moves["THUNDER_WAVE"])
        self.assertFalse(plan >> 6 & 1, f"plan {plan:#04x}")

    def stalemate_verdict(self, moves: list[str], *, status: int = 0, confused: bool = False,
                          disabled: int = 0) -> bool:
        """AIActiveCanDoNothing's answer for a Weezing that chose moves[0], every PP left. Estimates
        are cleared, so a damaging move counts as usable unless the routine knows it cannot work."""
        h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        try:
            h.inject_fight2_spec(
                [dict(self.mon("EKANS", ["POISON_STING"]), level=10)] * 2,
                [dict(self.mon("WEEZING", moves), level=60), dict(self.mon("CLEFABLE", ["BODY_SLAM"]), level=58)],
                trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3)
            h.boot_fight2(seed=1)
            entered = h.hook_flag("AIActiveCanDoNothing")
            can_act = h.hook_flag("AIActiveCanDoNothing.canAct")
            h.write8("wEnemySelectedMove", self.moves[moves[0]])
            h.write8("wEnemyMoveListIndex", 0)
            h.write8("wBattleMonStatus", status)
            h.write8("wPlayerBattleStatus1", 1 << 7 if confused else 0)
            h.write8("wPlayerBattleStatus2", 0)
            h.write8("wPlayerDisabledMove", disabled)
            for offset in range(8):
                h.write8("wAIEnemyEstimateCache", 0, offset)
            h.call_routine("AIActiveCanDoNothing")
            self.assertEqual(entered["count"], 1)
            return can_act["count"] == 0
        finally:
            h.close()

    def test_a_status_move_that_cannot_land_is_a_stalemate(self) -> None:
        """Seed 9008 (2026-11-24): ~70 turns of Poison Gas into a paralyzed target."""
        par = 1 << 6
        for moves, board, stuck in (
                (["POISON_GAS", "HAZE"], {"status": par}, True), (["POISON_GAS", "HAZE"], {}, False),
                (["CONFUSE_RAY", "HAZE"], {"confused": True}, True), (["CONFUSE_RAY", "HAZE"], {"status": par}, False),
                (["DISABLE", "HAZE"], {"disabled": 0x13}, True), (["DISABLE", "HAZE"], {}, False)):
            with self.subTest(moves=moves, board=board):
                self.assertEqual(self.stalemate_verdict(moves, **board), stuck)

    def test_dream_eater_is_an_attack_only_against_a_sleeper(self) -> None:
        # HAZE is chosen, so only Dream Eater could make this a board Weezing can act on.
        for status, stuck in ((1 << 6, True), (3, False)):
            with self.subTest(status=status):
                self.assertEqual(self.stalemate_verdict(["HAZE", "DREAM_EATER"], status=status), stuck)

    def toxic_staller(self, player_status: int) -> bool:
        def board(h) -> None:
            h.write8("wEnemySelectedMove", self.moves["DOUBLE_TEAM"])
            h.write8("wBattleMonStatus", player_status)
        return self.call_should_switch(
            dict(self.mon("RATTATA", ["TACKLE"]), level=10),
            [dict(self.mon("WEEZING", ["DOUBLE_TEAM", "REST", "TOXIC", "REFLECT"]), level=60),
             dict(self.mon("CLEFABLE", ["BODY_SLAM"]), level=58)],
            ai_tier=3, reveal=[0], post_boot=board,
        )

    def test_toxic_staller_keeps_stalling_while_the_player_is_poisoned(self) -> None:
        # Once Toxic lands, Double Team / Rest / Reflect turns are the plan, not a
        # stalemate: the poison does the damage. PSN (bit 3) is set for Toxic too.
        self.assertFalse(self.toxic_staller(1 << 3))

    def test_toxic_staller_with_nothing_ticking_is_a_stalemate(self) -> None:
        # Control on the same board: no residual on the player, no damage of ours.
        self.assertTrue(self.toxic_staller(0))

    def test_a_usable_attack_is_not_a_stalemate(self) -> None:
        # Negative control: Sludge deals damage, so Weezing stays and attacks.
        plan = self.stalemate_plan(["AMNESIA", "SELFDESTRUCT", "SLUDGE", "EXPLOSION"])
        self.assertFalse(plan >> 6 & 1, f"plan {plan:#04x}")

    # --- T3 generic bad-matchup case (AIBadMatchupRoll, $10 since 2026-11-18) -----------
    def bad_matchup_rolls(self, player: str, move: str, calls: int = 16) -> tuple[int, int]:
        """(switches, roll reached) over repeated decisions on one board; the roll's Random
        draws advance between calls."""
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            # One weak revealed move: no KO threat and no super-effective reply, so nothing
            # above the generic case decides. It must carry the player's type: the reserve
            # check ranks by the BELIEVED threat types (measured: with Tackle alone, Venusaur
            # was no better off than Starmie and the roll's 14/16 passes all stayed).
            # Venusaur resists Electric but is not immune, so free switch-in stays out of it.
            [self.mon(player, [move])],
            [self.mon("STARMIE", ["TACKLE"]), self.mon("VENUSAUR", ["VINE_WHIP"])],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3,
        )
        self.harness.boot_fight2(seed=1)
        self.harness.write8("wEnemyMonPartyPos", 0)
        self.harness.reveal_player_moves(0, [0], clear=True)
        switch = self.harness.hook_flag("AIShouldSwitch.switch")
        stay = self.harness.hook_flag("AIShouldSwitch.stay")
        roll = self.harness.hook_flag("AIBadMatchupRoll")
        for _ in range(calls):
            self.call_ai_should_switch()
        self.assertEqual(switch["count"] + stay["count"], calls)
        return switch["count"], roll["count"]

    def test_t3_bad_matchup_switches_on_the_roll(self) -> None:
        # Electric into Water/Psychic is x2: the 75% roll decides, so both outcomes occur.
        switches, rolls = self.bad_matchup_rolls("PIKACHU", "THUNDERSHOCK")
        self.assertEqual(rolls, 16)
        self.assertTrue(0 < switches < 16, f"{switches}/16 switched")

    def test_t3_neutral_matchup_never_switches(self) -> None:
        # Control: Normal into Starmie is neutral, so the roll is never drawn as a pass.
        switches, rolls = self.bad_matchup_rolls("RATTATA", "TACKLE")
        self.assertEqual((switches, rolls), (0, 16))

    # --- B17 Toxic pressure (Pokemon Stadium 1's term, 2026-11-17) ------------------
    # Stadium adds toxicCounter * 77 to its switch score against a -127 baseline and
    # doubles it when seeded: counter >= 2, or >= 1 while seeded, switches.
    def toxic_case(self, counter: int, *, seeded: bool = False, ai_tier: int = 3,
                   player_hp: int | None = None, accuracy: int = 7) -> tuple[bool, int]:
        """counter 0 = not poisoned at all; accuracy = the AI's accuracy stage (7 neutral)."""
        hit = {}

        def board(h) -> None:
            h.write8("wEnemySelectedMove", self.moves["WATER_GUN"])
            h.write8("wEnemyMoveListIndex", 0)
            h.write8("wEnemyMonAccuracyMod", accuracy)
            if counter:
                h.write8("wEnemyMonStatus", 1 << 3)  # PSN
                h.write8("wEnemyBattleStatus3", h.read8("wEnemyBattleStatus3") | 1)  # BADLY_POISONED
            h.write8("wEnemyToxicCounter", counter)
            if seeded:
                h.write8("wEnemyBattleStatus2", h.read8("wEnemyBattleStatus2") | 0x80)  # SEEDED
            if player_hp is not None:
                h.write8("wBattleMonHP", player_hp >> 8)
                h.write8("wBattleMonHP", player_hp & 0xFF, offset=1)
            hit["toxic"] = h.hook_flag("AIPushOutTerms")

        switched = self.call_should_switch(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("SLOWBRO", ["WATER_GUN"]), self.mon("CLEFABLE", ["BODY_SLAM"])],
            ai_tier=ai_tier, reveal=[0], post_boot=board,
        )
        self.assertEqual(hit["toxic"]["count"], 1, "the Toxic check must be reached")
        return switched, self.harness.read8("wBuffer", offset=19)

    def test_toxic_counter_two_switches_out(self) -> None:
        self.assertEqual(self.toxic_case(2), (True, 1))

    def test_toxic_counter_one_stays(self) -> None:
        self.assertFalse(self.toxic_case(1)[0])

    def test_toxic_counter_one_while_seeded_switches_out(self) -> None:
        self.assertEqual(self.toxic_case(1, seeded=True), (True, 1))

    def test_toxic_pressure_applies_at_t2(self) -> None:
        self.assertTrue(self.toxic_case(2, ai_tier=2)[0])

    def test_toxic_pressure_yields_to_a_reliable_first_ko(self) -> None:
        # The player cannot hurt Slowbro, so landing Water Gun on a 1-HP Snorlax is
        # reliable whoever moves first: stay and take the KO (Stadium's -255).
        self.assertFalse(self.toxic_case(4, player_hp=1)[0])

    # Stadium's other push-out term: a lowered accuracy stage (measured 2026-11-18 on 200
    # forced states: -1 +0.052, -2 +0.095 of party HP for switching, over the undropped state).
    def test_lowered_accuracy_switches_out(self) -> None:
        self.assertEqual(self.toxic_case(0, accuracy=6), (True, 1))

    def test_neutral_accuracy_and_no_poison_stays(self) -> None:
        self.assertFalse(self.toxic_case(0)[0])

    def test_lowered_accuracy_yields_to_a_reliable_first_ko(self) -> None:
        self.assertFalse(self.toxic_case(0, accuracy=6, player_hp=1)[0])

    # --- B17 free switch-in target (AI_T4_REGRET_PLAN, 2026-11-17) -------------------
    # 600 seeds: where a reserve was immune to every damaging player move, the best switch
    # beat the best stay by +0.071 of party HP. AIFreeSwitchInTarget finds such a reserve:
    # immune by type to every believed threat (cheap), then the real B4 scan must keep
    # half its HP (prices fixed-damage moves, which ignore immunity in this engine).
    def free_in(self, player_moves: list[str], enemy: list[str]) -> tuple[bool, int, int]:
        """(found, AI_BUF_BESTPARTYSLOT, B4 scans run = reserves that passed the type stage)."""
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [self.mon("PIKACHU", player_moves)], [self.mon(name, ["TACKLE"]) for name in enemy],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3,
        )
        self.harness.boot_fight2(seed=1)
        self.harness.write8("wEnemyMonPartyPos", 0)
        self.harness.reveal_player_moves(0, list(range(len(player_moves))), clear=True)
        types = self.harness.read_bytes("wEnemyMonType1", 2)
        found = self.harness.hook_flag("AIFreeSwitchInTarget.found")
        none = self.harness.hook_flag("AIFreeSwitchInTarget.noneRestore")
        scans = self.harness.hook_flag("AIBestReserveSurvivesThreat")
        self.harness.call_routine("AIFreeSwitchInTarget")
        self.assertEqual(found["count"] + none["count"], 1, "exactly one exit must fire")
        self.assertEqual(self.harness.read_bytes("wEnemyMonType1", 2), types,
                         "the active mon's live types must be restored")
        return (bool(found["count"]), self.harness.read8("wBuffer", offset=19),  # AI_BUF_BESTPARTYSLOT
                scans["count"])

    def test_free_switch_in_finds_the_immune_reserve(self) -> None:
        # Thunderbolt only: Geodude (Ground) takes nothing, Starmie takes it super effective.
        self.assertEqual(self.free_in(["THUNDERBOLT"], ["STARMIE", "GEODUDE"]), (True, 1, 1))

    def test_free_switch_in_skips_to_a_later_immune_slot(self) -> None:
        # Slowbro fails the type stage, so only Sandslash costs a B4 scan.
        self.assertEqual(self.free_in(["THUNDERBOLT"], ["STARMIE", "SLOWBRO", "SANDSLASH"]),
                         (True, 2, 1))

    def test_free_switch_in_rejects_a_reserve_one_threat_reaches(self) -> None:
        found, _, scans = self.free_in(["THUNDERBOLT", "SURF"], ["STARMIE", "GEODUDE"])
        self.assertEqual((found, scans), (False, 0), "rejected by the type stage, no B4 scan")

    def test_free_switch_in_prices_fixed_damage_that_ignores_immunity(self) -> None:
        # The type stage passes (Seismic Toss is left out of the threat types), but the
        # toss deals the user's level to a Ground type too; the faster Pikachu then hits
        # Geodude twice before it acts, so B4 says it does not keep half.
        found, _, scans = self.free_in(["THUNDERBOLT", "SEISMIC_TOSS"], ["STARMIE", "GEODUDE"])
        self.assertEqual((found, scans), (False, 1), "passed the type stage, rejected by B4")

    def test_free_switch_in_ignores_an_active_mon_that_is_already_immune(self) -> None:
        found, _, scans = self.free_in(["THUNDERBOLT"], ["RHYHORN", "GEODUDE"])
        self.assertEqual((found, scans), (False, 0))

    def free_in_decision(self, ai_tier: int) -> tuple[bool, int, int]:
        # Clefairy takes Thunderbolt neutrally and survives it, so neither the KO
        # trigger nor the bad-matchup case can be what switches; Pound keeps the
        # stalemate breaker (no damaging move) out of it too.
        hit = {}
        switched = self.call_should_switch(
            self.mon("PIKACHU", ["THUNDERBOLT"]),
            [self.mon("CLEFAIRY", ["POUND"]), self.mon("GEODUDE", ["TACKLE"])],
            ai_tier=ai_tier, reveal=[0],
            post_boot=lambda h: hit.update(found=h.hook_flag("AIFreeSwitchInTarget.found")),
        )
        return switched, self.harness.read8("wBuffer", offset=19), hit["found"]["count"]

    def test_t3_switches_into_a_free_switch_in(self) -> None:
        self.assertEqual(self.free_in_decision(3), (True, 1, 1))

    def test_t2_has_no_free_switch_in_term(self) -> None:
        self.assertFalse(self.free_in_decision(2)[0])

    def test_reserve_that_keeps_half_is_switched_in(self) -> None:
        # Control for the case above: at 2 x hit + 2 HP it keeps more than half.
        switched, gate, *_ = self.sacrifice_case("WIGGLYTUFF", lambda hit: 2 * hit + 2)
        self.assertEqual((switched, gate), (True, 1))

    # --- B4/B5 combined scan (Codex review 2026-10-22) -------------------------
    # B4's reserve scan derives B5's half-HP answer (wBuffer + AI_BUF_RESERVEHALF)
    # from its largest delivery instead of B5 rescanning at half HP. These pin
    # the derived answer to the rescan (AIBestReserveKeepsHalf, the reference)
    # at the rounding boundaries, and Super Fang, which the delivery leaves out,
    # to a NO with no rescan. UNKNOWN ($FF) was the old Super Fang marker; the
    # ROM no longer stores it, and the asserts keep it out.
    RESERVE_HALF = {"NO": 0, "KEEPS": 1, "UNKNOWN": 0xFF}

    def half_answers(self, player_moves: list[str], reserve_hps, reserve: str = "WIGGLYTUFF") -> list[dict[str, int]]:
        """Per reserve HP: the derived answer, B4's largest delivery, the
        rescan's answer (1 keeps half, 0 not), and how often B5's gate itself
        fell back to the rescan. reserve_hps(hit) maps the measured full-HP
        delivery to the HPs to test."""
        h = self.harness
        assert h is not None
        h.inject_fight2_spec(
            [self.mon("RATICATE", player_moves)],
            [self.mon("PIKACHU"), self.mon(reserve)],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=2,
        )
        h.boot_fight2(seed=1)
        h.write8("wEnemyMonPartyPos", 0)
        h.reveal_player_moves(0, list(range(len(player_moves))), clear=True)
        scans: list[tuple[int, int]] = []
        exits: list[int] = []
        rf = h.pyboy.register_file
        h.register_hook("_AIBestReserveThreatScan.storeHalf",
                        lambda _ctx: scans.append((rf.A, (rf.D << 8) | rf.E)))
        h.register_hook("_AIBestReserveThreatScan.restore", lambda _ctx: exits.append(rf.E))
        rescans = h.hook_flag("AIBestReserveKeepsHalf")

        def run(label: str) -> None:
            h.write8("wBuffer", 1, offset=self.ai["AI_BUF_BESTPARTYSLOT"])
            h.call_routine(label)

        run("AIBestReserveSurvivesThreat")
        hit = scans[-1][1]
        results = []
        for hp in reserve_hps(hit):
            h.write8("wEnemyMon2HP", hp >> 8)
            h.write8("wEnemyMon2HP", hp & 0xFF, offset=1)
            run("AIBestReserveSurvivesThreat")
            derived, delivery = scans[-1]
            self.assertEqual(h.read8("wBuffer", self.ai["AI_BUF_RESERVEHALF"]), derived)
            # The gate first: the reference rescan below writes the byte too.
            before = rescans["count"]
            run("AISacrificeBeatsSwitch")  # the active mon is at full HP
            gate_rescans = rescans["count"] - before
            run("AIBestReserveKeepsHalf")
            rescan = exits[-1]
            results.append({"hp": hp, "hit": hit, "derived": derived, "delivery": delivery,
                            "rescan": rescan, "gate_rescans": gate_rescans})
        return results

    def assert_derived_matches_rescan(self, results) -> None:
        for r in results:
            with self.subTest(hp=r["hp"]):
                self.assertNotEqual(r["derived"], self.RESERVE_HALF["UNKNOWN"], r)
                self.assertEqual(r["derived"], r["rescan"], r)
                self.assertEqual(r["gate_rescans"], 0, r)

    def test_derived_half_answer_matches_the_rescan_at_even_hp(self) -> None:
        # HP 2 x hit: the hit takes exactly half (NO); 2 x hit + 2 keeps more.
        # Electrode outspeeds the player's Raticate, so the half test applies
        # (B5 v2: a faster reserve acts right after the entry hit).
        results = self.half_answers(["BODY_SLAM"], lambda hit: (2 * hit, 2 * hit + 2), reserve="ELECTRODE")
        self.assert_derived_matches_rescan(results)
        self.assertEqual([r["derived"] for r in results],
                         [self.RESERVE_HALF["NO"], self.RESERVE_HALF["KEEPS"]], results)

    def test_derived_half_answer_matches_the_rescan_at_odd_hp(self) -> None:
        # Both scans round HP / 2 down: at 2 x hit + 1 the half is the hit
        # itself (NO), at 2 x hit - 1 it is below it (NO), and 2 x hit + 3 keeps.
        results = self.half_answers(
            ["BODY_SLAM"], lambda hit: (2 * hit - 1, 2 * hit + 1, 2 * hit + 3), reserve="ELECTRODE")
        self.assert_derived_matches_rescan(results)
        self.assertEqual([r["derived"] for r in results],
                         [self.RESERVE_HALF["NO"], self.RESERVE_HALF["NO"],
                          self.RESERVE_HALF["KEEPS"]], results)

    def test_slower_reserve_must_survive_two_hits_and_a_crit(self) -> None:
        # B5 v2: Wigglytuff is slower than the player's Raticate, so it takes the
        # entry hit and next turn's before it acts. It must keep 3 x hit < HP:
        # 2 x hit + 2 kept "half" before v2 and is now a NO; 3 x hit is still a
        # NO; 3 x hit + 1 KEEPS. (The Super Fang rescan keeps the half rule.)
        results = self.half_answers(
            ["BODY_SLAM"], lambda hit: (2 * hit + 2, 3 * hit, 3 * hit + 1))
        self.assertEqual([r["derived"] for r in results],
                         [self.RESERVE_HALF["NO"], self.RESERVE_HALF["NO"], self.RESERVE_HALF["KEEPS"]], results)

    # --- AI review CP1 (2026-11-12): the reserve's Speed after send-out ---------
    # Send-out quarters a paralysed mon's Speed (minimum 1), so B5 v2's
    # faster-reserve half test must not see the raw party Speed.
    PAR = 1 << 6

    def reserve_speed_runner(self):
        """Boots once (player Raticate, reserve Electrode in slot 2) and returns
        run(status, reserve_speed=None, player_speed=None): B4's scan with those
        values, reporting the entry Speed reserveIsFaster computed, the Speeds
        used, and whether the faster-reserve half test ran. One boot per test:
        the harness cannot boot FIGHT 2 twice."""
        h = self.harness
        assert h is not None
        h.inject_fight2_spec(
            [self.mon("RATICATE", ["BODY_SLAM"])],
            [self.mon("PIKACHU"), self.mon("ELECTRODE")],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=2,
        )
        h.boot_fight2(seed=1)
        h.write8("wEnemyMonPartyPos", 0)
        h.reveal_player_moves(0, [0], clear=True)
        rf = h.pyboy.register_file
        entry: list[int] = []
        h.register_hook("_AIBestReserveThreatScan.gotSpeed", lambda _ctx: entry.append((rf.D << 8) | rf.E))
        half_test = h.hook_flag("_AIBestReserveThreatScan.halfTest")
        word = lambda label: int.from_bytes(bytes(h.read_bytes(label, 2)), "big")
        healthy = {"party": word("wEnemyMon2Speed"), "player": word("wBattleMonSpeed")}

        def write_word(label: str, value: int) -> None:
            h.write8(label, value >> 8)
            h.write8(label, value & 0xFF, offset=1)

        def run(status: int, reserve_speed: int | None = None, player_speed: int | None = None):
            h.write8("wEnemyMon2Status", status)
            write_word("wEnemyMon2Speed", healthy["party"] if reserve_speed is None else reserve_speed)
            write_word("wBattleMonSpeed", healthy["player"] if player_speed is None else player_speed)
            before_entry, before_half = len(entry), half_test["count"]
            h.write8("wBuffer", 1, offset=self.ai["AI_BUF_BESTPARTYSLOT"])
            h.call_routine("AIBestReserveSurvivesThreat")
            self.assertEqual(len(entry) - before_entry, 1, "the scan must reach the speed check once (no KO)")
            return {"entry": entry[-1], "party": word("wEnemyMon2Speed"), "player": word("wBattleMonSpeed"),
                    "faster": half_test["count"] > before_half}

        return run, healthy

    def test_healthy_reserve_speed_is_unchanged(self) -> None:
        run, _ = self.reserve_speed_runner()
        r = run(0)
        self.assertEqual(r["entry"], r["party"], r)
        self.assertGreater(r["party"], r["player"], r)  # Electrode outspeeds Raticate
        self.assertTrue(r["faster"], r)

    def test_paralysis_reverses_the_order(self) -> None:
        run, _ = self.reserve_speed_runner()
        r = run(self.PAR)
        self.assertEqual(r["entry"], max(1, r["party"] // 4), r)
        self.assertLess(r["entry"], r["player"], r)
        self.assertFalse(r["faster"], r)  # B5 v2's slower rule: 3 x hit < HP

    def test_paralysed_reserve_can_still_be_faster(self) -> None:
        run, healthy = self.reserve_speed_runner()
        r = run(self.PAR, player_speed=healthy["party"] // 4 - 1)
        self.assertTrue(r["faster"], r)

    def test_equal_entry_speed_counts_as_slower(self) -> None:
        run, healthy = self.reserve_speed_runner()
        r = run(self.PAR, player_speed=healthy["party"] // 4)
        self.assertEqual(r["entry"], r["player"], r)
        self.assertFalse(r["faster"], r)

    def test_paralysed_speed_has_a_minimum_of_one(self) -> None:
        run, _ = self.reserve_speed_runner()
        for party in (0, 3, 4):
            with self.subTest(party=party):
                r = run(self.PAR, reserve_speed=party, player_speed=0)
                self.assertEqual(r["entry"], max(1, party // 4), r)
                self.assertTrue(r["faster"], r)  # 1 beats a player Speed of 0

    def test_reserve_ko_is_a_no_without_a_rescan(self) -> None:
        # HP = hit: B4 stops at the KO and never measures the rest; NO, as the
        # rescan says.
        results = self.half_answers(["BODY_SLAM"], lambda hit: (hit,))
        self.assert_derived_matches_rescan(results)
        self.assertEqual(results[0]["derived"], self.RESERVE_HALF["NO"], results)

    def test_super_fang_is_a_half_no_without_a_rescan(self) -> None:
        # Super Fang takes max(1, floor(HP / 2)) of the reserve's own HP, which
        # always meets the half bar, so the scan answers NO itself, odd HP or
        # even, and B5's gate never rescans. Body Slam alone would keep half
        # here, so the NO must come from Super Fang. The reference rescan agrees.
        results = self.half_answers(
            ["SUPER_FANG", "BODY_SLAM"], lambda hit: (4 * hit, 4 * hit + 1))
        for r in results:
            with self.subTest(hp=r["hp"]):
                self.assertLess(2 * r["delivery"], r["hp"], r)  # Body Slam keeps half
                self.assertEqual(r["derived"], self.RESERVE_HALF["NO"], r)
                self.assertEqual(r["rescan"], 0, r)
                self.assertEqual(r["gate_rescans"], 0, r)

    def test_baseline_healthy_no_threat_stays(self) -> None:
        # Splash is revealed: with no type guess left, there is no threat.
        self.assertFalse(self.call_should_switch(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("PIKACHU"), self.mon("RATTATA")],
            ai_tier=2,
            reveal=[0],
        ))

    def test_unrevealed_type_guess_is_a_threat(self) -> None:
        # Same board with nothing revealed: slot 0 reads as Body Slam (Normal
        # STAB guess), which can KO the Pikachu. Geodude resists Normal, so it
        # is strictly better off and the emergency trigger switches to it.
        self.assertTrue(self.call_should_switch(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("PIKACHU"), self.mon("GEODUDE")],
            ai_tier=2,
        ))

    def test_no_emergency_switch_into_a_reserve_that_would_be_koed(self) -> None:
        # B4: Geodude resists the Body Slam guess, so it ranks better than
        # Pikachu, but at 1 HP it dies to it anyway. Staying at least attacks.
        self.assertFalse(self.call_should_switch(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("PIKACHU"), self.mon("GEODUDE")],
            ai_tier=2,
            prime={"wEnemyMon2HP": 0},  # high byte; the low byte is set below
            post_boot=lambda h: h.write8("wEnemyMon2HP", 1, offset=1),
        ))

    def reserve_slot_hit(self, h, slot: int, move: str = "BODY_SLAM") -> int:
        """The player's `move` one-hit maximum into enemy party slot `slot` (1-based)."""
        saved = {label: h.read_bytes(label, 2)
                 for label in ("wEnemyMonType1", "wEnemyMonDefense", "wEnemyMonSpecial", "wPlayerMoveNum")}
        for live, field in (("wEnemyMonType1", "Type1"), ("wEnemyMonDefense", "Defense"),
                            ("wEnemyMonSpecial", "Special")):
            for offset, value in enumerate(h.read_bytes(f"wEnemyMon{slot}{field}", 2)):
                h.write8(live, value, offset=offset)
        bank, address = h.symbols.get("Moves")
        rom = (REPO_ROOT / "pokeblue_debug.gbc").read_bytes()
        start = bank * 0x4000 + address - 0x4000 + (self.moves[move] - 1) * 6
        for offset, value in enumerate(rom[start:start + 6]):
            h.write8("wPlayerMoveNum", value, offset=offset)
        h.call_routine("AIEstimatePlayerDamage")
        hit = int.from_bytes(bytes(h.read_bytes("wAIDamageEstimate", 2)), "big")
        for label, values in saved.items():
            for offset, value in enumerate(values):
                h.write8(label, value, offset=offset)
        return hit

    def fallback_case(self, second: str, a_dies: bool = True):
        """FOLLOWUPS #88 board: player Snorlax L60 with Body Slam REVEALED (it used
        to be Splash unrevealed with the old type table guessing Body Slam; E1's
        learnset guess says Hyper Beam at 60, and reserve_slot_hit prices Body
        Slam, so the threat is now explicit), enemy Pikachu at 2/5 HP (lethal), reserves
        Aerodactyl (resists Normal: ranked best) at a lethal HP when a_dies, and
        `second`. Returns (switched, chosen slot, info)."""
        info = {}

        def post_boot(h):
            word = lambda label: int.from_bytes(bytes(h.read_bytes(label, 2)), "big")  # noqa: E731
            active_hp = word("wEnemyMonMaxHP") * 2 // 5
            h.write8("wEnemyMonHP", active_hp >> 8)
            h.write8("wEnemyMonHP", active_hp & 255, offset=1)
            for slot in (2, 3):
                info[slot] = {"max": word(f"wEnemyMon{slot}MaxHP"), "hit": self.reserve_slot_hit(h, slot),
                              "speed": word(f"wEnemyMon{slot}Speed")}
            info["player_speed"] = word("wBattleMonSpeed")
            if a_dies:  # above a quarter (no HP-penalty reorder) and at or below the hit
                a_hp = max(info[2]["max"] // 4 + 1, min(info[2]["hit"], info[2]["max"] - 1))
                h.write8("wEnemyMon2HP", a_hp >> 8)
                h.write8("wEnemyMon2HP", a_hp & 255, offset=1)
                info[2]["hp"] = a_hp
            info["checks"] = h.hook_flag("AIBestReserveSurvivesThreat")

        player = dict(self.mon("SNORLAX", ["BODY_SLAM"]), level=60)
        switched = self.call_should_switch(
            player, [self.mon("PIKACHU"), self.mon("AERODACTYL"), self.mon(second)],
            ai_tier=2, reveal=[0], post_boot=post_boot)
        return switched, self.harness.read8("wBuffer", 19), info

    def test_fallback_switches_to_the_next_reserve_that_survives(self) -> None:
        # FOLLOWUPS #88, its own reproduction board: Aerodactyl ranks best but
        # dies on entry (the guessed Body Slam does 51 to its 51 HP). The enemy
        # Snorlax outspeeds the player's (57 vs 54) and keeps more than half (102
        # of 230), so B4 and B5 v2 both pass it. Before the fallback the AI
        # stayed in and its Pikachu died.
        switched, slot, info = self.fallback_case("SNORLAX")
        self.assertGreaterEqual(info[2]["hit"], info[2]["hp"], info)  # Aerodactyl really dies
        self.assertGreater(info[3]["speed"], info["player_speed"], info)
        self.assertLess(2 * info[3]["hit"], info[3]["max"], info)  # Snorlax keeps half
        self.assertEqual(info["checks"]["count"], 2)  # Aerodactyl, then Snorlax
        self.assertTrue(switched)
        self.assertEqual(slot, 2)

    def test_fallback_still_stays_when_the_next_reserve_would_lose_half(self) -> None:
        # Tauros survives the entry hit, and is faster, but it would lose 78 of
        # 145: B5 sacrifices the active mon rather than spend most of Tauros.
        switched, slot, info = self.fallback_case("TAUROS")
        self.assertEqual(info["checks"]["count"], 2)
        self.assertGreaterEqual(2 * info[3]["hit"], info[3]["max"], info)
        self.assertFalse(switched)

    def test_no_emergency_switch_into_a_reserve_no_better_off(self) -> None:
        # Review F5 (2026-09-29): Rattata takes Body Slam exactly as Pikachu
        # does, at the same full HP, so switching only hands over a free hit.
        self.assertFalse(self.call_should_switch(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("PIKACHU"), self.mon("RATTATA")],
            ai_tier=2,
        ))

    def test_grace_period_outranks_emergency_triggers(self) -> None:
        # Review F5: a mon sent in on the previous decision stays for one
        # decision even when frozen with a healthy reserve behind it.
        self.assertFalse(self.call_should_switch(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("PIKACHU"), self.mon("GEODUDE")],
            ai_tier=2,
            prime={"wEnemyMonStatus": 1 << 5, "wAISwitchedFlags": 1},
        ))

    def test_frozen_forces_switch(self) -> None:
        self.assertTrue(self.call_should_switch(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("PIKACHU"), self.mon("RATTATA")],
            ai_tier=2,
            prime={"wEnemyMonStatus": 1 << 5},  # FRZ
        ))

    def test_long_sleep_forces_switch(self) -> None:
        self.assertTrue(self.call_should_switch(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("PIKACHU"), self.mon("RATTATA")],
            ai_tier=2,
            prime={"wEnemyMonStatus": 3},  # SLP_MASK, 3 turns remaining
        ))

    def test_short_sleep_does_not_force_switch(self) -> None:
        # Waking up next turn is better than spending the switch and handing
        # the player a free hit anyway - a 1-turn sleep is deliberately left
        # alone (AIShouldSwitch's own comment: "cp 2 / jp nc, .switch").
        self.assertFalse(self.call_should_switch(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("PIKACHU"), self.mon("RATTATA")],
            ai_tier=2,
            prime={"wEnemyMonStatus": 1},
            reveal=[0],
        ))

    def test_trapped_and_slower_forces_switch(self) -> None:
        # Cannot break out by KOing first, so staying trapped is pure loss.
        self.assertTrue(self.call_should_switch(
            self.mon("ELECTRODE", ["SPLASH"]),  # faster than Slowpoke
            [self.mon("SLOWPOKE"), self.mon("RATTATA")],
            ai_tier=2,
            prime={"wPlayerBattleStatus1": 1 << 5},  # USING_TRAPPING_MOVE
        ))

    def test_trapped_but_faster_does_not_force_switch(self) -> None:
        # Still gets to act despite being trapped, so no emergency exists.
        self.assertFalse(self.call_should_switch(
            self.mon("SLOWPOKE", ["SPLASH"]),  # slower than Electrode
            [self.mon("ELECTRODE"), self.mon("RATTATA")],
            ai_tier=2,
            prime={"wPlayerBattleStatus1": 1 << 5},
        ))

    def test_veto_super_effective_move_keeps_mon_in(self) -> None:
        # T3 deliberately: only at T3 does the generic bad-matchup case exist
        # for the veto to actually suppress. Electric is a real threat to
        # Water/Flying (the Water half doubles what Flying takes neutrally),
        # so without the veto this would be a genuine bad-matchup candidate
        # for the generic case; the veto must short-circuit BEFORE that
        # roll ever executes, which is what makes this deterministic despite
        # the generic case itself being probabilistic.
        self.assertFalse(self.call_should_switch(
            self.mon("GYARADOS", ["SPLASH"]),
            [self.mon("PIKACHU", ["THUNDERBOLT"]), self.mon("RATTATA")],
            ai_tier=3,
        ))

    def test_veto_stat_boost_keeps_mon_in(self) -> None:
        self.assertFalse(self.call_should_switch(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("PIKACHU"), self.mon("RATTATA")],
            ai_tier=3,
            prime={"wEnemyMonAttackMod": 9},  # strictly above BASE_STAT_LEVEL (7)
        ))

    def test_grace_period_suppresses_reevaluation_after_a_switch(self) -> None:
        # wAISwitchedFlags bit 0 = "party slot 0 was just switched in by
        # AISelectSendOut" - the exact state a fresh send-out leaves behind.
        # Must suppress the T3 generic case's re-evaluation even on an
        # otherwise-benign board, which is the scenario that would otherwise
        # cause oscillation.
        self.assertFalse(self.call_should_switch(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("PIKACHU"), self.mon("RATTATA")],
            ai_tier=3,
            prime={"wAISwitchedFlags": 1 << 0},
        ))

    def test_t0_and_t1_bypass_smart_switching_entirely(self) -> None:
        # T0/T1 are "not supposed to switch intelligently" (the routine's own
        # header) and take an unconditional early exit sharing .switch's
        # address. A completely benign board (healthy, unstatused, no trap)
        # isolates this: any OTHER trigger would require a condition this
        # board does not have, so a switch result here can only be the T0/T1
        # early-out itself.
        #
        # A fresh RedRogueHarness per tier, not the shared self.harness:
        # boot_fight2 is not safe to call twice on one instance (confirmed by
        # this test itself, before this fix - the second boot_fight2 in the
        # loop failed with "DebugMenu was not reached").
        for tier in (0, 1):
            with self.subTest(tier=tier):
                harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
                try:
                    harness.inject_fight2_spec(
                        [self.mon("SNORLAX", ["SPLASH"])],
                        [self.mon("RATTATA"), self.mon("PIKACHU")],
                        trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=tier,
                    )
                    harness.boot_fight2(seed=1)
                    harness.write8("wEnemyMonPartyPos", 0)
                    switch = harness.hook_flag("AIShouldSwitch.switch")
                    stay = harness.hook_flag("AIShouldSwitch.stay")
                    harness.call_routine("AIShouldSwitch")
                    self.assertEqual((switch["count"], stay["count"]), (1, 0))
                finally:
                    harness.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
