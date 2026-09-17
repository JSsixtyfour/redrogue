"""Audit: does the Phase 7d theft actually take the right mon, at full fidelity?

Runs the whole arrival beat and compares the party before and after, then
decodes the SRAM record against the mon that disappeared. Checks the things a
"the party got smaller" assertion would miss:

  1. the party shrinks by exactly one
  2. the record's tag says STOLEN_MON
  3. the stolen box struct is byte-identical to the victim's box struct as it
     was BEFORE the theft - this is what "full fidelity" has to mean, and it
     covers the form/fusion/shiny bits implicitly because they live in
     MON_CATCH_RATE inside that struct
  4. the nickname and OT name came across
  5. the surviving party is the original minus the victim, in order, so
     RemovePokemon's compaction did not scramble anything

Fidelity is checked by comparison against a snapshot rather than by asserting
specific values, so it cannot pass by accident on a party that happens to be
all-default.

Usage:
    python3 tools/pyboy_smoke/audit_cave_stage_theft.py [--type N]
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

STOLEN_ITEM = 2
# Parallel count arrays for the three stealable pockets (Key Items and TMs are
# excluded from the theft). Lengths come from the constants the WRAM arrays are
# sized with, so this cannot drift out of step with the tables.
POCKETS = [
    ("wRecoveryItemCounts", "NUM_RECOVERY_ITEMS"),
    ("wStatItemCounts", "NUM_STAT_ITEMS"),
    ("wValuableItemCounts", "NUM_VALUABLE_ITEMS"),
]

# Mirrors constants/item_constants.asm: HM01-HM05 are $C4-$C8, TM01-TM50 start
# at $C9. Both ranges are stealable - see the note on owned_tm_indexes.
HM01 = 0xC4
NUM_HMS = 5
TM01 = 0xC9
NUM_TMS = 50

BOXMON_STRUCT_LENGTH = 0x21
PARTYMON_STRUCT_LENGTH = 0x2C
NAME_LENGTH = 11
RECORD_BANK = 1
STOLEN_MON = 1


def pocket_lengths():
    text = (REPO_ROOT / "constants" / "ram_constants.asm").read_text()
    out = {}
    for name, value in re.findall(r"^\s*DEF (NUM_(?:RECOVERY|STAT|VALUABLE)_ITEMS)\s+EQU\s+(\d+)",
                                  text, re.M):
        out[name] = int(value)
    return out


def read_pockets(h, lengths):
    """Snapshot every stealable pocket's count array."""
    out = {}
    for label, length_name in POCKETS:
        n = lengths[length_name]
        base = h.address(label)
        out[label] = list(h.pyboy.memory[base:base + n])
    return out


def read_tms(h):
    """Snapshot the TM/HM ownership bitfield (7 bytes, SRAM bank 1)."""
    return h.read_sram_bytes("sTMBitfield", 7, bank=RECORD_BANK)


def owned_tm_indexes(bits):
    """Owned TM/HM bit indexes.

    HMs are INCLUDED. Red Rogue has no out-of-combat field moves, so an HM is
    mechanically just a TM at a higher index - there is no Surf/Strength
    progression for losing one to strand. Spanning only NUM_TMS here would
    silently exclude five stealable items and quietly disagree with the
    theft code, which walks the whole bitfield.
    """
    return [i for i in range(NUM_TMS + NUM_HMS) if bits[i >> 3] & (1 << (i & 7))]


def item_id_for_bit(index):
    """Inverse of tm_bag.asm's _TMHMIndex: one bit run, two id ranges."""
    if index < NUM_TMS:
        return TM01 + index
    return HM01 + (index - NUM_TMS)


