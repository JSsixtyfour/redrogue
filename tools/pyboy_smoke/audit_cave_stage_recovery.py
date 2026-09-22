"""Audit: does the Phase 7e give-back return the stolen mon INTACT?

Runs a real theft, snapshots the victim, then invokes StageEventGiveBack and
compares what came back against what left. Fidelity is the whole point of the
56-byte record, so this compares bytes rather than checking that the party got
bigger.

What it proves, and why each part is worth proving separately:

  1. the party grows back by one and the record's tag is cleared, so the
     give-back cannot fire twice
  2. the returned box struct is byte-identical to the victim's - which covers
     DVs, stat exp, moves, PP, OT ID, and the MON_CATCH_RATE byte carrying
     form/fusion/shiny, none of which any "create a mon" helper would preserve
  3. nickname and OT name survive
  4. LEVEL and the five STATS match the originals. These are the two fields
     the rebuild deliberately does NOT copy - it recomputes them from
     experience, the way _MoveMon's box-to-party path does. Recomputing should
     reproduce the originals exactly; if it does not, either the CalcStats
     call convention is wrong (its `hl` is the stat-exp base, NOT the stats
     destination - an easy and silent thing to get backwards) or the level
     derivation is.
  5. the phase advanced to SETTLED

Usage:
    python3 tools/pyboy_smoke/audit_cave_stage_recovery.py [--type N]
"""

from __future__ import annotations

import argparse
import re
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
RECORD_BANK = 1
STAGE_EVENT_PHASE_MASK = 0b00011000
STAGE_EVENT_PHASE_SHIFT = 3
STAGE_EVENT_PHASE_SETTLED = 2


def read_party(h):
    count = h.read8("wPartyCount")
    mons = []
    for slot in range(count):
        base = h.address("wPartyMons") + slot * PARTYMON_STRUCT_LENGTH
        nick = h.address("wPartyMonNicks") + slot * NAME_LENGTH
        ot = h.address("wPartyMonOT") + slot * NAME_LENGTH
        full = list(h.pyboy.memory[base:base + PARTYMON_STRUCT_LENGTH])
        mons.append({
            "box": full[:BOXMON_STRUCT_LENGTH],
            "level": full[BOXMON_STRUCT_LENGTH],
            "stats": full[BOXMON_STRUCT_LENGTH + 1:],
            "nick": list(h.pyboy.memory[nick:nick + NAME_LENGTH]),
            "ot": list(h.pyboy.memory[ot:ot + NAME_LENGTH]),
        })
    return mons


def giveback_const(name):
    """STAGE_GIVEBACK_* value, read from the asm so this cannot go stale."""
    text = (REPO_ROOT / "constants" / "ram_constants.asm").read_text()
    m = re.search(r"^DEF %s\s+EQU\s+(\d+)" % name, text, re.M)
    if m is None:
        raise SystemExit("could not find DEF %s in ram_constants.asm" % name)
    return int(m.group(1))


STAGE_GIVEBACK_MON = giveback_const("STAGE_GIVEBACK_MON")
STAGE_GIVEBACK_NO_ROOM = giveback_const("STAGE_GIVEBACK_NO_ROOM")
STAGE_GIVEBACK_TO_BOX = giveback_const("STAGE_GIVEBACK_TO_BOX")
# Derived from the count constant, not from a hand-kept list of names. The
# list version silently went stale the moment TO_BOX was added in 1C, which
# would have let the range check below pass a value that indexes past the
# recovery text table.
STAGE_GIVEBACK_MAX = giveback_const("NUM_STAGE_GIVEBACK_RESULTS") - 1

STAGE_EVENT_PHASE_OWED = 3
MONS_PER_BOX = 20
MON_BOX_LEVEL = 3


def report(failures, pass_message):
    print()
    if failures:
        for line in failures:
            print("  FAIL: %s" % line)
        return 1
    print("PASS: %s" % pass_message)
    return 0


def read_box_slot(h, slot):
    base = h.address("wBoxMons") + slot * BOXMON_STRUCT_LENGTH
    nick = h.address("wBoxMonNicks") + slot * NAME_LENGTH
    ot = h.address("wBoxMonOT") + slot * NAME_LENGTH
    return {
        "box": list(h.pyboy.memory[base:base + BOXMON_STRUCT_LENGTH]),
        "nick": list(h.pyboy.memory[nick:nick + NAME_LENGTH]),
        "ot": list(h.pyboy.memory[ot:ot + NAME_LENGTH]),
    }


def set_party_count(h, count, species):
    """Force wPartyCount, keeping the species list and its terminator valid."""
    h.write8("wPartyCount", count)
    base = h.address("wPartySpecies")
    for i in range(count):
        h.pyboy.memory[base + i] = species[i % len(species)]
    h.pyboy.memory[base + count] = 0xFF


def set_box_count(h, count, species):
    h.write8("wBoxCount", count)
    base = h.address("wBoxSpecies")
    for i in range(count):
        h.pyboy.memory[base + i] = species[i % len(species)]
    h.pyboy.memory[base + count] = 0xFF


