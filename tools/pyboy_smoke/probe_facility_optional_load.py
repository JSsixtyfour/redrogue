"""The Facility optional encounter's true rate and load cost, measured.

Rate: real Facility generations with production odds; how many got the encounter,
and where. Load: player-visible frames from WarpFound2 to the first JoypadOverworld
after EnterMap (reference_load_time_measurement), for a fresh Facility with and
without its search.

    python3 tools/pyboy_smoke/probe_facility_optional_load.py [--layouts 300]
"""
from __future__ import annotations

import argparse
import io
from collections import Counter
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_facility_subroom as fs  # noqa: E402
from source_constants import parse_rgbds_constants  # noqa: E402

RAM = parse_rgbds_constants(fs.ROOT / "constants/ram_constants.asm")


class Probe(fs.FacilitySuperNerdTest):
    def runTest(self):
        pass


def rate(layouts):
    p = Probe()
    p.setUp()
    h = p.h
    try:
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        h.write8("wStatusFlags6", h.read8("wStatusFlags6") & ~(1 << RAM["BIT_DEBUG2_MODE"]))
        lobby = io.BytesIO()
        h.save_state(lobby)
        pads = encounters = 0
        where = Counter()
        seeds = random.Random(20261105)
        for seed in range(layouts):
            h.load_state(lobby)
            # Independent seeds. Arithmetic ones walk correlated RNG states and misread
            # the rate (measured 5.0% and 21.4% on the same code; these give 8.8%).
            h.seed_rng((seeds.randrange(256), seeds.randrange(256), seeds.randrange(256), seeds.randrange(256)))
            h.preload_and_enter_wild_area(p.maps["PROCEDURAL_FACILITY"], "facility")
            pads += p.subroom_pad() < len(fs.PAD_SITES)
            where[h.read8("wOptionalEncounterMap")] += 1
            if h.read8("wOptionalEncounterSpecies"):
                encounters += 1
        facility = where[p.maps["PROCEDURAL_FACILITY"]]
        print(f"{layouts} Facilities: {pads} with a warp room ({100 * pads / layouts:.1f}%), "
              f"{encounters} with the encounter ({100 * encounters / layouts:.1f}%), "
              f"{facility} in the Facility, {where[p.maps['PROCEDURAL_FACILITY_SUBROOM']]} in the warp room")
    finally:
        h.close()


def fresh_load(layouts):
    """A fresh Facility's load, same layout, encounter off and on (Debug 2's palette
    fixture, whose search is the costliest path). Same seed, same RNG up to the bake."""
    p = Probe()
    p.setUp()
    h = p.h
    try:
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        lobby = io.BytesIO()
        h.save_state(lobby)
        seeds = random.Random(11)
        rows = []
        context = {}
        h.register_hook("OptionalFacilityAssignEncounter", lambda _: h.pyboy.memory.__setitem__(
            h.address("sProcFacilityPalette"), context["palette"]))
        spans, start = [], {}
        h.register_hook("WarpFound2", lambda _: start.__setitem__("at", h.pyboy.frame_count))

        def overworld(_):
            if "at" in start:
                spans.append(h.pyboy.frame_count - start.pop("at"))

        h.register_hook("JoypadOverworld", overworld)
        for _ in range(layouts):
            seed = tuple(seeds.randrange(256) for _ in range(4))
            row = []
            for palette in (0, 1):
                h.load_state(lobby)
                h.seed_rng(seed)
                context["palette"] = palette
                spans.clear()
                start.clear()
                h.preload_and_enter_wild_area(p.maps["PROCEDURAL_FACILITY"], "facility")
                h.tick(60)
                row.append(spans[-1] if spans else None)
            rows.append(row)
        print("fresh Facility load frames [off, on]:", rows)
    finally:
        h.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--layouts", type=int, default=300)
    args = ap.parse_args()
    fresh_load(8)
    rate(args.layouts)


if __name__ == "__main__":
    main()