def read_party(h):
    """Snapshot every party mon's box struct, nickname and OT name."""
    count = h.read8("wPartyCount")
    mons = []
    for slot in range(count):
        base = h.address("wPartyMons") + slot * PARTYMON_STRUCT_LENGTH
        nick = h.address("wPartyMonNicks") + slot * NAME_LENGTH
        ot = h.address("wPartyMonOT") + slot * NAME_LENGTH
        mons.append({
            "box": list(h.pyboy.memory[base:base + BOXMON_STRUCT_LENGTH]),
            "nick": list(h.pyboy.memory[nick:nick + NAME_LENGTH]),
            "ot": list(h.pyboy.memory[ot:ot + NAME_LENGTH]),
        })
    return mons


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--type", type=int, default=2,
                        help="STAGE_EVENT_* type (2 = Psychic, a mon thief)")
    parser.add_argument("--expect-item", action="store_true",
                        help="assert an ITEM was taken: use for the Burglar, and "
                             "with --force-party 1 for the mon->item fallback")
    parser.add_argument("--only-hm", action="store_true",
                        help="empty every other pocket and leave exactly one HM, so "
                             "the theft MUST take it - proves the HM branch and its "
                             "bit-index->item-id conversion, which a random pick "
                             "almost never reaches (5 HMs against 50 TMs)")
    parser.add_argument("--force-party", type=int, default=0,
                        help="shrink wPartyCount to this before the theft, to "
                             "exercise the >=2 guard (the plan's explicit test)")
    args = parser.parse_args()

    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]
    failures = []

    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_to_lobby()
        h.write8("wStageEvent", args.type)
        h.preload_and_enter_wild_area(map_id, "Procedural Cave")

        # Shrink the party BEFORE the text is dismissed, i.e. before
        # StageEventDoTheft reads wPartyCount. The theft runs between the
        # arrival text and the dark flash, and the arrival text is still open
        # at this point, so this lands in the window the guard reads.
        if args.force_party:
            h.write8("wPartyCount", args.force_party)

        if args.only_hm:
            # Strip every count pocket and every TM, keeping HM03 (bit
            # NUM_TMS+2) alone. With one stack left the pick is forced onto it.
            for label, length_name in POCKETS:
                base = h.address(label)
                for i in range(pocket_lengths()[length_name]):
                    h.pyboy.memory[base + i] = 0
            bits = [0] * 7
            target = NUM_TMS + 2
            bits[target >> 3] |= 1 << (target & 7)
            h.write_sram_bytes("sTMBitfield", bits, bank=RECORD_BANK)
            print("forced: only HM bit %d (id %d) remains"
                  % (target, item_id_for_bit(target)))

        lengths = pocket_lengths()
        pockets_before = read_pockets(h, lengths)
        tms_before = read_tms(h)
        before = read_party(h)
        print("party before: %d mon(s), species %s"
              % (len(before), [m["box"][0] for m in before]))
        print("owned stacks before: %d count-array + %d TM(s)"
              % (sum(1 for v in pockets_before.values() for c in v if c),
                 len(owned_tm_indexes(tms_before))))
        if len(before) < 2:
            print("  (party of %d - the >=2 guard should REFUSE this theft)" % len(before))

        # Dismiss the arrival text; the theft runs between it and the flash.
        for _ in range(6):
            h.tap("a", frames=12)
            h.tick(40)

        after = read_party(h)
        kind = h.read_sram_bytes("sStolenKind", 1, bank=RECORD_BANK)[0]
        box = h.read_sram_bytes("sStolenBoxMon", BOXMON_STRUCT_LENGTH, bank=RECORD_BANK)
        nick = h.read_sram_bytes("sStolenNickname", NAME_LENGTH, bank=RECORD_BANK)
        ot = h.read_sram_bytes("sStolenOTName", NAME_LENGTH, bank=RECORD_BANK)
        print("party after : %d mon(s), species %s"
              % (len(after), [m["box"][0] for m in after]))
        print("sStolenKind = %d, stolen species = %d, catch-rate byte = $%02x"
              % (kind, box[0], box[6]))

        pockets_after = read_pockets(h, lengths)
        item = h.read_sram_bytes("sStolenItem", 1, bank=RECORD_BANK)[0]
        dropped = []
        for label, counts in pockets_before.items():
            for index, count in enumerate(counts):
                if pockets_after[label][index] < count:
                    dropped.append((label, index, count, pockets_after[label][index]))

        tms_after = read_tms(h)
        lost_tms = sorted(set(owned_tm_indexes(tms_before))
                          - set(owned_tm_indexes(tms_after)))

        # No HM assertion here, deliberately. An earlier version asserted HMs
        # were never touched, on the vanilla reasoning that losing Surf or
        # Strength can strand a run. Red Rogue has no field moves, so that is
        # not true and HMs are ordinary theft targets; the bit checks below
        # cover them like any TM.

        if kind == STOLEN_ITEM or args.expect_item:
            # Either the Burglar, or a mon thief that fell back to the bag.
            # A stolen TM shows up as a cleared bit, not a shrunken stack, so
            # exactly one of the two has to have moved - never both, never
            # neither.
            print("item theft: sStolenItem = %d, pocket deltas = %s, TM bits lost = %s"
                  % (item, dropped, lost_tms))
            if kind != STOLEN_ITEM:
                failures.append("expected an ITEM theft, got sStolenKind = %d" % kind)
            if item == 0:
                failures.append("sStolenItem is 0 with an item theft recorded")
            if len(dropped) + len(lost_tms) != 1:
                failures.append("expected exactly ONE thing to leave the bag, got "
                                "%d stack(s) and %d TM(s)" % (len(dropped), len(lost_tms)))
            elif dropped and dropped[0][2] - dropped[0][3] != 1:
                failures.append("stack fell by %d, expected 1" % (dropped[0][2] - dropped[0][3]))
            if lost_tms:
                # The recorded id must name the bit that actually cleared. This
                # is the check that catches a wrong TM/HM index->id conversion,
                # which would otherwise record one item while removing another.
                want = item_id_for_bit(lost_tms[0])
                if item != want:
                    failures.append("recorded item %d but bit index %d (id %d) was removed"
                                    % (item, lost_tms[0], want))
                kind_word = "HM" if lost_tms[0] >= NUM_TMS else "TM"
                print("  (%s taken: bit %d -> id %d)" % (kind_word, lost_tms[0], want))
            if len(after) != len(before):
                failures.append("an item theft also changed the party size")
        elif len(before) < 2:
            if kind != 0 or len(after) != len(before):
                failures.append("the >=2 party guard did not hold")
            else:
                print("guard held: nothing stolen from a party of %d" % len(before))
        else:
            if kind != STOLEN_MON:
                failures.append("sStolenKind = %d, expected STOLEN_MON" % kind)
            if len(after) != len(before) - 1:
                failures.append("party went %d -> %d, expected one fewer"
                                % (len(before), len(after)))

            # Which one vanished? Identify by matching the surviving structs.
            survivors = [m["box"] for m in after]
            missing = [m for m in before if m["box"] not in survivors]
            if len(missing) != 1:
                failures.append("could not identify exactly one missing mon (%d candidates)"
                                % len(missing))
            else:
                victim = missing[0]
                if box != victim["box"]:
                    failures.append("stolen box struct differs from the victim's")
                    for i, (g, w) in enumerate(zip(box, victim["box"])):
                        if g != w:
                            failures.append("  byte %d: record=$%02x party=$%02x" % (i, g, w))
                if nick != victim["nick"]:
                    failures.append("stolen nickname differs: %s vs %s" % (nick, victim["nick"]))
                if ot != victim["ot"]:
                    failures.append("stolen OT name differs: %s vs %s" % (ot, victim["ot"]))
                expected = [m["box"] for m in before if m["box"] != victim["box"]]
                if survivors != expected:
                    failures.append("surviving party order changed; RemovePokemon's "
                                    "compaction scrambled it")
                if not failures:
                    print("victim species %d matched byte-for-byte across "
                          "struct, nickname and OT" % victim["box"][0])
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
    print("PASS: theft took exactly one eligible mon at full fidelity")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
