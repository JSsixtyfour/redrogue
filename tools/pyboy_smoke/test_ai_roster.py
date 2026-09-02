"""AI_OVERHAUL_PLAN.md follow-up F18: Phase 6 (item AI + tier-scaled DVs/stat
exp) had ZERO scenario fixtures despite being fully implemented and gate-
verified by other means at ship time. Backfilled directly against the
routines, mirroring test_ai_switching.py's established pattern, for two
reasons specific to this phase:

1. Item AI (AIIncreaseStat and friends) is reached in real play only through
   per-trainer-class item AI dispatch with its own probability rolls, and its
   final "item genuinely used" path prints text and waits on real VBlank
   frames - which call_routine's hijack technique cannot survive (it parks
   inside the VBlank handler itself, where IME is disabled - see
   harness.park_before_hijack's docstring). probe_routine_until is used
   instead where the test needs to observe that the routine PROCEEDED past a
   gate, since it restores state as soon as its predicate holds rather than
   waiting for the routine to return.

2. Tier-scaled DVs/stat exp (AIRollEnemyDVs/AIFinishEnemyMonStats) cannot
   currently be exercised through inject_fight2_spec(ai_tier=N) at all - a
   real, separate bug in DebugFight2Setup's injected-spec build path writes
   wAIDebugTierOverride AFTER both parties are already built, so every DV
   roll sees the override still at 0 regardless of the requested tier. See
   pending_contracts.json:debugfight2-tier-override-written-after-dv-roll
   (Codex-owned file, not fixed here). Worked around by calling _AddPartyMon
   directly with the tier pre-resolved, bypassing the buggy ordering
   entirely - this is not a lesser test than going through FIGHT2 injection,
   since it exercises the exact same AI-side code (AddPartyMon's farcall to
   _AddPartyMon is the identical HOME wrapper the real ReadTrainer path uses).
"""

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
ENEMY_PARTY_DATA = 1
PARTYMON_STRUCT_LENGTH = 44


class RosterHarnessTestCase(unittest.TestCase):
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

    def mon(self, species: str, moves: list[str] | None = None,
            level: int = 50) -> dict[str, object]:
        return {
            "species": self.species[species],
            "level": level,
            "moves": [self.moves[name] for name in (moves or ["TACKLE"])],
        }

    def boot(self, player: dict[str, object], enemy: list[dict[str, object]],
             ai_tier: int) -> None:
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [player], enemy,
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=ai_tier,
        )
        self.harness.boot_fight2(seed=1)


class AIActiveMonIsAceTest(RosterHarnessTestCase):
    def call_is_ace(self, hp_alive: list[bool], active_slot: int) -> bool:
        """hp_alive[i] = whether party slot i is alive (nonzero HP)."""
        assert self.harness is not None
        self.boot(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("RATTATA")] * len(hp_alive),
            ai_tier=3,
        )
        self.harness.write8("wEnemyMonPartyPos", active_slot)
        base = self.harness.address("wEnemyMon1HP")
        for index, alive in enumerate(hp_alive):
            address = base + index * PARTYMON_STRUCT_LENGTH
            self.harness.pyboy.memory[address] = 0
            self.harness.pyboy.memory[address + 1] = 100 if alive else 0
        ace = self.harness.hook_flag("AIActiveMonIsAce.isAce")
        not_ace = self.harness.hook_flag("AIActiveMonIsAce.notAce")
        self.harness.call_routine("AIActiveMonIsAce")
        self.assertEqual(ace["count"] + not_ace["count"], 1)
        return bool(ace["count"])

    def test_last_living_party_member_is_ace(self) -> None:
        self.assertTrue(self.call_is_ace([True, False, False], active_slot=0))

    def test_not_ace_while_a_teammate_is_still_alive(self) -> None:
        self.assertFalse(self.call_is_ace([True, True, False], active_slot=0))

    def test_solo_mon_is_always_the_ace(self) -> None:
        self.assertTrue(self.call_is_ace([True], active_slot=0))


