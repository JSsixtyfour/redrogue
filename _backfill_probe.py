import sys, io, pathlib, faulthandler, json
faulthandler.dump_traceback_later(180, exit=True)
sys.path.insert(0, 'tools/pyboy_smoke')
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = pathlib.Path('.').resolve()
ART = ROOT / 'tools' / 'pyboy_smoke' / 'artifacts'
species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

def run(name, player, enemy, ai_tier, prime=None, prime_hp=None, trainer_class="COOLTRAINER_M"):
    h = RedRogueHarness(ROOT, ART)
    def mon(spec):
        return {"species": species[spec["species"]], "level": spec["level"],
                "moves": [moves[m] for m in spec["moves"]]}
    h.inject_fight2_spec([mon(p) for p in player], [mon(e) for e in enemy],
                          trainer_class=trainers[trainer_class], ai_tier=ai_tier)
    scores = h.hook_ai_scores()
    if prime or prime_hp:
        def apply_prime():
            for label, value in (prime or {}).items():
                h.write8(label, value)
            for entry in (prime_hp or []):
                mhi, mlo = h.read_bytes(entry["max_label"], 2)
                mx = (mhi << 8) | mlo
                v = max(1, min(mx, mx * entry["numerator"] // entry["denominator"]))
                h.write8(entry["current_label"], v >> 8, offset=0)
                h.write8(entry["current_label"], v & 0xFF, offset=1)
        h.hook_flag("AIEnemyTrainerChooseMoves.beforeLayers", action=apply_prime)
    h.boot_fight2(seed=1)
    for _ in range(300):
        h.tap("a", 1)
        h.tick(8)
        if scores:
            break
    if not scores:
        print(name, "NO DECISION CAPTURED")
        return
    t = scores[0]
    print(f"=== {name} ===")
    print("  scores:", t["scores"], "moves:", t["moves"])
    for l in t["layer_trace"]:
        if l["enabled"] or any(l["delta"]):
            print("   ", l["layer"], l["before"], "->", l["after"], "delta", l["delta"])

# F9: AIOwnsPhysicalMove gate. T1 = REDUNDANT|BASIC|TYPES|SETUP only.
run("F9_positive_no_physical_move",
    player=[{"species":"RATTATA","level":50,"moves":["TACKLE"]}],
    enemy=[{"species":"KRABBY","level":50,"moves":["LEER","BUBBLE"]}],
    ai_tier=1)
run("F9_negative_has_physical_move",
    player=[{"species":"RATTATA","level":50,"moves":["TACKLE"]}],
    enemy=[{"species":"KRABBY","level":50,"moves":["LEER","TACKLE"]}],
    ai_tier=1)

# F17: stat-up cap / stat-down floor, T0 isolates AI_REDUNDANT alone.
run("F17_statup_capped",
    player=[{"species":"RATTATA","level":50,"moves":["TACKLE"]}],
    enemy=[{"species":"MACHOP","level":50,"moves":["SWORDS_DANCE","TACKLE"]}],
    ai_tier=0, prime={"wEnemyMonAttackMod": 13})
run("F17_statup_legal",
    player=[{"species":"RATTATA","level":50,"moves":["TACKLE"]}],
    enemy=[{"species":"MACHOP","level":50,"moves":["SWORDS_DANCE","TACKLE"]}],
    ai_tier=0, prime={"wEnemyMonAttackMod": 7})
run("F17_statdown_floored",
    player=[{"species":"RATTATA","level":50,"moves":["TACKLE"]}],
    enemy=[{"species":"MACHOP","level":50,"moves":["GROWL","TACKLE"]}],
    ai_tier=0, prime={"wPlayerMonAttackMod": 1})
run("F17_statdown_legal",
    player=[{"species":"RATTATA","level":50,"moves":["TACKLE"]}],
    enemy=[{"species":"MACHOP","level":50,"moves":["GROWL","TACKLE"]}],
    ai_tier=0, prime={"wPlayerMonAttackMod": 7})

# F14: charge moves and evasion. T2 = REDUNDANT|BASIC|TYPES|SETUP|SMART|DAMAGE|OMNISCIENT
run("F14_charge_exposed_not_stalling",
    player=[{"species":"SNORLAX","level":50,"moves":["TACKLE"]}],
    enemy=[{"species":"ELECTRODE","level":50,"moves":["RAZOR_WIND","MIST"]}],
    ai_tier=2)
run("F14_charge_exposed_stalling",
    player=[{"species":"SNORLAX","level":50,"moves":["TACKLE"]}],
    enemy=[{"species":"ELECTRODE","level":50,"moves":["RAZOR_WIND","MIST"]}],
    ai_tier=2, prime={"wBattleMonStatus": 1<<3})  # PSN bit
run("F14_dig_invulnerable_not_stalling",
    player=[{"species":"SNORLAX","level":50,"moves":["TACKLE"]}],
    enemy=[{"species":"ELECTRODE","level":50,"moves":["DIG","MIST"]}],
    ai_tier=2)
run("F14_dig_invulnerable_stalling",
    player=[{"species":"SNORLAX","level":50,"moves":["TACKLE"]}],
    enemy=[{"species":"ELECTRODE","level":50,"moves":["DIG","MIST"]}],
    ai_tier=2, prime={"wBattleMonStatus": 1<<3})
run("F14_evasion_not_stalling",
    player=[{"species":"SNORLAX","level":50,"moves":["TACKLE"]}],
    enemy=[{"species":"ELECTRODE","level":50,"moves":["DOUBLE_TEAM","MIST"]}],
    ai_tier=2)
run("F14_evasion_stalling",
    player=[{"species":"SNORLAX","level":50,"moves":["TACKLE"]}],
    enemy=[{"species":"ELECTRODE","level":50,"moves":["DOUBLE_TEAM","MIST"]}],
    ai_tier=2, prime={"wBattleMonStatus": 1<<3})

# F15: Metronome last resort. T3 = full stack incl RISKY.
run("F15_metronome_fires_when_nothing_better",
    player=[{"species":"SNORLAX","level":50,"moves":["TACKLE"]}],
    enemy=[{"species":"ELECTRODE","level":50,"moves":["METRONOME","MIST"]}],
    ai_tier=3)
run("F15_metronome_silent_when_kill_available",
    player=[{"species":"RATTATA","level":50,"moves":["TACKLE"]}],
    enemy=[{"species":"SNORLAX","level":50,"moves":["METRONOME","HYPER_BEAM"]}],
    ai_tier=3)
