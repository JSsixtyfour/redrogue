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
import io
import json
import os
import sys
import tempfile
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
                only: str | None = None) -> list[dict[str, object]]:
    """Bytes that came back different, named by the nearest WRAM/HRAM label."""
    found = []
    for name, first, _length in region_spans(h):
        if only is not None and name != only:
            continue
        for offset, (was, now) in enumerate(zip(saved[name], loaded[name])):
            if was == now:
                continue
            address = first + offset
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
            if len(polled) >= 2 and not h.read8("hJoyIgnore") and not h.read8("hSimulatedJoypadStatesIndex"):
                return True
        return False
    finally:
        h.unregister_hook("JoypadOverworld", poll)


def save_now(h: RedRogueHarness) -> dict[str, bytes]:
    """Run SaveGameData; return the saved regions as they were when it began
    (call_routine lets the game run on after it returns, so reading WRAM
    afterwards would compare against bytes the save never wrote)."""
    image: dict[str, bytes] = {}

    def capture(_context) -> None:
        if not image:
            image.update(region_image(h))

    h.register_hook("SaveGameData", capture)
    try:
        h.call_routine("SaveGameData", limit=60_000)
    finally:
        h.unregister_hook("SaveGameData", capture)
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

    def load(self) -> None:
        h = self.h
        _, done = h.symbols.get("TryLoadSaveFile.done")

        def checked(_context) -> None:
            if self.status is None:
                self.status = h.pyboy.register_file.A  # 2: loaded; 1: refused or none
                self.loaded = region_image(h)

        def polled(_context) -> None:
            self.overworld = True

        h.register_hook("TryLoadSaveFile.done", checked)
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
             loaded: dict[str, bytes]) -> dict[str, str]:
    """Each region: new, old, unchanged or other, allowing expected changes.

    A region equal in both snapshots cannot establish a mixed checkpoint.
    """
    result = {}
    for name in new:
        def matches(image: dict[str, bytes]) -> bool:
            return not [d for d in differences(h, {name: image[name]}, {name: loaded[name]}, only=name)]
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
    saved = save_now(h)
    sram = sram_image(h)
    boot = Reboot(sram, cgb_mode=cgb_mode)
    try:
        boot.load()
        result = {"snapshot": snapshot.name, "status": boot.status, "overworld": boot.overworld}
        if boot.status != 2:
            result["problem"] = "a fresh save did not load"
            return result
        result["differences"] = differences(h, saved, boot.loaded)
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
    new = region_image(h)  # the same moment save_now captures: nothing runs in between
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
        save_now(h)
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
            else:
                regions = classify(h, old, new, boot.loaded)
                outcome = checkpoint_kind(regions)
            results.append({"cut": f"{older.name}->{newer.name} at {name}", "loads": outcome,
                            "regions": regions})
        finally:
            boot.close()
    return results


def run_save_checks(seed: int, snapshots: list, *, play_after: bool = True,
                    cgb_mode: bool = False) -> dict[str, object]:
    lobbies = [s for s in snapshots if s.kind == "lobby"]
    findings, trips, cut_results = [], [], []
    h = RedRogueHarness(autoplay.ROOT, autoplay.ARTIFACTS, rom=autoplay.ROM,
                        cgb_mode=cgb_mode)
    driver_harness = (RedRogueHarness(autoplay.ROOT, autoplay.ARTIFACTS, rom=autoplay.ROM,
                                     cgb_mode=cgb_mode) if play_after else None)
    try:
        driver = autoplay_branch.BranchDriver(driver_harness) if driver_harness else None
        for snapshot in lobbies:
            trip = round_trip(h, snapshot, driver, f"reload/{seed}/{snapshot.name}",
                              cgb_mode=cgb_mode)
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
