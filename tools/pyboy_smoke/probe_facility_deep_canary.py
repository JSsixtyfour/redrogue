"""Deep-floor plan Phase 6 (Facility) Phase 0.2: idle-buffer canary (from the Forest's).

Same method as probe_deep_floor_canary.py (the cave's), with two candidate homes
for a Forest floor-2 shadow guarded at once while a Forest map is live
(PROCEDURAL_FOREST, its grotto, its rest house):

  A  bank 0: the cave's map buffer and state block, sProcCaveStagingBuffer
     (600 B) and sProcCaveStagingEntranceY..sProcCaveBaked (23 B)
  B  bank 1: the whole "Procedural Facility SRAM" section,
     sProcFacilityStagingBuffer .. sProcFacilityGenScratch + 81 (702 B)

Each region holds a known pattern, checked every few frames with banked reads
that leave the MBC registers alone. A change while armed is reported with the
region, map, PC and changed offsets. Arming resets on load_state (a restore is
not a write) and when the test itself writes that bank through the harness.

CANARY_CONTROL=1 arms on every map: the lobby preloads (cave and Facility
generators, legitimate writers) must then be caught, proving the canary sees.

usage (worktree tools/pyboy_smoke): python3 probe_forest_deep_canary.py test_module [...]
"""
import inspect
import json
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, ".")
import harness as H  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ROOT = Path(".").resolve().parents[1]
MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
ARM_MAPS = {MAPS["PROCEDURAL_FACILITY"], MAPS["PROCEDURAL_FACILITY_SUBROOM"]}
if os.environ.get("CANARY_CONTROL"):
    ARM_MAPS = set(range(256))
CHECK_EVERY = 4
EVENTS = []
STATS = {"arms": 0, "checks": 0, "armed_frames": 0, "tests_armed": set()}


def test_id():
    for frame in inspect.stack():
        owner = frame.frame.f_locals.get("self")
        if isinstance(owner, unittest.TestCase):
            return owner.id()
    return "?"


def pattern(n, salt):
    return bytes(((salt ^ (i * 13)) + (i >> 8)) & 0xFF for i in range(n))


def regions(h):
    a0 = h.address("sProcCaveStagingBuffer")
    s0 = h.address("sProcCaveStagingEntranceY")
    f0 = h.address("sProcForestStagingBuffer")
    g0 = h.address("sProcForestExitI")
    g1 = h.address("sProcForestGenScratch") + 81
    return [
        {"name": "A cave map", "bank": 0, "start": a0, "len": 600, "salt": 0x5C},
        {"name": "A cave state", "bank": 0, "start": s0, "len": 23, "salt": 0x3B},
        {"name": "F forest map", "bank": 0, "start": f0, "len": 400, "salt": 0x71},
        {"name": "F forest state", "bank": 0, "start": g0, "len": g1 - g0, "salt": 0x2E},
    ]


def setup(h):
    if not hasattr(h, "_canary"):
        h._canary = {"regions": regions(h), "armed": False, "frames": 0, "since": 0}
        # Some tests restore with a raw pyboy.load_state (test_procedural_progression,
        # test_procedural_trainer_return): a restore is not a write, so disarm there too.
        # PyBoy's own attribute is read-only, so wrap the object in a pass-through proxy.
        h.pyboy = _RestoreProxy(h.pyboy, h)


class _RestoreProxy:
    def __init__(self, inner, h):
        object.__setattr__(self, "_inner", inner)
        object.__setattr__(self, "_h", h)

    def load_state(self, f):
        self._inner.load_state(f)
        self._h._canary["armed"] = False
        STATS["raw_restores"] = STATS.get("raw_restores", 0) + 1

    def __getattr__(self, name):
        return getattr(self._inner, name)

    def __setattr__(self, name, value):
        setattr(self._inner, name, value)


def read(h, r):
    return bytes(h.pyboy.memory[r["bank"], r["start"]:r["start"] + r["len"]])


def plant(h):
    c = h._canary
    for r in c["regions"]:
        data = pattern(r["len"], r["salt"])
        for i, v in enumerate(data):
            h.pyboy.memory[r["bank"], r["start"] + i] = v
        if read(h, r) != data:
            raise RuntimeError(f"canary plant did not stick: {r['name']}")
        r["live"] = True
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
    m = h.read8("hCurMap")
    if not c["armed"]:
        if m in ARM_MAPS:
            plant(h)
        return
    STATS["checks"] += 1
    for r in c["regions"]:
        if not r.get("live"):
            continue
        now = read(h, r)
        want = pattern(r["len"], r["salt"])
        if now != want:
            diff = [i for i in range(r["len"]) if now[i] != want[i]]
            EVENTS.append({
                "region": r["name"], "test": test_id(), "map": m, "pc": h.pyboy.register_file.PC,
                "frames_since_arm": c["since"], "n_changed": len(diff),
                "first": diff[0], "last": diff[-1], "sample": [(i, now[i]) for i in diff[:8]],
            })
            r["live"] = False                  # one report per region per arm
    if not any(r.get("live") for r in c["regions"]):
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
    if self._canary["armed"] and any(r["bank"] == bank for r in self._canary["regions"]):
        self._canary["armed"] = False          # the test itself wrote that bank


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
    STATS["tests_armed"] = len(STATS["tests_armed"])
    print("CANARY_STATS", json.dumps(STATS))
    print("CANARY_EVENTS", len(EVENTS))
    for e in EVENTS:
        print("EVENT", json.dumps(e))
    print("TESTS_OK", result.wasSuccessful(), "run", result.testsRun,
          "fail", len(result.failures), "err", len(result.errors), "skip", len(result.skipped))
