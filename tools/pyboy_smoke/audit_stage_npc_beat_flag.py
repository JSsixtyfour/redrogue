"""Audit: a stage-event NPC's "beaten" flag must land on its OWN event bit.

MEASURED BUG this guards (2026-09-17, reported as "the psychic battles you,
the battle ends, it sees you and battles you again"):

  ExecuteCurMapScriptInTable stores the `hl` it is handed - the trainer header
  table base - into wTrainerHeaderPtr on EVERY tick. EndTrainerBattle then
  takes the flag BIT from wTrainerHeaderFlagBit (cached by TalkToTrainer from
  the ENGAGED trainer's own header) but re-reads the flag BYTE POINTER from
  wTrainerHeaderPtr, i.e. from the table base.

  Vanilla never trips on this, because `dw wEventFlags + (event -
  CURRENT_TRAINER_BIT) / 8` is CONSTANT across one consecutive def_trainers
  block: every trainer in a block shares a byte. Phase 7 gave the Cave, Forest
  and Facility a SECOND block with a DIFFERENT byte, so the NPC's bit was
  written into the boss's byte. The NPC's own event never got set, it never
  read as beaten, and it re-engaged forever. On the Facility it also silently
  set EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_1/2.

  The fix: each affected map picks the header block matching the engaged
  trainer, selected by wTrainerHeaderFlagBit - the exact value
  EndTrainerBattle will pair the pointer with.

This audit reads the real header bytes out of the built ROM, parses each
script's selection threshold out of its source, and asserts that the block the
script WOULD select for each trainer's bit yields that trainer's own event.

Usage:
    python3 tools/pyboy_smoke/audit_stage_npc_beat_flag.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HEADER_SIZE = 12

# map script, table base symbol, NPC block base symbol (None = single block),
# every header symbol in the table
MAPS = [
    ("scripts/ProceduralCave1.asm", "ProceduralCave1TrainerHeaders",
     "PCStageNpc1Header",
     ["PCBossTrainerHeader", "PCStageNpc1Header", "PCStageNpc2Header"]),
    ("scripts/ProceduralForest.asm", "ProceduralForestTrainerHeaders",
     "PFStageNpc1Header",
     ["PFBossTrainerHeader", "PFStageNpc1Header", "PFStageNpc2Header"]),
    ("scripts/ProceduralFacility.asm", "ProceduralFacilityTrainerHeaders",
     "PFacStageNpc1Header",
     ["PFacBossTrainerHeader", "PFacStageNpc1Header", "PFacStageNpc2Header"]),
    ("scripts/ProceduralCemetery1.asm", "PCemStageTrainerHeaders", None,
     ["PCemStageNpc1Header", "PCemStageNpc2Header"]),
]


def load(rom_name):
    rom = (REPO_ROOT / (rom_name + ".gbc")).read_bytes()
    text = (REPO_ROOT / (rom_name + ".sym")).read_text(
        encoding="utf-8", errors="replace")
    addrs = {}
    for line in text.split("\n"):
        m = re.match(r"([0-9a-fA-F]{2}):([0-9a-fA-F]{4}) (\S+)", line.strip())
        if m:
            addrs.setdefault(m.group(3), (int(m.group(1), 16), int(m.group(2), 16)))
    return rom, addrs


def header(rom, addrs, name):
    bank, addr = addrs[name]
    off = bank * 0x4000 + (addr - 0x4000)
    raw = rom[off:off + HEADER_SIZE]
    return raw[0], raw[2] | (raw[3] << 8)


def threshold(script_rel, npc_base):
    """The `cp N` guarding the switch to npc_base, parsed from the source."""
    src = (REPO_ROOT / script_rel).read_text(encoding="utf-8", errors="replace")
    m = re.search(
        r"ld a, \[wTrainerHeaderFlagBit\]\s*\n\s*cp (\d+)\s*\n"
        r"\s*jr c, \.\w+\s*\n\s*ld hl, " + re.escape(npc_base),
        src)
    return int(m.group(1)) if m else None


def main() -> int:
    failures = []
    for rom_name in ("pokered", "pokeblue"):
        if not (REPO_ROOT / (rom_name + ".gbc")).exists():
            continue
        rom, addrs = load(rom_name)
        wev = addrs["wEventFlags"][1]
        print("=== %s ===" % rom_name)
        for script_rel, base_name, npc_base, members in MAPS:
            missing = [m for m in members + [base_name] if m not in addrs]
            if missing:
                failures.append("%s: missing symbols %s" % (base_name, missing))
                continue
            _, base_ptr = header(rom, addrs, base_name)
            cut = None
            if npc_base is not None:
                cut = threshold(script_rel, npc_base)
                if cut is None:
                    failures.append(
                        "%s has header blocks with different flag bytes but no "
                        "wTrainerHeaderFlagBit gate selecting %s - every NPC's "
                        "beat flag will be written into the table base's event "
                        "byte" % (script_rel, npc_base))
                    continue
                _, npc_ptr = header(rom, addrs, npc_base)
            print("  %-34s base=+%d  gate: bit >= %s -> %s"
                  % (base_name, base_ptr - wev, cut, npc_base or "(single block)"))
            for member in members:
                bit, ptr = header(rom, addrs, member)
                own_event = (ptr - wev) * 8 + bit
                chosen = npc_ptr if (cut is not None and bit >= cut) else base_ptr
                set_event = (chosen - wev) * 8 + bit
                ok = "ok" if set_event == own_event else "WRONG"
                print("    %-26s bit=%2d own event=%-4d -> sets %-4d  %s"
                      % (member, bit, own_event, set_event, ok))
                if set_event != own_event:
                    failures.append(
                        "%s/%s: beating it sets event %d, not its own %d - it "
                        "never reads as beaten and re-engages forever"
                        % (rom_name, member, set_event, own_event))
        print()

    if failures:
        for line in failures:
            print("  FAIL: %s" % line)
        return 1
    print("PASS: every stage trainer's beat flag lands on its own event bit")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
