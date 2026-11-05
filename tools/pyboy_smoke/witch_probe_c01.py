"""Measurement: who opens RogueRewardMenu under challenge 1, and with what visible?

Usage (through witch_probe.sh): witch_probe_c01.py <evidence> <rom>
Prints one row per RogueRewardMenu entry: map, stack words (return addresses), the toggle
flags of the three balls and the trade NPC, and the player's position.
"""
import io
import sys
from pathlib import Path

import witch_autoplay as wa
import witch_cases as wc

evidence, rom = Path(sys.argv[1]), sys.argv[2]
case = wc.CASES["C01"]
pre, interventions = wa.build_preoffer(case, rom, evidence)
branch = sys.argv[3] if len(sys.argv) > 3 else "accept"
run = wa.Run(case, rom, branch, evidence)
run.interventions = list(interventions)
run.h = wa.harness(rom, evidence)
run.h.load_state(io.BytesIO(pre))
run.agent = wa.WitchAgent(run.h, answers=wa.ANSWERS[branch], seed=1, stall_frames=30000)
h = run.h
log = []


def menu(_context):
    sp = h.pyboy.register_file.SP
    stack = [h.pyboy.memory[sp + i] | h.pyboy.memory[sp + i + 1] << 8 for i in range(0, 12, 2)]
    log.append({"frame": h.pyboy.frame_count, "map": h.read8("hCurMap"), "bank": h.read8("hLoadedROMBank"),
                "stack": [f"{w:04x}" for w in stack], "textid": h.read8("hTextID"),
                "player_yx": (h.read8("wYCoord"), h.read8("wXCoord")),
                "hidden_ball1_ball2_ball3_trade": [wc.toggle_hidden(h, n) for n in (
                    "TOGGLE_ROGUE_REWARD_POKEBALL_1", "TOGGLE_ROGUE_REWARD_POKEBALL_2",
                    "TOGGLE_ROGUE_REWARD_POKEBALL_3", "TOGGLE_ROGUE_TRADE_NPC")],
                "sprite_index": h.read8("hSpriteIndex"),
                "sprite_state1": h.read_bytes("wSpriteStateData1", 16 * 16)[h.read8("hSpriteIndex") * 16:][:16],
                "sprite_state2": h.read_bytes("wSpriteStateData2", 16 * 16)[h.read8("hSpriteIndex") * 16:][:16],
                "map_sprite_data": h.read_bytes("wMapSpriteData", 32)[(h.read8("hSpriteIndex") - 1) * 2:][:2],
                "toggle_list": h.read_bytes("wToggleableObjectList", 33)})
    log[-1]["last_inputs"] = run.agent.report.inputs[-8:]
    log[-1]["last_events"] = [e for e in run.agent.report.events[-4:]]
    log[-1]["goal"] = str(getattr(run.agent, "goal", None))[:200]
    log[-1]["facing_and_pos"] = (h.read8("wSpritePlayerStateData1FacingDirection"),
                                 h.read8("wSpritePlayerStateData1YPixels"))


h.register_hook("RogueRewardMenu", menu)
run.talk()
run.play_zone()
for row in log:
    print(row)
for name in ("RogueRewardMenu", "DisplayTextID", "RogueShowStageRewards"):
    print(name, h.symbols.get(name))
for row in log:
    for word in row["stack"]:
        value = int(word, 16)
        print(word, h.symbols.nearest(row["bank"] if value >= 0x4000 else 0, value))

