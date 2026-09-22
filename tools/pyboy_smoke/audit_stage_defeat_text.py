"""Audit: the Wild Area stage-event trainers' END-BATTLE text, read from the ROM.

MEASURED BUG this guards (2026-09-22, reported as "end battle text from Wild
Area Trainers is super quick at beginning, can hardly see trainer name"):

  All three of a stage-event trainer header's text pointers aimed at one
  dispatcher, PC/PF/PFac/PCemStageEventHideoutText, and that dispatcher did
  `call PrintText`. Two consequences, both only visible on the END-BATTLE beat:

    1. PrintText goes through DisplayTextBoxID, and TextBoxBorder BLANKS the
       box interior. PrintEndBattleText had already written "<CLASS>: " there
       from _TrainerNameText, so the trainer's name was wiped three frames
       (Delay3) after it appeared. That flash is what was reported.

    2. The hideout strings end "@" + `text_end`, no `prompt`. Every other
       stage-event string gets away with that because DisplayTextID waits
       afterwards (AfterDisplayingTextID -> WaitForTextScrollButtonPress).
       PrintEndBattleText is called straight from engine/battle/core.asm and
       does not, so the box printed and returned and the "got money for
       winning" box drew over the top of it.

  The fix splits the end-battle pointer off to its own dispatcher that RETURNS
  hl instead of calling PrintText - continuing the stream leaves the name in
  place - and gives the defeat strings their own `prompt`.

WHAT THIS CHECKS, all of it from the linked ROM rather than from source, so it
catches a header rewired to the wrong dispatcher as well as a string edited
back to `text_end`:

  A. each stage-NPC trainer header's end-battle pointer (offsets 8 and 10) is
     the map's DEFEAT dispatcher, not its hideout dispatcher
  B. the dispatcher's opcodes are the exact shape the fix depends on: it
     preserves bc across the table lookup and returns, and NEVER calls
     PrintText
  C. every string the dispatcher can reach terminates with <PROMPT> ($58) and
     has no "@" ($50) before it, which would orphan the prompt

(B) matters more than it looks. bc is the LIVE TILE CURSOR and the PickText
helpers destroy it - they use bc as the table offset. Dropping the push/pop is
the misprint the PCSignText header warns about: TX_START then places line 1 at
a garbage coordinate, off screen. The audit asserts the push/pop by opcode.

NEGATIVE CONTROLS, both run 2026-09-22 and both reverted:

  - putting `call PrintText` back into PCStageEventDefeatText failed (B) for
    the Cave and the Cemetery - which is also the check that the two really do
    share one dispatcher - naming PrintText as the cause.
  - changing _StageEventDefeatBurglarText's `prompt` back to "@" + `text_end`
    failed (C) with "ends $50, no <PROMPT>", reported by the Forest and the
    Facility. The Cave and Cemetery did not also report it only because (B)
    had already failed for them and the string walk is skipped after that.

Usage:
    python3 tools/pyboy_smoke/audit_stage_defeat_text.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

HEADER_SIZE = 12
END_BATTLE_WIN = 8       # `dw \3, \5, \4, \4` - \4 is the end-battle text
END_BATTLE_LOSE = 10

TX_END = 0x50            # also "@"
TX_FAR = 0x17
TX_START = 0x00
TX_START_ASM = 0x08
PROMPT = 0x58
DONE = 0x57

# map script, the two stage-NPC headers, the expected defeat dispatcher, and
# the PickText helper that dispatcher must call.
#
# The Cemetery deliberately shares the CAVE's dispatcher: maps.asm puts both
# files in the one "Maps 6" SECTION and a section cannot straddle a bank, so
# the reference is always in-bank. Bank 17 had 95 free bytes when this landed
# and a second copy does not fit. Asserting the shared symbol here is what
# keeps that deliberate choice from looking like a mistake later.
MAPS = [
    ("Cave", ["PCStageNpc1Header", "PCStageNpc2Header"],
     "PCStageEventDefeatText", "PCStageEventPickText"),
    ("Forest", ["PFStageNpc1Header", "PFStageNpc2Header"],
     "PFStageEventDefeatText", "PFStageEventPickText"),
    ("Facility", ["PFacStageNpc1Header", "PFacStageNpc2Header"],
     "PFacStageEventDefeatText", "PFacStageEventPickText"),
    ("Cemetery", ["PCemStageNpc1Header", "PCemStageNpc2Header"],
     "PCStageEventDefeatText", "PCStageEventPickText"),
]

# How many rows the defeat table carries: one per rollable stage-event type.
# There is deliberately NO sixth row. STAGE_EVENT_BOTH_GOOD was removed on
# 2026-09-22 - the sprite and trainer tables had already dropped it and the
# text tables were the last thing carrying it - and each table now asserts
# NUM_STAGE_EVENT_TYPES == 5 at build time instead, so re-enabling type 6
# fails the build rather than reading past the end of a table.
TABLE_ROWS = 5


def load(rom_name: str):
    rom = (REPO_ROOT / (rom_name + ".gbc")).read_bytes()
    sym = (REPO_ROOT / (rom_name + ".sym")).read_text(
        encoding="utf-8", errors="replace")
    addrs: dict[str, tuple[int, int]] = {}
    for line in sym.split("\n"):
        m = re.match(r"([0-9a-fA-F]{2}):([0-9a-fA-F]{4}) (\S+)", line.strip())
        if m:
            addrs.setdefault(
                m.group(3), (int(m.group(1), 16), int(m.group(2), 16)))
    return rom, addrs


def offset(bank: int, addr: int) -> int:
    """Flat ROM offset for a bank:address pair."""
    return addr if bank == 0 else bank * 0x4000 + (addr - 0x4000)


def reverse_charmap() -> dict[int, str]:
    """Byte -> printable text, for reporting what a string actually says."""
    src = (REPO_ROOT / "constants" / "charmap.asm").read_text(
        encoding="utf-8", errors="replace")
    table: dict[int, str] = {}
    for name, value in re.findall(
            r'^\s*charmap "(.*?)",\s*\$([0-9a-fA-F]+)', src, re.MULTILINE):
        table.setdefault(int(value, 16), name)
    return table


CHARS = reverse_charmap()


def decode(raw: bytes) -> str:
    """Printable rendering. Kept ASCII-only: several charmap names are box
    drawing or accented glyphs that a cp1252 console refuses to print, and an
    audit that crashes on its own report is worse than a slightly lossy one."""
    out = []
    for b in raw:
        # charmap.asm gives $00 the name "<NULL>", but in a text STREAM $00 is
        # TX_START - the `text` macro's own opening byte. Say so, or every
        # string in the report looks like it begins with a bug.
        if b == TX_START:
            out.append("<TX_START>")
            continue
        name = CHARS.get(b, "\\x%02x" % b)
        out.append(name if name.isascii() else "\\x%02x" % b)
    return "".join(out)


def read_far_string(rom, bank, addr, limit=256):
    """The raw bytes of a text_far target, up to and including its terminator."""
    off = offset(bank, addr)
    out = bytearray()
    for i in range(limit):
        b = rom[off + i]
        out.append(b)
        if b in (TX_END, PROMPT, DONE):
            break
    return bytes(out)


def main() -> int:
    failures: list[str] = []

    for rom_name in ("pokered", "pokeblue"):
        if not (REPO_ROOT / (rom_name + ".gbc")).exists():
            continue
        rom, addrs = load(rom_name)
        print("=== %s ===" % rom_name)

        print_text = addrs.get("PrintText")

        for area, headers, dispatcher, picker in MAPS:
            missing = [s for s in headers + [dispatcher, picker]
                       if s not in addrs]
            if missing:
                failures.append("%s: missing symbols %s" % (area, missing))
                continue

            d_bank, d_addr = addrs[dispatcher]

            # ---- A: both headers, both end-battle slots, point at it -------
            for h in headers:
                h_bank, h_addr = addrs[h]
                raw = rom[offset(h_bank, h_addr):
                          offset(h_bank, h_addr) + HEADER_SIZE]
                for label, slot in (("win", END_BATTLE_WIN),
                                    ("lose", END_BATTLE_LOSE)):
                    ptr = raw[slot] | (raw[slot + 1] << 8)
                    ok = ptr == d_addr
                    print("  %-9s %-20s end-battle(%-4s) -> $%04x  %s"
                          % (area, h, label, ptr,
                             "ok" if ok else "WRONG, want $%04x" % d_addr))
                    if not ok:
                        failures.append(
                            "%s: %s end-battle(%s) points at $%04x, not %s "
                            "($%04x). The hideout dispatcher calls PrintText, "
                            "which blanks the box the trainer's name was just "
                            "written into."
                            % (area, h, label, ptr, dispatcher, d_addr))

            # ---- B: the dispatcher's opcodes -------------------------------
            off = offset(d_bank, d_addr)
            body = rom[off:off + 10]
            p_bank, p_addr = addrs[picker]
            want = bytes([
                TX_START_ASM,
                0xC5,                                    # push bc
                0x21, 0x00, 0x00,                        # ld hl, <table>
                0xCD, p_addr & 0xFF, p_addr >> 8,        # call <picker>
                0xC1,                                    # pop bc
                0xC9,                                    # ret
            ])
            # `ld hl, nn` is opcode at [2], operand at [3:5]; `call nn` is
            # opcode at [5], operand at [6:8].
            table_addr = body[3] | (body[4] << 8)
            got = bytearray(body)
            got[3] = got[4] = 0                          # table address varies
            shape_ok = bytes(got) == want
            print("  %-9s %-20s shape %s  (table $%04x)"
                  % (area, dispatcher,
                     "ok" if shape_ok else "WRONG: " + body.hex(), table_addr))
            if not shape_ok:
                # Diagnose over a WIDER window than the 10 bytes compared. An
                # inserted call pushes the tail out of the compared window, so
                # looking for PrintText only inside it would miss the single
                # most likely cause and report the vaguer bc complaint instead.
                near = rom[off:off + 24]
                detail = ""
                if print_text and bytes([0xCD, print_text[1] & 0xFF,
                                         print_text[1] >> 8]) in near:
                    detail = (" It calls PrintText, which goes through "
                              "DisplayTextBoxID and blanks the box the "
                              "trainer's name is sitting in.")
                elif 0xC5 not in body or 0xC1 not in body:
                    detail = (" It does not preserve bc - bc is the live tile "
                              "cursor and %s destroys it." % picker)
                failures.append(
                    "%s: %s is not the push bc / lookup / pop bc / ret shape "
                    "the fix needs: %s.%s"
                    % (area, dispatcher, body.hex(), detail))
                continue

            # ---- C: every string it can reach ends in <PROMPT> -------------
            t_off = offset(d_bank, table_addr)
            seen: set[int] = set()
            for row in range(TABLE_ROWS):
                entry = rom[t_off + row * 2] | (rom[t_off + row * 2 + 1] << 8)
                if entry in seen:
                    continue
                seen.add(entry)
                w = rom[offset(d_bank, entry):offset(d_bank, entry) + 5]
                if w[0] != TX_FAR:
                    failures.append(
                        "%s: defeat table row %d -> $%04x is not a text_far "
                        "wrapper (starts $%02x)" % (area, row, entry, w[0]))
                    continue
                # `dab` is ADDRESS (little endian) then BANK - see
                # TextCommand_FAR, which reads e, d, then the bank byte.
                raw = read_far_string(rom, w[3], w[1] | (w[2] << 8))
                rendered = decode(raw)
                end = raw[-1]
                ok = end == PROMPT
                print("      row %d -> %-38s %s"
                      % (row, repr(rendered)[:38],
                         "ok" if ok else "ENDS $%02x, NO <PROMPT>" % end))
                if not ok:
                    failures.append(
                        "%s: defeat row %d ends $%02x, not <PROMPT> ($58). "
                        "PrintEndBattleText has no AfterDisplayingTextID wait "
                        "behind it, so this box prints and returns and the "
                        "money box draws straight over it. Rendered: %s"
                        % (area, row, end, rendered))
                elif TX_END in raw[:-1]:
                    failures.append(
                        "%s: defeat row %d has an \"@\" ($50) before its "
                        "<PROMPT>. PlaceNextChar returns the instant it sees "
                        "one, so the prompt is never dispatched and the text "
                        "still does not wait. Rendered: %s"
                        % (area, row, rendered))
        print()

    if failures:
        print("FAIL (%d)" % len(failures))
        for f in failures:
            print("  - %s" % f)
        return 1
    print("PASS: every Wild Area stage trainer's end-battle text is its own "
          "prompting string, reached without a box redraw.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
