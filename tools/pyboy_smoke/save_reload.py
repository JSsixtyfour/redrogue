"""Save and reload checks: does a save bring back exactly what was saved, and
what does a power cut in the middle of saving leave?

Full saves run SaveGameData. The original writer published a checksum after
each of three component saves; the optimized writer shares raw-copy helpers
and publishes one final checksum. Both lifecycles are sampled below. For key
moments of an autoplay run (lobby arrivals, from SnapshotReel):

- round trip: run SaveGameData, boot a fresh emulator on nothing but that
  cartridge RAM, and when TryLoadSaveFile finishes compare every saved region
  (player name, wMainData, sprite data, current box, party, hCurMap,
  hTileAnimations) byte for byte with what was saved. Then CONTINUE into the
  overworld and play random input with autoplay_checks on.
- power cut: with an older complete save in SRAM, save again and capture the
  cartridge RAM at each step of the save (each part's start and each checksum
  write). Reboot on each capture and classify what loads: the old save, the
  new one, a mix of the two (regions from different moments, accepted as
  valid), or refused ("file data destroyed").

    python3 tools/pyboy_smoke/save_reload.py --seed 3 --stages 6
    make autoplay AUTOPLAY_ARGS='--seeds 1-8 --save-checks'
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import sys
import tempfile
import time
from pathlib import Path

import autoplay
import autoplay_branch
from harness import RedRogueHarness

SRAM_BANKS = 4
SRAM_BANK_SIZE = 0x2000
NAME_LENGTH = 11
BOOT_FRAMES = 3000  # power-on to the main menu's save check, pressing A
CONTINUE_FRAMES = 3000  # CONTINUE to the first overworld frame
AFTER_LOAD_FRAMES = 1500  # random play after a reload, with the checks on
# Regions SaveGameData writes, as (name, start label, end label or length).
REGIONS = (("player name", "wPlayerName", NAME_LENGTH),
           ("main data", "wMainDataStart", "wMainDataEnd"),
           ("sprite data", "wSpriteDataStart", "wSpriteDataEnd"),
           ("current box", "wBoxDataStart", "wBoxDataEnd"),
           ("party", "wPartyDataStart", "wPartyDataEnd"),
           ("hCurMap", "hCurMap", 1),
           ("hTileAnimations", "hTileAnimations", 1))
# Differences a correct save and load make on purpose: label -> (mask of bits
# allowed to differ, why). Measured 2026-10-20 on Debug 2 lobby saves.
EXPECTED_LOAD_CHANGES = {
    "wCurMapTileset": (0x80, "LoadMainData sets BIT_NO_PREVIOUS_MAP so CONTINUE skips the previous-map logic"),
    # The play timer keeps counting during the frames the load takes, and its
    # frames carry into seconds, minutes and hours.
    "wPlayTimeFrames": (0xFF, "the play timer runs during the load"),
    "wPlayTimeSeconds": (0xFF, "the play timer runs during the load"),
    "wPlayTimeMinutes": (0xFF, "the play timer runs during the load"),
    "wPlayTimeHours": (0xFF, "the play timer runs during the load"),
    "wStolenSaveSnapshot": (0xFF, "SaveMainData refreshes it from sStolenRecord (SRAM) as it saves"),
}


def sram_image(h: RedRogueHarness) -> bytes:
    memory = h.pyboy.memory
    return bytes(memory[bank, 0xA000 + i] for bank in range(SRAM_BANKS) for i in range(SRAM_BANK_SIZE))


def write_sram(h: RedRogueHarness, data: bytes) -> None:
    memory = h.pyboy.memory
    for bank in range(SRAM_BANKS):
        for i in range(SRAM_BANK_SIZE):
            memory[bank, 0xA000 + i] = data[bank * SRAM_BANK_SIZE + i]


def region_spans(h: RedRogueHarness) -> list[tuple[str, int, int]]:
    spans = []
    for name, start, end in REGIONS:
        first = h.address(start)
        length = end if isinstance(end, int) else h.address(end) - first
        spans.append((name, first, length))
    return spans


def region_image(h: RedRogueHarness) -> dict[str, bytes]:
    memory = h.pyboy.memory
    return {name: bytes(memory[first + i] for i in range(length)) for name, first, length in region_spans(h)}


def differences(h: RedRogueHarness, saved: dict[str, bytes], loaded: dict[str, bytes],
                only: str | None = None, *, accounted_timer: dict | None = None) -> list[dict[str, object]]:
    """Bytes that came back different, named by the nearest WRAM/HRAM label."""
    found = []
    for name, first, _length in region_spans(h):
        if only is not None and name != only:
            continue
        for offset, (was, now) in enumerate(zip(saved[name], loaded[name])):
            if was == now:
                continue
            address = first + offset
            if accounted_timer and accounted_timer["status"] == "accounted":
                timer_index = address - h.address("wRunTimerState")
                if 0 <= timer_index < 5 and now == accounted_timer["expected_clock"][timer_index]:
                    continue
            label = h.symbols.nearest(0, address) or f"${address:04X}"
            allowed = EXPECTED_LOAD_CHANGES.get(label.split("+")[0])
            if allowed is not None and not (was ^ now) & ~allowed[0] & 0xFF:
                continue
            found.append({"region": name, "label": label, "address": f"${address:04X}",
                          "saved": f"${was:02X}", "loaded": f"${now:02X}"})
    return found


SETTLE_FRAMES = 1200  # at most, from a snapshot to an idle overworld frame


def settle(h: RedRogueHarness) -> bool:
    """Run the game until the overworld polls for input with no text or script
    running: a moment a player could open START > SAVE. A lobby snapshot is
    taken the step hCurMap changes, before the new map's header has loaded;
    saving there stored half of each map, and CONTINUE rebuilt the lobby with
    the previous map's collision (measured 2026-10-20: its top row became
    walkable and walking off it loaded map $FF). Returns False if none came."""
    polled = []

    def poll(_context) -> None:
        polled.append(h.pyboy.frame_count)

    h.register_hook("JoypadOverworld", poll)
    try:
        for _ in range(SETTLE_FRAMES):
            h.tick(1)
            if (len(polled) >= 2 and not h.read8("hJoyIgnore")
                    and not h.read8("hSimulatedJoypadStatesIndex") and not h.read8("wWalkCounter")):
                return True
        return False
    finally:
        h.unregister_hook("JoypadOverworld", poll)


def timer_observation(h: RedRogueHarness, boundary: str) -> dict:
    return {"boundary": boundary, "frame": h.pyboy.frame_count,
            "clock": h.read_bytes("wRunTimerState", 5),
            "timer_enabled": bool(h.read8("wStatusFlags6") & 1)}


def advance_run_clock(clock: list[int], ticks: int) -> list[int]:
    """Independent base-60 accounting; crossing 256 hours stops at the cap."""
    if (len(clock) != 5 or any(type(value) is not int or not 0 <= value <= 255 for value in clock)
            or clock[0] not in (0, 1, 2) or type(ticks) is not int or ticks < 0):
        raise ValueError("invalid run clock or tick count")
    state, hours, minutes, seconds, frames = clock
    if state != 1:
        return list(clock)  # inactive/finished fields must remain byte-exact
    if any(value >= 60 for value in (minutes, seconds, frames)):
        raise ValueError("active run clock is not normalized")
    total = ((hours * 60 + minutes) * 60 + seconds) * 60 + frames + ticks
    maximum = 256 * 60 * 60 * 60 - 1
    if total > maximum:
        return [2, 255, 59, 59, 59]
    hours, rest = divmod(total, 60 * 60 * 60)
    minutes, rest = divmod(rest, 60 * 60)
    seconds, frames = divmod(rest, 60)
    return [state, hours, minutes, seconds, frames]


def account_run_timer(published, saved, loaded, ticks, *, saved_enabled, loaded_enabled):
    """Only an exact publication and complete tick chain can explain a delta.

    A tick ledger records the clock BEFORE each active RunTimerTick call.
    Requiring each predecessor also detects corruption subsequently overwritten
    by another clock field or a timer reset. No broad timer-byte allowance.
    """
    problems = []
    expected = list(published)
    if not isinstance(ticks, list):
        ticks = []
        problems.append("active tick ledger is unavailable")
    try:
        advance_run_clock(expected, 0)
        if published != saved:
            problems.append("published clock differs from save-entry clock")
        if type(saved_enabled) is not bool or type(loaded_enabled) is not bool or saved_enabled != loaded_enabled:
            problems.append("timer enable changed or is unavailable")
        for tick in ticks:
            if not saved_enabled or tick["timer_enabled"] is not True or tick["clock"] != expected or expected[0] != 1:
                problems.append("active tick predecessor or enable does not match")
                break
            expected = advance_run_clock(expected, 1)
        if expected != loaded:
            problems.append("loaded clock is not explained by observed active ticks")
    except (ValueError, TypeError, KeyError) as error:
        problems.append(f"invalid timer evidence: {error}")
    return {"version": 1, "status": "invalid" if problems else "accounted",
            "published_clock": published, "saved_clock": saved, "loaded_clock": loaded,
            "expected_clock": expected, "active_ticks": len(ticks), "problems": problems}


def published_run_clock(h, sram):
    bank, address = h.symbols.get("sMainData")
    offset = bank * SRAM_BANK_SIZE + address - 0xa000 + h.address("wRunTimerState") - h.address("wMainDataStart")
    return list(sram[offset:offset + 5])


def account_saved_timer(h, saved, loaded, sram, ticks):
    clock_offset = h.address("wRunTimerState") - h.address("wMainDataStart")
    enable_offset = h.address("wStatusFlags6") - h.address("wMainDataStart")
    return account_run_timer(published_run_clock(h, sram),
        list(saved["main data"][clock_offset:clock_offset + 5]),
        list(loaded["main data"][clock_offset:clock_offset + 5]), ticks,
        saved_enabled=bool(saved["main data"][enable_offset] & 1),
        loaded_enabled=bool(loaded["main data"][enable_offset] & 1))


def save_now(h: RedRogueHarness, *, timer_observations=None) -> dict[str, bytes]:
    """Run SaveGameData; return the saved regions as they were when it began
    (call_routine lets the game run on after it returns, so reading WRAM
    afterwards would compare against bytes the save never wrote)."""
    image: dict[str, bytes] = {}
    copy_boundary = "SaveGameData.copyMain" if "SaveGameData.copyMain" in h.symbols._symbols else "CopyMainSaveData"

    def capture(_context) -> None:
        if not image:
            image.update(region_image(h))
            if timer_observations is not None:
                timer_observations.append(timer_observation(h, "SaveGameData.entry"))

    def copying(_context) -> None:
        if timer_observations is not None:
            timer_observations.append(timer_observation(h, copy_boundary))

    h.register_hook("SaveGameData", capture)
    h.register_hook(copy_boundary, copying)
    try:
        h.call_routine("SaveGameData", limit=60_000)
    finally:
        h.unregister_hook("SaveGameData", capture)
        h.unregister_hook(copy_boundary, copying)
    return image


class Reboot:
    """A fresh emulator on a cartridge RAM image: power on, let the main
    menu check the save, and (if it loads) CONTINUE into the overworld."""

    def __init__(self, sram: bytes, *, cgb_mode: bool = False):
        autoplay.ARTIFACTS.mkdir(parents=True, exist_ok=True)
        fd, path = tempfile.mkstemp(suffix=".sram", dir=autoplay.ARTIFACTS)
        os.close(fd)
        self.path = Path(path)
        self.path.write_bytes(sram)
        self.h = RedRogueHarness(autoplay.ROOT, autoplay.ARTIFACTS, ram_path=self.path,
                                 rom=autoplay.ROM, cgb_mode=cgb_mode)
        self.path.unlink()
        self.status: int | None = None
        self.loaded: dict[str, bytes] | None = None
        self.overworld = False
        self.timer_observations = []
        self.active_timer_ticks = []

    def load(self) -> None:
        h = self.h
        _, done = h.symbols.get("TryLoadSaveFile.done")
        active_ticks = {"count": 0}

        def timer_tick(_context) -> None:
            if h.read8("wRunTimerState") == 1:
                active_ticks["count"] += 1
                if self.status is None:
                    self.active_timer_ticks.append(timer_observation(h, "RunTimerTick.entry"))

        def checked(_context) -> None:
            if self.status is None:
                self.status = h.pyboy.register_file.A  # 2: loaded; 1: refused or none
                self.loaded = region_image(h)
                self.timer_observations.append({**timer_observation(h, "TryLoadSaveFile.done"),
                                                "active_run_timer_ticks": active_ticks["count"]})

        def polled(_context) -> None:
            self.overworld = True

        h.register_hook("TryLoadSaveFile.done", checked)
        h.register_hook("RunTimerTick", timer_tick)
        h.register_hook("JoypadOverworld", polled)
        for frame in range(BOOT_FRAMES + CONTINUE_FRAMES):
            h.tick(1)
            if self.overworld or (self.status is not None and self.status != 2):
                break
            if frame % 12 == 0:
                h.tap("a", 2)  # title, CONTINUE (first when a save exists), the info box

    def close(self) -> None:
        self.h.close()


def classify(h: RedRogueHarness, old: dict[str, bytes], new: dict[str, bytes],
             loaded: dict[str, bytes], *, timer_context=None) -> dict[str, str]:
    """Each region: new, old, unchanged or other, allowing expected changes.

    A region equal in both snapshots cannot establish a mixed checkpoint.
    """
    result = {}
    for name in new:
        def matches(image: dict[str, bytes]) -> bool:
            accounted = account_saved_timer(h, image, loaded, *timer_context) if timer_context is not None and name == "main data" else None
            if accounted is not None and accounted["status"] != "accounted":
                return False
            return not [d for d in differences(h, {name: image[name]}, {name: loaded[name]}, only=name,
                                               accounted_timer=accounted)]
        is_new, is_old = matches(new), matches(old)
        result[name] = ("unchanged" if is_new and is_old else "new" if is_new
                        else "old" if is_old else "other")
    return result


def checkpoint_kind(regions: dict[str, str]) -> str:
    kinds = set(regions.values()) - {"unchanged"}
    return "unchanged" if not kinds else kinds.pop() if len(kinds) == 1 else "mixed"


def round_trip(h: RedRogueHarness, snapshot, driver: autoplay_branch.BranchDriver | None,
               key: str, *, cgb_mode: bool = False) -> dict[str, object]:
    h.load_state(io.BytesIO(snapshot.state))
    if not settle(h):
        return {"snapshot": snapshot.name, "status": None, "overworld": False,
                "skipped": "no idle overworld frame to save at"}
    timer_save = []
    saved = save_now(h, timer_observations=timer_save)
    sram = sram_image(h)
    boot = Reboot(sram, cgb_mode=cgb_mode)
    try:
        boot.load()
        result = {"snapshot": snapshot.name, "status": boot.status, "overworld": boot.overworld}
        errors = h.hook_errors + boot.h.hook_errors
        result["detectors"] = {"run_timer": {"enabled": True, "available": True,
                                              "status": "error" if errors else "ok", "errors": errors}}
        if errors:
            result["problem"] = "save/load observer hook failed"
        result["run_timer_boundaries"] = {"save": timer_save,
                                          "published_sram_clock": published_run_clock(h, sram),
                                          "load": boot.timer_observations,
                                          "comparison_policy": "unchanged; raw timing evidence only"}
        if boot.status != 2:
            result["problem"] = "a fresh save did not load"
            return result
        if not boot.overworld:
            result["problem"] = "loaded save did not return to overworld control"
        accounting = account_saved_timer(h, saved, boot.loaded, sram, boot.active_timer_ticks)
        result["run_timer_comparison"] = accounting
        result["run_timer_boundaries"].update(comparison_policy="exact publication and active tick chain v1",
                                               active_ticks=boot.active_timer_ticks)
        result["raw_differences"] = differences(h, saved, boot.loaded)
        result["differences"] = differences(h, saved, boot.loaded, accounted_timer=accounting)
        if accounting["status"] != "accounted":
            result["problem"] = "run timer publication or tick accounting failed"
        if boot.overworld and driver is not None:
            state = io.BytesIO()
            boot.h.save_state(state)
            play = driver.run(state.getvalue(), key, AFTER_LOAD_FRAMES)
            if play["outcome"] != "ok" or play["anomalies"]:
                result["after_load"] = {k: play[k] for k in ("outcome", "detail", "anomalies")}
        return result
    finally:
        boot.close()


def power_cuts(h: RedRogueHarness, older, newer, *, cgb_mode: bool = False) -> list[dict[str, object]]:
    """Save at `older`, then save again at `newer` and cut power at each step."""
    h.load_state(io.BytesIO(older.state))
    if not settle(h):
        return []
    old = save_now(h)
    old_sram = sram_image(h)
    h.load_state(io.BytesIO(newer.state))
    if not settle(h):
        return []
    write_sram(h, old_sram)
    cuts: list[tuple[str, bytes]] = []
    counts: dict[str, int] = {}

    def cut(name: str):
        def capture(_context) -> None:
            counts[name] = counts.get(name, 0) + 1
            cuts.append((f"{name} #{counts[name]}", sram_image(h)))
        return capture

    labels = ("SaveCurrentBoxData", "SavePartyAndDexData", "CopyMainSaveData",
              "CopyCurrentBoxSaveData", "CopyPartySaveData", "FinishSaveData", "CalcCheckSum",
              "SaveGameData.copyName", "SaveGameData.copyMain", "SaveGameData.copySprites",
              "SaveGameData.copyParty", "SaveGameData.copyBox", "SaveGameData.copyMap",
              "SaveGameData.commit", "StoreSaveChecksum")
    hooks = [(label, cut(label)) for label in labels if label in h.symbols._symbols]
    for label, callback in hooks:
        h.register_hook(label, callback)
    try:
        new = save_now(h)  # capture at actual entry, after call_routine parks safely
    finally:
        for label, callback in hooks:
            h.unregister_hook(label, callback)
    cuts.append(("after the save", sram_image(h)))
    results = []
    for name, sram in cuts:
        boot = Reboot(sram, cgb_mode=cgb_mode)
        try:
            boot.load()
            if boot.status != 2:
                outcome, regions = "refused", {}
            elif h.hook_errors or boot.h.hook_errors:
                outcome, regions = "detector_error", {}
            else:
                regions = classify(h, old, new, boot.loaded, timer_context=(sram, boot.active_timer_ticks))
                outcome = checkpoint_kind(regions)
            results.append({"cut": f"{older.name}->{newer.name} at {name}", "loads": outcome,
                            "regions": regions, "active_run_timer_ticks": len(boot.active_timer_ticks),
                            "detector_errors": h.hook_errors + boot.h.hook_errors})
        finally:
            boot.close()
    return results


def run_save_checks(seed: int, snapshots: list, *, play_after: bool = True,
                    cgb_mode: bool = False) -> dict[str, object]:
    lobbies = [s for s in snapshots if s.kind == "lobby"]
    save_snapshots = [s for s in snapshots if s.kind in ("lobby", "save_overworld")]
    findings, trips, cut_results = [], [], []
    h = RedRogueHarness(autoplay.ROOT, autoplay.ARTIFACTS, rom=autoplay.ROM,
                        cgb_mode=cgb_mode)
    driver_harness = (RedRogueHarness(autoplay.ROOT, autoplay.ARTIFACTS, rom=autoplay.ROM,
                                     cgb_mode=cgb_mode) if play_after else None)
    try:
        driver = autoplay_branch.BranchDriver(driver_harness) if driver_harness else None
        retained = None
        for snapshot in save_snapshots:
            trip = round_trip(h, snapshot, driver, f"reload/{seed}/{snapshot.name}",
                              cgb_mode=cgb_mode)
            if snapshot.kind == "save_overworld":
                if retained is None:
                    retained = autoplay.ARTIFACTS / f"{autoplay.stem(seed)}_save-{time.time_ns()}"
                    retained.mkdir(parents=True, exist_ok=False)
                path = retained / f"{snapshot.name}.state"
                path.write_bytes(snapshot.state)
                trip["source_snapshot"] = {"kind": snapshot.kind, "frame": snapshot.frame, "info": snapshot.info,
                    "state": str(path), "sha256": hashlib.sha256(snapshot.state).hexdigest(),
                    "rom_sha256": h.rom_sha256, "sym_sha256": h.sym_sha256}
                (retained / f"{snapshot.name}.json").write_text(json.dumps(trip, indent=2) + "\n")
            trips.append(trip)
            if trip.get("problem") or trip.get("differences") or trip.get("after_load"):
                findings.append({"check": "round_trip", **trip})
        for older, newer in zip(lobbies, lobbies[1:]):
            # Keep interruptions separate from ordinary round-trip findings.
            # Release acceptance must inspect mixed/other outcomes explicitly;
            # a successful command alone does not certify power-cut safety.
            cut_results.extend(power_cuts(h, older, newer, cgb_mode=cgb_mode))
    finally:
        h.close()
        if driver_harness is not None:
            driver_harness.close()
    return {"round_trips": trips, "power_cuts": cut_results, "findings": findings}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Save, reload and power-cut checks on one seed.")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--stages", type=int, default=6)
    parser.add_argument("--new-game", action="store_true")
    parser.add_argument("--cgb", action="store_true", help="run the emulator in CGB mode")
    args = parser.parse_args(argv)
    data = autoplay.play(args.seed, stages=args.stages, max_frames=1_000_000, new_game=args.new_game,
                         save_checks=True, cgb_mode=args.cgb)
    checks = data["save_checks"]
    print(json.dumps({k: checks[k] for k in ("findings",)}, indent=1))
    for cut in checks["power_cuts"]:
        print(f"  {cut['cut']}: loads {cut['loads']} {cut['regions'] if cut['loads'] == 'mixed' else ''}")
    return 1 if checks["findings"] else 0


if __name__ == "__main__":
    sys.exit(main())
