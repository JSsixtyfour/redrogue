"""Audit: does beating a wild-area boss award credits?

It never used to. The award lived in TrainerBattleVictory's
.wildAreaBossCredits branch, which tested the three procedural maps - but the
boss is declared OW_POKEMON, so it fights as a WILD battle (hIsInBattle = 1)
and both callers of that routine return before reaching the credits block. The
branch was unreachable from the day it was written, so wild-area bosses paid
out nothing. Only the Cemetery ever worked, because ProceduralCemetery4.asm
awards from its own map script instead - which is the pattern the other three
now follow.

METHOD. Driving a real boss fight to victory in the harness is a long
sequence; what this checks instead is the exact gate the award sits behind.
The script fires it once, when EVENT_BEAT_PC_BOSS is set and
EVENT_PC_BOSS_OFFERED is not. So: set the beat flag, run script ticks, and
watch wPlayerCoins. The control - beat flag NOT set - proves the award is
gated rather than unconditional, which is the failure mode that would quietly
hand out credits on every map load.

Usage:
    python3 tools/pyboy_smoke/audit_wild_area_boss_credits.py
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"


def event_bit(name):
    """Resolve an EVENT_* constant to (byte offset, mask)."""
    text = (REPO_ROOT / "constants" / "event_constants.asm").read_text()
    for line in text.splitlines():
        if line.startswith("DEF %s " % name):
            value = int(line.split("EQU")[1].split(";")[0].strip())
            return value // 8, 1 << (value % 8)
    raise KeyError(name)


def coins(h):
    base = h.address("wPlayerCoins")
    return list(h.pyboy.memory[base:base + 2])


def run(map_name, set_beat_flag):
    maps = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
    beat_off, beat_mask = event_bit("EVENT_BEAT_PC_BOSS")
    off_off, off_mask = event_bit("EVENT_PC_BOSS_OFFERED")

    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_to_lobby()
        h.preload_and_enter_wild_area(maps[map_name], map_name)
        flags = h.address("wEventFlags")
        # Make sure the one-shot has not already been consumed.
        h.pyboy.memory[flags + off_off] &= 0xFF ^ off_mask
        if set_beat_flag:
            h.pyboy.memory[flags + beat_off] |= beat_mask
        else:
            h.pyboy.memory[flags + beat_off] &= 0xFF ^ beat_mask
        # BIT_PRINT_END_BATTLE_TEXT must be clear or the block defers.
        h.write8("wStatusFlags3", 0)
        before = coins(h)
        for _ in range(8):
            h.tick(30)
            h.tap("a", frames=10)
        after = coins(h)
        return before, after
    finally:
        try:
            h.close()
        except Exception:
            pass


def main() -> int:
    failures = []
    for map_name in ("PROCEDURAL_CAVE_1", "PROCEDURAL_FOREST", "PROCEDURAL_FACILITY"):
        before, after = run(map_name, True)
        awarded = after != before
        print("%-22s beat flag SET    coins %s -> %s  %s"
              % (map_name, before, after, "AWARDED" if awarded else "NOTHING"))
        if not awarded:
            failures.append("%s: boss defeat awarded no credits" % map_name)

    before, after = run("PROCEDURAL_CAVE_1", False)
    awarded = after != before
    print("%-22s beat flag CLEAR  coins %s -> %s  %s"
          % ("PROCEDURAL_CAVE_1", before, after, "AWARDED" if awarded else "nothing"))
    if awarded:
        failures.append("credits were awarded with no boss defeated - the gate is "
                        "not working")

    print()
    if failures:
        for line in failures:
            print("  FAIL: %s" % line)
        return 1
    print("PASS: every wild-area boss pays out, and only on a real defeat")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
