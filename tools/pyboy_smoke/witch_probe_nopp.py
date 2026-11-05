"""Replay one campaign seed until the agent has sat at the battle's move menu without progress, then
report every move, its PP and what the game and the policy make of them.

  wsl bash .../witch_probe.sh witch_probe_nopp.py <seed> <difficulty> <reset 0/1>
"""
import json
import os
import sys
from pathlib import Path

import benchmark_policies
import witch_autoplay as wa

STUCK_FRAMES = 3000


def main() -> None:
    evidence = Path(sys.argv[1]) / "probe_nopp"
    evidence.mkdir(parents=True, exist_ok=True)
    seed, difficulty, reset = int(sys.argv[2]), sys.argv[3], bool(int(sys.argv[4]))
    original_note = wa.CampaignAgent.note_progress

    def note(self) -> None:
        original_note(self)
        h = self.h
        if self.game_world_reads_ready() and self.mode() == "battle":
            if h.pyboy.frame_count - self.last_progress_frame > STUCK_FRAMES:
                state = benchmark_policies.read_state(h)
                moves = h.read_bytes("wBattleMonMoves", 4)
                raw_pp = h.read_bytes("wBattleMonPP", 4)
                print(json.dumps({
                    "frame": h.pyboy.frame_count, "map": self.map_name(h.read8("hCurMap")),
                    "species": h.read8("wBattleMonSpecies"), "moves": moves, "raw_pp": raw_pp,
                    "pp": [p & 0x3F for p in raw_pp], "state_moves": list(state.player.moves),
                    "state_pp": list(state.player.pp), "legal": benchmark_polices_legal(state),
                    "disabled": h.read8("wPlayerDisabledMove"), "cursor": h.read8("hCurrentMenuItem"),
                    "list_index": h.read8("wPlayerMoveListIndex"), "body_armor": self.has_body_armor(),
                    "player_status": h.read8("wBattleMonStatus"), "whose": h.read8("hWhoseTurn"),
                    "party": [h.read8("wPartyCount")], "policy": self.battle_policy, "menu_input": self.menu_input,
                    "witch": h.read8("wWitchChallenge"), "last_menu": self.last_menu_caller,
                    "inputs": self.report.inputs[-12:]}, default=str), flush=True)
                h.write_failure_artifacts(f"nopp_{seed}")
                os._exit(0)

    def benchmark_polices_legal(state):
        return list(benchmark_policies.legal_slots(state.player))

    wa.CampaignAgent.note_progress = note
    options = {"rom": "pokeblue_debug", "evidence": str(evidence), "stages": 300, "max_frames": 2500000,
               "stall_frames": 20000, "strong": True, "difficulty": difficulty, "endless_stages": 60,
               "endless_reset_prizes": reset}
    row = wa.run_campaign_seed(seed, options)
    print(json.dumps({"finished": row["outcome"], "stages": row["stages"]}), flush=True)


if __name__ == "__main__":
    main()
