"""Reproducible lobby CPU profiling, without changing ROM timing or RAM layout.

Run through WSL, e.g. python3 tools/pyboy_smoke/profile_lobby.py --output builds/...
Entry/real caller-return hooks measure inclusive cycles. Mainline samples also
report cycles excluding intervening VBlank interrupts. Nested routines overlap:
do not add their totals. Hooks execute on the host, adding no emulated cycles.
--light retains only OAM/update/VBlank hooks to check instrumentation effects.
Fixtures change follower options at map preparation, and checkpoint eligibility
at a fresh map-script boundary. Navigation and samples use actual joypad input.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
LABELS = ("VBlank", "PrepareOAMData", "_UpdateSprites", "UpdateNPCSprite",
          "CheckSpriteAvailability", "IsObjectHidden", "UpdateSpriteImage",
          "GetTileSpriteStandsOn", "GetTileSpriteStandsOn_roundUP", "FollowerUpdate")


def summary(values):
    ordered = sorted(values)
    return {"calls": len(values), "mean": round(sum(values) / len(values), 2),
            "p95": ordered[math.ceil(len(values) * .95) - 1], "max": max(values)} if values else {}


class Timings:
    def __init__(self, h, light):
        self.h = h
        self.enabled = False
        self.pending = defaultdict(list)
        self.returns = set()
        self.records = []
        self.interrupt_cycles = 0
        self.starts = []
        for name in LABELS[:3] if light else LABELS:
            h.register_hook(name, lambda _, name=name: self.enter(name))

    def enter(self, name):
        h = self.h
        sp = h.pyboy.register_file.SP
        addr = h.pyboy.memory[sp] | h.pyboy.memory[sp + 1] << 8
        bank = 0 if addr < 0x4000 else h.read8("hLoadedROMBank")
        key = bank, addr
        self.pending[key].append((name, sp + 2, h.cycle_count(), self.interrupt_cycles, self.enabled))
        if name == "_UpdateSprites" and self.enabled:
            self.starts.append(h.cycle_count())
        if key not in self.returns:
            self.returns.add(key)
            h._register_at(key, lambda _, key=key: self.leave(key))

    def leave(self, key):
        h = self.h
        stack = self.pending[key]
        # Tail calls share caller return sites; SP identifies the actual return.
        while stack and stack[-1][1] == h.pyboy.register_file.SP:
            name, _, start, interrupt_start, enabled = stack.pop()
            end = h.cycle_count()
            elapsed = end - start
            own = elapsed if name == "VBlank" else elapsed - (self.interrupt_cycles - interrupt_start)
            if name == "VBlank":
                self.interrupt_cycles += elapsed
            if enabled and self.enabled:
                self.records.append((name, elapsed, own))

    def begin(self):
        self.records.clear()
        self.starts.clear()
        self.enabled = True

    def finish(self):
        self.enabled = False
        return {name: {"inclusive": summary([r[1] for r in self.records if r[0] == name]),
                       "without_vblank": summary([r[2] for r in self.records if r[0] == name])}
                for name in LABELS if any(r[0] == name for r in self.records)} | {
                    "update_start_intervals": summary([b-a for a,b in zip(self.starts,self.starts[1:])])}


def position(h):
    return h.read8("wXCoord"), h.read8("wYCoord")


def step(h, direction):
    before = position(h)
    start = h.pyboy.frame_count
    h.pyboy.button_press(direction)
    for _ in range(120):
        h.tick()
        if position(h) != before:
            break
    else:
        h.pyboy.button_release(direction)
        raise AssertionError(f"blocked {direction} at {before}")
    h.pyboy.button_release(direction)
    h.wait_until(lambda: h.read8("wWalkCounter") == 0, "complete tile movement", 120)
    return h.pyboy.frame_count - start


def snapshot(h):
    return {"xy": position(h), "options2": h.read8("wOptions2"),
            "battle_count": h.read8("wBattleCount"),
            "badges": h.read8("wObtainedBadges"),
            "source_map": h.read8("wWarpedFromWhichMap"),
            "font_loaded": h.read8("wFontLoaded"),
            "sprites": h.read_bytes("wSpriteStateData1", 256),
            "sprite_state2": h.read_bytes("wSpriteStateData2", 256),
            "toggle_flags": h.read_bytes("wToggleableObjectFlags", 32)}


def sample(h, timing, name, repeats):
    metadata = snapshot(h)
    # Random is called directly by VBlank just after PrepareOAMData returns.
    # Sample there, rather than at a frame boundary partway through OAM writes.
    oam_frames = []
    vblank_start, vblank_end = h.address("VBlank"), h.address("DelayFrame")

    def observe_oam(_):
        sp = h.pyboy.register_file.SP
        caller = h.pyboy.memory[sp] | h.pyboy.memory[sp+1] << 8
        if not vblank_start <= caller < vblank_end:
            return
        oam = h.read_bytes("wShadowOAM", 160)
        lines = [0] * 144
        entries = 0
        for index in range(0, 160, 4):
            y, x = oam[index:index+2]
            if not 0 < x < 168:
                continue
            top = y - 16
            rows = range(max(0, top), min(144, top+8))
            if not rows:
                continue
            entries += 1
            for row in rows:
                lines[row] += 1
        slots = [slot for slot in range(16)
                 if h.read8("wSpriteStateData1", slot*16)
                 and h.read8("wSpriteStateData1", slot*16+2) != 255]
        oam_frames.append((entries, max(lines), slots))

    def oam_summary():
        peak = max(oam_frames, key=lambda row: len(row[2])) if oam_frames else None
        return {"visible_entries": summary([row[0] for row in oam_frames]),
                "entries_on_busiest_scanline": summary([row[1] for row in oam_frames]),
                "visible_slots": summary([len(row[2]) for row in oam_frames]),
                "slots_at_peak": peak[2] if peak else []}

    h.register_hook("Random", observe_oam)
    timing.begin()
    h.tick(120)
    idle = timing.finish()
    idle_oam = oam_summary()
    oam_frames.clear()
    timing.begin()
    frames = []
    occupancy = []
    for _ in range(repeats):
        frames.append(step(h, "right"))
        frames.append(step(h, "left"))
        occupancy.append(sum(0 < h.pyboy.memory[h.address("wShadowOAM") + i] < 160
                             for i in range(0, 160, 4)))
    walking = timing.finish()
    walking_oam = oam_summary()
    h.unregister_hook("Random", observe_oam)
    assert position(h) == tuple(metadata["xy"])
    assert not h.hook_errors, h.hook_errors
    return {"area": name, "fixture": metadata, "idle": idle, "walking": walking,
            "frames_per_tile": summary(frames), "frames_per_tile_all": frames,
            "oam_entries_at_segment_end": occupancy,
            "idle_oam": idle_oam, "walking_oam": walking_oam}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--rom-root", type=Path, default=ROOT,
                        help="directory containing the matching ROM/sym pair")
    parser.add_argument("--light", action="store_true")
    parser.add_argument("--cgb", action="store_true")
    parser.add_argument("--repeats", type=int, default=12)
    parser.add_argument("--single", action="store_true", help="first visibility/follower fixture only")
    parser.add_argument("--crowded", action="store_true", help="also walk past the central counter with all services offered")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    maps = parse_map_constants(ROOT / "constants/map_constants.asm")
    for checkpoint, follower in [(False, False)] if args.single else [(c,f) for c in (False,True) for f in (False,True)]:
        h = RedRogueHarness(args.rom_root, args.output, cgb_mode=args.cgb)
        try:
            def options(_):
                value = h.read8("wOptions2")
                h.write8("wOptions2", value & ~8 if follower else value | 8)
            h.register_hook("FollowerPrepareMap", options)
            h.boot_to_lobby()
            h.tick(120)
            h.wait_until(lambda: not (h.read8("wFontLoaded") & 1), "lobby text closed", 600)
            if args.crowded:
                toggles = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
                def all_services(_):
                    for name in ("PSYCHIC","WITCH","POKESALESMAN","TRADENERD","MOVETUTOR","RENTAL_OFFICIAL"):
                        bit = toggles["TOGGLE_PC_" + name]
                        address = h.address("wToggleableObjectFlags") + bit // 8
                        h.pyboy.memory[address] &= ~(1 << (bit % 8))
                h.register_hook("IndigoPlateauLobby_Script", all_services)
                h.tick(60)
            if checkpoint:
                def eligibility(_):
                    h.write8("wBattleCount", 29)
                    h.write8("wObtainedBadges", 7)
                    h.write8("wWarpedFromWhichMap", maps["REWARD_ROOM"])
                h.register_hook("IndigoPlateauLobby_Script", eligibility)
                h.tick(60)
            timing = Timings(h, args.light)
            stem = f"{'checkpoint' if checkpoint else 'normal'}_follower{int(follower)}"
            # Entrance (7,10); tutor (2,3); counter front (11,7).
            step(h, "up")
            routes = [("entrance", []),
                                ("tutor", [("up",3),("left",5),("up",4)]),
                                ("counter", [("down",4),("right",9)])]
            if args.crowded:
                routes.append(("crowded_counter", [("left",3)]))
            for name, route in routes:
                for direction, count in route:
                    for _ in range(count):
                        step(h, direction)
                state_path = args.output / f"{stem}_{name}.state"
                with state_path.open("wb") as state:
                    h.save_state(state)
                h.tick(1, render=True)
                h.pyboy.screen.image.save(args.output / f"{stem}_{name}.png")
                result = sample(h, timing, name, args.repeats)
                result.update(checkpoint=checkpoint, follower=follower)
                results.append(result)
                print(stem, name, result["fixture"]["xy"], result["frames_per_tile"], flush=True)
        finally:
            h.close()
    report = {"rom_sha256": hashlib.sha256((args.rom_root / "pokeblue_debug.gbc").read_bytes()).hexdigest(),
              "mode": "CGB" if args.cgb else "DMG", "light": args.light,
              "repeats": args.repeats, "crowded": args.crowded, "results": results}
    (args.output / "profile.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
