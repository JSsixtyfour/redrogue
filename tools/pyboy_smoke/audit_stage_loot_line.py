"""Audit: the villain names what it took, and the recovery names what came back.

Checks the naming path end to end rather than just the plumbing:
  1. after the arrival, wNameBuffer holds the stolen mon's NICKNAME (the name
     the player knows it by), copied out of sStolenNickname
  2. the greeting box is still on screen when it does, i.e. the loot line
     prints as part of the same sequence
  3. after StageEventGiveBack - which clears the stolen record - wNameBuffer
     STILL holds that name, which is the whole reason GiveBack fills it first

Saves a screenshot of the loot line so the wording can be eyeballed.

Usage:
    python3 tools/pyboy_smoke/audit_stage_loot_line.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"
NAME_LENGTH = 11
RECORD_BANK = 1


def stage_const(name):
    text = (REPO_ROOT / "constants" / "ram_constants.asm").read_text()
    m = re.search(r"^DEF %s\s+EQU\s+(\d+)" % name, text, re.M)
    return int(m.group(1))


def decode(raw):
    out = []
    for b in raw:
        if b == 0x50:
            break
        if 0x80 <= b <= 0x99:
            out.append(chr(ord("A") + b - 0x80))
        elif 0xA0 <= b <= 0xB9:
            out.append(chr(ord("a") + b - 0xA0))
        elif 0xF6 <= b <= 0xFF:
            out.append(chr(ord("0") + b - 0xF6))
        else:
            out.append("?")
    return "".join(out)


def main() -> int:
    map_id = parse_map_constants(
        REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]
    failures = []

    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_to_lobby()
        h.write8("wStageEvent", stage_const("STAGE_EVENT_JESSIE_JAMES"))
        h.preload_and_enter_wild_area(map_id, "Procedural Cave")

        kind = h.read_sram_bytes("sStolenKind", 1, bank=RECORD_BANK)[0]
        nick_raw = h.read_sram_bytes("sStolenNickname", NAME_LENGTH, bank=RECORD_BANK)
        nickname = decode(nick_raw)
        print("sStolenKind=%d  sStolenNickname=%r" % (kind, nickname))
        if kind != 1:
            print("no mon was stolen this run - nothing to check")
            return 0

        # Step through the greeting; the loot line is the second box.
        h.tap("a", frames=12)
        h.tick(60)
        name_after_greet = decode(h.read_bytes("wNameBuffer", NAME_LENGTH))
        print("wNameBuffer after the greeting: %r" % name_after_greet)
        h.pyboy.tick(render=True)
        shot = ARTIFACTS / "stage_loot_line.png"
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        h.pyboy.screen.image.save(shot)
        print("screenshot: %s" % shot)
        if name_after_greet != nickname:
            failures.append(
                "wNameBuffer is %r but the stolen nickname is %r - the loot "
                "line would print the wrong name (or none)"
                % (name_after_greet, nickname))

        # Close out the arrival, then hand the mon back.
        for _ in range(6):
            h.tap("a", frames=12)
            h.tick(40)
        h.call_routine("StageEventGiveBack")
        name_after_giveback = decode(h.read_bytes("wNameBuffer", NAME_LENGTH))
        print("wNameBuffer after GiveBack:     %r" % name_after_giveback)
        if name_after_giveback != nickname:
            failures.append(
                "wNameBuffer is %r after GiveBack, expected %r - GiveBack must "
                "name the loot BEFORE it clears the stolen record, or the "
                "recovery line has nothing to print"
                % (name_after_giveback, nickname))
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
    print("PASS: the stolen mon is named at the theft and still named at the "
          "give-back")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
