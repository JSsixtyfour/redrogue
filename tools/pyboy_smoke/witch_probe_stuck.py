"""Replay one Endless campaign seed up to a frame, then report what the agent has been
doing: every stall-watchdog marker change and map change after `watch_from`.

  wsl bash .../witch_probe.sh witch_probe_stuck.py <seed> <watch_from> <stop_at> [difficulty]
"""
import collections
import json
import os
import sys
from pathlib import Path

import witch_autoplay as wa


def main() -> None:
    evidence = Path(sys.argv[1]) / "probe_stuck"
    seed, watch_from, stop_at = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    difficulty = sys.argv[5] if len(sys.argv) > 5 else "VERY_EASY"
    evidence.mkdir(parents=True, exist_ok=True)
    original_init = wa.CampaignAgent.__init__
    original_note = wa.CampaignAgent.note_progress
    changes: collections.deque = collections.deque(maxlen=12)
    first: list = []
    maps: collections.Counter = collections.Counter()
    fields = ("stages", "warps", "won", "unbeaten", "talked", "choices", "healed", "blackouts", "count", "party",
              "runs", "in_battle", "enemy_hp_hi", "enemy_hp_lo")
    state: dict = {"marker": None, "map": None, "changed": collections.Counter()}

    def wanted_map(agent) -> int:
        return agent.h.read8("hCurMap") if len(sys.argv) <= 6 else int(sys.argv[6])

    def note(self) -> None:
        original_note(self)
        h = self.h
        frame = h.pyboy.frame_count
        if frame < watch_from or not self.game_world_reads_ready():
            return
        current = h.read8("hCurMap")
        if current != state["map"]:
            state["map"] = current
            maps[self.map_name(current)] += 1
        marker = self.progress_marker
        if marker != state["marker"]:
            if state["marker"] is not None:
                diff = {fields[i] if i < len(fields) else str(i): (state["marker"][i], marker[i])
                        for i in range(min(len(marker), len(state["marker"]))) if marker[i] != state["marker"][i]}
                state["changed"].update(diff.keys())
                change = {"frame": frame, "map": self.map_name(current), "pos": self.position(), "diff": diff}
                changes.append(change)
                if len(first) < 70:
                    first.append(change)
            state["marker"] = marker
        if frame >= stop_at and self.mode() == "overworld" and current == wanted_map(self):
            grid = self.read_grid()
            width, height = self.map_size()
            here = self.position()
            sprites = self.sprites()
            occupied = {(s["x"], s["y"]): slot for slot, s in sprites.items()}
            warps = {(x, y): dest for y, x, _, dest in h.warp_entries()}
            rows = []
            for y in range(height):
                row = ""
                for x in range(width):
                    if (x, y) == here:
                        row += "@"
                    elif (x, y) in occupied:
                        row += "S"
                    elif (x, y) in warps:
                        row += "W"
                    else:
                        row += "." if grid.walkable(x, y) else "#"
                rows.append(row)
            blocked = self.obstacles()
            paths = {}
            for goal in self.exit_goals():
                spots = dict(goal.spots)
                with_block = wa.autoplay.world.find_path(grid, here, spots, blocked, enter_impassable_goals=True)
                without = wa.autoplay.world.find_path(grid, here, spots, set(), enter_impassable_goals=True)
                paths[str(sorted(spots))] = {"blocked_len": len(with_block) if with_block else None,
                                             "free_len": len(without) if without else None}
            print("\n".join(rows), flush=True)
            import audit_stage_pair_blocks_exit as audit
            blockset = (audit.REPO_ROOT / "gfx/blocksets/facility.bst").read_bytes()
            model = audit.walkable_grid(
                [[h.pyboy.memory[h.address("wOverworldMap") + audit.GRID_BASE + y * audit.GRID_STRIDE + x]
                  for x in range(audit.GRID_SIZE)] for y in range(audit.GRID_SIZE)],
                blockset, audit.passable_tiles("Facility_Coll"))
            pair = {(sprites[10]["x"], sprites[10]["y"]), (sprites[11]["x"], sprites[11]["y"])}
            exit_step = (39, 18)
            print(json.dumps({"control_exit_reached_free": audit.touches(audit.flood(model, here, {}, set()), exit_step),
                              "control_exit_reached_with_pair": audit.touches(audit.flood(model, here, {}, pair), exit_step),
                              "hideout_now": h.read_sram_bytes("sStageEventHideoutX", 1, bank=0)
                              + h.read_sram_bytes("sStageEventHideoutY", 1, bank=0),
                              "rooms": [list(h.read_sram_bytes("sProcFacilityGenScratch", 4, bank=1, offset=4 * i))
                                        if False else None for i in range(0)],
                              "picks": picks[-8:], "stage_event_now": h.read8("wStageEvent")}, default=str), flush=True)
            print(json.dumps({"exit_paths": paths, "sprites": {str(k): v for k, v in sprites.items()},
                              "headers": {str(k): v for k, v in self.trainer_header_slots().items()},
                              "pads": {str(k): v for k, v in self.warp_pads().items()},
                              "arrows": {str(k): v for k, v in self.arrow_tiles().items()},
                              "blocked_steps": {str(k): v for k, v in self.blocked_steps.items()},
                              "script_steps": {str(k): v for k, v in self.script_steps.items()}},
                             default=str), flush=True)
            print(json.dumps({"frame": frame, "map": self.map_name(current), "position": self.position(),
                              "mode": self.mode(), "marker": list(marker),
                              "marker_fields_changed": dict(state["changed"]), "maps_entered": dict(maps),
                              "first_changes": first, "changes": list(changes),
                              "exit_goals": [str(g) for g in self.exit_goals()][:12],
                              "visited_low": h.read_bytes("wVisitedStagesBitfield", 4), "talked": sorted(map(str, self.talked))[:40],
                              "unbeaten": [str(t) for t in self.unbeaten_trainers()][:20],
                              "stage_event": h.read8("wStageEvent"), "depth": h.read8("wEndlessDepth"),
                              "battle_count": h.read8("wBattleCount"), "rogue_flags": h.read8("wRogueFlagsBitfield"),
                              "challenge": h.read8("wWitchChallenge"),
                              "events": [json.dumps(e, default=str)[:220] for e in self.report.events[-25:]]},
                             default=str), flush=True)
            h.write_failure_artifacts(f"probe_stuck_{seed}")
            os._exit(0)

    picks: list = []

    def init(self, harness, **kwargs):
        original_init(self, harness, **kwargs)
        h = harness

        def on_pick(_context) -> None:
            if h.pyboy.frame_count >= watch_from - 60000:
                memory = h.pyboy.memory
                picks.append({"frame": h.pyboy.frame_count, "map": h.read8("hCurMap"),
                              "stage_event": h.read8("wStageEvent"), "rogue_map": h.read8("wRogueMap"),
                              "hideout": [memory[h.address("sStageEventHideoutX")],
                                          memory[h.address("sStageEventHideoutY")]],
                              "floor": memory[h.address("sStageEventHideoutFloor")]})

        h.register_hook("PFacPickHideout.restoreBank", on_pick)

    wa.CampaignAgent.__init__ = init
    wa.CampaignAgent.note_progress = note
    options = {"rom": "pokeblue_debug", "evidence": str(evidence), "stages": 300, "max_frames": 2500000,
               "stall_frames": 20000, "strong": True, "difficulty": difficulty, "endless_stages": 60,
               "endless_reset_prizes": False}
    row = wa.run_campaign_seed(seed, options)
    print(json.dumps({"finished_early": row["outcome"], "stages": row["stages"], "frames": row["frames"]}), flush=True)


if __name__ == "__main__":
    main()
