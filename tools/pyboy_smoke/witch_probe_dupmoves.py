"""Replay one Endless campaign seed and stop at its first anomaly, reporting how the
enemy party's movesets were built. Also scans the curated sets for a repeated move.

  wsl bash .../witch_probe.sh witch_probe_dupmoves.py <seed> [rom] [difficulty]
"""
import json
import os
import re
import sys
from collections import deque
from pathlib import Path

import witch_autoplay as wa

ROOT = Path(__file__).resolve().parents[2]
TRACE = ("PartyGenApplyMoveset", "PartyGenRollMoveset", "PartyGenApplySetMovesetMask", "PartyGenApplyExplicitMoves",
         "PartyGenApplyRequireFlags", "PartyGenEnsureAttack", "PartyGenWriteMove")
MON_LENGTH = 44


def scan_curated() -> None:
    found = []
    for path in (ROOT / "data/trainers").glob("*.asm"):
        for number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
            match = re.match(r"\s*db\s+(\w+),\s*(\w+),\s*(\w+),\s*(\w+),\s*TIER_", line)
            if match:
                moves = [m for m in match.groups() if m != "NO_MOVE"]
                if len(set(moves)) != len(moves):
                    found.append(f"{path.name}:{number}: {line.strip()}")
    print(json.dumps({"curated_sets_with_a_repeat": found}), flush=True)


def main() -> None:
    evidence, seed = Path(sys.argv[1]) / "probe_dupmoves", int(sys.argv[2])
    rom = sys.argv[3] if len(sys.argv) > 3 else "pokeblue_debug"
    difficulty = sys.argv[4] if len(sys.argv) > 4 else "VERY_EASY"
    evidence.mkdir(parents=True, exist_ok=True)
    scan_curated()
    trail: deque = deque(maxlen=60)
    original_init = wa.CampaignAgent.__init__

    def init(self, harness, **kwargs):
        original_init(self, harness, **kwargs)
        h = harness

        def read(name, offset=0):
            try:
                return h.read8(name, offset=offset)
            except Exception as error:
                return f"unavailable: {error}"

        def dump() -> None:
            count = h.read8("wEnemyPartyCount")
            mons = []
            for i in range(count):
                base = h.address("wEnemyMon1") + i * MON_LENGTH
                memory = h.pyboy.memory
                mons.append({"species": memory[base], "level": memory[h.address("wEnemyMon1Level") + i * MON_LENGTH],
                             "moves": [memory[h.address("wEnemyMon1Moves") + i * MON_LENGTH + m] for m in range(4)],
                             "catch_rate": memory[h.address("wEnemyMon1CatchRate") + i * MON_LENGTH]})
            print(json.dumps({"frame": h.pyboy.frame_count, "anomalies": self.checks.anomalies, "mons": mons,
                              "state": {name: read(name) for name in (
                                  "wCurOpponent", "wTrainerClass", "wTrainerNo", "wEndlessDepth", "wBattleCount",
                                  "wWitchChallenge", "wWitchPrize", "wRogueFlagsBitfield", "wOptions2", "hIsInBattle",
                                  "wPartyGenSource", "wPartyGenSlot", "wIsTrainerBattle", "hCurMap", "wStageEvent")},
                              "trail": list(trail)}), flush=True)
            h.write_failure_artifacts(f"probe_dupmoves_{seed}")
            os._exit(0)

        class Stop(list):
            def append(inner, item):
                list.append(inner, item)
                dump()

        self.checks.anomalies = Stop(self.checks.anomalies)

        def tracer(label):
            def hook(_context) -> None:
                registers = h.pyboy.register_file
                trail.append({"label": label, "frame": h.pyboy.frame_count, "slot": read("wPartyGenSlot"),
                              "source": read("wPartyGenSource"), "a": registers.A, "c": registers.C,
                              "moves": [h.read8("wEnemyMon1Moves", offset=m) for m in range(4)]})
            return hook

        for label in TRACE:
            try:
                h.register_hook(label, tracer(label))
            except Exception as error:
                print(json.dumps({"no_hook": label, "error": str(error)}), flush=True)

    wa.CampaignAgent.__init__ = init
    options = {"rom": rom, "evidence": str(evidence), "stages": 300, "max_frames": 2500000, "stall_frames": 20000,
               "strong": True, "difficulty": difficulty, "endless_stages": 60, "endless_reset_prizes": True}
    row = wa.run_campaign_seed(seed, options)
    print(json.dumps({"no_anomaly": True, "outcome": row["outcome"], "stages": row["stages"]}), flush=True)


if __name__ == "__main__":
    main()
