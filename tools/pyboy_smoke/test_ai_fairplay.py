"""AI_OVERHAUL_PLAN.md follow-up F18: Phase 7 (fair play) had ZERO scenario
fixtures. It cannot get any through ai_scenarios.json either: as that phase's
own "honest, load-bearing finding" records, clearing AI_OMNISCIENT on T0/T1
currently has no observable effect on move SCORING at all - AIGetPlayerMoveN's
only consumer (AIPlayerWouldKO/AIHealWouldStillDie, ai_threat.asm) is reached
only through AI_THREAT (T3-only) or AIShouldSwitch's emergency trigger
(T2+), which were omniscient until 2026-09-29. Since then no tier is: every
tier reads the per-party-member revealed mask plus a visible-type guess, and
omniscience is the per-class AIOmniscientClasses opt-in (FINAL_AI). Before
that change there was no board where a
score-array assertion could distinguish "fair play worked" from "fair play is
wired up but nothing reads it yet". The mechanism itself has to be tested
directly against the routine, which is what this file does.

AIGetPlayerMoveN takes its slot argument in `a`, which makes it a genuinely
different testing problem from everything else in this backfill: `a` cannot
survive Bankswitch's own first instruction (`ldh a, [hLoadedROMBank]`)
inbound, so call_routine's normal ROMX path (which always routes through
Bankswitch) would destroy the argument before the routine's own first
instruction ever runs - the exact reason this routine cannot be farcalled in
real gameplay either (see its own header, ai_accessors.asm). Verified the same
way it was originally verified when Phase 7 shipped: map the target bank
directly (mirroring call_routine's own bank-restore step) and jump straight
to the routine, bypassing Bankswitch entirely, then hook the routine's own
`.exit` label (kept in the shipped file for exactly this) to capture `a`
before the `ret` that would otherwise carry it back into a caller context
this test does not have.
"""

from __future__ import annotations

import io
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import (
    parse_rgbds_constants,
    parse_trainer_constants,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"


def call_a_preserving(harness: RedRogueHarness, label: str, a_value: int) -> int:
    """Invokes a ROMX routine that takes its argument in `a`, bypassing the
    farcall/call_routine machinery that would destroy it inbound. Returns the
    value of `a` at the routine's own `.exit` label, then restores emulator
    state - the whole call is a side-effect-free probe, like
    probe_routine_until, not a normal call_routine completion.
    """
    harness.park_before_hijack()
    baseline = io.BytesIO()
    harness.save_state(baseline)
    bank, address = harness.symbols.get(label)
    exit_bank, exit_address = harness.symbols.get(f"{label}.exit")
    result: dict[str, int] = {}

    def capture(_context) -> None:
        result["a"] = harness.pyboy.register_file.A

    harness.pyboy.hook_register(exit_bank, exit_address, capture, None)
    try:
        # A return-address sentinel MUST be on the stack before the hijack,
        # matching probe_routine_until's own convention - without it, the
        # routine's own `ret` after .exit pops whatever garbage happens to be
        # on the stack from the parked VBlank context and jumps there, which
        # can burn the rest of the current tick() frame churning through
        # unrelated memory-as-instructions before PyBoy ever returns control
        # (confirmed: the hook fires correctly and instantly either way, but
        # omitting this sentinel made a single tick() call hang for the full
        # 30-second watchdog in the script that found this bug).
        return_address = 0x3FFF
        stack_pointer = (harness.pyboy.register_file.SP - 2) & 0xFFFF
        harness.pyboy.memory[stack_pointer] = return_address & 0xFF
        harness.pyboy.memory[stack_pointer + 1] = return_address >> 8
        harness.pyboy.register_file.SP = stack_pointer
        harness.pyboy.memory[0x2000] = bank
        harness.write8("hLoadedROMBank", bank)
        harness.pyboy.register_file.A = a_value
        harness.pyboy.register_file.PC = address
        harness.wait_until(lambda: "a" in result, f"{label}.exit", limit=300)
    finally:
        harness.pyboy.hook_deregister(exit_bank, exit_address)
        harness.load_state(baseline)
    return result["a"]


class AIGetPlayerMoveNTest(unittest.TestCase):
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

    def mon(self, species: str, moves: list[str]) -> dict[str, object]:
        return {
            "species": self.species[species],
            "level": 50,
            "moves": [self.moves[name] for name in moves],
        }

    def boot(self, ai_tier: int, player_moves: list[str]) -> None:
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [self.mon("SNORLAX", player_moves)],
            [self.mon("RATTATA", ["TACKLE"])],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=ai_tier,
        )
        self.harness.boot_fight2(seed=1)

    def prime_seen_moves(self, slots: list[int], party_slot: int = 0) -> None:
        """Mark move slots revealed for one player party member, clearing the
        rest of wAISeenPlayerMoveMask - the sparse state AIGetPlayerMoveN's
        fair-play branch must handle correctly."""
        assert self.harness is not None
        self.harness.reveal_player_moves(party_slot, slots, clear=True)

    def test_fair_play_tier_reads_only_revealed_moves(self) -> None:
        # The revealed set is sparse - slot 1 revealed (GROWL), slot 0 not.
        # Unseen slot 0 returns the visible-type guess (Snorlax is Normal ->
        # BODY_SLAM), never the real unrevealed TACKLE; unseen slot 2 has no
        # guess at all.
        assert self.harness is not None
        self.boot(ai_tier=1, player_moves=["TACKLE", "GROWL", "SPLASH"])
        growl = self.moves["GROWL"]
        self.prime_seen_moves([1])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 0),
                         self.moves["BODY_SLAM"])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 1), growl)

    def test_top_tier_is_fair_play_too(self) -> None:
        # 2026-09-29: T3 lost omniscience. Identical revealed-mask state as the
        # test above must give identical answers - the real unrevealed SPLASH
        # in slot 2 stays hidden.
        assert self.harness is not None
        self.boot(ai_tier=3, player_moves=["TACKLE", "GROWL", "SPLASH"])
        self.prime_seen_moves([1])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 0),
                         self.moves["BODY_SLAM"])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 1),
                         self.moves["GROWL"])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 2), 0)

    def test_t0_is_also_fair_play(self) -> None:
        # Nothing revealed: only the type guess for slot 0 (mono-Normal gets
        # no second guess in slot 1), and the real moves stay hidden.
        assert self.harness is not None
        self.boot(ai_tier=0, player_moves=["TACKLE", "GROWL", "SPLASH"])
        self.prime_seen_moves([])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 0),
                         self.moves["BODY_SLAM"])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 1), 0)

    def test_dual_type_guesses_one_move_per_visible_type(self) -> None:
        # Gyarados is Water/Flying: slot 0 guesses SURF, slot 1 DRILL_PECK.
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [{"species": self.species["GYARADOS"], "level": 50,
              "moves": [self.moves[m] for m in ("SPLASH", "GROWL", "LEER")]}],
            [self.mon("RATTATA", ["TACKLE"])],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3,
        )
        self.harness.boot_fight2(seed=1)
        self.prime_seen_moves([])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 0),
                         self.moves["SURF"])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 1),
                         self.moves["DRILL_PECK"])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 2), 0)

    def test_empty_slot_gets_no_guess(self) -> None:
        # A one-move Gyarados must not carry a phantom slot-1 attack forever.
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [{"species": self.species["GYARADOS"], "level": 50,
              "moves": [self.moves["SPLASH"]]}],
            [self.mon("RATTATA", ["TACKLE"])],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3,
        )
        self.harness.boot_fight2(seed=1)
        self.prime_seen_moves([])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 1), 0)

    def test_revealed_moves_do_not_follow_a_player_switch(self) -> None:
        # Review F6 (2026-09-29): moves revealed by party member 0 must not be
        # reported for party member 1. The old slot-indexed buffer did.
        assert self.harness is not None
        self.boot(ai_tier=1, player_moves=["TACKLE", "GROWL", "SPLASH"])
        self.prime_seen_moves([0, 1], party_slot=0)
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 1),
                         self.moves["GROWL"])
        self.harness.write8("wPlayerMonNumber", 1)
        # Member 1 revealed nothing: slot 0 is back to the type guess, and
        # member 0's GROWL does not carry over into slot 1.
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 0),
                         self.moves["BODY_SLAM"])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 1), 0)
        self.harness.reveal_player_moves(1, [0])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 0),
                         self.moves["TACKLE"])


