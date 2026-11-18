"""Guard: stack headroom and SRAM left enabled, over real autoplay runs.

Two game-wide properties no unit test can cover, because the worst case comes
from whatever the game happens to be doing:

1. Stack watermark. At the first overworld idle (JoypadOverworld), every byte
   from the unused WRAM0 gap below the stack up to SP is filled with CANARY.
   Every 60 frames of overworld idle, and when the run ends, the lowest byte no
   longer CANARY is the deepest the stack has gone, battles and every interrupt
   included (the canary remembers; the scan only reads it). A reset re-runs
   Init, which wipes WRAM0, so a hook on Init re-arms the fill at the next idle.
     - HARD FAIL (exit 2): anything written in the gap below SECTION "Stack"
       ($DEB2-$DEFF, 78 B, on 2026-11-18). The stack overflowed.
     - FAIL (exit 1): fewer than MIN_SPARE_BYTES (48) left above the stack's
       low end ($DF00). Margin, not overflow.
2. SRAM left enabled. At overworld idle (every 30 frames) the MBC RAM-enable
   latch is read from a save state; SRAM switched on there is a missing
   CloseSRAM somewhere upstream (HARD FAIL).
     The latch's byte offset in PyBoy's save state is not hard-coded: a
   throwaway harness finds it at startup (save, write $0A to $0000, save, write
   $00, save, keep the bytes that follow the latch). Each run also self-tests
   the detector on the live game: at one idle check it enables SRAM, requires
   the detector to see it, disables SRAM, and requires the detector to see that
   too, all inside the hook with no emulated instruction in between, so the
   game itself is never perturbed. A detector that stops working after a PyBoy
   upgrade therefore fails the guard instead of passing silently.

The deepest point is seed-dependent and was still creeping lower at frame
130k-145k in 150k-frame runs (6 seeds, 2026-11-18: 93-99 B spare, deepest $DF5D,
always at overworld idle, never in battle). Each run is 150k frames for that
reason: two runs take ~75 s (60k frames each took 34 s, 2026-11-18). Even so a
run need not find the true worst case; MIN_SPARE_BYTES carries that margin.

Usage:
    python3 tools/pyboy_smoke/audit_runtime_stack_sram.py [--dmg-seeds 3] [--cgb-seeds 5] [--frames 150000]
"""
from __future__ import annotations

import argparse
import io
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

import autoplay  # noqa: E402
from harness import RedRogueHarness  # noqa: E402
from stack_layout import MIN_SPARE_BYTES, stack_layout  # noqa: E402

CANARY = 0xA5
SCAN_EVERY = 60
SRAM_EVERY = 30
SELF_TEST_AFTER_FRAME = 3000
CRASH_OUTCOMES = ("crashed", "hung", "error")
GAP_LOW, STACK_LOW = stack_layout(REPO_ROOT / "pokeblue_debug.map")


def snapshot(pyboy) -> bytes:
    buffer = io.BytesIO()
    pyboy.save_state(buffer)
    return buffer.getvalue()


class LatchDetector:
    """Reads the MBC RAM-enable latch out of a PyBoy save state."""

    def __init__(self, cgb: bool):
        h = RedRogueHarness(REPO_ROOT, REPO_ROOT / "tools/pyboy_smoke/artifacts", cgb_mode=cgb)
        try:
            h.tick(120)
            h.pyboy.memory[0x0000] = 0x00
            off = snapshot(h.pyboy)
            h.pyboy.memory[0x0000] = 0x0A
            on = snapshot(h.pyboy)
            h.pyboy.memory[0x0000] = 0x00
            off_again = snapshot(h.pyboy)
        finally:
            h.close()
        if not len(off) == len(on) == len(off_again):
            raise RuntimeError("save-state length changed while calibrating")
        self.offsets = [i for i in range(len(off)) if off[i] != on[i] and off[i] == off_again[i]]
        if not self.offsets:
            raise RuntimeError("no save-state byte tracks the RAM-enable latch")
        self.length = len(off)
        self.on = {i: on[i] for i in self.offsets}

    def enabled(self, pyboy) -> bool:
        state = snapshot(pyboy)
        if len(state) != self.length:
            raise RuntimeError(f"save-state length {len(state)} != calibrated {self.length}")
        return all(state[i] == value for i, value in self.on.items())


class Watch:
    """One seed's findings, filled in by WatchedHarness."""

    def __init__(self):
        self.lows: list[dict] = []
        self.sram_open: list[dict] = []
        self.sram_checks = 0
        self.scans = 0
        self.refills = 0
        self.self_test: str | None = None  # None = never ran, "ok", or what failed

    @property
    def lowest(self) -> int | None:
        return self.lows[-1]["low"] if self.lows else None


WATCH: Watch | None = None
DETECTOR: LatchDetector | None = None


