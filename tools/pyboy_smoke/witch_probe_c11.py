"""Measurement: what the witch's Challenge 11 gate sees at the roll.

Usage (through witch_probe.sh): witch_probe_c11.py <evidence> <rom> [case]
Prints one row per IsLegendaryBossOfferable exit and the state a lobby entry settled on.
"""
import sys
from pathlib import Path

import witch_autoplay as wa
import witch_cases as wc

evidence, rom = Path(sys.argv[1]), sys.argv[2]
case = wc.CASES[sys.argv[3] if len(sys.argv) > 3 else "C11L"]
run = wa.Run(case, rom, "setup", evidence)
run.h = wa.harness(rom, evidence)
h = run.h
base = wa.fixture_path(evidence, rom).read_bytes()
draws = wa.steer_offer(h, case.challenge, case.prize)
rows = []


def gate(_context):
    rows.append({"gym_choice": h.read8("wGymChoice"), "badges": h.read8("wObtainedBadges"),
                 "lineup": h.read_bytes("wRunGymLineup", 8), "endless": h.read8("wEndlessDepth"),
                 "earned": h.read_bytes("wWitchPrizesEarned", 2),
                 "party": h.read_bytes("wPartySpecies", h.read8("wPartyCount") + 1),
                 "battle_count": h.read8("wBattleCount"), "flags": h.read8("wRogueFlagsBitfield")})


h.register_hook("IsLegendaryBossOfferable", gate)
result = wa.prepare_offer(run, base, 1)
print("offered", result, "challenge", h.read8("wWitchChallenge"), "prize", h.read8("wWitchPrize"), "draws", draws)
print("door maps", h.read8("wLobbyDoor1StageMap"), h.read8("wLobbyDoor2StageMap"), "map", h.read8("hCurMap"))
print("gate calls", len(rows))
for row in rows[:4]:
    print(row)
print("final", {"gym_choice": h.read8("wGymChoice"), "badges": h.read8("wObtainedBadges"),
                "visible": wc.witch_visible(h) if hasattr(wc, "witch_visible") else None})
h.close()