class TrainerAIItemGateTest(RosterHarnessTestCase):
    """The T2+ 'items only on the ace' restriction (TrainerAI's own gate,
    trainer_ai.asm) - distinct from AIIncreaseStat's own idempotence/KO gates
    below, which run only after this one has already let dispatch proceed."""

    def reaches_dispatch(self, ai_tier: int, ace: bool) -> bool:
        assert self.harness is not None
        self.boot(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("RATTATA"), self.mon("PIDGEY")],
            ai_tier=ai_tier,
        )
        self.harness.write8("wEnemyMonPartyPos", 0)
        # Teammate (slot 1) alive unless this mon is meant to be the ace.
        self.harness.write8("wEnemyMon2HP", 0 if ace else 100, offset=1)
        self.harness.write8("wAICount", 5)
        dispatch = self.harness.hook_flag("TrainerAI.dispatch")
        self.harness.hook_flag("TrainerAI.noItem")
        self.harness.call_routine("TrainerAI")
        return bool(dispatch["count"])

    def test_t2_non_ace_is_blocked_from_item_consideration(self) -> None:
        self.assertFalse(self.reaches_dispatch(ai_tier=2, ace=False))

    def test_t2_ace_reaches_item_dispatch(self) -> None:
        self.assertTrue(self.reaches_dispatch(ai_tier=2, ace=True))

    def test_t1_has_no_ace_restriction(self) -> None:
        # T0/T1 fall straight to .dispatch, unchanged from vanilla item AI -
        # the ace restriction is a T2+ rule.
        self.assertTrue(self.reaches_dispatch(ai_tier=1, ace=False))


