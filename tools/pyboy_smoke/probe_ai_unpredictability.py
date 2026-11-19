"""How predictable is the enemy's decision? (AI_T4_REGRET_PLAN E2b / E4, 2026-11-18). A probe.

For every recorded T3 turn decision (ai_counterfactual's pass 1, so the states are the gate's own),
reload the exact battle-menu state, reseed ONLY the RNG (Replayer.reseed: hRandomAdd/Sub and the
CMWC table), re-run the real pre-menu decision (AIPlanEnemyTurn) and read what it planned: a switch
to slot r, or a move slot s. N reseeds per state. A deterministic AI answers the same every time; a
probabilistic one (Stadium-style switching, or E4's near-tie mixing) varies. Reported:
  - share of states whose answer changes under reseeding, overall and by kind of answer;
  - mean Shannon entropy of the answer (bits; 0 = always the same);
  - how often the switch/stay answer itself flips (the visible part of predictability).
Each build is measured on its OWN states: a save state cannot cross builds (the stack holds return
addresses into that ROM's layout), so builds compare as populations, as the swarm does.

    python3 tools/pyboy_smoke/probe_ai_unpredictability.py --root ~/redrogue_e2b --seeds 280:300
"""
import argparse
import io
import json
import math
import statistics
import sys
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

PLAN_SWITCH_BIT = 6
PLAN_SLOT_MASK = 0b111


def answer(rp):
    """The planned action as a label: 'switch:r' or 'move:s'."""
    h = rp.h
    plan = h.read8("wAITurnPlan")
    if plan >> PLAN_SWITCH_BIT & 1:
        return f"switch:{(plan & PLAN_SLOT_MASK) - 1}"
    return f"move:{h.read8('wEnemyMoveListIndex')}"


def per_seed(args):
    root, seed, reseeds, policy = args
    sys.path.insert(0, str(Path(root) / "tools/pyboy_smoke"))
    import ai_counterfactual as cf
    rp = cf.Replayer(seed, 3, policy, root=Path(root))
    out = []
    try:
        states, decisions, _ = cf.record_battle(rp)
        h = rp.h
        for d in decisions:
            if d.kind != "turn":
                continue
            answers = []
            for k in range(reseeds):
                h.load_state(io.BytesIO(states[d.state_index]))
                rp.reseed(f"unpredict:{seed}:{d.index}", k)
                for label in ("wAIPlayerKOCache", "wAIReliableKOFound"):  # call_routine leaves these
                    h.write8(label, 0)
                h.park_before_hijack()
                h.call_routine("AIPlanEnemyTurn", limit=200000)
                answers.append(answer(rp))
            out.append({"seed": seed, "index": d.index, "chosen_in_play": d.chosen, "answers": answers})
    finally:
        rp.close()
    return out


def entropy(counts):
    n = sum(counts.values())
    return -sum(c / n * math.log2(c / n) for c in counts.values())


def summarize(rows):
    def kind(a):
        return a.split(":")[0]
    varied = [r for r in rows if len(set(r["answers"])) > 1]
    flips = [r for r in rows if len({kind(a) for a in r["answers"]}) > 1]
    ent = [entropy(Counter(r["answers"])) for r in rows]
    print(f"{len(rows)} turn states, {len(rows[0]['answers']) if rows else 0} reseeds each")
    print(f"  answer changes under reseeding: {len(varied)} ({100 * len(varied) / max(len(rows), 1):.1f}%)")
    print(f"  switch/stay itself flips:       {len(flips)} ({100 * len(flips) / max(len(rows), 1):.1f}%)")
    print(f"  mean entropy {statistics.fmean(ent) if ent else 0:.3f} bits")
    by = Counter(kind(Counter(r["answers"]).most_common(1)[0][0]) for r in rows)
    for k, n in by.items():
        sub = [r for r in rows if kind(Counter(r["answers"]).most_common(1)[0][0]) == k]
        v = sum(len(set(r["answers"])) > 1 for r in sub)
        print(f"  mostly {k:6}: {n:4} states, {v} vary ({100 * v / max(n, 1):.1f}%)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    ap.add_argument("--seeds", default="280:290")
    ap.add_argument("--reseeds", type=int, default=8)
    ap.add_argument("--policy", default="best_power")
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--out", type=Path, default=None)
    a = ap.parse_args()
    lo, hi = (int(x) for x in a.seeds.split(":"))
    tasks = [(str(a.root), s, a.reseeds, a.policy) for s in range(lo, hi)]
    with ProcessPoolExecutor(max_workers=a.jobs) as pool:
        rows = [r for chunk in pool.map(per_seed, tasks) for r in chunk]
    if a.out:
        a.out.write_text("".join(json.dumps(r) + "\n" for r in rows))
    summarize(rows)


if __name__ == "__main__":
    main()
