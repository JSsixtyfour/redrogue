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
import hashlib
import copy
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
    identity: dict | None = None
    state_sha256: str = field(init=False)

    def __post_init__(self):
        self.state_sha256 = hashlib.sha256(self.state).hexdigest()

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
    identity: dict | None = None
    rare_limit: int = 4  # extra bounded representatives per kind, outside temporal thinning
    reserved: dict[str, dict[str, Snapshot]] = field(default_factory=dict)
    unreserved: dict[str, set[str]] = field(default_factory=dict)

    def offer(self, kind: str, frame: int, info: dict[str, object], save) -> None:
        number = self.seen[kind] = self.seen.get(kind, 0) + 1
        stride = self.stride.setdefault(kind, 1)
        features = info.get('rare_features', [])
        if not isinstance(features, list) or any(not isinstance(item, str) or not item for item in features):
            raise ValueError('rare_features must contain nonempty feature names')
        reserved = self.reserved.setdefault(kind, {})
        novel = [feature for feature in dict.fromkeys(features) if feature not in reserved]
        admitted = novel[:max(0, self.rare_limit - len(reserved))]
        self.unreserved.setdefault(kind, set()).update(set(novel) - set(admitted))
        temporal = not (number - 1) % stride
        if not temporal and not admitted:
            return
        kept = self.kept.setdefault(kind, [])
        state = io.BytesIO()
        save(state)
        snapshot = Snapshot(kind, number, frame, copy.deepcopy(info), state.getvalue(), copy.deepcopy(self.identity))
        for feature in admitted:
            reserved[feature] = snapshot
        if not temporal:
            return
        kept.append(snapshot)
        if len(kept) >= self.limit:
            self.kept[kind] = kept[::2]
            self.stride[kind] = stride * 2

    def select(self, per_kind: int) -> list[Snapshot]:
        """Up to per_kind snapshots of each kind, evenly spaced from the first
        to the last, so early and late game are both covered."""
        chosen = []
        if per_kind <= 0:
            return chosen
        for kind in SNAPSHOT_KINDS:
            kept = self.kept.get(kind, [])
            protected = list({snapshot.name: snapshot for snapshot in self.reserved.get(kind, {}).values()}.values())
            protected = protected[:per_kind]
            if len(kept) <= per_kind:
                temporal = kept
            elif per_kind == 1:
                temporal = [kept[len(kept) // 2]]
            else:
                picks = sorted({round(i * (len(kept) - 1) / (per_kind - 1)) for i in range(per_kind)})
                temporal = [kept[i] for i in picks]
            chosen.extend((protected + [snapshot for snapshot in temporal if snapshot.name not in {item.name for item in protected}])[:per_kind])
        return chosen


class BranchDriver:
    """Plays random input from a loaded state with GameChecks attached. One
    driver (and one set of hooks) serves every branch in a process."""

    def __init__(self, harness: RedRogueHarness, *, freeze_frames: int = FREEZE_FRAMES):
        self.h = harness
        self.freeze_frames = freeze_frames
        maps = autoplay.parse_map_constants(autoplay.ROOT / "constants/map_constants.asm")
        self.map_names = autoplay.names_by_value(maps)
        self.species_names = autoplay.names_by_value(autoplay.parse_rgbds_constants(
            autoplay.ROOT / "constants/pokemon_constants.asm"))
        self.events: list[dict[str, object]] = []
        self.joypad_frame = 0
        self.interrupted = (0, 0, 0)  # (bank, PC, SP) the last VBlank cut into: the main code
        self.h.register_hook("Joypad", self._on_joypad)
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
        h.hook_errors.clear()
        rng = random.Random(key)
        buttons, weights = zip(*BUTTONS)
        start = h.pyboy.frame_count
        self.joypad_frame = start  # frame_count is not part of a state: it never goes back
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
                button = rng.choices(buttons, weights)[0]
                hold = rng.randint(1, 20 if button in DIRECTIONS else 6)
                inputs.append((now - start, button, hold))
                h.pyboy.button_press(button)
                h.tick(hold)
                h.pyboy.button_release(button)
                h.tick(rng.randint(1, MAX_GAP))
                self.checks.after_step()
                if h.hook_errors:
                    outcome, detail = "error", "a hook callback raised: " + h.hook_errors[0].strip().splitlines()[-1]
                    break
                if self.checks.crash is not None:
                    crash = self.checks.crash
                    where = crash.get("from") or crash.get("pc") or {}
                    outcome = "crashed"
                    detail = f"{crash['kind']}: {crash['detail']}" + (
                        f" at {where.get('label') or where.get('address')}" if where else "")
                    # tick() ends inside VBlank: the main code it interrupted
                    # says what the game itself was doing.
                    crash["main_code"] = self.main_stack()[:6]
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
            "detector_health": self.checks.summary()['detector_health'],
            "hook_errors": list(h.hook_errors),
            "maps_entered": [e["map"] for e in self.events if e["kind"] == "enter_map"],
            "last_inputs": inputs[-BRANCH_INPUT_LOG:],
        }


def branch_key(seed: int, snapshot: Snapshot, branch: int) -> str:
    return f"branch/{seed}/{snapshot.name}/{branch}"


def state_path(seed: int, snapshot: Snapshot) -> Path:
    return autoplay.ARTIFACTS / f"{autoplay.stem(seed)}_{snapshot.name}.state"


def replay_command(path: Path, key: str, frames: int, freeze_frames: int = FREEZE_FRAMES) -> str:
    try:
        shown = path.relative_to(Path.cwd())
    except ValueError:
        shown = path
    rom = "" if autoplay.ROM == autoplay.DEBUG_ROM else f" --rom {autoplay.ROM}"
    cgb = " --cgb" if autoplay.CGB_MODE else ""
    freeze = f' --freeze-frames {freeze_frames}' if freeze_frames != FREEZE_FRAMES else ''
    return (f"python3 tools/pyboy_smoke/autoplay_branch.py --state {shown} "
            f"--key {key} --frames {frames}{rom}{cgb}{freeze}")


def snapshot_identity(harness):
    return {'rom_sha256': harness.rom_sha256, 'sym_sha256': harness.sym_sha256,
            'hardware_mode': harness.hardware_mode}


def retain_snapshot(snapshot, harness, path, seed):
    from run_campaign import atomic_json
    if snapshot.identity != snapshot_identity(harness):
        raise ValueError('snapshot capture identity missing or incompatible')
    if hashlib.sha256(snapshot.state).hexdigest() != snapshot.state_sha256:
        raise ValueError('snapshot bytes changed after capture')
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.state.tmp')
    temporary.write_bytes(snapshot.state)
    temporary.replace(path)
    metadata = {'schema_version': 1, 'identity': snapshot.identity, 'state_sha256': snapshot.state_sha256,
                'origin': {'seed': seed, 'kind': snapshot.kind, 'number': snapshot.number,
                           'frame': snapshot.frame, 'info': snapshot.info}}
    sidecar = path.with_suffix(path.suffix + '.json')
    atomic_json(sidecar, metadata)
    return {**metadata, 'state': str(path), 'metadata': str(sidecar)}


def read_snapshot(path, harness):
    """Legacy states without identity evidence require recapture, never guessing."""
    sidecar = path.with_suffix(path.suffix + '.json')
    try:
        metadata = json.loads(sidecar.read_text())
    except (OSError, ValueError) as error:
        raise ValueError('snapshot identity metadata missing or malformed; recapture on the exact build') from error
    if not isinstance(metadata, dict) or type(metadata.get('schema_version')) is not int or metadata['schema_version'] != 1:
        raise ValueError('unsupported snapshot metadata schema')
    if metadata.get('identity') != snapshot_identity(harness):
        raise ValueError('snapshot ROM/SYM/hardware identity mismatch')
    state = path.read_bytes()
    if hashlib.sha256(state).hexdigest() != metadata.get('state_sha256'):
        raise ValueError('snapshot state hash mismatch')
    if not isinstance(metadata.get('origin'), dict) or not isinstance(metadata['origin'].get('info'), dict):
        raise ValueError('snapshot provenance missing')
    return state


def run_snapshots(seed: int, snapshots: list[Snapshot], *, branches: int, frames: int,
                  freeze_frames: int = FREEZE_FRAMES, heartbeat: Path | None = None,
                  coverage: bool = False, cgb_mode: bool = False) -> dict[str, object]:
    """Every branch of every snapshot, in a fresh emulator. Returns the
    findings (with replay commands) and per-kind totals."""
    started = time.monotonic()
    harness = RedRogueHarness(autoplay.ROOT, autoplay.ARTIFACTS, rom=autoplay.ROM,
                              cgb_mode=cgb_mode)
    findings = []
    detector_records = []
    retained = []
    totals: dict[str, dict[str, int]] = {}
    longest_quiet = {"frames": 0}
    try:
        driver = BranchDriver(harness, freeze_frames=freeze_frames)
        hits = harness.track_coverage(autoplay.coverage_hooks())[0] if coverage else set()
        for snapshot in snapshots:
            path = state_path(seed, snapshot)
            retained.append(retain_snapshot(snapshot, harness, path, seed))
            for branch in range(branches):
                key = branch_key(seed, snapshot, branch)
                if heartbeat is not None:
                    heartbeat.write_text(json.dumps({
                        "frame": harness.pyboy.frame_count, "mode": f"branching {key}",
                        "map": snapshot.info.get("map"), "position": None,
                    }) + "\n", encoding="utf-8")
                result = driver.run(snapshot.state, key, frames)
                detector_records.append({name: result[name] for name in
                                         ('key', 'outcome', 'detector_health', 'hook_errors')})
                total = totals.setdefault(snapshot.kind, {"branches": 0, "frames": 0, "findings": 0})
                total["branches"] += 1
                total["frames"] += result["frames"]
                if result["longest_quiet_frames"] > longest_quiet["frames"]:
                    longest_quiet = {"frames": result["longest_quiet_frames"], "key": key,
                                     **(result["longest_quiet_at"] or {})}
                if result["outcome"] == "ok" and not result["anomalies"]:
                    continue
                total["findings"] += 1
                findings.append({"snapshot": snapshot.name, "at": snapshot.info, **result,
                                 "replay": replay_command(path, key, frames, freeze_frames)})
    finally:
        harness.close()
    return {
        "snapshots": [{"name": s.name, "frame": s.frame, **s.info} for s in snapshots],
        'retained_snapshots': retained,
        "branches_per_snapshot": branches,
        "frames_per_branch": frames,
        "hardware_mode": harness.hardware_mode,
        "totals": totals,
        "detector_records": detector_records,
        "longest_quiet": longest_quiet,
        "findings": findings,
        **({"coverage_hits": sorted(hits)} if coverage else {}),
        "wall_seconds": round(time.monotonic() - started, 1),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Replay one random-input branch from a saved state.")
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--key", required=True, help="the branch's key, as its report prints it")
    parser.add_argument("--frames", type=int, default=3000)
    parser.add_argument("--freeze-frames", type=int, default=FREEZE_FRAMES)
    parser.add_argument("--rom", choices=autoplay.ROMS, default=autoplay.DEBUG_ROM,
                        help="the build the state was saved on")
    parser.add_argument("--cgb", action="store_true",
                        help="replay the state in CGB mode (default: DMG)")
    args = parser.parse_args(argv)

    autoplay.ROM = args.rom
    autoplay.CGB_MODE = args.cgb
    harness = RedRogueHarness(autoplay.ROOT, autoplay.ARTIFACTS, rom=args.rom,
                              cgb_mode=args.cgb)
    try:
        captured = read_snapshot(args.state, harness)
        driver = BranchDriver(harness, freeze_frames=args.freeze_frames)
        result = driver.run(captured, args.key, args.frames)
        stem = f"autoplay_branch_{args.key.replace('/', '_')}"
        image, state = harness.write_failure_artifacts(stem)
        result["artifacts"] = {"image": str(image), "state": str(state)}
    finally:
        harness.close()
    print(json.dumps(result, indent=1))
    return 0 if result["outcome"] == "ok" and not result["anomalies"] else 1


if __name__ == "__main__":
    sys.exit(main())