def run_full_party(h, victim, failures):
    """1C: a full party must send the mon to the BOX, not destroy it.

    Two give-backs, in this order, because the interesting property is the one
    between them:

      1. party full AND box full  -> NO_ROOM, and the event must stay OPEN.
         This is the case that used to lose the mon outright: the phase was
         advanced to SETTLED before the outcome was known, so the recovery
         could never fire again and the record was wiped at the next lobby
         selection. It must now leave the phase at OWED with sStolenKind
         intact, which is what makes the villain's after-battle line a retry.
      2. box emptied, give back again -> TO_BOX, record cleared, SETTLED.
         That second call IS the retry path, invoked the same way the NPC's
         after-battle handler invokes it.

    MON_BOX_LEVEL is checked separately from the rest of the struct on
    purpose. The record was copied out of a PARTY struct, where byte 3 is the
    unused BoxLevel cache and the live level lives past the 33 bytes that were
    saved, so a straight copy leaves it stale. Recomputing it from experience
    is the whole of what StageEventStolenMonToBox adds over a memcpy.
    """
    species = [m["box"][0] for m in read_party(h)] or [1]
    set_party_count(h, 6, species)
    set_box_count(h, MONS_PER_BOX, species)
    print("forced wPartyCount=6, wBoxCount=%d" % MONS_PER_BOX)

    h.call_routine("StageEventGiveBack")
    scratch = h.read8("wStageEventScratch")
    phase = (h.read8("wStageEvent") & STAGE_EVENT_PHASE_MASK) >> STAGE_EVENT_PHASE_SHIFT
    kind = h.read_sram_bytes("sStolenKind", 1, bank=RECORD_BANK)[0]
    print("both full -> result %d, phase %d, sStolenKind %d" % (scratch, phase, kind))
    if scratch != STAGE_GIVEBACK_NO_ROOM:
        failures.append("party and box both full gave result %d, expected %d "
                        "(STAGE_GIVEBACK_NO_ROOM)" % (scratch, STAGE_GIVEBACK_NO_ROOM))
    if phase != STAGE_EVENT_PHASE_OWED:
        failures.append("phase is %d after a failed hand-over, expected OWED (%d) - "
                        "anything else either reprints forever (HIDING) or closes "
                        "the event with the mon still unreturned (SETTLED)"
                        % (phase, STAGE_EVENT_PHASE_OWED))
    if kind != 1:
        failures.append("sStolenKind is %d after a failed hand-over - the record "
                        "was cleared, so the mon is gone and the retry has "
                        "nothing to give back" % kind)
    if h.read8("wBoxCount") != MONS_PER_BOX:
        failures.append("wBoxCount changed on the no-room path, so something was "
                        "written into a full box")

    set_box_count(h, 0, species)
    h.call_routine("StageEventGiveBack")
    scratch = h.read8("wStageEventScratch")
    phase = (h.read8("wStageEvent") & STAGE_EVENT_PHASE_MASK) >> STAGE_EVENT_PHASE_SHIFT
    kind = h.read_sram_bytes("sStolenKind", 1, bank=RECORD_BANK)[0]
    count = h.read8("wBoxCount")
    print("retry with room -> result %d, phase %d, sStolenKind %d, wBoxCount %d"
          % (scratch, phase, kind, count))
    if scratch != STAGE_GIVEBACK_TO_BOX:
        failures.append("retry gave result %d, expected %d (STAGE_GIVEBACK_TO_BOX)"
                        % (scratch, STAGE_GIVEBACK_TO_BOX))
    if phase != STAGE_EVENT_PHASE_SETTLED:
        failures.append("phase is %d after a successful retry, expected SETTLED (%d)"
                        % (phase, STAGE_EVENT_PHASE_SETTLED))
    if kind != 0:
        failures.append("sStolenKind is still %d after a successful retry - the "
                        "record was not cleared, so the mon could be duplicated"
                        % kind)
    if count != 1:
        failures.append("wBoxCount is %d, expected 1" % count)
        return

    got = read_box_slot(h, 0)
    want = victim["box"]
    for i, (g, w) in enumerate(zip(got["box"], want)):
        if i == MON_BOX_LEVEL:
            continue
        if g != w:
            failures.append("box struct byte %d: got $%02x want $%02x" % (i, g, w))
    if got["nick"] != victim["nick"]:
        failures.append("nickname differs: %s vs %s" % (got["nick"], victim["nick"]))
    if got["ot"] != victim["ot"]:
        failures.append("OT differs: %s vs %s" % (got["ot"], victim["ot"]))
    if got["box"][MON_BOX_LEVEL] != victim["level"]:
        failures.append("MON_BOX_LEVEL is %d, expected %d - the record's copy of "
                        "byte 3 is a stale party-struct BoxLevel, so it has to be "
                        "recomputed from experience"
                        % (got["box"][MON_BOX_LEVEL], victim["level"]))
    else:
        print("MON_BOX_LEVEL recomputed to %d, matching the original"
              % victim["level"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full-party", action="store_true",
                        help="fill the party (and box) first, exercising the 1C "
                             "box path and the no-room retry instead")
    parser.add_argument("--type", type=int, default=2,
                        help="STAGE_EVENT_* type (2 = Psychic, a mon thief)")
    args = parser.parse_args()

    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]
    failures = []

    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_to_lobby()
        h.write8("wStageEvent", args.type)
        # Snapshot in the LOBBY. StageEventDoTheft was reordered 2026-09-17 to
        # run at map LOAD, before the arrival text, so the greeting can name
        # what it took - a snapshot taken after entry is already post-theft.
        before = read_party(h)
        print("party before theft: %s" % [m["box"][0] for m in before])

        h.preload_and_enter_wild_area(map_id, "Procedural Cave")

        # The theft already happened during the load; these taps just close
        # the greeting and the loot line.
        for _ in range(6):
            h.tap("a", frames=12)
            h.tick(40)

        robbed = read_party(h)
        kind = h.read_sram_bytes("sStolenKind", 1, bank=RECORD_BANK)[0]
        print("party after theft : %s  (sStolenKind=%d)"
              % ([m["box"][0] for m in robbed], kind))
        if kind != 1:
            print("  no mon was stolen - nothing for this audit to check")
            return 0

        survivors = [m["box"] for m in robbed]
        victim = next(m for m in before if m["box"] not in survivors)
        print("victim: species %d, level %d" % (victim["box"][0], victim["level"]))

        if args.full_party:
            run_full_party(h, victim, failures)
            return report(failures, "a full party sent the mon to the BOX, and "
                                    "the both-full case stayed retryable")

        # Invoke the give-back directly. The alternative is winning a real
        # trainer battle in the harness, which tests the map script's trigger
        # rather than the rebuild this audit is about.
        h.call_routine("StageEventGiveBack")

        # The give-back's RESULT CODE, which the map script uses to pick the
        # recovery line. It must arrive through wStageEventScratch, written by
        # GiveBack itself - it cannot come back in `a`, because every caller is
        # a map script reaching this by farcall and Bankswitch's return leg
        # ends `ld a, b` with the caller's ROM bank. That is what printed
        # "12 ERROR.": $11 indexed 26 bytes past a 4-entry text table and
        # PrintText ran on garbage. Nothing read this byte before, which is
        # exactly why the bug shipped.
        scratch = h.read8("wStageEventScratch")
        print("wStageEventScratch after GiveBack = %d" % scratch)
        if scratch > STAGE_GIVEBACK_MAX:
            failures.append(
                "wStageEventScratch is %d, outside the valid STAGE_GIVEBACK_* "
                "range 0..%d - the recovery text handler indexes a %d-entry "
                "pointer table with this, so anything larger runs PrintText on "
                "whatever follows the table"
                % (scratch, STAGE_GIVEBACK_MAX, STAGE_GIVEBACK_MAX + 1))
        elif scratch != STAGE_GIVEBACK_MON:
            failures.append(
                "wStageEventScratch is %d, expected %d (STAGE_GIVEBACK_MON) - "
                "a mon was stolen and the party had room, so the give-back "
                "should report returning a mon"
                % (scratch, STAGE_GIVEBACK_MON))

        after = read_party(h)
        print("party after return: %s" % [m["box"][0] for m in after])

        if len(after) != len(robbed) + 1:
            failures.append("party went %d -> %d, expected one more"
                            % (len(robbed), len(after)))
        else:
            got = after[-1]
            if got["box"] != victim["box"]:
                failures.append("returned box struct differs from the victim's")
                for i, (g, w) in enumerate(zip(got["box"], victim["box"])):
                    if g != w:
                        failures.append("  byte %d: got $%02x want $%02x" % (i, g, w))
            if got["nick"] != victim["nick"]:
                failures.append("nickname differs: %s vs %s" % (got["nick"], victim["nick"]))
            if got["ot"] != victim["ot"]:
                failures.append("OT differs: %s vs %s" % (got["ot"], victim["ot"]))
            if got["level"] != victim["level"]:
                failures.append("level recomputed as %d, original was %d"
                                % (got["level"], victim["level"]))
            if got["stats"] != victim["stats"]:
                failures.append("stats recomputed as %s, original was %s"
                                % (got["stats"], victim["stats"]))
            else:
                print("recomputed level and stats match the originals exactly")

        kind_after = h.read_sram_bytes("sStolenKind", 1, bank=RECORD_BANK)[0]
        if kind_after != 0:
            failures.append("sStolenKind is still %d - the record was not cleared, "
                            "so the mon could be duplicated" % kind_after)
        phase = (h.read8("wStageEvent") & STAGE_EVENT_PHASE_MASK) >> STAGE_EVENT_PHASE_SHIFT
        if phase != STAGE_EVENT_PHASE_SETTLED:
            failures.append("phase is %d, expected SETTLED (%d)"
                            % (phase, STAGE_EVENT_PHASE_SETTLED))
    finally:
        try:
            h.close()
        except Exception:
            pass

    return report(failures, "the stolen mon came back byte-identical, with "
                            "level and stats correctly recomputed")


if __name__ == "__main__":
    raise SystemExit(main())
