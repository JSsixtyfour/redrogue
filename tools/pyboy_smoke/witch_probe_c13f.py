"""Measurement: which maps does the C13F row (badges $FF, Victory Road not cleared) play?

Usage (through witch_probe.sh): witch_probe_c13f.py <evidence> <rom>
Prints the two door maps at the offer and the name of every map the zone visits.
"""
import io
import sys
from pathlib import Path

import witch_autoplay as wa
import witch_cases as wc

evidence, rom = Path(sys.argv[1]), sys.argv[2]
case = wc.CASES["C13F"]
pre, interventions = wa.build_preoffer(case, rom, evidence)
run = wa.Run(case, rom, "accept", evidence)
run.interventions = list(interventions)
run.h = wa.harness(rom, evidence)
run.h.load_state(io.BytesIO(pre))
run.agent = wa.WitchAgent(run.h, answers=wa.ANSWERS["accept"], seed=1, stall_frames=30000)
h = run.h
names = {value: name for name, value in wc.MAPS.items()}
print("doors", [names.get(h.read8(label)) for label in ("wLobbyDoor1StageMap", "wLobbyDoor2StageMap")])
seen = []


def poll(_context):
    current = names.get(h.read8("hCurMap"))
    if not seen or seen[-1] != current:
        seen.append(current)


h.register_hook("JoypadOverworld", poll)
run.talk()
run.play_zone()
print("maps", seen)
h.close()
