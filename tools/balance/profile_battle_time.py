"""Where does a battle's time go? Frames attributed to the routine that waited.

Opt-in measurement, NOT part of make smoke (plan A1, BALANCE_PHASE5_PLAN.md).
It reuses calibrate_battle_time.py's fixture and player driver, and adds one
hook: every DelayFrame (the routine nearly every wait in the game ends in) is
charged to its nearest meaningful caller, found by walking the stack past thin
wrappers such as DelayFrames and Delay3. That is an attribution of waited
frames, not VBlank PC sampling, which only shows where each frame happens to
end (see the "VBlank PC sampling is not a profile" note).

Frames not spent inside DelayFrame are reported as "computation / other".

Usage (WSL, needs PyBoy):
    python3 tools/balance/profile_battle_time.py
    python3 tools/balance/profile_battle_time.py --round 5 --mons 3 --gap 6 --top 25
"""

from __future__ import annotations

import argparse
import random
import sys
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))
sys.path.insert(0, str(REPO_ROOT / "tools" / "balance"))

from harness import RedRogueHarness  # noqa: E402
from run_ai_benchmark import choose_player_move, choose_player_slot, parse_move_powers, prepare_party_driver  # noqa: E402
from source_constants import parse_trainer_constants  # noqa: E402
import calibrate_battle_time as cal  # noqa: E402
import model  # noqa: E402
import parse  # noqa: E402

WRAPPERS = {"DelayFrames", "Delay3", "DelayFrame"}
BIT_BATTLE_ANIMATION = 7     # wOptions: set = battle animations OFF
TEXT_DELAY_MASK = 0b111      # wOptions bits 0-2; 0 = instant
BATTLE_SPEED_MASK = 0b110    # wOptions3 bits 1-2 (constants/ram_constants.asm)


class Symbols:
    def __init__(self, path: Path):
        self.by_bank: dict[int, list[tuple[int, str]]] = {}
        for line in path.read_text().splitlines():
            parts = line.split()
            if len(parts) != 2 or ":" not in parts[0]:
                continue
            bank, addr = (int(x, 16) for x in parts[0].split(":"))
            if addr >= 0x8000:
                continue
            self.by_bank.setdefault(bank, []).append((addr, parts[1]))
        for v in self.by_bank.values():
            v.sort()

    def name(self, bank: int, addr: int) -> str | None:
        table = self.by_bank.get(0 if addr < 0x4000 else bank)
        if not table:
            return None
        lo, hi = 0, len(table) - 1
        best = None
        while lo <= hi:
            mid = (lo + hi) // 2
            if table[mid][0] <= addr:
                best = table[mid][1]
                lo = mid + 1
            else:
                hi = mid - 1
        return best.split(".")[0] if best else None