class AITrackSeenPlayerMoveTest(unittest.TestCase):
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

    def test_records_the_move_at_its_real_moveset_slot(self) -> None:
        # AITrackSeenPlayerMove takes no register input (reads
        # wPlayerSelectedMove directly), so it is safely callable via the
        # normal call_routine path unlike AIGetPlayerMoveN above.
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [{
                "species": self.species["SNORLAX"], "level": 50,
                "moves": [self.moves[name] for name in
                          ("TACKLE", "GROWL", "SPLASH", "BODY_SLAM")],
            }],
            [{"species": self.species["RATTATA"], "level": 50,
              "moves": [self.moves["TACKLE"]]}],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=1,
        )
        self.harness.boot_fight2(seed=1)
        splash = self.moves["SPLASH"]  # real moveset slot 2
        self.harness.write8("wPlayerSelectedMove", splash)
        self.harness.call_routine("AITrackSeenPlayerMove")
        self.assertEqual(self.harness.revealed_player_moves(0), [2],
                         "must land in slot 2, not slot 0")
        self.assertEqual(self.harness.read_bytes("wAISeenPlayerMoveMask", 4),
                         [0b0100, 0, 0, 0])
        # An odd party slot writes the high nibble of the same byte.
        self.harness.write8("wPlayerMonNumber", 1)
        self.harness.park_before_hijack()
        self.harness.call_routine("AITrackSeenPlayerMove")
        self.assertEqual(self.harness.revealed_player_moves(1), [2])
        self.assertEqual(self.harness.read_bytes("wAISeenPlayerMoveMask", 4),
                         [0b0100_0100, 0, 0, 0])

    def test_zero_selected_move_is_never_recorded(self) -> None:
        # wPlayerSelectedMove == 0 is never a real move (the old buffer's "nothing
        # revealed" sentinel - the routine must bail rather than ever writing
        # 0 as if it meant something was recorded there.
        assert self.harness is not None
        self.harness.inject_fight2_spec(
            [{"species": self.species["SNORLAX"], "level": 50,
              "moves": [self.moves["TACKLE"]]}],
            [{"species": self.species["RATTATA"], "level": 50,
              "moves": [self.moves["TACKLE"]]}],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=1,
        )
        self.harness.boot_fight2(seed=1)
        self.harness.write8("wPlayerSelectedMove", 0)
        self.harness.call_routine("AITrackSeenPlayerMove")
        recorded = self.harness.read_bytes("wAISeenPlayerMoveMask", 4)
        self.assertEqual(recorded, [0, 0, 0, 0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
