"""Measurement: the in-battle ITEM path under CHALLENGE_NO_HEALING.

Usage (through witch_probe.sh): witch_probe_c15b.py <evidence> <rom> [branch]
Takes control at the first battle menu of a stage, stages a hurt lead and potions, and
presses DOWN, A, ... printing the screen after each press, so the row can be written
against what is really there.
"""
import io
import sys
from pathlib import Path

import witch_autoplay as wa
import witch_cases as wc

evidence, rom = Path(sys.argv[1]), sys.argv[2]
branch = sys.argv[3] if len(sys.argv) > 3 else "accept"
case = wc.CASES["C15"]
pre, interventions = wa.build_preoffer(case, rom, evidence)
run = wa.Run(case, rom, branch, evidence)
run.interventions = list(interventions)
run.h = wa.harness(rom, evidence)
run.h.load_state(io.BytesIO(pre))
run.agent = wa.WitchAgent(run.h, answers=wa.ANSWERS[branch], seed=1, stall_frames=30000)
h, agent = run.h, run.agent
menus = h.hook_flag("DisplayBattleMenu")
blocks = h.hook_flag("RogueWitchBlockHealing")
uses = h.hook_flag("ItemUseMedicine")
run.talk()
lobby = agent.lobby_map
limit = h.pyboy.frame_count + 6000
while h.read8("hCurMap") == lobby and h.pyboy.frame_count < limit:
    agent.step()
end = h.pyboy.frame_count + 30000
while not menus["count"] and h.pyboy.frame_count < end:
    agent.step()
print("battle menu reached:", menus["count"], "mode", agent.mode(), "frame", h.pyboy.frame_count)
agent.menu_goal = None
item = min(agent.heal_amounts, key=lambda i: agent.heal_amounts[i])
slot = agent.recovery_table.index(item)
h.write8("wRecoveryItemCounts", 3, offset=slot)
maximum = h.read8("wBattleMonMaxHP") << 8 | h.read8("wBattleMonMaxHP", 1)
h.write8("wBattleMonHP", (maximum // 5) >> 8)
h.write8("wBattleMonHP", (maximum // 5) & 0xFF, offset=1)
h.write8("wPartyMon1HP", (maximum // 5) >> 8)
h.write8("wPartyMon1HP", (maximum // 5) & 0xFF, offset=1)
print("item", item, "slot", slot, "max", maximum)


def show(label: str) -> None:
    print(f"--- {label}  (blocks {blocks['count']}, uses {uses['count']})")
    for row in wa.screen_rows(h):
        if row.strip():
            print("  |" + row)


h.tick(30)
show("start")
for button in sys.argv[4:]:
    agent.press(button)
    h.tick(20)
    show(f"after {button}")