class WatchedHarness(RedRogueHarness):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._filled = False
        self._next_scan = 0
        self._next_sram = 0
        self.register_hook("JoypadOverworld", self._idle)
        self.register_hook("Init", self._init)

    def _context(self) -> dict:
        def read(label):
            try:
                return self.read8(label)
            except KeyError:
                return -1
        return {"frame": self.pyboy.frame_count, "map": read("hCurMap"),
                "battle": read("hIsInBattle"), "sp": self.pyboy.register_file.SP}

    def _init(self, _context):
        # Init wipes WRAM0, canary included; refill at the next idle. Scan first,
        # so a low reached just before the reset is not lost.
        self._scan()
        if self._filled:
            WATCH.refills += 1
        self._filled = False

    def _scan(self):
        if not self._filled:
            return
        WATCH.scans += 1
        mem = self.pyboy.memory
        low = next((a for a in range(GAP_LOW, 0xE000) if mem[a] != CANARY), 0xE000)
        if WATCH.lowest is None or low < WATCH.lowest:
            WATCH.lows.append(dict(self._context(), low=low))

    def _idle(self, _context):
        frame = self.pyboy.frame_count
        if not self._filled:
            sp = self.pyboy.register_file.SP
            for address in range(GAP_LOW, sp - 2):  # leave the hook's own frame alone
                self.pyboy.memory[address] = CANARY
            self._filled = True
            self._next_scan = frame + SCAN_EVERY
            return
        if frame >= self._next_scan:
            self._next_scan = frame + SCAN_EVERY
            self._scan()
        if frame < self._next_sram:
            return
        self._next_sram = frame + SRAM_EVERY
        WATCH.sram_checks += 1
        if DETECTOR.enabled(self.pyboy):
            hit = self._context()
            if not WATCH.sram_open or WATCH.sram_open[-1]["map"] != hit["map"]:
                WATCH.sram_open.append(hit)
            return
        if WATCH.self_test is None and frame >= SELF_TEST_AFTER_FRAME:
            self.pyboy.memory[0x0000] = 0x0A
            seen_on = DETECTOR.enabled(self.pyboy)
            self.pyboy.memory[0x0000] = 0x00
            seen_off = not DETECTOR.enabled(self.pyboy)
            WATCH.self_test = "ok" if seen_on and seen_off else (
                f"detector saw SRAM {'on' if seen_on else 'off'} after enabling it and "
                f"{'off' if seen_off else 'on'} after disabling it")

    def close(self, *args, **kwargs):
        self._scan()
        return super().close(*args, **kwargs)


def run_seed(seed: int, cgb: bool, frames: int) -> tuple[int, list[str]]:
    """(exit code, report lines) for one seed."""
    global WATCH
    WATCH = Watch()
    report = autoplay.play(seed, max_frames=frames, cgb_mode=cgb)
    mode = "CGB" if cgb else "DMG"
    lines = [f"{mode} seed {seed}: outcome={report.get('outcome')} frames={report.get('frames')} "
             f"stack scans={WATCH.scans} refills={WATCH.refills} sram checks={WATCH.sram_checks}"]
    code = 0

    def fail(level: int, text: str):
        nonlocal code
        code = max(code, level)
        lines.append(f"  {'HARD FAIL' if level == 2 else 'FAIL'}: {text}")

    low = WATCH.lowest
    if low is None:
        fail(2, "the stack was never measured (no overworld idle reached)")
    else:
        deepest = WATCH.lows[-1]
        lines.append(f"  deepest stack ${low:04x}: {0xE000 - low} B deep, {low - STACK_LOW} B spare "
                     f"above ${STACK_LOW:04x} (first seen at map {deepest['map']:#04x}, "
                     f"battle {deepest['battle']}, frame {deepest['frame']})")
        for entry in WATCH.lows[-4:-1]:
            lines.append(f"    earlier low ${entry['low']:04x} map {entry['map']:#04x} "
                         f"battle {entry['battle']} frame {entry['frame']}")
        if low < STACK_LOW:
            fail(2, f"stack OVERFLOWED: wrote ${low:04x}, inside the unused gap "
                    f"${GAP_LOW:04x}-${STACK_LOW - 1:04x}")
        elif low - STACK_LOW < MIN_SPARE_BYTES:
            fail(1, f"only {low - STACK_LOW} B of stack spare, minimum {MIN_SPARE_BYTES}")
    for hit in WATCH.sram_open[:10]:
        fail(2, f"SRAM enabled at overworld idle, map {hit['map']:#04x} frame {hit['frame']}")
    if WATCH.self_test is None:
        fail(2, f"SRAM detector self-test never ran (no clean idle check after frame "
                f"{SELF_TEST_AFTER_FRAME})")
    elif WATCH.self_test != "ok":
        fail(2, f"SRAM detector self-test failed: {WATCH.self_test}")
    else:
        lines.append("  SRAM detector self-test: ok")
    if report.get("hook_errors"):
        fail(2, f"{len(report['hook_errors'])} hook error(s); first:\n{report['hook_errors'][0]}")
    if report.get("outcome") in CRASH_OUTCOMES:
        fail(2, f"autoplay ended '{report.get('outcome')}': {report.get('detail')}")
    return code, lines


def main() -> int:
    global DETECTOR
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dmg-seeds", default="3", help="comma-separated; '' for none")
    parser.add_argument("--cgb-seeds", default="5", help="comma-separated; '' for none")
    parser.add_argument("--frames", type=int, default=150_000)
    args = parser.parse_args()
    print(f"stack ${STACK_LOW:04x}-$dfff, unused gap below it ${GAP_LOW:04x}-${STACK_LOW - 1:04x} "
          f"({STACK_LOW - GAP_LOW} B), minimum spare {MIN_SPARE_BYTES} B")
    autoplay.RedRogueHarness = WatchedHarness
    worst = 0
    for cgb, seeds in ((False, args.dmg_seeds), (True, args.cgb_seeds)):
        seeds = [int(s) for s in seeds.split(",") if s.strip()]
        if not seeds:
            continue
        DETECTOR = LatchDetector(cgb)
        print(f"{'CGB' if cgb else 'DMG'}: RAM-enable latch at save-state offset(s) "
              f"{DETECTOR.offsets} of {DETECTOR.length}")
        for seed in seeds:
            code, lines = run_seed(seed, cgb, args.frames)
            print("\n".join(lines), flush=True)
            worst = max(worst, code)
    print("PASS" if worst == 0 else ("HARD FAIL" if worst == 2 else "FAIL"))
    return worst


if __name__ == "__main__":
    raise SystemExit(main())
