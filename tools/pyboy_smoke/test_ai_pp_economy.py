"""PP economy (Phase 4 of the 2026-10-20 AI review): B8 and B10.

Enemies spend PP since 2026-10-20 and a trainer's party keeps the PP it spent,
so a long battle leaves mons that can only Struggle.
- B10: AIScoreSendOutMon scores a mon with no damaging move left to use
  AI_SEND_OUT_SPENT, so the send-out ranking and AIReplacementIsBetter put it
  behind every mon that can still attack.
- B8: AIShouldSwitch switches a Struggling mon with no KO threat on it to a
  reserve that is better (B10) and survives the believed threat, unless
  Struggle reliably KOs first.
"""
from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"


class _PPEconomyBase(unittest.TestCase):
    harness: RedRogueHarness | None = None

    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.species = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")
        self.moves = parse_rgbds_constants(REPO_ROOT / "constants" / "move_constants.asm")
        self.trainers = parse_trainer_constants(REPO_ROOT / "constants" / "trainer_constants.asm")
        self.ai = parse_rgbds_constants(REPO_ROOT / "constants" / "ai_constants.asm")

    def tearDown(self) -> None:
        if self.harness is not None:
            self.harness.close()

    def mon(self, species: str, moves: list[str] | None = None) -> dict[str, object]:
        return {
            "species": self.species[species],
            "level": 50,
            "moves": [self.moves[name] for name in (moves or ["TACKLE"])],
        }

    def boot(self, player, enemy, tier: int) -> None:
        h = self.harness
        h.inject_fight2_spec([player], enemy,
                             trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=tier)
        h.boot_fight2(seed=1)
        h.write8("wEnemyMonPartyPos", 0)

    def spend_party_pp(self, slot: int, move_slots=range(4)) -> None:
        for move in move_slots:
            self.harness.write8(f"wEnemyMon{slot + 1}PP", 0, offset=move)

    def spend_active_pp(self) -> None:
        for move in range(4):
            self.harness.write8("wEnemyMonPP", 0, offset=move)


class SendOutRankingTest(_PPEconomyBase):
    """B10 through AISelectSendOut: three neutral matchups, so the earliest
    living reserve (slot 1) wins unless its PP is spent."""

    def select(self) -> tuple[int, int]:
        h = self.harness
        h.call_routine("AISelectSendOut")
        return h.read8("hWhichPokemon"), h.read8("wBuffer", self.ai["AI_BUF_BESTPARTYSCORE"])

    def boot_three(self, slot1_moves=None) -> None:
        self.boot(self.mon("SNORLAX"),
                  [self.mon("PIKACHU"), self.mon("RATTATA", slot1_moves), self.mon("PIDGEY")], tier=3)

    def test_control_earliest_reserve_with_pp(self) -> None:
        self.boot_three()
        self.assertEqual(self.select(), (1, 20))

    def test_spent_reserve_ranks_behind_one_that_can_attack(self) -> None:
        self.boot_three()
        self.spend_party_pp(1)
        self.assertEqual(self.select(), (2, 20))

    def test_status_move_pp_alone_does_not_count(self) -> None:
        self.boot_three(["TACKLE", "GROWL"])
        self.spend_party_pp(1, [0])
        self.assertEqual(self.select(), (2, 20))

    def test_fixed_damage_move_counts_as_an_attack(self) -> None:
        self.boot_three(["TACKLE", "SONICBOOM"])
        self.spend_party_pp(1, [0])
        self.assertEqual(self.select(), (1, 20))

    def test_night_shade_counts_as_an_attack(self) -> None:
        # Night Shade has base power 0; only its SPECIAL_DAMAGE_EFFECT marks it as damage.
        # shipped: (2, 20), the Night Shade reserve ranked as spent
        self.boot_three(["TACKLE", "NIGHT_SHADE"])
        self.spend_party_pp(1, [0])
        self.assertEqual(self.select(), (1, 20))

    def test_all_spent_still_sends_out_the_earliest(self) -> None:
        self.boot_three()
        self.spend_party_pp(1)
        self.spend_party_pp(2)
        self.assertEqual(self.select(), (1, self.ai["AI_SEND_OUT_SPENT"]))


class StruggleSwitchTest(_PPEconomyBase):
    """B8 at T2. Snorlax's Tackle cannot KO a full-HP Pikachu or Geodude."""

    def should_switch(self, selected: str = "STRUGGLE") -> bool:
        h = self.harness
        h.write8("wEnemySelectedMove", self.moves[selected])
        # A fresh decision against the board as this test left it: boot_fight2
        # now makes turn 1's whole decision silently before its own first menu
        # (ai_turn_plan.asm, 2026-10-22), so wAIPlayerKOCache/wAIReliableKOFound
        # may still hold that decision's answer rather than one that reflects
        # `selected`. call_routine's own "fresh decision" precondition only
        # resets the damage-estimate span, not these two (test_ai_switching.py
        # AIShouldSwitchTest.call_ai_should_switch has the same note).
        h.write8("wAIPlayerKOCache", 0)
        h.write8("wAIReliableKOFound", 0)
        switch = h.hook_flag("AIShouldSwitch.switch")
        stay = h.hook_flag("AIShouldSwitch.stay")
        h.call_routine("AIShouldSwitch")
        self.assertEqual(switch["count"] + stay["count"], 1, "exactly one exit must fire")
        return bool(switch["count"])

    def boot_struggling(self) -> None:
        self.boot(self.mon("SNORLAX"), [self.mon("PIKACHU"), self.mon("GEODUDE")], tier=2)
        self.harness.reveal_player_moves(0, [0], clear=True)
        self.spend_active_pp()

    def test_struggling_mon_switches_to_a_reserve_that_can_attack(self) -> None:
        self.boot_struggling()
        self.assertTrue(self.should_switch())

    def test_control_a_mon_with_a_move_stays(self) -> None:
        self.boot(self.mon("SNORLAX"), [self.mon("PIKACHU"), self.mon("GEODUDE")], tier=2)
        self.harness.reveal_player_moves(0, [0], clear=True)
        self.assertFalse(self.should_switch("TACKLE"))

    def test_struggling_mon_switches_to_a_night_shade_reserve(self) -> None:
        # shipped: stays, because a Night Shade-only reserve scored AI_SEND_OUT_SPENT too
        h = self.harness
        self.boot(self.mon("SNORLAX"),
                  [self.mon("PIKACHU"), self.mon("GEODUDE", ["NIGHT_SHADE"])], tier=2)
        h.reveal_player_moves(0, [0], clear=True)
        self.spend_active_pp()
        self.assertTrue(self.should_switch())

    def test_struggling_stays_when_the_reserve_is_spent_too(self) -> None:
        self.boot_struggling()
        self.spend_party_pp(1)
        self.assertFalse(self.should_switch())

    def test_struggling_stays_when_struggle_finishes_the_player(self) -> None:
        self.boot_struggling()
        self.harness.write8("wBattleMonHP", 0)
        self.harness.write8("wBattleMonHP", 1, offset=1)
        self.assertFalse(self.should_switch())


if __name__ == "__main__":
    unittest.main()
