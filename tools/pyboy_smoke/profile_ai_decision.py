"""Where a T3 enemy decision spends its cycles (2026-11-18). A probe, not a smoke test.
Run from WSL: python3 tools/pyboy_smoke/profile_ai_decision.py

Profiles the pre-menu decision (AIPlanEnemyTurn, which the swarm's "decision cycles" time) on a
few FIGHT 2 boards: every global label in the AI's banks ($0E layers, $0F damage engine, $10
post-KO/B17, $2C switching, $08 E1 guess) plus the HOME helpers they lean on gets an entry hook,
timed to its return with profile_postko_sendout.Timings (farcall returns and loop-to-entry
re-entries handled there). Rows are INCLUSIVE and overlap between nested routines: rank by them,
do not add them. "no-VBlank" subtracts VBlank time inside the routine.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/pyboy_smoke"))
from harness import RedRogueHarness  # noqa: E402
from profile_postko_sendout import FRAME, MV, SP, TR, Timings  # noqa: E402

BANKS = (0x0E, 0x0F, 0x10, 0x2C, 0x08, 0x0C, 0x04, 0x3C)
HOME = ["CopyData", "FarCopyData", "AddNTimes", "Multiply", "Divide", "Random",
        "GetMonHeader", "ReadMove", "VBlank"]  # not Bankswitch: call_routine hooks it raw
BOARDS = [
    ("SNORLAX", ["BODY_SLAM", "EARTHQUAKE", "REST", "SPLASH"]),
    ("STARMIE", ["SURF", "PSYCHIC_M", "THUNDERBOLT", "ICE_BEAM"]),
    ("GENGAR", ["NIGHT_SHADE", "HYPNOSIS", "THUNDERBOLT", "MEGA_DRAIN"]),
    ("CHARIZARD", ["FLAMETHROWER", "SLASH", "EARTHQUAKE", "SWORDS_DANCE"]),
]
ENEMY = [("RHYDON", ["EARTHQUAKE", "ROCK_SLIDE", "BODY_SLAM", "SUBSTITUTE"]),
         ("STARMIE", ["SURF", "PSYCHIC_M", "RECOVER", "THUNDER_WAVE"]),
         ("JOLTEON", ["THUNDERBOLT", "DOUBLE_KICK", "PIN_MISSILE", "AGILITY"]),
         ("ALAKAZAM", ["PSYCHIC_M", "RECOVER", "REFLECT", "SEISMIC_TOSS"]),
         ("EXEGGUTOR", ["MEGA_DRAIN", "SLEEP_POWDER", "EXPLOSION", "PSYCHIC_M"]),
         ("LAPRAS", ["BLIZZARD", "SURF", "BODY_SLAM", "CONFUSE_RAY"])]
TOP = "AIPlanEnemyTurn"


class DecisionTimings(Timings):
    """Timings enabled only around the call_routine(AIPlanEnemyTurn) (run() toggles it)."""


DATA_NAME = re.compile(r"(Table|Index|Pointers|Classes|Ratios|Rows|None|Effects|Moves$|_[0-9a-f]{2}$)")


def labels(h):
    """CODE labels only, one per address. A PyBoy hook replaces the opcode at its address, so a
    hooked DATA label corrupts every read of that data (measured: the first all-labels version
    crashed the decision). Known engine routines (profile_postko_sendout.LABELS) plus AI-prefixed
    labels whose names do not look like data."""
    from profile_postko_sendout import LABELS
    out, seen = [], {h.symbols.get(TOP)}  # call_routine hooks TOP's address itself
    candidates = HOME + LABELS
    for bank in BANKS:
        for _addr, name in h.symbols._by_bank.get(bank, ()):
            if name.startswith(("AI", "_AI", "TrainerAI")) and "." not in name and not DATA_NAME.search(name):
                candidates.append(name)
    for name in candidates:
        if name in h.symbols._symbols and name != TOP and h.symbols.get(name) not in seen:
            seen.add(h.symbols.get(name))
            out.append(name)
    return out


def run(player, moves):
    h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
    try:
        mon = lambda s, m: dict(species=SP[s], level=50, moves=[MV[x] for x in m])  # noqa: E731
        h.inject_fight2_spec([mon(player, moves)], [mon(s, m) for s, m in ENEMY],
                             trainer_class=TR["COOLTRAINER_M"], ai_tier=3)
        # Boot with NO hooks (hooking ~1500 labels through the boot took 40+ minutes), then
        # time one fresh decision at the battle menu, where the game itself calls it.
        h.boot_fight2(seed=1)
        for label in ("wAIPlayerKOCache", "wAIReliableKOFound"):  # call_routine leaves these
            h.write8(label, 0)
        skipped = []
        original = h.register_hook

        def safe(label, callback):  # an address the harness already hooks raw is skipped
            try:
                original(label, callback)
            except ValueError:
                skipped.append(label)
                h._hook_callbacks.pop(h.symbols.get(label), None)
        h.register_hook = safe
        t = DecisionTimings(h, labels(h))
        h.register_hook = original
        if skipped:
            print("  skipped (address already hooked raw):", ", ".join(skipped))
        t.top = "__none__"  # the base class's special top handling is not used here
        t.done = False
        h.park_before_hijack()
        t.enabled = True
        start, vb0, end = h.cycle_count(), t.vblank, []
        h.call_routine(TOP, limit=200000, capture=lambda hh: end.append(hh.cycle_count()))
        t.enabled = False
        inc = end[0] - start
        t.records.append((TOP, inc, inc - (t.vblank - vb0)))
        return t
    finally:
        h.close()


def main():
    totals = defaultdict(lambda: [0, 0, 0])
    top_total = 0
    for player, moves in BOARDS:
        t = run(player, moves)
        rows = defaultdict(lambda: [0, 0, 0])
        for name, inc, own in t.records:
            r = rows[name]
            r[0] += 1
            r[1] += inc
            r[2] += own
        top = rows.get(TOP, [0, 0, 0])
        print(f"{player:10} decision {top[2]:7} cycles without VBlank ({top[2] / FRAME:.2f} 1x-frames), "
              f"{len(t.hooked)} labels hooked")
        top_total += top[2]
        for name, r in rows.items():
            tt = totals[name]
            tt[0] += r[0]
            tt[1] += r[1]
            tt[2] += r[2]
    print(f"\nAll boards: {top_total} cycles in {TOP} (no VBlank). Inclusive rows (overlap!):")
    print(f"{'routine':40} {'calls':>6} {'no-VBlank':>10} {'% decision':>10} {'per call':>9}")
    for name, (n, _inc, own) in sorted(totals.items(), key=lambda kv: -kv[1][2])[:45]:
        print(f"{name:40} {n:6} {own:10} {100 * own / max(top_total, 1):10.1f} {own // max(n, 1):9}")


if __name__ == "__main__":
    main()
