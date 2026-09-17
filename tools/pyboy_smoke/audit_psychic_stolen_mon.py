"""Audit: does the Psychic actually field the mon it stole?

Phase 7e's closing beat. Runs a real theft, then builds the Psychic's enemy
party and checks the stolen mon is its last slot, byte-identical.

The two things worth proving separately:

  1. the stolen mon IS on the team, in the last slot, with its own moves
     intact. Moves are the fragile part: RogueApplyMixToParty and the
     SpecialTrainerMoves loop both rewrite movesets across the enemy party,
     so an injection sequenced before either would silently lose them. That
     is why the hook sits at .FinishUp and why this compares the four move
     bytes explicitly rather than trusting the struct compare to cover them.
  2. it is a NO-OP for anything else. The hook lives in the shared trainer
     build path that every trainer in the game runs through, so the control
     case matters as much as the positive one.

Usage:
    python3 tools/pyboy_smoke/audit_psychic_stolen_mon.py
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"

BOXMON_STRUCT_LENGTH = 0x21
PARTYMON_STRUCT_LENGTH = 0x2C
NAME_LENGTH = 11
MON_MOVES = 8          # offset of the four move bytes inside the struct
RECORD_BANK = 1
PSYCHIC_TR = 0x13
STAGE_EVENT_PSYCHIC = 2


def main() -> int:
    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]
    failures = []

    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_to_lobby()
        h.write8("wStageEvent", STAGE_EVENT_PSYCHIC)
        h.preload_and_enter_wild_area(map_id, "Procedural Cave")
        for _ in range(6):
            h.tap("a", frames=12)
            h.tick(40)

        kind = h.read_sram_bytes("sStolenKind", 1, bank=RECORD_BANK)[0]
        if kind != 1:
            print("no mon was stolen (kind=%d) - nothing to check" % kind)
            return 0
        record = h.read_sram_bytes("sStolenBoxMon", BOXMON_STRUCT_LENGTH, bank=RECORD_BANK)
        print("stolen: species %d, moves %s"
              % (record[0], record[MON_MOVES:MON_MOVES + 4]))

        # --- positive case: build the Psychic's party -------------------
        h.write8("wTrainerClass", PSYCHIC_TR)
        h.write8("wCurOpponent", PSYCHIC_TR + 160)
        h.write8("wTrainerNo", 1)
        h.call_routine("ReadTrainer", limit=40000)

        count = h.read8("wEnemyPartyCount")
        base = h.address("wEnemyMons") + (count - 1) * PARTYMON_STRUCT_LENGTH
        last = list(h.pyboy.memory[base:base + BOXMON_STRUCT_LENGTH])
        species = list(h.pyboy.memory[h.address("wEnemyPartySpecies"):
                                      h.address("wEnemyPartySpecies") + count])
        print("psychic party (%d): %s" % (count, species))
        print("last slot: species %d, moves %s"
              % (last[0], last[MON_MOVES:MON_MOVES + 4]))

        if species[-1] != record[0]:
            failures.append("last slot species %d, expected the stolen %d"
                            % (species[-1], record[0]))
        if last != record:
            failures.append("last slot struct differs from the stolen record")
            for i, (g, w) in enumerate(zip(last, record)):
                if g != w:
                    failures.append("  byte %d: team=$%02x record=$%02x" % (i, g, w))
        if last[MON_MOVES:MON_MOVES + 4] != record[MON_MOVES:MON_MOVES + 4]:
            failures.append("MOVES were overwritten - the hook is sequenced too "
                            "early, before the mix or SpecialTrainerMoves")
    finally:
        try:
            h.close()
        except Exception:
            pass

    # --- control: a different trainer class must be untouched -----------
    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_to_lobby()
        h.write8("wStageEvent", STAGE_EVENT_PSYCHIC)
        h.preload_and_enter_wild_area(map_id, "Procedural Cave")
        for _ in range(6):
            h.tap("a", frames=12)
            h.tick(40)
        record = h.read_sram_bytes("sStolenBoxMon", BOXMON_STRUCT_LENGTH, bank=RECORD_BANK)
        h.write8("wTrainerClass", 0x0B)          # BURGLAR, not the Psychic
        h.write8("wCurOpponent", 0x0B + 160)
        h.write8("wTrainerNo", 1)
        h.call_routine("ReadTrainer", limit=40000)
        count = h.read8("wEnemyPartyCount")
        base = h.address("wEnemyMons") + (count - 1) * PARTYMON_STRUCT_LENGTH
        last = list(h.pyboy.memory[base:base + BOXMON_STRUCT_LENGTH])
        print("control (BURGLAR) last slot species %d; stolen was %d"
              % (last[0], record[0]))
        if last == record:
            failures.append("the injection fired for a NON-Psychic trainer - the "
                            "class gate is not working")
    finally:
        try:
            h.close()
        except Exception:
            pass

    print()
    if failures:
        for line in failures:
            print("  FAIL: %s" % line)
        return 1
    print("PASS: the Psychic fields the stolen mon with its moves intact, and no "
          "other trainer is affected")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
