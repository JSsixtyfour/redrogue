"""Measure the real menu save, with interrupts, before adding checkpoints.

Runs the existing START > SAVE lifecycle. Only cursor/option fixture bytes
are set; SaveGameData is never injected into a parked VBlank. The counter is
calibrated against 60 display frames separately at each hardware speed.
"""
from __future__ import annotations

import hashlib
import argparse
import io
import json
import re
import subprocess
from pathlib import Path

from harness import RedRogueHarness
from save_reload import settle

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
FRAME_MS = 70224 / 4194304 * 1000


def measure(mode: str, trials: int = 3, phase_step: int = 3) -> dict:
    h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=mode != "DMG")
    try:
        h.boot_to_lobby()
        if mode == "CGB single":
            h.write8("wOptions2", h.read8("wOptions2") & 0x7f)
        h.tick(30)  # let the ordinary overworld apply the option
        assert settle(h), "lobby did not settle"
        start = h.cycle_count()
        h.tick(60)
        units_per_frame = (h.cycle_count() - start) / 60
        baseline = io.BytesIO()
        h.save_state(baseline)
        samples = []
        active = {}
        returns = set()

        def returned(_):
            if not active or h.pyboy.register_file.SP != active["sp"] + 2:
                return
            elapsed = h.cycle_count() - active["cycles"]
            samples.append({"counter_units": elapsed,
                            "display_frames": elapsed / units_per_frame,
                            "milliseconds": elapsed / units_per_frame * FRAME_MS,
                            "frame_boundaries": h.pyboy.frame_count - active["frame"],
                            "key1": active["key1"],
                            "interrupt_enable": active["ie"],
                            "vblanks": active["vblanks"],
                            "checksum_publications": active["publications"] if has_commit_seam else None,
                            "checksum_passes": active["checksums"]})
            active.clear()

        def entered(_):
            assert not active, "nested full save"
            sp = h.pyboy.register_file.SP
            address = h.pyboy.memory[sp] | h.pyboy.memory[sp + 1] << 8
            bank = h.read8("hLoadedROMBank") if address >= 0x4000 else 0
            key = (bank, address)
            if key not in returns:
                h._register_at(key, returned)
                returns.add(key)
            active.update(cycles=h.cycle_count(), frame=h.pyboy.frame_count,
                          sp=sp, key1=h.pyboy.memory[0xff4d] if mode != "DMG" else None,
                          ie=h.pyboy.memory[0xffff], checksums=0, vblanks=0, publications=0)

        def checksum(_):
            if active:
                active["checksums"] += 1

        def vblank(_):
            if active:
                active["vblanks"] += 1

        def commit(_):
            if active:
                active["publications"] += 1

        h.register_hook("SaveGameData", entered)
        h.register_hook("CalcCheckSum", checksum)
        h.register_hook("VBlank", vblank)
        has_commit_seam = "StoreSaveChecksum" in h.symbols._symbols
        if has_commit_seam:
            h.register_hook("StoreSaveChecksum", commit)
        for trial in range(trials):
            h.load_state(io.BytesIO(baseline.getvalue()))
            h.tick(trial * phase_step)
            # Debug 2 has a Pokedex, so SAVE is row 4.
            h.write8("wBattleAndStartSavedMenuItem", 4)
            h.tap("start", 6)
            for _ in range(350):
                h.tap("a", 3)
                if len(samples) > trial:
                    break
            assert len(samples) == trial + 1, "menu save did not complete"
            assert samples[-1]["vblanks"] > 0, "measurement did not service VBlank"
            expected_speed = 0x80 if mode == "CGB double" else 0
            if mode != "DMG":
                assert samples[-1]["key1"] & 0x80 == expected_speed
            assert not h.hook_errors, h.hook_errors
        return {"mode": mode, "counter_units_per_display_frame": units_per_frame,
                "fixture": "settled Debug 2 lobby; real START > SAVE input", "samples": samples}
    finally:
        h.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ARTIFACTS / "save_profile_current.json")
    parser.add_argument("--trials", type=int, default=3)
    parser.add_argument("--phase-step", type=int, default=3,
                        help="idle display frames between independent starting phases")
    args = parser.parse_args()
    if args.trials < 1 or args.phase_step < 0:
        parser.error("trials must be positive and phase-step must be nonnegative")
    identity = {name: {suffix: hashlib.sha256((ROOT / f"{name}.{suffix}").read_bytes()).hexdigest()
                       for suffix in ("gbc", "sym", "map")}
                for name in ("pokered", "pokeblue", "pokeblue_debug")}
    storage = {}
    for name in identity:
        map_text = (ROOT / f"{name}.map").read_text()
        banks = {}
        for bank, body in re.findall(r"SRAM bank #(\d+):\n(.*?)(?=\n\w|\Z)", map_text, re.S):
            banks[bank] = int(re.search(r"TOTAL EMPTY: \$([0-9a-f]+)", body)[1], 16)
        assert len(banks) == 4, "expected all SRAM bank measurements"
        syms = {}
        for bank, addr, label in re.findall(r"^(\w+):(\w+) (s\w+)$", (ROOT / f"{name}.sym").read_text(), re.M):
            syms[label] = (int(bank, 16), int(addr, 16))
        payload = syms["sGameDataEnd"][1] - syms["sGameData"][1]
        storage[name] = {"unallocated_by_bank": banks, "total_unallocated": sum(banks.values()),
                         "main_payload_bytes": payload,
                         "saved_box_bytes": syms["sBox2"][1] - syms["sBox1"][1],
                         "x7_reserved_bytes": 4 * 256}
    result = {"identity": identity, "source_revision": subprocess.check_output(
                  ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "storage": storage, "measurements": []}
    for mode in ("DMG", "CGB single", "CGB double"):
        row = measure(mode, args.trials, args.phase_step)
        result["measurements"].append(row)
        print(json.dumps(row), flush=True)
    path = args.output
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, indent=2) + "\n")
    print(path)


if __name__ == "__main__":
    main()
