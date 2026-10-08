"""Run the ROM's own UncompressSpriteData over every compressed pic.

Golden contract for SPRITE_DECOMPRESSION_PLAN.md (Red Rogue Files): whatever
replaces or rewrites the decoder must leave sSpriteBuffer1-2 byte-identical to
the vanilla routine for every pic, flipped and unflipped. sSpriteBuffer0 is
NOT part of the contract: no caller keeps data in it across a decode (audited
2026-10-07), so a replacement decoder may use it as scratch.

Why not call_routine: it is good for ~10 calls a boot and detects its return
heuristically. This needs ~1350 calls, so it drives the CPU directly instead:
park inside VBlank, set IE = 0 so nothing interrupts, then for each pic set
A / wSpriteInputPtr / wSpriteFlipped, push a sentinel return address and jump
to UncompressSpriteData. One hook on the sentinel captures the buffers and
starts the next pic. The game is never resumed, so nothing it was doing can be
corrupted into a false result.

CLI (run from WSL, repo root):
    python3 tools/pyboy_smoke/sprite_decompression.py --write-golden
    python3 tools/pyboy_smoke/sprite_decompression.py --bench
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
GOLDEN_PATH = Path(__file__).resolve().parent / "sprite_decompression_golden.json"
PIC_SOURCES = ("gfx/pics.asm", "gfx/player.asm", "data/pokemon/mew.asm")

SPRITEBUFFERSIZE = 7 * 7 * 8
FILL = 0xA5  # pre-fill pattern; proves which bytes the decoder writes
# Sentinel return target: a HOME routine the decoder never calls, and which
# cannot run on its own once interrupts are off and the game is abandoned.
SENTINEL = "DelayFrame"
DMG_FRAME_CYCLES = 70224

# Every compressed pic: LZ (.lz) since 2026-10-07, Gen 1 .pic before that.
PIC_LABEL = re.compile(r"^([A-Za-z0-9_]+)::?\s+INCBIN\s+\"([^\"]+\.(?:lz|pic))\"", re.M)


def pic_labels(repo_root: Path = REPO_ROOT) -> list[tuple[str, str]]:
    """(label, compressed pic path) for every labelled pic, in source order."""
    pics = []
    for source in PIC_SOURCES:
        pics.extend(PIC_LABEL.findall((repo_root / source).read_text()))
    return pics


def run_all(harness, flips=(0, 1)) -> dict[str, dict[str, object]]:
    """Decompress every pic; return {"<label>/<flip>": {"sha256", "cycles", "buffers"}}."""
    h = harness
    mem = h.pyboy.memory
    jobs = []
    for label, _path in pic_labels(h.repo_root):
        bank, address = h.symbols.get(label)
        for flip in flips:
            jobs.append((f"{label}/{flip}", bank, address, flip))

    buffer0 = h.address("sSpriteBuffer0")
    for name in ("sSpriteBuffer1", "sSpriteBuffer2"):
        expected = buffer0 + SPRITEBUFFERSIZE * int(name[-1])
        if h.address(name) != expected:
            raise AssertionError(f"{name} is not contiguous with sSpriteBuffer0")
    span = 3 * SPRITEBUFFERSIZE
    entry = h.address("UncompressSpriteData")
    sentinel = h.address(SENTINEL)
    input_ptr = h.address("wSpriteInputPtr")
    flipped = h.address("wSpriteFlipped")

    h.park_before_hijack()
    mem[0xFFFF] = 0  # IE: nothing may interrupt from here on
    stack_top = h.pyboy.register_file.SP & 0xFFFE

    results: dict[str, dict[str, object]] = {}
    state = {"index": 0, "start": 0, "done": False}

    def start(index: int) -> None:
        name, bank, address, flip = jobs[index]
        mem[0x0000] = 0x0A  # enable SRAM, bank 0, so the pre-fill lands
        mem[0x4000] = 0
        for offset in range(span):
            mem[buffer0 + offset] = FILL
        mem[input_ptr] = address & 0xFF
        mem[input_ptr + 1] = address >> 8
        mem[flipped] = flip
        sp = (stack_top - 2) & 0xFFFF
        mem[sp] = sentinel & 0xFF
        mem[sp + 1] = sentinel >> 8
        regs = h.pyboy.register_file
        regs.SP = sp
        regs.A = bank
        regs.PC = entry
        state["start"] = h.cycle_count()

    def finished(_context) -> None:
        if state["done"]:
            return
        cycles = h.cycle_count() - state["start"]
        mem[0x0000] = 0x0A
        mem[0x4000] = 0
        data = bytes(mem[buffer0 : buffer0 + span])
        name = jobs[state["index"]][0]
        results[name] = {
            # buffers 1-2 only; see the module docstring for why not buffer 0
            "sha256": hashlib.sha256(data[SPRITEBUFFERSIZE:]).hexdigest(),
            "cycles": cycles,
            "buffers": data,
        }
        state["index"] += 1
        if state["index"] == len(jobs):
            state["done"] = True
            return
        start(state["index"])

    h.register_hook(SENTINEL, finished)
    start(0)
    # ~3M T-cycles per pic worst case observed; generous frame budget.
    budget = len(jobs) * 60 + 600
    for _ in range(budget):
        h.tick(1)
        if state["done"]:
            break
    if not state["done"]:
        name = jobs[state["index"]][0]
        raise AssertionError(
            f"decoder did not return for {name} (job {state['index']} of {len(jobs)}); "
            f"PC=${h.pyboy.register_file.PC:04x}"
        )
    return results


def load_golden() -> dict[str, str]:
    return json.loads(GOLDEN_PATH.read_text())["sha256"]


def _make_harness():
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from harness import RedRogueHarness

    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    h.tick(120)  # past boot init; the game itself is never used
    return h


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-golden", action="store_true")
    parser.add_argument("--bench", action="store_true")
    args = parser.parse_args()

    h = _make_harness()
    try:
        results = run_all(h)
    finally:
        h.close()

    cycles = sorted(r["cycles"] for r in results.values())
    total = sum(cycles)
    print(
        f"{len(results)} decompressions; cycles total {total} "
        f"({total / DMG_FRAME_CYCLES:.0f} DMG frames), mean "
        f"{total / len(cycles) / DMG_FRAME_CYCLES:.2f} frames, median "
        f"{cycles[len(cycles) // 2] / DMG_FRAME_CYCLES:.2f}, max "
        f"{cycles[-1] / DMG_FRAME_CYCLES:.2f}"
    )
    if args.write_golden:
        golden = {
            "note": "sha256 of sSpriteBuffer1-2 (pre-filled $A5) after "
            "UncompressSpriteData; key = <pic label>/<wSpriteFlipped>. "
            "Generated from the vanilla decoder; see sprite_decompression.py.",
            "sha256": {k: v["sha256"] for k, v in sorted(results.items())},
        }
        # write_bytes, not write_text: LF line endings even if run on Windows
        GOLDEN_PATH.write_bytes((json.dumps(golden, indent=1) + "\n").encode())
        print(f"wrote {GOLDEN_PATH}")
    if args.bench or not args.write_golden:
        if GOLDEN_PATH.is_file():
            golden = load_golden()
            bad = [k for k, v in results.items() if golden.get(k) != v["sha256"]]
            missing = [k for k in golden if k not in results]
            print(f"golden: {len(bad)} mismatched, {len(missing)} missing")
            for k in bad[:10]:
                print("  mismatch", k)
    return 0


if __name__ == "__main__":
    sys.exit(main())
