"""Deep-floor plan Phase 0.2: idle-buffer canary over the Facility SRAM section.

Runs existing smoke test modules with RedRogueHarness patched so that, whenever
the cave (or its subroom) is live, the whole "Procedural Facility SRAM" section
(bank 1) holds a known pattern, checked every few frames without touching the
MBC registers. Any change while armed is reported with the map, PC and the
changed offsets. Arming is reset on load_state (a state restore is not a write)
and on harness bank-1 SRAM writes.

usage: python3 facility_canary.py test_module [test_module ...]
Run from the worktree's tools/pyboy_smoke directory.
"""
import inspect
import json
import sys
import unittest

sys.path.insert(0, ".")
import harness as H  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402
from pathlib import Path  # noqa: E402

ROOT = Path(".").resolve().parents[1]
MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
CAVE_MAPS = {MAPS["PROCEDURAL_CAVE_1"], MAPS["PROCEDURAL_CAVE_SUBROOM"]}
import os  # noqa: E402
if os.environ.get("CANARY_CONTROL"):
    # Positive control: arm on every map, so a Facility preload in the lobby
    # (a legitimate writer) must be caught.
    CAVE_MAPS = set(range(256))
CHECK_EVERY = 4
EVENTS = []
STATS = {"arms": 0, "checks": 0, "armed_frames": 0, "tests_armed": set()}


def test_id():
    for frame in inspect.stack():
        owner = frame.frame.f_locals.get("self")
        if isinstance(owner, unittest.TestCase):
            return owner.id()
    return "?"


def pattern(n):
    return bytes(((0xA5 ^ (i * 13)) + (i >> 8)) & 0xFF for i in range(n))


def setup(h):
    if hasattr(h, "_canary"):
        return
    start = h.address("sProcFacilityStagingBuffer")
    end = h.address("sProcFacilityGenScratch") + 81
    h._canary = {"start": start, "len": end - start, "armed": False, "frames": 0, "since": 0}


def plant(h):
    c = h._canary
    data = pattern(c["len"])
    for i, v in enumerate(data):
        h.pyboy.memory[1, c["start"] + i] = v
    back = bytes(h.pyboy.memory[1, c["start"]:c["start"] + c["len"]])
    if back != data:
        raise RuntimeError("canary plant did not stick")
    c["armed"] = True
    c["since"] = 0
    STATS["arms"] += 1
    STATS["tests_armed"].add(test_id())


def check(h, force=False):
    setup(h)
    c = h._canary
    c["frames"] += 1
    if c["armed"]:
        STATS["armed_frames"] += 1
        c["since"] += 1
    if not force and c["frames"] % CHECK_EVERY:
        return
    m = h.pyboy.memory[0xFFB5] if False else h.read8("hCurMap")
    if not c["armed"]:
        if m in CAVE_MAPS:
            plant(h)
        return
    STATS["checks"] += 1
    now = bytes(h.pyboy.memory[1, c["start"]:c["start"] + c["len"]])
    want = pattern(c["len"])
    if now != want:
        diff = [i for i in range(c["len"]) if now[i] != want[i]]
        EVENTS.append({
            "test": test_id(), "map": m, "pc": h.pyboy.register_file.PC,
            "rom_bank": h.pyboy.memory[0xFF00 - 0xFF00 + 0x2000] if False else None,
            "frames_since_arm": c["since"], "n_changed": len(diff),
            "first": diff[0], "last": diff[-1],
            "sample": [(i, now[i]) for i in diff[:12]],
            "lobby_doors": [h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap")],
        })
        c["armed"] = False


_tick = H.RedRogueHarness.tick
_wait = H.RedRogueHarness.wait_until
_load = H.RedRogueHarness.load_state
_wsram = H.RedRogueHarness.write_sram_bytes
_close = H.RedRogueHarness.close


def tick(self, frames=1, *, render=False):
    for _ in range(frames):
        _tick(self, 1, render=render)
        check(self)


def wait_until(self, predicate, description, limit=2400):
    def wrapped():
        check(self)
        return predicate()
    return _wait(self, wrapped, description, limit)


def load_state(self, f):
    _load(self, f)
    setup(self)
    self._canary["armed"] = False


def write_sram_bytes(self, label, values, bank=1):
    _wsram(self, label, values, bank)
    setup(self)
    if bank == 1 and self._canary["armed"]:
        self._canary["armed"] = False   # the test itself wrote bank 1


def close(self):
    try:
        if hasattr(self, "_canary"):
            check(self, force=True)
    finally:
        _close(self)


H.RedRogueHarness.tick = tick
H.RedRogueHarness.wait_until = wait_until
H.RedRogueHarness.load_state = load_state
H.RedRogueHarness.write_sram_bytes = write_sram_bytes
H.RedRogueHarness.close = close

if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromNames(sys.argv[1:])
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    STATS["tests_armed"] = sorted(STATS["tests_armed"])
    print("CANARY_STATS", json.dumps(STATS))
    print("CANARY_EVENTS", len(EVENTS))
    for e in EVENTS:
        print("EVENT", json.dumps(e))
    print("TESTS_OK", result.wasSuccessful(), "run", result.testsRun,
          "fail", len(result.failures), "err", len(result.errors), "skip", len(result.skipped))
