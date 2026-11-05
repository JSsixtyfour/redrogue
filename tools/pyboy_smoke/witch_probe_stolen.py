"""Replay a campaign seed and compare a stolen mon before the theft, on the villain's team, and after it
comes back: level, experience, HP, max HP.

  wsl bash .../witch_probe.sh witch_probe_stolen.py <seed> [difficulty] [reset 0/1]
"""
import json
import os
import sys
from pathlib import Path

import witch_autoplay as wa

MON_LENGTH = 44


def mon(h, base_label, index):
    memory = h.pyboy.memory
    base = h.address(base_label) + index * MON_LENGTH
    return {"species": memory[base], "level_box": memory[base + 3], "hp": memory[base + 1] << 8 | memory[base + 2],
            "exp": memory[base + 14] << 16 | memory[base + 15] << 8 | memory[base + 16],
            "level": memory[base + 33], "max_hp": memory[base + 34] << 8 | memory[base + 35],
            "attack": memory[base + 36] << 8 | memory[base + 37], "catch_rate": memory[base + 7],
            "dvs": [memory[base + 27], memory[base + 28]]}


def main() -> None:
    evidence = Path(sys.argv[1]) / "probe_stolen"
    evidence.mkdir(parents=True, exist_ok=True)
    seed = int(sys.argv[2])
    difficulty = sys.argv[3] if len(sys.argv) > 3 else "VERY_EASY"
    reset = bool(int(sys.argv[4])) if len(sys.argv) > 4 else True
    original_init = wa.CampaignAgent.__init__
    log = {"thefts": 0}

    def init(self, harness, **kwargs):
        original_init(self, harness, **kwargs)
        h = harness

        def party():
            return [mon(h, "wPartyMon1", i) for i in range(h.read8("wPartyCount"))]

        def theft(_context):
            if h.read8("wStageEvent") & 7 == 2:
                log["before"] = {"frame": h.pyboy.frame_count, "party": party(), "depth": h.read8("wEndlessDepth")}

        def give_back(_context):
            log["give_back_entry"] = {"frame": h.pyboy.frame_count, "party_count": h.read8("wPartyCount"),
                                      "phase": h.read8("wStageEvent")}

        def enemy_slot(_context):
            if h.read8("wStageEvent") & 7 == 2 and h.read8("wTrainerClass") == 19 and "before" in log:
                count = h.read8("wEnemyPartyCount")
                print(json.dumps({"on_villain_team": mon(h, "wEnemyMon1", count - 1), "frame": h.pyboy.frame_count},
                                 default=str), flush=True)

        h.register_hook("StageEventDoTheft", theft)
        h.register_hook("StageEventGiveBack", give_back)
        h.register_hook("ReadTrainer.LastLoop", enemy_slot) if False else None

    original_note = wa.CampaignAgent.note_progress

    def note(self):
        original_note(self)
        h = self.h
        if "before" in log and "after" not in log and self.game_world_reads_ready() and self.mode() == "overworld":
            if h.read8("wStageEvent") & 0x18 == 0x10 and h.read8("wStageEvent") & 7 == 2:
                party = [mon(h, "wPartyMon1", i) for i in range(h.read8("wPartyCount"))]
                was = {tuple(m["dvs"]): m for m in log["before"]["party"]}
                now = {tuple(m["dvs"]): m for m in party}
                keep = ("species", "level", "exp", "hp", "max_hp", "attack")
                print(json.dumps({"theft_frame": log["before"]["frame"], "back_frame": h.pyboy.frame_count,
                                  "depth": log["before"]["depth"], "box": h.read8("wBoxCount"),
                                  "mons": [{"was": {k: was[d][k] for k in keep}, "now": {k: now[d][k] for k in keep}}
                                           for d in was if d in now and now[d]["level"] < was[d]["level"]
                                           or d in now and now[d]["max_hp"] < was[d]["max_hp"]],
                                  "stolen": [{k: was[d][k] for k in keep} for d in was if d not in now]},
                                 default=str), flush=True)
                log.pop("before")
                log.pop("give_back_entry", None)
                if h.pyboy.frame_count > 1420000:
                    os._exit(0)

    wa.CampaignAgent.__init__ = init
    wa.CampaignAgent.note_progress = note
    options = {"rom": "pokeblue_debug", "evidence": str(evidence), "stages": 300, "max_frames": 2500000,
               "stall_frames": 20000, "strong": True, "difficulty": difficulty, "endless_stages": 60,
               "endless_reset_prizes": reset}
    row = wa.run_campaign_seed(seed, options)
    print(json.dumps({"finished": row["outcome"], "log": log}, default=str), flush=True)


if __name__ == "__main__":
    main()
