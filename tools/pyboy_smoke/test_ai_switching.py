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

    def tearDown(self) -> None:
        if self.harness is not None:
            self.harness.close()

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
    ) -> bool:
        """Returns True if AIShouldSwitch chose to switch, False if it stayed."""
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
        switch = self.harness.hook_flag("AIShouldSwitch.switch")
        stay = self.harness.hook_flag("AIShouldSwitch.stay")
        self.harness.call_routine("AIShouldSwitch")
        self.assertEqual(switch["count"] + stay["count"], 1, "exactly one exit must fire")
        return bool(switch["count"])

    def prime_lethal_hp(self) -> None:
        """Primes the ACTIVE enemy mon into the range AIPlayerWouldKO reports true."""
        assert self.harness is not None
        max_hi, max_lo = self.harness.read_bytes("wEnemyMonMaxHP", 2)
        max_hp = (max_hi << 8) | max_lo
        value = max(1, max_hp * 1 // 20)
        self.harness.write8("wEnemyMonHP", value >> 8, offset=0)
        self.harness.write8("wEnemyMonHP", value & 0xFF, offset=1)

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
            [self.mon("PIKACHU"), self.mon("RATTATA")],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=2,
        )
        self.harness.boot_fight2(seed=1)
        self.harness.write8("wEnemyMonPartyPos", 0)
        self.prime_lethal_hp()
        switch = self.harness.hook_flag("AIShouldSwitch.switch")
        stay = self.harness.hook_flag("AIShouldSwitch.stay")
        self.harness.call_routine("AIShouldSwitch")
        self.assertEqual((switch["count"], stay["count"]), (1, 0))

    def test_baseline_healthy_no_threat_stays(self) -> None:
        self.assertFalse(self.call_should_switch(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("PIKACHU"), self.mon("RATTATA")],
            ai_tier=2,
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
