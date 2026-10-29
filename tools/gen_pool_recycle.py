#!/usr/bin/env python3
"""Regenerate data/events/pool_recycle.asm: what a recycled content pool resets.

Why this exists
---------------
A run normally visits each stage route and each gift room at most once, because
both pools keep a no-repeat history (wVisitedStagesBitfield, the bridge offered
mask) and a run is too short to exhaust either. Endless mode keeps that history
across circuits, so both pools run out MID-circuit, clear their history, and
can offer a map the player already cleared earlier in the same circuit, while
that map's trainer, reward and script state is still set from the first visit.

So when a pool's history clears, every map in the pool is put back to the state
a fresh run gives it: the run-scoped events its scripts own are cleared and its
map script bytes are zeroed (custom_functions/endless.asm, RecycleStagePool /
RecycleBridgePool). This script decides which events those are.

Classification
--------------
For each pool, every ZONE 1 event referenced by one of the pool's map scripts
is either
  RECYCLE  every reference is inside the pool's own scripts, or the event is
           listed in EXTRA_OK for that pool with the reason it is still safe, or
  KEEP     listed in KEEP for that pool with the reason it must survive.
Anything else is an error: a new event shared between a pool map and other
code must be classified here by hand before the build can include it.

Usage:  python3 tools/gen_pool_recycle.py [--check]
"""

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_event_constants as gec  # noqa: E402  (scrape helpers only)

ROOT = gec.ROOT
OUT_REL = "data/events/pool_recycle.asm"
OUT = os.path.join(ROOT, OUT_REL)
EVENTS = os.path.join(ROOT, "constants", "event_constants.asm")

# Maps a stage warps into without returning to the lobby are part of that stage.
CLOSURE_STOP = {"INDIGO_PLATEAU_LOBBY", "ROGUE_MAP", "LAST_MAP", "WARP_NO_RETURN"}

POOLS = [
    # name, label prefix, (table file, start marker, stop marker), follow warps
    ("STAGE", "StagePool",
     ("custom_functions/random_stage_selection.asm", "RogueStageMapTable:", "GymMapByBadge:"),
     True),
    ("BRIDGE", "BridgePool",
     ("custom_functions/bridge_selection.asm", "BridgeRoomMaps:", "DEF NUM_BRIDGE_ROOMS"),
     False),
]

ENTER_ROOM = {"EVENT_ENTER_ROOM": "per-visit: reset on every warp (home/overworld.asm)"}

KEEP = {
    "STAGE": dict(ENTER_ROOM, **{
        "EVENT_GOT_ROGUE_POKEMON": "per-visit: reset by each stage's entry script",
        "EVENT_ROGUE_POKEMON_OFFERED": "per-visit: reset by each stage's entry script",
        # Route 25 reads Bill's House state for its Bill sprites. That state is
        # the BRIDGE pool's, recycled with Bill's House, never with Route 25.
        "EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING": "Bill's House state (BRIDGE pool)",
        "EVENT_MET_BILL_2": "Bill's House state (BRIDGE pool)",
        "EVENT_BILL_SAID_USE_CELL_SEPARATOR": "Bill's House state (BRIDGE pool)",
    }),
    "BRIDGE": dict(ENTER_ROOM, **{
        "EVENT_BRIDGE_RECEIVE_GIFT": "per-visit: reset by each gift room's entry script",
        # Oak's Lab is also the starter room. EndlessContinue keeps these so the
        # starter and intro never replay in a run that is not new.
        "EVENT_GOT_STARTER": "starter state, kept by EndlessContinue",
        "EVENT_ESTABLISHED_STARTER": "starter state, kept by EndlessContinue",
        "EVENT_BATTLED_RIVAL_IN_OAKS_LAB": "starter state, kept by EndlessContinue",
        "EVENT_BRIDGE_INTRO": "kept by EndlessContinue; rooms reset it on entry",
    }),
}

EXTRA_OK = {
    "STAGE": {
        "EVENT_MANSION_SWITCH_ON": "other readers are Mansion floors no stage reaches",
        "EVENT_RESCUED_MR_FUJI": "Tower 7F's rescue; Lavender Mart only reads it",
    },
    "BRIDGE": {
        "EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING": "Bill's PC mode; Route 25 only reads it",
        "EVENT_MET_BILL_2": "Bill's cutscene; Route 25 only reads it",
        "EVENT_BILL_SAID_USE_CELL_SEPARATOR": "Bill's cutscene; read by his PC and Route 25",
        "EVENT_USED_CELL_SEPARATOR_ON_BILL": "Bill's cutscene; read by his PC",
        "EVENT_MET_BILL": "only picks the 'sent to Bill's PC' wording",
    },
}