class AIIncreaseStatGateTest(RosterHarnessTestCase):
    """Called via AIUseXAttack (which hardcodes its own b=effect/a=item id
    and needs no register input), not AIIncreaseStat directly - that routine
    takes both a and b as live register arguments from a same-bank jr, and a
    cannot survive call_routine's Bankswitch-routed entry regardless."""

    def probe(self, ai_tier: int, attack_mod: int, prime_lethal: bool) -> str:
        """Returns 'maxed', 'would_die', or 'proceed' - whichever gate/path
        was reached first. Uses probe_routine_until, not call_routine: the
        real 'item used' path prints text and halts waiting for a real
        VBlank frame, which cannot be driven through a hijacked PC (see this
        module's own header). Stopping at .proceed (before AIPrintItemUse_
        runs) is enough to prove the gates behaved correctly without needing
        the routine to complete.
        """
        assert self.harness is not None
        self.boot(
            self.mon("PIKACHU", ["THUNDERBOLT"]),
            [self.mon("SNORLAX", ["SPLASH"])],
            ai_tier=ai_tier,
        )
        self.harness.write8("wEnemyMonAttackMod", attack_mod)
        if prime_lethal:
            max_hi, max_lo = self.harness.read_bytes("wEnemyMonMaxHP", 2)
            max_hp = (max_hi << 8) | max_lo
            value = max(1, max_hp * 1 // 20)
            self.harness.write8("wEnemyMonHP", value >> 8, offset=0)
            self.harness.write8("wEnemyMonHP", value & 0xFF, offset=1)
        self.harness.call_routine("AIGetTier")  # resolve wAITier before the direct call
        proceed = self.harness.hook_flag("AIIncreaseStat.proceed")
        maxed = self.harness.hook_flag("AIIncreaseStat.maxedOut")
        would_die = self.harness.hook_flag("AIIncreaseStat.wouldDie")
        self.harness.probe_routine_until(
            "AIUseXAttack",
            lambda: bool(proceed["count"] or maxed["count"] or would_die["count"]),
        )
        if proceed["count"]:
            return "proceed"
        if maxed["count"]:
            return "maxed"
        return "would_die"

    def test_idempotence_skips_a_capped_stat(self) -> None:
        # Attack mod already at the Gen 1 cap ($D/13) - the boost would do
        # nothing, and StatModifierUpEffect's own "Nothing happened" refusal
        # happens too late (after announcing the item and spending a use).
        self.assertEqual(
            self.probe(ai_tier=2, attack_mod=13, prime_lethal=False), "maxed"
        )

    def test_ko_gate_skips_setup_when_player_would_kill(self) -> None:
        self.assertEqual(
            self.probe(ai_tier=2, attack_mod=7, prime_lethal=True), "would_die"
        )

    def test_t0_bypasses_the_ko_gate(self) -> None:
        self.assertEqual(
            self.probe(ai_tier=0, attack_mod=7, prime_lethal=True), "proceed"
        )

    def test_t1_bypasses_the_ko_gate(self) -> None:
        self.assertEqual(
            self.probe(ai_tier=1, attack_mod=7, prime_lethal=True), "proceed"
        )

    def test_normal_case_proceeds(self) -> None:
        self.assertEqual(
            self.probe(ai_tier=2, attack_mod=7, prime_lethal=False), "proceed"
        )


class TierScaledDVsAndStatExpTest(RosterHarnessTestCase):
    """AIRollEnemyDVs / AIFinishEnemyMonStats, exercised via a direct
    _AddPartyMon call with wAITier pre-resolved - see this module's own
    header for why inject_fight2_spec(ai_tier=N) cannot currently reach this
    code with the requested tier at all.
    """

    def add_enemy_mon_at_tier(self, ai_tier: int) -> tuple[int, int]:
        """Boots a minimal 1v1 battle, force-resolves ai_tier, then appends
        ONE new enemy mon via a direct _AddPartyMon call. Returns
        (dvs_byte0, dvs_byte1) for the newly appended slot - the party
        already has one enemy mon from boot_fight2, so the new mon lands at
        slot 1 (wEnemyMon2), never colliding with the boot-time mon.
        """
        assert self.harness is not None
        self.boot(
            self.mon("SNORLAX", ["SPLASH"]),
            [self.mon("RATTATA")],
            ai_tier=ai_tier,
        )
        self.harness.write8("wAIDebugTierOverride", ai_tier + 1)
        self.harness.call_routine("AIGetTier")
        before = self.harness.read8("wEnemyPartyCount")
        self.harness.write8("wCurPartySpecies", self.species["MACHOP"])
        self.harness.write8("wCurEnemyLevel", 50)
        self.harness.write8("wMonDataLocation", ENEMY_PARTY_DATA)
        self.harness.call_routine("_AddPartyMon", limit=2000)
        after = self.harness.read8("wEnemyPartyCount")
        self.assertEqual(after, before + 1, "the new mon must have been appended")
        slot = after - 1
        dvs = self.harness.read_bytes("wEnemyMon1DVs", 2, offset=slot * PARTYMON_STRUCT_LENGTH)
        return dvs[0], dvs[1]

    def stat_exp_word(self, slot: int) -> int:
        assert self.harness is not None
        hi, lo = self.harness.read_bytes(
            "wEnemyMon1AttackExp", 2, offset=slot * PARTYMON_STRUCT_LENGTH
        )
        return (hi << 8) | lo

    def test_t0_uses_the_exact_fixed_pair(self) -> None:
        atk_def, spd_spc = self.add_enemy_mon_at_tier(0)
        self.assertEqual((atk_def, spd_spc), (0x98, 0x88))  # ATKDEFDV_TRAINER/SPDSPCDV_TRAINER
        assert self.harness is not None
        self.assertEqual(self.stat_exp_word(1), 0, "T0 rolls no stat exp")

    def test_t1_floors_dv_nibbles_at_10_and_rolls_level_shift_6(self) -> None:
        atk_def, spd_spc = self.add_enemy_mon_at_tier(1)
        for byte in (atk_def, spd_spc):
            self.assertGreaterEqual(byte >> 4, 10, "high nibble below T1 floor")
            self.assertGreaterEqual(byte & 0xF, 10, "low nibble below T1 floor")
        assert self.harness is not None
        self.assertEqual(self.stat_exp_word(1), 50 << 6)

    def test_t2_floors_dv_nibbles_at_12_and_rolls_level_shift_7(self) -> None:
        atk_def, spd_spc = self.add_enemy_mon_at_tier(2)
        for byte in (atk_def, spd_spc):
            self.assertGreaterEqual(byte >> 4, 12, "high nibble below T2 floor")
            self.assertGreaterEqual(byte & 0xF, 12, "low nibble below T2 floor")
        assert self.harness is not None
        self.assertEqual(self.stat_exp_word(1), 50 << 7)

    def test_t3_floors_dv_nibbles_at_14_and_rolls_level_shift_8(self) -> None:
        atk_def, spd_spc = self.add_enemy_mon_at_tier(3)
        for byte in (atk_def, spd_spc):
            self.assertGreaterEqual(byte >> 4, 14, "high nibble below T3 floor")
            self.assertGreaterEqual(byte & 0xF, 14, "low nibble below T3 floor")
        assert self.harness is not None
        self.assertEqual(self.stat_exp_word(1), 50 << 8)


if __name__ == "__main__":
    unittest.main(verbosity=2)
