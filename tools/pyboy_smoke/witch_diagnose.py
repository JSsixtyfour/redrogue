"""Replay one campaign seed on the frozen ROM with a watchdog and a flight recorder.

    python3 witch_diagnose.py <rom> <seed> <evidence-dir> [--stages N] [--max-frames N]

Prints where it ended: map, position, mode, on-screen rows, last events, last inputs,
last witch offer and settlement. If the emulator stops returning from tick(), the
watchdog thread dumps PC, SP, bank and the Python stack, then exits, so a hang gets
a location rather than a kill.
"""
from __future__ import annotations

import argparse
import faulthandler
import os
import sys
import threading
import time
from pathlib import Path

import autoplay
import witch_autoplay as wa


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("rom")
    parser.add_argument("seed", type=int)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--stages", type=int, default=12)
    parser.add_argument("--max-frames", type=int, default=250_000)
    parser.add_argument("--stall-frames", type=int, default=20_000)
    parser.add_argument("--hang-seconds", type=float, default=60)
    parser.add_argument("--strong", action="store_true")
    args = parser.parse_args()
    autoplay.ROM = args.rom
    h = wa.harness(args.rom, args.evidence)
    if args.rom == autoplay.DEBUG_ROM:
        autoplay.boot(h, args.seed, 1, "HARD")
    else:
        autoplay.boot_new_game(h, args.seed, "HARD")
    options = {"player": "strong"} if args.strong else {"offer_policy": "random"}
    agent = wa.CampaignAgent(h, seed=args.seed, stall_frames=args.stall_frames,
                             battle_policy="type_switcher", **options)
    beat = {"time": time.monotonic(), "frame": 0}
    original_tick = h.tick  # PyBoy's own tick is read-only; every caller here goes through this

    def tick(*a, **k):
        beat["time"], beat["frame"] = time.monotonic(), h.pyboy.frame_count
        return original_tick(*a, **k)

    h.tick = tick

    def describe() -> None:
        registers = h.pyboy.register_file
        pc, sp = registers.PC, registers.SP
        bank = h.read8("hLoadedROMBank")
        where = h.symbols.nearest(0 if pc < 0x4000 else bank, pc)
        print(f"pc={bank:02x}:{pc:04x} {where} sp={sp:04x} ly={h.pyboy.memory[0xff44]}", flush=True)
        stack = [h.pyboy.memory[sp + i] | h.pyboy.memory[sp + i + 1] << 8 for i in range(0, 24, 2)]
        print("stack " + " ".join(f"{word:04x}" for word in stack), flush=True)
        print("map", agent.map_name(h.read8("hCurMap")), "pos", agent.position(), "inBattle", h.read8("hIsInBattle"),
              "count", h.read8("wBattleCount"), "challenge", h.read8("wWitchChallenge"),
              "accepted", bool(h.read8("wRogueFlagsBitfield") & wa.ACCEPTED), flush=True)
        for y, row in enumerate(wa.screen_rows(h)):
            print(f"{y:02d} {row}", flush=True)

    def watchdog() -> None:
        while True:
            time.sleep(5)
            if time.monotonic() - beat["time"] > args.hang_seconds:
                print(f"\nHANG: tick() has not returned for {args.hang_seconds}s, last frame {beat['frame']}", flush=True)
                describe()
                # Frozen PC and SP mean a hook wedge or a stopped CPU; moving ones, a game loop.
                for _ in range(6):
                    registers = h.pyboy.register_file
                    print(f"sample pc={registers.PC:04x} sp={registers.SP:04x} a={registers.A:02x} "
                          f"hl={registers.HL:04x} ly={h.pyboy.memory[0xff44]} lcdc={h.pyboy.memory[0xff40]:02x} "
                          f"ie={h.pyboy.memory[0xffff]:02x} if={h.pyboy.memory[0xff0f]:02x}", flush=True)
                    time.sleep(0.7)
                print("cur script", {label: h.read8(label) for label in (
                    "wCurMapScript", "wGameCornerCurScript", "wEngagedTrainerClass", "hSpriteIndex")
                    if label in h.symbols._symbols}, flush=True)
                table_bank, table = h.symbols.get("GameCorner_ScriptPointers")
                print("table", [f"{h.pyboy.memory[table_bank, table + i * 2] | h.pyboy.memory[table_bank, table + i * 2 + 1] << 8:04x}"
                                for i in range(12)], flush=True)
                pc = h.pyboy.register_file.PC
                print("rom at pc", " ".join(f"{h.pyboy.memory[0, pc + i]:02x}" for i in range(16)), flush=True)
                hooked = sorted(key for key in h._hook_callbacks if key[1] < 0x4000 and abs(key[1] - pc) < 64)
                print("hooks near pc", [(f"{b:02x}:{a:04x}", h.symbols.nearest(b, a)) for b, a in hooked], flush=True)
                print("events", agent.report.events[-8:], flush=True)
                print("inputs", agent.report.inputs[-15:], flush=True)
                faulthandler.dump_traceback()
                os._exit(3)

    threading.Thread(target=watchdog, daemon=True).start()
    try:
        agent.run(runs=1, stages=args.stages, max_frames=args.max_frames)
    finally:
        print("outcome", agent.report.outcome, agent.report.detail, "stages", agent.report.stages_cleared,
              "frames", agent.report.frames, flush=True)
        describe()
        print("mode", agent.mode(), "goal", agent.menu_goal, "plan", agent.plan, "errand", agent.errand,
              "caller", agent.last_menu_caller, flush=True)
        print("transcript", agent.transcript[-14:], flush=True)
        print("events", agent.report.events[-10:], flush=True)
        print("inputs", agent.report.inputs[-30:], flush=True)
        print("offers", agent.offers[-3:], flush=True)
        print("anomalies", agent.checks.anomalies[-5:], flush=True)
        image = args.evidence / "diagnose" / f"{args.rom}_{args.seed}.png"
        image.parent.mkdir(parents=True, exist_ok=True)
        h.pyboy.screen.image.save(image)
        print("screen", image, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
