"""Branching from save states: short random-input runs from key moments.

The autoplay agent plays one sensible line through each run. Edge cases sit
just off that line: B in the reward picker, the START menu in the lobby, a
switch or an item at a battle's first menu. During a run the agent snapshots
these moments (battle start, the reward and gift pickers, arriving in the
lobby); afterwards each chosen snapshot is loaded again and again, and played
for a few thousand frames with random presses, with autoplay_checks on:

- `crashed`: rst $38, code running from RAM, SP outside the stack;
- `frozen`: the game stopped asking for input. Every input wait in the game
  calls Joypad (JoypadLowSensitivity and JoypadOverworld both do), so no call
  for --freeze-frames means it is stuck in a loop that cannot be left;
- `anomaly`: invalid game data (party, items, warps, battle state);
- `error`: the driver itself failed.

A branch is decided entirely by its snapshot and its key, so the snapshot
of any branch with a finding is written to artifacts/ and the report prints the
command that replays it:

    python3 tools/pyboy_smoke/autoplay_branch.py --state artifacts/autoplay_seed3_reward2.state \\
        --key branch/3/reward2/5 --frames 3000

The batch runner branches with `make autoplay AUTOPLAY_ARGS='--branches 8'`.
"""
from __future__ import annotations

import argparse
import io
import json
import random
import sys
import time
import traceback
from dataclasses import dataclass, field
from pathlib import Path

import autoplay
import autoplay_checks
from harness import RedRogueHarness

SNAPSHOT_KINDS = ("battle", "reward", "gift", "lobby")
REEL_LIMIT = 32  # snapshots kept per kind during a run, spread over all of it
FREEZE_FRAMES = 1800
# Cutscenes that run longer than FREEZE_FRAMES without asking for input, by a
# routine they run (hooked), with their own limit since the last input poll. The
# trade animation measured 1,725 frames (2026-10-20). A blanket higher limit
# would have missed Witch Challenge 7's runaway text (1,847 frames).
LONG_SEQUENCES = {"TradeAnimCommon": 3600}
STACK_WORDS = 12
BRANCH_INPUT_LOG = 60

# Weighted presses: about as many d-pad as button presses, so the overworld
# walks somewhere and menus both move and get answered.
BUTTONS = (("a", 22), ("b", 14), ("up", 11), ("down", 11), ("left", 11), ("right", 11),
           ("start", 12), ("select", 8))
DIRECTIONS = {"up", "down", "left", "right"}
MAX_GAP = 12  # frames with nothing held after a press


@dataclass
class Snapshot:
    kind: str
    number: int  # this kind's nth moment in the run, from 1
    frame: int
    info: dict[str, object]
    state: bytes

    @property
    def name(self) -> str:
        return f"{self.kind}{self.number}"


