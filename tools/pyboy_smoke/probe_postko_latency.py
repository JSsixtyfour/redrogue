"""Post-KO send-out latency probe (AI_T4_REGRET_PLAN C0, 2026-11-17). Probe, not a smoke test.

Cycles of one AISelectSendOut after a faint, legacy T1 against the T3 post-KO pass, with call
counts of the expensive callees. Run from WSL: python3 tools/pyboy_smoke/probe_postko_latency.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_rgbds_constants, parse_trainer_constants  # noqa: E402

SP = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
MV = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
TR = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
FRAME = 70224

RESERVES = [
    ("SLOWBRO", ["SURF", "PSYCHIC_M", "ICE_BEAM", "BODY_SLAM"]),
    ("MAGMORTAR", ["FLAMETHROWER", "THUNDERBOLT", "BODY_SLAM", "EARTHQUAKE"]),
    ("ELECTRODE", ["THUNDERBOLT", "SWIFT", "TAKE_DOWN", "EXPLOSION"]),
    ("RHYDON", ["EARTHQUAKE", "ROCK_SLIDE", "BODY_SLAM", "HYPER_BEAM"]),
    ("GENGAR", ["THUNDERBOLT", "PSYCHIC_M", "NIGHT_SHADE", "MEGA_DRAIN"]),
]


def run(tier, count):
    h = RedRogueHarness(ROOT, Path(__file__).resolve().parent / "artifacts")
    try:
        mon = lambda s, m: dict(species=SP[s], level=50, moves=[MV[x] for x in m])
        res = [mon(s, m) for s, m in RESERVES[:count]]
        h.inject_fight2_spec([mon("STARMIE", ["SURF", "PSYCHIC_M", "THUNDERBOLT", "ICE_BEAM"])],
                             [mon("RATTATA", ["TACKLE"]), *res],
                             trainer_class=TR["COOLTRAINER_M"], ai_tier=tier)
        h.boot_fight2(seed=1)
        h.write8("wAITurnPlan", 0)
        h.write8("wAISeenPlayerMoveMask", 15)
        h.write8("wEnemyMonHP", 0); h.write8("wEnemyMonHP", 0, offset=1)
        h.write8("wEnemyMon1HP", 0); h.write8("wEnemyMon1HP", 0, offset=1)
        span = {}
        b, a = h.symbols.get("AISelectSendOut")

        def enter(_):
            span["start"] = h.cycle_count()

        h.pyboy.hook_register(b, a, enter, None)
        counts = {}
        for lbl in ("AIEstimateDamage", "AIEstimatePlayerMoveDamage", "AIBestReserveSurvivesThreat",
                    "AIBuildPlayerThreatTypes", "AIEnemyCritAlsoKOs"):
            if lbl not in h.symbols._symbols:
                continue
            bb, aa = h.symbols.get(lbl)
            counts[lbl] = 0
            def bump(_, l=lbl):
                counts[l] += 1
            h.pyboy.hook_register(bb, aa, bump, None)
        span["counts"] = counts
        span["key1"] = h.pyboy.memory[0xFF4D]
        # Measure entry -> return via capture at return.
        sel = h.call_routine("AISelectSendOut", limit=200000,
                             capture=lambda hh: (hh.cycle_count(), hh.read8("hWhichPokemon")))
        end, slot = sel
        return end - span["start"], slot, span
    finally:
        h.close()


for count in (5,):
    for tier in (1, 3):
        cyc, slot, span = run(tier, count)
        print(f"reserves={count} T{tier}: {cyc:>9} cycles = {cyc / FRAME:6.2f} 1x-frames  -> slot {slot} key1={span['key1']:#04x} {span['counts']}")
