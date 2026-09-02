"""AI_OVERHAUL_PLAN.md follow-up F18: Phase 7 (fair play) had ZERO scenario
fixtures. It cannot get any through ai_scenarios.json either: as that phase's
own "honest, load-bearing finding" records, clearing AI_OMNISCIENT on T0/T1
currently has no observable effect on move SCORING at all - AIGetPlayerMoveN's
only consumer (AIPlayerWouldKO/AIHealWouldStillDie, ai_threat.asm) is reached
only through AI_THREAT (T3-only) or AIShouldSwitch's emergency trigger
(T2+), both of which stay omniscient regardless. So there is no board where a
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

    def prime_seen_moves(self, moves: list[int]) -> None:
        """moves[i] = the move id AITrackSeenPlayerMove would have recorded
        for slot i, or 0 if nothing has been revealed there yet - the sparse
        layout AIGetPlayerMoveN's fair-play branch must handle correctly."""
        assert self.harness is not None
        base = self.harness.address("wAISeenPlayerMoves")
        for index, move_id in enumerate(moves):
            self.harness.pyboy.memory[base + index] = move_id

    def test_fair_play_tier_reads_only_revealed_moves(self) -> None:
        # T1: AI_OMNISCIENT is cleared. wAISeenPlayerMoves is sparse - slot 1
        # revealed (GROWL), slot 0 not - and the routine must return exactly
        # that, not fall back to the real (unrevealed) moveset.
        assert self.harness is not None
        self.boot(ai_tier=1, player_moves=["TACKLE", "GROWL", "SPLASH"])
        growl = self.moves["GROWL"]
        self.prime_seen_moves([0, growl, 0, 0])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 0), 0)
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 1), growl)

    def test_omniscient_tier_ignores_seen_moves_entirely(self) -> None:
        # T3: AI_OMNISCIENT stays set. Identical wAISeenPlayerMoves state as
        # the fair-play test above, but the routine must return the REAL
        # moveset at every slot regardless - proving the omniscient branch
        # does not consult wAISeenPlayerMoves at all, not merely that it
        # happens to agree on the revealed slot.
        assert self.harness is not None
        self.boot(ai_tier=3, player_moves=["TACKLE", "GROWL", "SPLASH"])
        growl = self.moves["GROWL"]
        self.prime_seen_moves([0, growl, 0, 0])
        tackle = self.moves["TACKLE"]
        splash = self.moves["SPLASH"]
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 0), tackle)
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 1), growl)
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 2), splash)

    def test_t0_is_also_fair_play(self) -> None:
        # AI_OMNISCIENT is cleared on T0 as well as T1 (AITierLayers,
        # ai_core.asm) - confirm the flip applies to both, not just T1.
        assert self.harness is not None
        self.boot(ai_tier=0, player_moves=["TACKLE", "GROWL", "SPLASH"])
        self.prime_seen_moves([0, 0, 0, 0])
        self.assertEqual(call_a_preserving(self.harness, "AIGetPlayerMoveN", 0), 0)


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
        recorded = self.harness.read_bytes("wAISeenPlayerMoves", 4)
        self.assertEqual(recorded, [0, 0, splash, 0],
                          "must land in slot 2, not slot 0")

    def test_zero_selected_move_is_never_recorded(self) -> None:
        # wPlayerSelectedMove == 0 is also wAISeenPlayerMoves' own "nothing
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
        recorded = self.harness.read_bytes("wAISeenPlayerMoves", 4)
        self.assertEqual(recorded, [0, 0, 0, 0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