def run_events():
    """ZONE 1 event names, in file order."""
    text = gec.read(EVENTS)
    zone = text[text.index("DEF RUN_EVENTS_START"):text.index("DEF RUN_EVENTS_END")]
    return re.findall(r"^DEF (EVENT_[A-Z0-9_]+)\s+EQU", zone, re.M)


def map_scripts():
    """map constant -> script file base name, from the map headers."""
    out = {}
    hd = os.path.join(ROOT, "data/maps/headers")
    for fn in os.listdir(hd):
        if fn.endswith(".asm"):
            m = re.search(r"map_header\s+(\w+),\s*(\w+)", gec.read(os.path.join(hd, fn)))
            if m:
                out[m.group(2)] = m.group(1)
    return out


def pool_maps(table, follow):
    maps = gec.table_seeds(*table)
    if not follow:
        return maps
    warps, conns, _ = gec.scrape_graph()
    seen, queue = set(), list(maps)
    while queue:
        cur = queue.pop()
        if cur in seen or cur in CLOSURE_STOP:
            continue
        seen.add(cur)
        queue.extend(warps.get(cur, set()) | conns.get(cur, set()))
    return seen


def cur_scripts(script_names):
    found = set()
    for name in script_names:
        text = gec.strip_comments(os.path.join(ROOT, "scripts", name + ".asm"))
        found |= set(re.findall(r"\b(w[A-Za-z0-9]+CurScript)\b", text))
    wram = gec.read(os.path.join(ROOT, "ram", "wram.asm"))
    for sym in found:
        if not re.search(r"^%s::" % sym, wram, re.M):
            raise SystemExit("%s is not a WRAM label" % sym)
    return sorted(found)


def classify(pool, script_names, names, refs):
    recycle, touched, errors = [], set(), []
    for name in names:
        paths = {p for p in refs.get(name, set())
                 if not p.startswith("tools/") and p != OUT_REL}
        mine = {p for p in paths if p.startswith("scripts/")
                and os.path.basename(p)[:-4] in script_names}
        if not mine:
            continue
        touched.add(name)
        if name in KEEP[pool]:
            continue
        if paths == mine or name in EXTRA_OK[pool]:
            recycle.append(name)
            continue
        errors.append("%s pool: classify %s (also read by %s)"
                      % (pool, name, ", ".join(sorted(paths - mine))))
    # A stale entry would quietly stop meaning anything; refuse it instead.
    for table in (KEEP[pool], EXTRA_OK[pool]):
        for name in sorted(set(table) - touched):
            errors.append("%s pool: %s is listed but no pool script uses it" % (pool, name))
    return recycle, errors


def build():
    names = run_events()
    refs = gec.scrape_refs(names)
    headers = map_scripts()
    out = [
        "; Recycled-pool preparation (ENDLESS_MODE_CHECKPOINT_A.md, checkpoint C).",
        ";",
        "; GENERATED FILE - DO NOT EDIT BY HAND.",
        ";   regenerate:  python3 tools/gen_pool_recycle.py",
        ";   verify only: python3 tools/gen_pool_recycle.py --check",
        ";",
        "; When a content pool's no-repeat history runs out mid-run, every map in",
        "; the pool goes back to the state a fresh run gives it: the run events its",
        "; scripts own are cleared and its map script bytes are zeroed. KEEP and",
        "; EXTRA_OK in the generator say why each shared event is or is not here.",
        "; INCLUDEd by custom_functions/endless.asm, which defines the macros.",
    ]
    errors = []
    for pool, label, table, follow in POOLS:
        maps = sorted(pool_maps(table, follow))
        missing = [m for m in maps if m not in headers]
        if missing:
            raise SystemExit("%s pool: no map header for %s" % (pool, ", ".join(missing)))
        script_names = {headers[m] for m in maps}
        recycle, errs = classify(pool, script_names, names, refs)
        errors += errs
        out += ["", "; ---- %s pool: %s" % (pool, ", ".join(maps)), "%sEventMask:" % label,
                "\tpool_mask_begin"]
        out += ["\tpool_event %s" % n for n in recycle]
        out += ["\tpool_mask_emit", "", "%sScripts:" % label]
        out += ["\tdw %s" % s for s in cur_scripts(script_names)]
        out += ["\tdw 0"]
    if errors:
        raise SystemExit("\n".join(errors))
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="verify the file on disk matches, write nothing")
    args = ap.parse_args()
    text = build()
    if args.check:
        current = gec.read(OUT) if os.path.exists(OUT) else ""
        if current != text:
            print("OUT OF DATE: %s does not match the generator" % OUT)
            return 1
        print("up to date")
        return 0
    with open(OUT, "w", newline="\n") as fh:
        fh.write(text)
    print("wrote %s" % os.path.relpath(OUT, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