def profile(g, player, enemy, ai_tier, powers, trainer_class, options_fn, syms):
    h = RedRogueHarness(REPO_ROOT, cal.ARTIFACTS)
    waits: Counter = Counter()
    busy: Counter = Counter()
    try:
        def keep_learnset_moves() -> None:
            enemy_side = h.read8("wMonDataLocation") & 0x0F
            count = h.read8("wEnemyPartyCount" if enemy_side else "wPartyCount")
            label = "wEnemyMon1Moves" if enemy_side else "wPartyMon1Moves"
            moves = h.read_bytes(label, 4, offset=(count - 1) * cal.PARTYMON_STRUCT_LENGTH)
            for i, mv in enumerate(moves):
                h.write8("wBuffer", mv, 2 + i)

        h.hook_flag("DebugFight2Setup.gotSpecParty", action=keep_learnset_moves)
        h.register_hook("MainInBattleLoop.noLinkBattle",
                        lambda _c: h.write8("wTestBattlePlayerSelectedMove",
                                            choose_player_move(h, "best_power", powers)))
        h.hook_flag("DisplayBattleMenu", action=lambda: h.write8("wBattleAndStartSavedMenuItem", 0))
        h.hook_flag("MoveSelectionMenu",
                    action=lambda: h.write8("wPlayerMoveListIndex",
                                            choose_player_slot(h, "best_power", powers)[0]))
        turns = h.hook_turn_telemetry()
        party_inputs, party_modes, _ = prepare_party_driver(h)
        victories, defeats = h.hook_flag("TrainerBattleVictory"), h.hook_flag("HandlePlayerBlackOut")
        state = {"on": False}

        def on_delay_frame(_ctx) -> None:
            if not state["on"]:
                return
            rf = h.pyboy.register_file
            bank = h.read8("hLoadedROMBank")
            caller = None
            sp = rf.SP
            for depth in range(8):
                ret = h.pyboy.memory[sp + 2 * depth] | (h.pyboy.memory[sp + 2 * depth + 1] << 8)
                if ret >= 0x8000:
                    continue
                name = syms.name(bank, ret)
                if name and name not in WRAPPERS:
                    caller = name
                    break
            waits[caller or "?"] += 1

        h.register_hook("DelayFrame", on_delay_frame)

        halt_lo = h.address("DelayFrame.halt")
        halt_hi = halt_lo + 7        # halt / ldh / and / jr / ret: the idle loop

        def on_vblank(_ctx) -> None:
            """At VBlank entry the stack top is the PC the interrupt cut into and
            hLoadedROMBank is still its bank. Inside DelayFrame's halt loop =
            an idle frame (already charged by on_delay_frame); anywhere else =
            the frame was spent computing, so charge the interrupted routine."""
            if not state["on"]:
                return
            mem, sp = h.pyboy.memory, h.pyboy.register_file.SP
            pc = mem[sp] | (mem[sp + 1] << 8)
            if halt_lo <= pc < halt_hi:
                return
            bank = h.read8("hLoadedROMBank")
            names = [syms.name(bank, pc) or f"${pc:04x}"]
            for depth in range(1, 12):
                ret = mem[sp + 2 * depth] | (mem[sp + 2 * depth + 1] << 8)
                if ret >= 0x8000:
                    continue
                name = syms.name(bank, ret)
                if name and name not in names:
                    names.append(name)
                if len(names) >= 3:
                    break
            busy[" < ".join(names)] += 1

        h.register_hook("VBlank", on_vblank)

        mon = lambda sp, lv: {"species": g.species[sp].internal_id, "level": lv, "moves": []}
        h.inject_fight2_spec([mon(*p) for p in player], [mon(*e) for e in enemy],
                             trainer_class=trainer_class, ai_tier=ai_tier)
        h.boot_fight2(seed=1)
        options_fn(h)
        opts = h.read8("wOptions") | (h.read8("wLetterPrintingDelayFlags") << 8)
        state["on"] = True
        start = h.pyboy.frame_count
        handled, mode_index = party_inputs["count"], 0
        for _ in range(cal.MAX_STEPS):
            if party_inputs["count"] > handled:
                h.tick(2)
                h.tap("a" if party_modes[mode_index] else "b")
                handled, mode_index = party_inputs["count"], mode_index + 1
            else:
                h.tap("a", 1)
                h.tick(8)
            if victories["count"] or defeats["count"]:
                break
        frames = h.pyboy.frame_count - start
        result = "win" if victories["count"] else "loss" if defeats["count"] else "timeout"
        return waits, busy, frames, len(turns), f"{result} letterflags/options=${opts:04x}"
    finally:
        try:
            h.close()
        except Exception:
            pass


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--round", type=int, default=5)
    ap.add_argument("--mons", type=int, default=3)
    ap.add_argument("--gap", type=int, default=6)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--top", type=int, default=20)
    ap.add_argument("--speeds-anim", action="store_true", help="the same, with battle animations ON")
    ap.add_argument("--speeds", action="store_true", help="compare BATTLE SPEED 1X/2X/4X (animations off, instant text)")
    args = ap.parse_args(argv)

    g = parse.load_all()
    cfg = model.Config()
    rng = random.Random(args.seed)
    level = cal.round_level(g, args.round)
    player = cal.player_team(g, cfg, level, args.gap, rng)
    enemy = cal.enemy_team(g, cfg, args.round, level, args.mons, rng)
    powers = parse_move_powers(REPO_ROOT / "data" / "moves" / "moves.asm")
    trainer_class = parse_trainer_constants(REPO_ROOT / "constants" / "trainer_constants.asm")[cal.ENEMY_CLASS]
    image = cal.Image("pokeblue_debug")
    ai_tier = image.rom[image.offset("AITierByRound"):][:9][args.round - 1]   # Normal row
    syms = Symbols(REPO_ROOT / "pokeblue_debug.sym")

    def as_is(h):
        pass

    def anim_off(h):
        h.write8("wOptions", h.read8("wOptions") | (1 << BIT_BATTLE_ANIMATION))

    def anim_off_instant(h):
        h.write8("wOptions", (h.read8("wOptions") | (1 << BIT_BATTLE_ANIMATION)) & ~TEXT_DELAY_MASK)
        # The FIGHT2 debug boot skips the main menu, which is what sets
        # BIT_FAST_TEXT_DELAY; without it every letter waits one frame whatever
        # the text-speed option says (PrintLetterDelay .waitOneFrame).
        h.write8("wLetterPrintingDelayFlags", h.read8("wLetterPrintingDelayFlags") | 1)

    print(f"player {player}\nenemy {enemy}\n")
    def speed(n):
        def fn(h):
            anim_off_instant(h)
            h.write8("wOptions3", (h.read8("wOptions3") & ~BATTLE_SPEED_MASK) | (n << 1))
        return fn

    variants = [("default options", as_is), ("animations off", anim_off),
                ("animations off + instant text", anim_off_instant)]
    def speed_anim_on(n):
        def fn(h):
            h.write8("wOptions", h.read8("wOptions") & ~TEXT_DELAY_MASK & ~(1 << BIT_BATTLE_ANIMATION))
            h.write8("wLetterPrintingDelayFlags", h.read8("wLetterPrintingDelayFlags") | 1)
            h.write8("wOptions3", (h.read8("wOptions3") & ~BATTLE_SPEED_MASK) | (n << 1))
        return fn

    if args.speeds:
        variants = [("animations off + instant text", anim_off_instant),
                    ("  + BATTLE SPEED 2X", speed(1)), ("  + BATTLE SPEED 4X", speed(2))]
    if args.speeds_anim:
        variants = [("animations ON + instant text, 1X", speed_anim_on(0)),
                    ("animations ON + instant text, 2X", speed_anim_on(1)),
                    ("animations ON + instant text, 4X", speed_anim_on(2))]
    for label, fn in variants:
        waits, busy, frames, turns, info = profile(g, player, enemy, ai_tier, powers, trainer_class, fn, syms)
        waited = sum(waits.values())
        print(f"== {label}: {info}, {turns} turns, {frames} frames = {frames / 60:.1f} s "
              f"({frames / max(turns, 1) / 60:.1f} s/turn at 60 fps)")
        for name, n in waits.most_common(args.top):
            print(f"   {n:6d}  {100 * n / frames:5.1f}%  {name}")
        print(f"   {frames - waited:6d}  {100 * (frames - waited) / frames:5.1f}%  computation / other (not in DelayFrame)")
        print(f"   busy frames (VBlank landed outside DelayFrame): {sum(busy.values())} (routine < callers)")
        for name, n in busy.most_common(args.top):
            print(f"      {n:6d}  {name}")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
