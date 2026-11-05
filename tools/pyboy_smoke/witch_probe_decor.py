"""Replay one Endless campaign seed and report how the blocks around a point changed through
the facility generator's final passes, for the generation that ran in a frame window.

  wsl bash .../witch_probe.sh witch_probe_decor.py <seed> <from> <to> <block_x> <block_y>
"""
import json
import os
import sys
from pathlib import Path

import witch_autoplay as wa

PASSES = ("PFacCarveEdgeOpenings", "PFacApplyDoorJambs", "PFacRemoveIsolatedGeneratedCorners",
          "PFacNormalizeReversedCorners", "PFacApplyWallEndCaps", "PFacApplyCornerCaps", "PFacRemoveStrandedJambs",
          "PFacPlaceSpinnerDecor", "PFacPlaceLargeDecor", "PFacPlaceItems", "PFacDecorateExploreRooms",
          "PFacPlaceFakeBalls", "PFacDecorateCorridorWalls", "PFacPickHideout", "PFacPlacePads")
BASE, STRIDE = 81, 26


def main() -> None:
    evidence = Path(sys.argv[1]) / "probe_decor"
    seed, start, stop, bx, by = (int(a) for a in sys.argv[2:7])
    evidence.mkdir(parents=True, exist_ok=True)
    original_init = wa.CampaignAgent.__init__
    previous = {}

    def init(self, harness, **kwargs):
        original_init(self, harness, **kwargs)
        h = harness

        def grab():
            origin = h.address("wOverworldMap") + BASE
            return [[h.pyboy.memory[origin + y * STRIDE + x] for x in range(bx - 4, bx + 5)]
                    for y in range(by - 3, by + 3)]

        def tracer(label):
            def hook(_context) -> None:
                frame = h.pyboy.frame_count
                if not start <= frame <= stop:
                    if frame > stop:
                        os._exit(0)
                    return
                now = grab()
                if now != previous.get("grid"):
                    print(f"-- before {label} (frame {frame}), x {bx - 4}..{bx + 4}, y {by - 3}..{by + 2}", flush=True)
                    for y, row in enumerate(now):
                        print(f"   y={by - 3 + y:2} " + " ".join(f"{b:3}" for b in row), flush=True)
                    previous["grid"] = now
            return hook

        for label in PASSES:
            h.register_hook(label, tracer(label))

    wa.CampaignAgent.__init__ = init
    options = {"rom": "pokeblue_debug", "evidence": str(evidence), "stages": 300, "max_frames": 2500000,
               "stall_frames": 20000, "strong": True, "difficulty": "VERY_EASY", "endless_stages": 60,
               "endless_reset_prizes": False}
    wa.run_campaign_seed(seed, options)


if __name__ == "__main__":
    main()