@dataclass
class SnapshotReel:
    """Keeps at most REEL_LIMIT snapshots per kind spread evenly over the
    run: when a kind's list is full, every other one is dropped and only every
    other later moment is kept, doubling the spacing."""
    limit: int = REEL_LIMIT
    kept: dict[str, list[Snapshot]] = field(default_factory=dict)
    seen: dict[str, int] = field(default_factory=dict)
    stride: dict[str, int] = field(default_factory=dict)

    def offer(self, kind: str, frame: int, info: dict[str, object], save) -> None:
        number = self.seen[kind] = self.seen.get(kind, 0) + 1
        stride = self.stride.setdefault(kind, 1)
        if (number - 1) % stride:
            return
        kept = self.kept.setdefault(kind, [])
        state = io.BytesIO()
        save(state)
        kept.append(Snapshot(kind, number, frame, info, state.getvalue()))
        if len(kept) >= self.limit:
            self.kept[kind] = kept[::2]
            self.stride[kind] = stride * 2

    def select(self, per_kind: int) -> list[Snapshot]:
        """Up to per_kind snapshots of each kind, evenly spaced from the first
        to the last, so early and late game are both covered."""
        chosen = []
        for kind in SNAPSHOT_KINDS:
            kept = self.kept.get(kind, [])
            if len(kept) <= per_kind:
                chosen.extend(kept)
            elif per_kind == 1:
                chosen.append(kept[len(kept) // 2])
            else:
                picks = sorted({round(i * (len(kept) - 1) / (per_kind - 1)) for i in range(per_kind)})
                chosen.extend(kept[i] for i in picks)
        return chosen


class BranchDriver:
    """Plays random input from a loaded state with GameChecks attached. One
    driver (and one set of hooks) serves every branch in a process."""

    def __init__(self, harness: RedRogueHarness, *, freeze_frames: int = FREEZE_FRAMES):
        self.h = harness
        self.freeze_frames = freeze_frames
        maps = autoplay.parse_map_constants(autoplay.ROOT / "constants/map_constants.asm")
        self.map_names = {value: name for name, value in maps.items()}
        self.species_names = {value: name for name, value in autoplay.parse_rgbds_constants(
            autoplay.ROOT / "constants/pokemon_constants.asm").items()}
        self.events: list[dict[str, object]] = []
        self.joypad_frame = 0
        self.overworld_frame = -1
        self.interrupted = (0, 0, 0)  # (bank, PC, SP) the last VBlank cut into: the main code
        self.h.register_hook("Joypad", self._on_joypad)
        self.h.register_hook("JoypadOverworld", self._on_overworld)
        self.h.register_hook("VBlank", self._on_vblank)
        self.long_sequence = (0, -1)  # (its limit, frame it last ran)
        for name, limit in LONG_SEQUENCES.items():
            self.h.register_hook(name, lambda _c, limit=limit: setattr(
                self, "long_sequence", (limit, self.h.pyboy.frame_count)))
        self.checks = autoplay_checks.GameChecks(self, autoplay.ROOT)

    # GameChecks reports through these, as it does through the agent.
    def map_name(self, map_id: int) -> str:
        return self.map_names.get(map_id, f"${map_id:02x}")

    def event(self, kind: str, **data) -> None:
        self.events.append({"frame": self.h.pyboy.frame_count, "kind": kind, **data})

    def _on_joypad(self, _context) -> None:
        self.joypad_frame = self.h.pyboy.frame_count

    def _on_overworld(self, _context) -> None:
        self.overworld_frame = self.h.pyboy.frame_count

    def _on_vblank(self, _context) -> None:
        memory = self.h.pyboy.memory
        sp = self.h.pyboy.register_file.SP
        self.interrupted = (self.h.read8("hLoadedROMBank"), memory[sp] | memory[sp + 1] << 8, sp)

    def main_code(self) -> str:
        """The routine the game's main code is in (tick() always stops inside
        VBlank, so the PC itself says nothing)."""
        bank, pc, _ = self.interrupted
        return self._label(bank, pc)

    def _label(self, bank: int, address: int) -> str:
        if address >= 0x8000:
            return f"${address:04X}"
        bank = 0 if address < 0x4000 else bank
        return self.h.symbols.nearest(bank, address) or f"{bank:02X}:{address:04X}"

    def main_stack(self) -> list[str]:
        """Labels of the code addresses on the main code's stack, innermost
        first. Stale words below live frames can show up too; good enough to
        recognise a known cutscene."""
        bank, pc, sp = self.interrupted
        memory = self.h.pyboy.memory
        words = [memory[(sp + 2 * i) & 0xFFFF] | memory[(sp + 2 * i + 1) & 0xFFFF] << 8
                 for i in range(1, STACK_WORDS)]
        return [self._label(bank, pc)] + [self._label(bank, w) for w in words if 0x40 <= w < 0x8000]

    def quiet_limit(self) -> int:
        limit, frame = self.long_sequence
        return max(self.freeze_frames, limit) if frame >= self.joypad_frame else self.freeze_frames

    def run(self, state: bytes, key: str, frames: int) -> dict[str, object]:
        h = self.h
        h.load_state(io.BytesIO(state))
        self.checks.reset()
        self.events = []
        rng = random.Random(key)
        buttons, weights = zip(*BUTTONS)
        start = h.pyboy.frame_count
        self.joypad_frame = start  # frame_count is not part of a state: it never goes back
        self.overworld_frame = -1
        self.long_sequence = (0, -1)
        current_map, in_battle = h.read8("hCurMap"), h.read8("hIsInBattle")
        inputs: list[tuple[int, str, int]] = []
        longest_quiet, longest_quiet_at = 0, None
        outcome, detail = "ok", ""
        try:
            while h.pyboy.frame_count - start < frames:
                now = h.pyboy.frame_count
                if h.read8("hCurMap") != current_map:
                    current_map = h.read8("hCurMap")
                    self.event("enter_map", map=self.map_name(current_map))
                    self.checks.on_map_change()
                battle = h.read8("hIsInBattle")
                if in_battle and not battle:
                    self.checks.on_battle_end()
                in_battle = battle
                if now - self.overworld_frame <= 2:
                    self.checks.before_overworld_step()
                button = rng.choices(buttons, weights)[0]
                hold = rng.randint(1, 20 if button in DIRECTIONS else 6)
                inputs.append((now - start, button, hold))
                h.pyboy.button_press(button)
                h.tick(hold)
                h.pyboy.button_release(button)
                h.tick(rng.randint(1, MAX_GAP))
                self.checks.after_step()
                if self.checks.crash is not None:
                    crash = self.checks.crash
                    where = crash.get("from") or crash.get("pc") or {}
                    outcome = "crashed"
                    detail = f"{crash['kind']}: {crash['detail']}" + (
                        f" at {where.get('label') or where.get('address')}" if where else "")
                    break
                quiet = h.pyboy.frame_count - self.joypad_frame
                if quiet > longest_quiet:
                    longest_quiet = quiet
                    longest_quiet_at = {"offset": self.joypad_frame - start, "map": self.map_name(
                        h.read8("hCurMap")), "in": self.main_code(), "stack": self.main_stack()[:6]}
                if quiet > self.freeze_frames and quiet > self.quiet_limit():
                    outcome = "frozen"
                    detail = f"no input poll for {quiet} frames, in {' < '.join(self.main_stack()[:4])}"
                    break
        except Exception as error:
            outcome, detail = "error", f"{type(error).__name__}: {error}"
        return {
            "key": key,
            "outcome": outcome,
            "detail": detail,
            "frames": h.pyboy.frame_count - start,
            "longest_quiet_frames": longest_quiet,
            "longest_quiet_at": longest_quiet_at,
            "map": self.map_name(h.read8("hCurMap")),
            "anomalies": self.checks.anomalies,
            "crash": self.checks.crash,
            "maps_entered": [e["map"] for e in self.events if e["kind"] == "enter_map"],
            "last_inputs": inputs[-BRANCH_INPUT_LOG:],
        }


def branch_key(seed: int, snapshot: Snapshot, branch: int) -> str:
    return f"branch/{seed}/{snapshot.name}/{branch}"


def state_path(seed: int, snapshot: Snapshot) -> Path:
    return autoplay.ARTIFACTS / f"autoplay_seed{seed}_{snapshot.name}.state"


def replay_command(path: Path, key: str, frames: int) -> str:
    try:
        shown = path.relative_to(Path.cwd())
    except ValueError:
        shown = path
    return (f"python3 tools/pyboy_smoke/autoplay_branch.py --state {shown} "
            f"--key {key} --frames {frames}")


def run_snapshots(seed: int, snapshots: list[Snapshot], *, branches: int, frames: int,
                  freeze_frames: int = FREEZE_FRAMES, heartbeat: Path | None = None) -> dict[str, object]:
    """Every branch of every snapshot, in a fresh emulator. Returns the
    findings (with replay commands) and per-kind totals."""
    started = time.monotonic()
    harness = RedRogueHarness(autoplay.ROOT, autoplay.ARTIFACTS)
    findings = []
    totals: dict[str, dict[str, int]] = {}
    longest_quiet = {"frames": 0}
    try:
        driver = BranchDriver(harness, freeze_frames=freeze_frames)
        for snapshot in snapshots:
            written = False
            for branch in range(branches):
                key = branch_key(seed, snapshot, branch)
                if heartbeat is not None:
                    heartbeat.write_text(json.dumps({
                        "frame": harness.pyboy.frame_count, "mode": f"branching {key}",
                        "map": snapshot.info.get("map"), "position": None,
                    }) + "\n", encoding="utf-8")
                result = driver.run(snapshot.state, key, frames)
                total = totals.setdefault(snapshot.kind, {"branches": 0, "frames": 0, "findings": 0})
                total["branches"] += 1
                total["frames"] += result["frames"]
                if result["longest_quiet_frames"] > longest_quiet["frames"]:
                    longest_quiet = {"frames": result["longest_quiet_frames"], "key": key,
                                     **(result["longest_quiet_at"] or {})}
                if result["outcome"] == "ok" and not result["anomalies"]:
                    continue
                total["findings"] += 1
                path = state_path(seed, snapshot)
                if not written:
                    path.write_bytes(snapshot.state)
                    written = True
                findings.append({"snapshot": snapshot.name, "at": snapshot.info, **result,
                                 "replay": replay_command(path, key, frames)})
    finally:
        harness.close()
    return {
        "snapshots": [{"name": s.name, "frame": s.frame, **s.info} for s in snapshots],
        "branches_per_snapshot": branches,
        "frames_per_branch": frames,
        "totals": totals,
        "longest_quiet": longest_quiet,
        "findings": findings,
        "wall_seconds": round(time.monotonic() - started, 1),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Replay one random-input branch from a saved state.")
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--key", required=True, help="the branch's key, as its report prints it")
    parser.add_argument("--frames", type=int, default=3000)
    parser.add_argument("--freeze-frames", type=int, default=FREEZE_FRAMES)
    args = parser.parse_args(argv)

    harness = RedRogueHarness(autoplay.ROOT, autoplay.ARTIFACTS)
    try:
        driver = BranchDriver(harness, freeze_frames=args.freeze_frames)
        result = driver.run(args.state.read_bytes(), args.key, args.frames)
        stem = f"autoplay_branch_{args.key.replace('/', '_')}"
        image, state = harness.write_failure_artifacts(stem)
        result["artifacts"] = {"image": str(image), "state": str(state)}
    finally:
        harness.close()
    print(json.dumps(result, indent=1))
    return 0 if result["outcome"] == "ok" and not result["anomalies"] else 1


if __name__ == "__main__":
    sys.exit(main())
