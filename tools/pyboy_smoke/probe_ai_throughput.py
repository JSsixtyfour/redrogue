"""AI_T4_REGRET_PLAN A0 (2026-11-17), a probe, not a smoke test. Run from WSL. Measures wall-clock throughput of one T3 FIGHT 2 battle played from a saved
state, 20 times, best_power policy. Setup and input loop mirror run_ai_benchmark.run_tier;
the RNG is reseeded per battle the way A2 specifies (SHA-256 of an id and k)."""
import hashlib
import io
import statistics
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/pyboy_smoke"))
import run_ai_benchmark as rab  # noqa: E402
from harness import RedRogueHarness  # noqa: E402

TIER, SEED, N, POLICY, MAX_STEPS = 3, 17, 20, "best_power", 5000

move_powers = rab.parse_move_powers(ROOT / "data/moves/moves.asm")
h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
try:
    override = TIER + 1
    h.write8("wAIDebugTierOverride", override)
    h.hook_flag("DebugFight2Setup", action=lambda: h.write8("wAIDebugTierOverride", override))
    h.register_hook("MainInBattleLoop.noLinkBattle", lambda _c: h.write8(
        "wTestBattlePlayerSelectedMove", rab.choose_player_move(h, POLICY, move_powers)))
    turns = h.hook_turn_telemetry()
    victories = h.hook_flag("TrainerBattleVictory")
    defeats = h.hook_flag("HandlePlayerBlackOut")
    voluntary = {"target": None, "count": 0}
    h.hook_flag("DisplayBattleMenu", action=lambda: h.write8("wBattleAndStartSavedMenuItem", 0))
    h.hook_flag("MoveSelectionMenu", action=lambda: h.write8(
        "wPlayerMoveListIndex", rab.choose_player_slot(h, POLICY, move_powers)[0]))
    party_inputs, party_modes, _trace = rab.prepare_party_driver(h, voluntary)
    t0 = time.perf_counter()
    h.boot_fight2(seed=SEED)
    boot_s = time.perf_counter() - t0
    base = io.BytesIO()
    t0 = time.perf_counter()
    h.save_state(base)
    save_s = time.perf_counter() - t0

    rows = []
    for k in range(N):
        t0 = time.perf_counter()
        h.load_state(base)
        load_s = time.perf_counter() - t0
        h.write8("wAIDebugTierOverride", override)
        digest = hashlib.sha256(f"a0:{SEED}:{k}".encode()).digest()
        h.write8("hRandomAdd", digest[0]); h.write8("hRandomSub", digest[1])
        for i in range(10):
            h.write8("wRandomTable", digest[2 + i], offset=i)
        turn0, v0, d0 = len(turns), victories["count"], defeats["count"]
        handled, mode_i = party_inputs["count"], len(party_modes)
        f0 = h.pyboy.frame_count
        t0 = time.perf_counter()
        for step in range(MAX_STEPS):
            if party_inputs["count"] > handled:
                h.tick(2)
                h.tap("a" if party_modes[mode_i] else "b")
                handled = party_inputs["count"]
                mode_i += 1
            else:
                h.tap("a", 1)
                h.tick(8)
            if victories["count"] > v0 or defeats["count"] > d0:
                break
        else:
            raise AssertionError(f"battle {k} exceeded {MAX_STEPS} steps")
        wall = time.perf_counter() - t0
        rows.append((k, wall, load_s, len(turns) - turn0, h.pyboy.frame_count - f0,
                     "win" if victories["count"] > v0 else "loss"))
        print(f"battle {k:2}: {wall:6.2f}s  load {load_s * 1000:5.1f}ms  turns {rows[-1][3]:3}  "
              f"frames {rows[-1][4]:6}  {rows[-1][5]}", flush=True)
finally:
    h.close()

walls = [r[1] for r in rows]
mean = statistics.mean(walls)
print(f"\nboot {boot_s:.1f}s, save_state {save_s * 1000:.1f}ms")
print(f"battle wall: mean {mean:.2f}s  median {statistics.median(walls):.2f}s  "
      f"min {min(walls):.2f}s  max {max(walls):.2f}s  (turns mean {statistics.mean(r[3] for r in rows):.1f})")
print(f"=> branches (battle-to-end) per minute: {60 / mean:.1f}")
print(f"=> one decision, 6 alternatives x K=4: {6 * 4 * mean / 60:.1f} min  (A0 stop line: ~2 min)")
print(f"=> K=8 (A3 default): {6 * 8 * mean / 60:.1f} min per decision")
