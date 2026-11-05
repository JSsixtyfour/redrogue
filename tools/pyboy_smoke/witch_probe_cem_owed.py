"""Where does PCemPlaceStageEventNpcs put the pair in each stage-event phase, on its hideout floor?
An OWED villain still holds the player's goods and has to stay reachable.

  wsl bash .../witch_probe.sh witch_probe_cem_owed.py
"""
import json
import sys
from pathlib import Path

from audit_stage_hideout_partner import stage_const
from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    evidence = Path(sys.argv[1]) / "probe_cem_owed"
    evidence.mkdir(parents=True, exist_ok=True)
    maps = parse_map_constants(ROOT / "constants/map_constants.asm")
    floors = [maps[f"PROCEDURAL_CEMETERY_{n}"] for n in (1, 2, 3, 4)]
    shift = stage_const("STAGE_EVENT_PHASE_SHIFT")
    h = RedRogueHarness(ROOT, evidence)
    h.boot_to_lobby()
    h.write8("wStageEvent", stage_const("STAGE_EVENT_JESSIE_JAMES") | (1 << shift))
    h.preload_and_enter_wild_area(floors[0], "Procedural Cemetery 1")
    h.tick(60)
    rolled = h.read_sram_bytes("sStageEventHideoutFloor", 1, bank=0)[0]
    h.park_before_hijack()
    h.write8("hCurMap", floors[rolled])
    h.call_routine("PCemFinalizeMap", limit=200000)
    cell = (h.read_sram_bytes("sStageEventHideoutX", 1, bank=0)[0], h.read_sram_bytes("sStageEventHideoutY", 1, bank=0)[0])
    print(json.dumps({"rolled_floor": rolled, "hideout_block": cell}), flush=True)
    flags = h.address("wStatusFlags4")
    for name in ("HIDING", "SETTLED", "OWED"):
        h.write8("wStageEvent", stage_const("STAGE_EVENT_JESSIE_JAMES") | (stage_const(f"STAGE_EVENT_PHASE_{name}") << shift))
        h.write8("wSprite02StateData2MapY", 0x77)
        h.write8("wSprite02StateData2MapX", 0x77)
        h.pyboy.memory[flags] &= ~(1 << 3) & 0xFF if False else 0xFF
        h.park_before_hijack()
        h.write8("hCurMap", floors[rolled])
        h.call_routine("PCemPlaceStageEventNpcs", limit=20000)
        y, x = h.read8("wSprite02StateData2MapY"), h.read8("wSprite02StateData2MapX")
        where = "untouched" if (y, x) == (0x77, 0x77) else "parked off the map" if (y, x) == (0, 0) else f"step ({x - 4},{y - 4})"
        print(json.dumps({"phase": name, "slot_2": where, "at_hideout": (x - 4, y - 4) == (cell[0] * 2, cell[1] * 2)}), flush=True)
    h.close()


if __name__ == "__main__":
    main()
