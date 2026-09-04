#!/usr/bin/env python3
"""Regenerate constants/event_constants.asm as a dense, zoned, byte-budgeted file.

Why this exists
---------------
The hand-maintained file inherited the base disassembly "room to grow" layout:
2623 numbered bits for 634 named events (770 bits of const_skip + 1219 bits of
const_next anchor gaps), i.e. 328 bytes of WRAM0 for 80 bytes of information.
Renumbering by hand is not safe: a dozen consumers depend on exact bit positions
or on runs of events staying contiguous. This script owns the numbering instead,
and emits a build-time ASSERT for every one of those constraints.

Layout
------
  ZONE 0  PERSISTENT_EVENTS_START .. _END   never wiped (intro, ELEMENT PRISM)
  ZONE 1  RUN_EVENTS_START .. _END          wiped by one ResetEventRange
  ZONE 2  EVENT_GRAVEYARD_BASE              unreachable maps, aliased/overlapping
          pad to NUM_EVENTS

Usage:  python3 tools/gen_event_constants.py [--check] [--report]
        --check   re-derive and diff against the file on disk, write nothing
        --report  print the classification and byte budget
"""

import argparse
import math
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "constants", "event_constants.asm")

# Total bits the array is pinned to. wEventFlags is `flag_array NUM_EVENTS`,
# so this is exactly NUM_EVENTS/8 bytes of WRAM0. Raise it only deliberately.
NUM_EVENTS = 512

# ---------------------------------------------------------------------------
# TABLE 1 - events to delete outright.
#
# Every name here must be referenced by nothing in the assembled tree (comments
# stripped); the generator verifies that and refuses otherwise. Deleting one is
# worth exactly 1 bit, so this list is about tidiness, not WRAM. To cut more
# later: add the name, re-run, `make`. The build says immediately if a name was
# secretly load-bearing.
# ---------------------------------------------------------------------------
DELETE = [
# ----------------------------------------------------------------------------
# POTENTIAL REMOVALS (not applied - flagged 2026-09-03, needs real feature
# deletion, not just a constant delete). Each is still referenced by live game
# code; cutting the event means cutting the code path it drives:
#   EVENT_GOT_POKEDEX, EVENT_DAISY_WALKING, EVENT_GOT_TOWN_MAP,
#   EVENT_ENTERED_BLUES_HOUSE, EVENT_PALLET_AFTER_FIRST_RUN,
#   EVENT_HALL_OF_FAME_DEX_RATING        - Pallet/Oak's Lab intro chain
#   EVENT_FIGHT_ROUTE12_SNORLAX, EVENT_FIGHT_ROUTE16_SNORLAX,
#   EVENT_BEAT_ROUTE12_SNORLAX, EVENT_BEAT_ROUTE16_SNORLAX
#                                         - largely vestigial already: the
#                                           Route12/16 scripts that would ever
#                                           SET the BEAT_ flag are commented
#                                           out, so the "already beaten" gate
#                                           can never trigger; only the Poke
#                                           Flute's write side survives
#                                           (engine/items/item_effects_pokeflute.asm)
#   EVENT_IN_SAFARI_ZONE, EVENT_SAFARI_GAME_OVER  - Safari Zone
#   EVENT_GAVE_FOSSIL_TO_LAB, EVENT_LAB_STILL_REVIVING_FOSSIL - Cinnabar Lab fossil revival
#   EVENT_GOT_SS_TICKET                  - Route 25 / Bill's house SS Ticket
#   EVENT_ROUTE22_RIVAL_WANTS_BATTLE     - Route 22 rival gate (checked from ViridianGym)
#   EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1/2,
#   EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH1
#                                         - CAUTION: boulder puzzles on the
#                                           mandatory path to Elite 4. A wrong
#                                           cut here risks a softlock.
#   EVENT_BEAT_SILPH_CO_GIOVANNI         - referenced only by dead Silph Co
#                                           floors' scripts + bench_guys.asm;
#                                           check bench_guys.asm's own liveness
#                                           before cutting
#   EVENT_FOUND_ROCKET_HIDEOUT           - GameCorner.asm (live map)
# Revisit only if there is a reason to (WRAM pressure isn't one - each cut is
# worth 1 bit now, the array is pinned at 64 B either way).
# ----------------------------------------------------------------------------
    "EVENT_BEAT_CELADON_GYM_TRAINER_4",
    "EVENT_BEAT_CELADON_GYM_TRAINER_5",
    "EVENT_BEAT_CELADON_GYM_TRAINER_6",
    "EVENT_BEAT_MT_MOON_1_TRAINER_5",
    "EVENT_BEAT_MT_MOON_1_TRAINER_6",
    "EVENT_BEAT_POKEMON_TOWER_RIVAL",
    "EVENT_BEAT_POWER_PLANT_VOLTORB_0",
    "EVENT_BEAT_POWER_PLANT_VOLTORB_1",
    "EVENT_BEAT_POWER_PLANT_VOLTORB_2",
    "EVENT_BEAT_POWER_PLANT_VOLTORB_3",
    "EVENT_BEAT_POWER_PLANT_VOLTORB_4",
    "EVENT_BEAT_POWER_PLANT_VOLTORB_5",
    "EVENT_BEAT_POWER_PLANT_VOLTORB_6",
    "EVENT_BEAT_POWER_PLANT_VOLTORB_7",
    "EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_5",
    "EVENT_BEAT_ROCK_TUNNEL_1_TRAINER_6",
    "EVENT_BEAT_ROUTE_12_TRAINER_5",
    "EVENT_BEAT_ROUTE_12_TRAINER_6",
    "EVENT_BEAT_ROUTE_13_TRAINER_5",
    "EVENT_BEAT_ROUTE_13_TRAINER_6",
    "EVENT_BEAT_ROUTE_13_TRAINER_7",
    "EVENT_BEAT_ROUTE_13_TRAINER_8",
    "EVENT_BEAT_ROUTE_13_TRAINER_9",
    "EVENT_BEAT_ROUTE_15_TRAINER_5",
    "EVENT_BEAT_ROUTE_15_TRAINER_6",
    "EVENT_BEAT_ROUTE_15_TRAINER_7",
    "EVENT_BEAT_ROUTE_15_TRAINER_8",
    "EVENT_BEAT_ROUTE_15_TRAINER_9",
    "EVENT_BEAT_ROUTE_17_TRAINER_5",
    "EVENT_BEAT_ROUTE_17_TRAINER_6",
    "EVENT_BEAT_ROUTE_17_TRAINER_7",
    "EVENT_BEAT_ROUTE_17_TRAINER_8",
    "EVENT_BEAT_ROUTE_17_TRAINER_9",
    "EVENT_BEAT_ROUTE_25_TRAINER_5",
    "EVENT_BEAT_ROUTE_25_TRAINER_6",
    "EVENT_BEAT_ROUTE_25_TRAINER_7",
    "EVENT_BEAT_ROUTE_25_TRAINER_8",
    "EVENT_BEAT_ROUTE_3_TRAINER_5",
    "EVENT_BEAT_ROUTE_3_TRAINER_6",
    "EVENT_BEAT_ROUTE_3_TRAINER_7",
    "EVENT_BEAT_ROUTE_6_TRAINER_5",
    "EVENT_BEAT_ROUTE_9_TRAINER_5",
    "EVENT_BEAT_ROUTE_9_TRAINER_6",
    "EVENT_BEAT_ROUTE_9_TRAINER_7",
    "EVENT_BEAT_ROUTE_9_TRAINER_8",
    "EVENT_BEAT_SAFFRON_GYM_TRAINER_4",
    "EVENT_BEAT_SAFFRON_GYM_TRAINER_5",
    "EVENT_BEAT_SAFFRON_GYM_TRAINER_6",
    "EVENT_BEAT_SS_ANNE_10_TRAINER_5",
    "EVENT_BEAT_VIRIDIAN_GYM_TRAINER_4",
    "EVENT_BEAT_VIRIDIAN_GYM_TRAINER_5",
    "EVENT_BEAT_VIRIDIAN_GYM_TRAINER_6",
    "EVENT_BEAT_VIRIDIAN_GYM_TRAINER_7",
    "EVENT_BEAT_ZAPDOS",
    "EVENT_ENTERED_ROCKET_HIDEOUT",
    "EVENT_FOLLOWED_OAK_INTO_LAB",
    "EVENT_GAVE_GOLD_TEETH",
    "EVENT_GOT_10_COINS",
    "EVENT_GOT_20_COINS",
    "EVENT_GOT_20_COINS_2",
    "EVENT_GOT_BIKE_VOUCHER",
    "EVENT_GOT_HM04",
    "EVENT_GOT_POKE_FLUTE",
    "EVENT_GOT_POTION_SAMPLE",
    "EVENT_LAB_HANDING_OVER_FOSSIL_MON",
    "EVENT_OAK_ASKED_TO_CHOOSE_MON",
    "EVENT_POKEMON_TOWER_RIVAL_ON_LEFT",
    "EVENT_SEAFOAM1_BOULDER1_DOWN_HOLE",
    "EVENT_SEAFOAM1_BOULDER2_DOWN_HOLE",
    "EVENT_SILPH_CO_RECEPTIONIST_AT_DESK",
    # SILPH_CO_1F trainer block - confirmed 2026-09-03 pure UNREF (no
    # scripts/SilphCo1F.asm trainer block exists; SILPH_CO_1F was also removed
    # from EXTRA_SEEDS the same pass, but these were unreferenced regardless).
    "EVENT_BEAT_SILPH_CO_1F_TRAINER_0",
    "EVENT_BEAT_SILPH_CO_1F_TRAINER_1",
    "EVENT_BEAT_SILPH_CO_1F_TRAINER_2",
    "EVENT_BEAT_SILPH_CO_1F_TRAINER_3",
    "EVENT_BEAT_SILPH_CO_1F_TRAINER_4",
]

# ---------------------------------------------------------------------------
# TABLE 2 - ZONE 0. Events that must survive a blackout and the Hall of Fame.
# Everything else that is still live becomes run-scoped and is cleared by
# RogueResetRunState.
# ---------------------------------------------------------------------------
PERSISTENT = [
    # Intro / one-time story state
    "EVENT_FIRST_RUN",
    "EVENT_PALLET_AFTER_FIRST_RUN",
    "EVENT_DAISY_WALKING",
    "EVENT_ENTERED_BLUES_HOUSE",
    "EVENT_GOT_TOWN_MAP",
    "EVENT_GOT_POKEDEX",
    # EVENT_ESTABLISHED_STARTER / EVENT_GOT_STARTER / EVENT_BATTLED_RIVAL_IN_OAKS_LAB
    # moved to run-scoped 2026-09-03 per user audit - OaksLab is never re-entered
    # after the intro, so persisting these bought nothing.
    "EVENT_INTRO_TOUR_COMPLETE",
    "EVENT_GAMMA_SHADER",
    "EVENT_HALL_OF_FAME_DEX_RATING",
    # ELEMENT PRISM "only the first time, ever" messages. MUST stay out of the
    # run-scoped range - never being cleared is the whole mechanism.
    # GYM1..GYM8 must also stay contiguous (see CONTIG below).
    "EVENT_PRISM_GYM1_SHOWN",
    "EVENT_PRISM_GYM2_SHOWN",
    "EVENT_PRISM_GYM3_SHOWN",
    "EVENT_PRISM_GYM4_SHOWN",
    "EVENT_PRISM_GYM5_SHOWN",
    "EVENT_PRISM_GYM6_SHOWN",
    "EVENT_PRISM_GYM7_SHOWN",
    "EVENT_PRISM_GYM8_SHOWN",
    "EVENT_PRISM_E4_ICE_SHOWN",
    "EVENT_PRISM_E4_FIGHTING_SHOWN",
    "EVENT_PRISM_E4_GHOST_SHOWN",
    "EVENT_PRISM_E4_DRAGON_SHOWN",
    "EVENT_PRISM_CHAMPION_SHOWN",
]

PERSISTENT_GROUP = "__persistent__"

# ---------------------------------------------------------------------------
# TABLE 3 - runs of events that must stay CONSECUTIVE, beyond the trainer
# blocks scraped from scripts/ (those are handled automatically).
#
#   (owner_map, [names in order], first_offset_or_None, why)
#
# first_offset pins where the run starts inside its owner window; None means
# "wherever it fits". A run may cross a byte boundary - FlagActionPredef and
# Set/ResetEventRange both handle bit indices >= 8 correctly.
# ---------------------------------------------------------------------------
CONTIG = [
    ("CinnabarGym",
     ["EVENT_BEAT_CINNABAR_GYM_TRAINER_%d" % i for i in range(7)], 0,
     "runtime index hGymGateIndex+2 off TRAINER_0 (cinnabar_gym_quiz.asm:106) "
     "and SetEventRange TRAINER_0..TRAINER_6 (CinnabarGym.asm:166)"),
    ("CinnabarGym",
     ["EVENT_CINNABAR_GYM_GATE%d_UNLOCKED" % i for i in range(5)], None,
     "runtime index hBackupGymGateIndex off GATE0 (cinnabar_gym_quiz.asm:92)"),
    ("FuchsiaGym",
     ["EVENT_BEAT_FUCHSIA_GYM_TRAINER_%d" % i for i in range(6)], None,
     "SetEventRange TRAINER_0..TRAINER_5 (FuchsiaGym.asm:96) - slots 4 and 5 "
     "have no trainer but the range needs them"),
    ("VermilionGym",
     ["EVENT_BEAT_VERMILION_GYM_TRAINER_%d" % i for i in range(3)], None,
     "SetEventRange TRAINER_0..TRAINER_2 (VermilionGym.asm:98)"),
    (PERSISTENT_GROUP,
     ["EVENT_PRISM_GYM%d_SHOWN" % i for i in range(1, 9)], None,
     "RogueGymLeaderVictory computes GYM1 + (wGymLeaderNo - 1) at runtime "
     "(element_prism.asm:93)"),
    # --- runs that live inside the graveyard (dead maps, kept correct anyway) -
    ("Route23",
     ["EVENT_PASSED_CASCADEBADGE_CHECK", "EVENT_PASSED_THUNDERBADGE_CHECK",
      "EVENT_PASSED_RAINBOWBADGE_CHECK", "EVENT_PASSED_SOULBADGE_CHECK",
      "EVENT_PASSED_MARSHBADGE_CHECK", "EVENT_PASSED_VOLCANOBADGE_CHECK",
      "EVENT_PASSED_EARTHBADGE_CHECK"], 0,
     "EventFlagBit walks CASCADE..EARTH and indexes EARTHBADGE+1 "
     "(Route23.asm:33,155-191)"),
    ("FightingDojo",
     ["EVENT_BEAT_KARATE_MASTER", "EVENT_BEAT_FIGHTING_DOJO_TRAINER_0",
      "EVENT_BEAT_FIGHTING_DOJO_TRAINER_1", "EVENT_BEAT_FIGHTING_DOJO_TRAINER_2",
      "EVENT_BEAT_FIGHTING_DOJO_TRAINER_3"], 1,
     "SetEventRange BEAT_KARATE_MASTER..TRAINER_3 (FightingDojo.asm:73)"),
]

# ---------------------------------------------------------------------------
# TABLE 4 - pairs read by CheckBothEventsSet / CheckEitherEventSet. Keeping a
# pair inside one byte keeps the small macro path (no push bc / push hl).
# Advisory only, but emitted as an ASSERT so a later layout change is caught.
# ---------------------------------------------------------------------------
SAME_BYTE_PAIRS = [
    ("EVENT_GOT_TOWN_MAP", "EVENT_ENTERED_BLUES_HOUSE"),
    ("EVENT_GOT_HITMONLEE", "EVENT_GOT_HITMONCHAN"),
    ("EVENT_GOT_DOME_FOSSIL", "EVENT_GOT_HELIX_FOSSIL"),
    ("EVENT_SEAFOAM3_BOULDER1_DOWN_HOLE", "EVENT_SEAFOAM3_BOULDER2_DOWN_HOLE"),
    ("EVENT_SEAFOAM4_BOULDER1_DOWN_HOLE", "EVENT_SEAFOAM4_BOULDER2_DOWN_HOLE"),
    ("EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_0",
     "EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_1"),
]

# ---------------------------------------------------------------------------
# TABLE 5 - maps entered by code-patched warps, invisible to the static
# warp/connection graph. Missing one here would wrongly graveyard a live map.
# ---------------------------------------------------------------------------
EXTRA_SEEDS = {
    # hub / final sequence
    "INDIGO_PLATEAU_LOBBY", "SILPH_CO_DORM", "SILPH_CO_B1F", "SILPH_CO_VR",
    "CREDIT_EXCHANGE", "REWARD_ROOM", "HALL_OF_FAME",
    "LORELEIS_ROOM", "BRUNOS_ROOM", "AGATHAS_ROOM", "LANCES_ROOM",
    "CHAMPIONS_ROOM", "VICTORY_ROAD_1F", "VICTORY_ROAD_2F", "VICTORY_ROAD_3F",
    # gyms (GymMapByBadge, random_stage_selection.asm)
    "PEWTER_GYM", "CERULEAN_GYM", "VERMILION_GYM", "CELADON_GYM",
    "FUCHSIA_GYM", "SAFFRON_GYM", "CINNABAR_GYM", "VIRIDIAN_GYM",
    # intro
    "PALLET_TOWN", "OAKS_LAB", "REDS_HOUSE_1F", "REDS_HOUSE_2F",
    # procedural stages
    "PROCEDURAL_CAVE_1", "PROCEDURAL_FACILITY", "PROCEDURAL_FOREST",
    "PROCEDURAL_CEMETERY_1", "PROCEDURAL_CEMETERY_2",
    "PROCEDURAL_CEMETERY_3", "PROCEDURAL_CEMETERY_4",
    # stages commented out of RogueStageMapTable whose events are reserved.
    # SILPH_CO_1F, SS_ANNE_BOW and UNDERGROUND_PATH_ROUTE_5 were REMOVED from this
    # list 2026-09-03 per user audit: SILPH_CO_1F's trainer events turned out to be
    # pure UNREF (no scripts/SilphCo1F.asm trainer block exists, so reserving it
    # bought nothing); SS_ANNE_BOW is commented out of RogueStageMapTable and the
    # user wants it graveyarded like every other unreachable map rather than kept
    # reserved; UNDERGROUND_PATH_ROUTE_5 was never in that table at all - it was a
    # fabricated justification, the map is reachable only through
    # UndergroundPathRoute6 -> UndergroundPathNorthSouth, both themselves
    # unreachable dead ends. Verified: dropping these three strands no other map.
    "SS_ANNE_B1F", "SS_ANNE_B1F_ROOMS",
    "GAME_CORNER", "ROUTE_17", "ROUTE_24",
}

MAP_DIRS = ("scripts", "data/maps/objects", "data/maps/headers", "text")
BAD_WARP = {"LAST_MAP", "WARP_NO_RETURN", "ROGUE_MAP"}


# ---------------------------------------------------------------------------
# Scraping
# ---------------------------------------------------------------------------
def read(path):
    with open(path, errors="ignore") as fh:
        return fh.read()


def strip_comments(path):
    """Event names inside comments are not references."""
    with open(path, errors="ignore") as fh:
        return "\n".join(line.split(";")[0] for line in fh)


# Symbols this file defines that are NOT events. The generator reads its own
# output, so without this the zone marker would be scraped back in as an event
# and then defined twice.
NOT_EVENTS = {"EVENT_GRAVEYARD_BASE"}


def scrape_events():
    """Canonical name list, in current file order."""
    names, seen = [], set()
    for line in open(OUT, errors="ignore"):
        m = re.match(r"\s*(?:const|DEF)\s+(EVENT_[A-Z0-9_]+)", line)
        if m and m.group(1) not in seen and m.group(1) not in NOT_EVENTS:
            seen.add(m.group(1))
            names.append(m.group(1))
    return names


def scrape_trainer_blocks():
    """map -> (def_trainers, [event names in trainer order])"""
    blocks = {}
    sd = os.path.join(ROOT, "scripts")
    for fn in sorted(os.listdir(sd)):
        if not fn.endswith(".asm") or fn.startswith("delete"):
            continue
        text = read(os.path.join(sd, fn))
        trainers = re.findall(r"^\s*trainer\s+(EVENT_[A-Z0-9_]+)", text, re.M)
        if not trainers:
            continue
        dt = re.findall(r"def_trainers(?:\s+(\d+))?", text)
        first = int(dt[0]) if (dt and dt[0]) else 1
        blocks[fn[:-4]] = (first, trainers)
    return blocks


def scrape_graph():
    warps, conns, obj_map = defaultdict(set), defaultdict(set), {}
    od = os.path.join(ROOT, "data/maps/objects")
    for fn in os.listdir(od):
        if not fn.endswith(".asm"):
            continue
        text = read(os.path.join(od, fn))
        m = re.search(r"def_warps_to\s+(\w+)", text)
        name = m.group(1) if m else fn[:-4].upper()
        obj_map[fn[:-4]] = name
        for dest in re.findall(r"warp_event\s+[^,]+,\s*[^,]+,\s*(\w+),", text):
            warps[name].add(dest)
    hd = os.path.join(ROOT, "data/maps/headers")
    for fn in os.listdir(hd):
        if not fn.endswith(".asm"):
            continue
        text = read(os.path.join(hd, fn))
        m = re.search(r"map_header\s+\w+,\s*(\w+),", text)
        if not m:
            continue
        for dest in re.findall(r"connection\s+\w+,\s*\w+,\s*(\w+),", text):
            conns[m.group(1)].add(dest)
    return warps, conns, obj_map


def table_seeds(path, start=None, stop=None):
    text = read(os.path.join(ROOT, path))
    if start:
        text = text[text.index(start):]
    if stop:
        text = text[:text.index(stop)]
    return set(re.findall(r"^\s*db\s+([A-Z][A-Z0-9_]+)", text, re.M))


def reachable_maps():
    warps, conns, obj_map = scrape_graph()
    seeds = set(EXTRA_SEEDS)
    seeds |= table_seeds("custom_functions/random_stage_selection.asm")
    seeds |= table_seeds("custom_functions/bridge_selection.asm",
                         "BridgeRoomMaps:", "DEF NUM_BRIDGE_ROOMS")
    seeds |= table_seeds("custom_functions/wild_area_selection.asm")
    seen, queue = set(), list(seeds)
    while queue:
        cur = queue.pop()
        if cur in seen:
            continue
        seen.add(cur)
        for dest in warps.get(cur, set()) | conns.get(cur, set()):
            if dest not in BAD_WARP and dest not in seen:
                queue.append(dest)
    return seen, obj_map


def scrape_refs(names):
    refs = defaultdict(set)
    nameset = set(names)
    for dirpath, _, files in os.walk(ROOT):
        parts = dirpath.replace("\\", "/").split("/")
        if "tmp" in parts or ".git" in parts or "pyboy_smoke" in parts:
            continue
        for fn in files:
            if not fn.endswith(".asm") or fn.startswith("delete"):
                continue
            path = os.path.join(dirpath, fn)
            if os.path.abspath(path) == os.path.abspath(OUT):
                continue
            for hit in set(re.findall(r"\bEVENT_[A-Z0-9_]+",
                                      strip_comments(path))):
                if hit in nameset:
                    refs[hit].add(
                        os.path.relpath(path, ROOT).replace("\\", "/"))
    return refs


def classify(names, refs, dead_scripts):
    """LIVE / DEADMAP / UNREF per event."""
    out = {}
    for name in names:
        paths = refs.get(name, set())
        if not paths:
            out[name] = "UNREF"
            continue
        verdict = "DEADMAP"
        for path in paths:
            base = os.path.basename(path)[:-4]
            if os.path.dirname(path) in MAP_DIRS and base in dead_scripts:
                continue
            verdict = "LIVE"
            break
        out[name] = verdict
    return out


def owning_map(name, refs):
    """First scripts/ file that references the event, else None."""
    for path in sorted(refs.get(name, set())):
        if path.startswith("scripts/"):
            return os.path.basename(path)[:-4]
    return None


# ---------------------------------------------------------------------------
# Allocation
# ---------------------------------------------------------------------------
class Runs(object):
    """A group of events that must occupy consecutive bits, in order."""

    def __init__(self, names, pinned, why):
        self.names = list(names)
        self.pinned = pinned          # offset inside the owner window, or None
        self.why = why

    def __len__(self):
        return len(self.names)


def build_owner_runs(trainer_blocks):
    """map -> [Runs], merging CONTIG runs that overlap the trainer block."""
    owner = defaultdict(list)
    for name, (first, trainers) in trainer_blocks.items():
        owner[name].append(
            Runs(trainers, first, "def_trainers %d trainer block" % first))
    for map_name, names, pinned, why in CONTIG:
        existing = owner.get(map_name, [])
        merged = False
        for run in existing:
            if set(run.names) & set(names):
                if set(names) <= set(run.names):
                    # Subset (e.g. VermilionGym SetEventRange 0..2 inside a
                    # 4-trainer block). Already guaranteed; record and move on.
                    run.why += "; covers " + why
                elif set(run.names) <= set(names):
                    # Superset (e.g. FuchsiaGym SetEventRange 0..5 over a
                    # 4-trainer block). The CONTIG order is authoritative;
                    # re-anchor so the trainer block keeps def_trainers.
                    shift = names.index(run.names[0])
                    if run.pinned is not None and run.pinned - shift < 0:
                        raise SystemExit(
                            "CONTIG run starts before bit 0: %s" % why)
                    if run.pinned is not None:
                        run.pinned -= shift
                    run.names = list(names)
                    run.why += "; + " + why
                else:
                    raise SystemExit(
                        "CONTIG run partially overlaps a trainer block: %s"
                        % why)
                merged = True
                break
        if not merged:
            owner[map_name].append(Runs(names, pinned, why))
    return owner


def place_window(runs):
    """Lay runs out inside one byte-aligned window. Returns (offsets, size)."""
    offsets, used = {}, set()

    def fits(start, length):
        return all((start + i) not in used for i in range(length))

    for run in sorted(runs, key=lambda r: (r.pinned is None, -len(r))):
        if run.pinned is not None:
            start = run.pinned
            if not fits(start, len(run)):
                raise SystemExit("pinned run collides: %s" % run.why)
        else:
            start = 0
            while not fits(start, len(run)):
                start += 1
        for i, name in enumerate(run.names):
            offsets[name] = start + i
            used.add(start + i)
    size = max(used) + 1 if used else 0
    return offsets, int(math.ceil(size / 8.0)) * 8


def colour_graveyard(dead_order, dead_by_map, owner_runs):
    """Assign each dead event an offset. Events sharing a map must differ;
    events in the same run stay consecutive. Maps overlap each other freely -
    two unreachable maps colliding is harmless by construction."""
    dead_events = set(dead_order)
    maps_of = defaultdict(set)
    for map_name, evs in dead_by_map.items():
        for ev in evs:
            maps_of[ev].add(map_name)

    assigned = {}
    taken = defaultdict(set)          # map -> offsets already used

    def conflict(name, offset):
        return any(offset in taken[m] for m in maps_of[name])

    def commit(name, offset):
        assigned[name] = offset
        for m in maps_of[name]:
            taken[m].add(offset)

    runs = []
    for map_name, rs in owner_runs.items():
        for run in rs:
            if all(n in dead_events for n in run.names):
                runs.append((map_name, run))
    # Longest first: the 10-trainer routes set the graveyard width.
    for _map_name, run in sorted(runs, key=lambda mr: -len(mr[1])):
        if any(n in assigned for n in run.names):
            continue
        start = run.pinned if run.pinned is not None else 0
        while any(conflict(n, start + i) for i, n in enumerate(run.names)):
            start += 1
        for i, name in enumerate(run.names):
            commit(name, start + i)

    # Pairs read by CheckBothEventsSet / CheckEitherEventSet must share a byte
    # so the macro keeps its small single-read path.
    for a, b in SAME_BYTE_PAIRS:
        if a not in dead_events or b not in dead_events:
            continue
        if a in assigned or b in assigned:
            continue
        offset = 0
        while (offset % 8 == 7
               or conflict(a, offset) or conflict(b, offset + 1)):
            offset += 1
        commit(a, offset)
        commit(b, offset + 1)

    for name in dead_order:
        if name in assigned:
            continue
        offset = 0
        while conflict(name, offset):
            offset += 1
        commit(name, offset)
    return assigned


def allocate(names, klass, refs, trainer_blocks, dead_scripts):
    keep = [n for n in names if n not in set(DELETE)]
    persistent = [n for n in PERSISTENT if n in keep]
    dead = [n for n in keep if klass[n] == "DEADMAP"]
    unref_kept = [n for n in keep if klass[n] == "UNREF"]
    live = [n for n in keep
            if klass[n] == "LIVE" and n not in set(persistent)]
    # Kept-but-unreferenced names (reserved stage blocks, runtime-indexed
    # bases) are real run-scoped bits, not graveyard aliases.
    live += unref_kept

    owner_runs = build_owner_runs(trainer_blocks)
    bit, layout, order = 0, {}, []

    # ---- ZONE 0 -----------------------------------------------------------
    zone0_start = bit
    for name in persistent:
        layout[name] = bit
        order.append((name, "ZONE0", None))
        bit += 1
    zone0_end = bit - 1
    bit = int(math.ceil(bit / 8.0)) * 8

    # ---- ZONE 1 -----------------------------------------------------------
    run_start = bit
    placed = set(persistent)
    holes = []
    live_set = set(live)
    for map_name in sorted(owner_runs):
        if map_name == PERSISTENT_GROUP or map_name in dead_scripts:
            continue
        runs = []
        for r in owner_runs[map_name]:
            if not any(n in live_set for n in r.names):
                continue
            done = [n for n in r.names if n in placed]
            if done and len(done) != len(r.names):
                raise SystemExit(
                    "run %s is only partly placed by an earlier map" % r.why)
            if done:
                # Shared with an earlier map (e.g. EVENT_BEAT_PC_BOSS is the
                # sole trainer of all three procedural stages). Already sited;
                # the byte-aligned window guarantees its bit is still
                # def_trainers % 8, which is all the trainer macro asserts.
                continue
            runs.append(r)
        if not runs:
            continue
        offsets, size = place_window(runs)
        for name, off in sorted(offsets.items(), key=lambda kv: kv[1]):
            layout[name] = bit + off
            order.append((name, "ZONE1", map_name))
            placed.add(name)
        holes += [bit + o for o in range(size) if o not in set(offsets.values())]
        bit += size

    # Sorted, not file-order: the generator reads its own output, so the
    # leftover pass must not depend on how the previous run happened to
    # order things, or regeneration would never reach a fixed point and
    # --check could never pass.
    remaining = sorted(n for n in live if n not in placed)
    for name in remaining:
        if holes:
            layout[name] = holes.pop(0)
        else:
            layout[name] = bit
            bit += 1
        order.append((name, "ZONE1", owning_map(name, refs)))
    bit = max(bit, max(layout.values()) + 1)
    bit = int(math.ceil(bit / 8.0)) * 8
    run_end = bit - 1

    # ---- ZONE 2 -----------------------------------------------------------
    grave_base = bit
    dead = sorted(dead)
    dead_by_map = defaultdict(list)
    for name in dead:
        for path in sorted(refs.get(name, set())):
            base = os.path.basename(path)[:-4]
            if os.path.dirname(path) in MAP_DIRS and base in dead_scripts:
                dead_by_map[base].append(name)
    grave = colour_graveyard(dead, dead_by_map, owner_runs)
    for name in dead:
        layout[name] = grave_base + grave[name]
        order.append((name, "ZONE2", owning_map(name, refs)))
    grave_size = (max(grave.values()) + 1) if grave else 0
    bit = grave_base + int(math.ceil(grave_size / 8.0)) * 8

    return {
        "layout": layout, "order": order,
        "zone0": (zone0_start, zone0_end),
        "zone1": (run_start, run_end),
        "grave": (grave_base, grave_size),
        "used_bits": bit, "holes_left": len(holes),
        "persistent": persistent, "live": live, "dead": dead,
    }


# ---------------------------------------------------------------------------
# Emission
# ---------------------------------------------------------------------------
def scrape_mask_groups():
    """Maps whose script folds several trainer bits into ONE byte read:
        ld a, [wEventFlags + (EVENT_..._TRAINER_0 / 8)]
        and  <mask built from 1 << (EVENT % 8)>
    Those trainers must share a byte, which the trainer macro does not check."""
    groups = []
    sd = os.path.join(ROOT, "scripts")
    for fn in sorted(os.listdir(sd)):
        if not fn.endswith(".asm") or fn.startswith("delete"):
            continue
        text = read(os.path.join(sd, fn))
        if "ALL_TRAINERS_MASK EQU" not in text:
            continue
        body = text[text.index("ALL_TRAINERS_MASK EQU"):]
        body = body[:body.index("\n\n")] if "\n\n" in body else body
        members = re.findall(r"(EVENT_[A-Z0-9_]+)\s*%\s*8", body)
        if len(members) > 1:
            groups.append((fn[:-4], members))
    return groups


def bitcomment(bit):
    return "; byte %d bit %d" % (bit // 8, bit % 8)


def emit(alloc, trainer_blocks, reach_count):
    layout = alloc["layout"]
    z0s, z0e = alloc["zone0"]
    z1s, z1e = alloc["zone1"]
    gbase, gsize = alloc["grave"]
    gbytes = int(math.ceil(gsize / 8.0))
    out = []
    w = out.append

    w("; wEventFlags bit flags")
    w(";")
    w("; ==========================================================================")
    w("; GENERATED FILE - DO NOT EDIT BY HAND.")
    w(";   regenerate:  python3 tools/gen_event_constants.py")
    w(";   verify only: python3 tools/gen_event_constants.py --check")
    w(";")
    w("; Three zones, each with explicit bounds:")
    w(";")
    w(";   ZONE 0  PERSISTENT_EVENTS_START .. _END")
    w(";           Survives a blackout AND the Hall of Fame. Intro/story state")
    w(";           plus the ELEMENT PRISM one-time-ever messages, whose whole")
    w(";           mechanism is never being cleared.")
    w(";")
    w(";   ZONE 1  RUN_EVENTS_START .. _END")
    w(";           Everything scoped to one roguelike run. Cleared wholesale by")
    w(";           RogueResetRunState on blackout and at the Hall of Fame - one")
    w(";           ResetEventRange, not a scatter of per-map ResetEvent calls.")
    w(";           Byte-aligned at both ends so that range emits plain")
    w(";           `ld [hli], a` stores and can never clip a neighbouring zone.")
    w(";")
    w(";   ZONE 2  EVENT_GRAVEYARD_BASE ..")
    w(";           Maps that no warp or connection can reach. Their scripts and")
    w(";           object data are still assembled, so the names must exist -")
    w(";           but they are ALIASES onto a shared %d-byte scratch band, and"
      % gbytes)
    w(";           dead maps deliberately overlap each other.")
    w(";")
    w(";           !!! If a map here is ever made reachable again, its events")
    w(";           !!! collide with another dead map - silently, with no build")
    w(";           !!! error. Give it fresh constants first. Reachability is")
    w(";           !!! re-derived on every run of the generator, and --check")
    w(";           !!! fails if the map graph has changed underneath this file.")
    w(";")
    w("; Reachability comes from the warp graph in data/maps/objects, the")
    w("; connection graph in data/maps/headers, and the code-driven destination")
    w("; tables named in TABLE 5 of the generator (rogue stages, gyms, bridge")
    w("; rooms, wild areas). %d maps are reachable." % reach_count)
    w("; ==========================================================================")
    w("")
    w("DEF NUM_EVENTS EQU %d" % NUM_EVENTS)
    w("")

    w("; ==========================================================================")
    w("; ZONE 0 - PERSISTENT (never cleared)")
    w("; ==========================================================================")
    w("DEF PERSISTENT_EVENTS_START EQU %d" % z0s)
    for name, zone, _owner in alloc["order"]:
        if zone != "ZONE0":
            continue
        w("DEF %-44s EQU %4d %s" % (name, layout[name], bitcomment(layout[name])))
    w("DEF PERSISTENT_EVENTS_END   EQU %d" % z0e)
    w("")

    w("; ==========================================================================")
    w("; ZONE 1 - RUN-SCOPED (cleared by RogueResetRunState)")
    w("; ==========================================================================")
    w("DEF RUN_EVENTS_START EQU %d" % z1s)
    current = object()
    zone1 = [o for o in alloc["order"] if o[1] == "ZONE1"]
    for name, _zone, owner in sorted(zone1, key=lambda o: layout[o[0]]):
        if owner != current:
            current = owner
            label = owner if owner else "(engine / cross-map)"
            extra = ""
            if owner in trainer_blocks:
                extra = "  [def_trainers %d, %d trainers]" % (
                    trainer_blocks[owner][0], len(trainer_blocks[owner][1]))
            w("")
            w("; -- %s%s" % (label, extra))
        w("DEF %-44s EQU %4d %s" % (name, layout[name], bitcomment(layout[name])))
    w("")
    w("DEF RUN_EVENTS_END   EQU %d" % z1e)
    w("")

    w("; ==========================================================================")
    w("; ZONE 2 - GRAVEYARD (unreachable maps; aliases, deliberately overlapping)")
    w("; ==========================================================================")
    w("DEF EVENT_GRAVEYARD_BASE EQU %d" % gbase)
    current = object()
    zone2 = [o for o in alloc["order"] if o[1] == "ZONE2"]
    for name, _zone, owner in sorted(zone2,
                                     key=lambda o: (o[2] or "", layout[o[0]])):
        if owner != current:
            current = owner
            w("")
            w("; -- %s (unreachable)" % (owner if owner else "cross-map"))
        w("DEF %-44s EQU EVENT_GRAVEYARD_BASE + %-3d %s"
          % (name, layout[name] - gbase, bitcomment(layout[name])))
    w("")

    w("; ==========================================================================")
    w("; Build-time invariants. Each encodes a consumer that would otherwise")
    w("; break silently on a renumber. The 334 asserts inside the `trainer` macro")
    w("; (macros/scripts/maps.asm) cover trainer bit alignment on top of these.")
    w("; ==========================================================================")
    w("ASSERT PERSISTENT_EVENTS_END < RUN_EVENTS_START")
    w("ASSERT RUN_EVENTS_START % 8 == 0")
    w("ASSERT RUN_EVENTS_END % 8 == 7")
    w("ASSERT EVENT_GRAVEYARD_BASE > RUN_EVENTS_END")
    w("ASSERT EVENT_GRAVEYARD_BASE % 8 == 0")
    w("; ELEMENT PRISM first-time-ever flags must survive the run wipe:")
    w("ASSERT EVENT_PRISM_GYM1_SHOWN < RUN_EVENTS_START")
    w("ASSERT EVENT_PRISM_CHAMPION_SHOWN < RUN_EVENTS_START")
    w("; the whole layout must fit the pinned budget:")
    w("ASSERT EVENT_GRAVEYARD_BASE + %d <= NUM_EVENTS" % gsize)
    w("")
    w("; -- runs that must stay consecutive --")
    for map_name, names, _pin, why in CONTIG:
        names = [n for n in names if n in layout]
        if len(names) < 2:
            continue
        w("; %s: %s" % (map_name, why))
        w("ASSERT %s - %s == %d" % (names[-1], names[0], len(names) - 1))
    for map_name in sorted(trainer_blocks):
        _first, trainers = trainer_blocks[map_name]
        trainers = [t for t in trainers if t in layout]
        if len(trainers) < 2:
            continue
        w("ASSERT %s - %s == %d ; %s trainer block"
          % (trainers[-1], trainers[0], len(trainers) - 1, map_name))
    w("")
    w("; -- trainer runs folded into ONE byte read by an ALL_TRAINERS_MASK --")
    for map_name, members in scrape_mask_groups():
        members = [m for m in members if m in layout]
        if len(members) < 2:
            continue
        w("ASSERT (%s) / 8 == (%s) / 8 ; %s"
          % (members[0], members[-1], map_name))
    w("")
    w("; -- CheckBothEventsSet / CheckEitherEventSet pairs (keeps the small path) --")
    for a, b in SAME_BYTE_PAIRS:
        if a in layout and b in layout:
            w("ASSERT (%s) / 8 == (%s) / 8" % (a, b))
    w("")
    return "\n".join(out) + "\n"


def verify(alloc, trainer_blocks):
    """Evaluate in Python every invariant the generated file asserts, so a bad
    layout fails here with a readable message instead of as `Assertion failed`
    at some line number during the build."""
    layout = alloc["layout"]
    problems = []

    def bit(name):
        return layout[name]

    z1s, z1e = alloc["zone1"]
    gbase, gsize = alloc["grave"]
    if alloc["zone0"][1] >= z1s:
        problems.append("zone 0 overlaps zone 1")
    if z1s % 8 != 0:
        problems.append("RUN_EVENTS_START %d is not byte aligned" % z1s)
    if z1e % 8 != 7:
        problems.append("RUN_EVENTS_END %d is not byte aligned" % z1e)
    if gbase % 8 != 0 or gbase <= z1e:
        problems.append("graveyard base %d misplaced" % gbase)
    for name in ("EVENT_PRISM_GYM1_SHOWN", "EVENT_PRISM_CHAMPION_SHOWN"):
        if name in layout and bit(name) >= z1s:
            problems.append("%s is inside the run-wiped range" % name)

    for map_name, names, _pin, why in CONTIG:
        names = [n for n in names if n in layout]
        if len(names) < 2:
            continue
        span = bit(names[-1]) - bit(names[0])
        if span != len(names) - 1:
            problems.append(
                "%s run not consecutive (span %d, expected %d): %s"
                % (map_name, span, len(names) - 1, why))

    for map_name, (_first, trainers) in sorted(trainer_blocks.items()):
        trainers = [t for t in trainers if t in layout]
        if len(trainers) < 2:
            continue
        span = bit(trainers[-1]) - bit(trainers[0])
        if span != len(trainers) - 1:
            problems.append("%s trainer block not consecutive (span %d, "
                            "expected %d)" % (map_name, span,
                                              len(trainers) - 1))

    for map_name, members in scrape_mask_groups():
        members = [m for m in members if m in layout]
        if len(members) < 2:
            continue
        if bit(members[0]) // 8 != bit(members[-1]) // 8:
            problems.append("%s ALL_TRAINERS_MASK spans two bytes" % map_name)

    for a, b in SAME_BYTE_PAIRS:
        if a in layout and b in layout and bit(a) // 8 != bit(b) // 8:
            problems.append("%s / %s are in different bytes" % (a, b))

    if gbase + gsize > NUM_EVENTS:
        problems.append("layout overflows NUM_EVENTS=%d" % NUM_EVENTS)

    if problems:
        raise SystemExit("layout invariants violated:\n  "
                         + "\n  ".join(problems))


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
def build():
    names = scrape_events()
    if not names:
        raise SystemExit("no EVENT_ constants found in %s" % OUT)
    trainer_blocks = scrape_trainer_blocks()
    seen_maps, obj_map = reachable_maps()

    script_to_map = {}
    for fn in os.listdir(os.path.join(ROOT, "scripts")):
        if fn.endswith(".asm"):
            script_to_map[fn[:-4]] = obj_map.get(fn[:-4])
    dead_scripts = {s for s, mc in script_to_map.items()
                    if mc is None or mc not in seen_maps}

    refs = scrape_refs(names)
    klass = classify(names, refs, dead_scripts)

    # A name is validated only on the run that actually removes it; after that
    # it is gone from the file and cannot be re-checked (the generator reads its
    # own output). Names already absent are a no-op, not an error.
    still_present = [n for n in DELETE if n in names]
    bad = [n for n in still_present if klass.get(n) != "UNREF"]
    if bad:
        raise SystemExit(
            "refusing to delete referenced events:\n  " + "\n  ".join(
                "%s (%s) %s" % (n, klass.get(n, "unknown"),
                                " ".join(sorted(refs.get(n, ()))[:3]))
                for n in bad))


    alloc = allocate(names, klass, refs, trainer_blocks, dead_scripts)

    # self-checks
    live_bits = {}
    for name, zone, _o in alloc["order"]:
        if zone == "ZONE2":
            continue
        bit = alloc["layout"][name]
        if bit in live_bits:
            raise SystemExit("bit %d shared by %s and %s"
                             % (bit, live_bits[bit], name))
        live_bits[bit] = name
    gbase = alloc["grave"][0]
    for bit, name in live_bits.items():
        if bit >= gbase:
            raise SystemExit("%s landed inside the graveyard" % name)
    if alloc["used_bits"] > NUM_EVENTS:
        raise SystemExit("layout needs %d bits, NUM_EVENTS is %d"
                         % (alloc["used_bits"], NUM_EVENTS))
    verify(alloc, trainer_blocks)

    return alloc, trainer_blocks, klass, len(seen_maps), dead_scripts


def report(alloc, klass, dead_scripts, reach_count):
    z1s, z1e = alloc["zone1"]
    gbase, gsize = alloc["grave"]
    counts = {}
    for v in klass.values():
        counts[v] = counts.get(v, 0) + 1
    print("reachable maps        : %d" % reach_count)
    print("unreachable scripts   : %d" % len(dead_scripts))
    print("events LIVE/DEAD/UNREF: %(LIVE)d / %(DEADMAP)d / %(UNREF)d" % counts)
    print("deleted               : %d" % len(DELETE))
    print("zone 0 persistent     : bits %d..%d (%d events)"
          % (alloc["zone0"][0], alloc["zone0"][1], len(alloc["persistent"])))
    print("zone 1 run-scoped     : bits %d..%d (%d bytes, %d holes left)"
          % (z1s, z1e, (z1e - z1s + 1) // 8, alloc["holes_left"]))
    print("zone 2 graveyard      : base %d, %d bits (%d bytes), %d aliases"
          % (gbase, gsize, int(math.ceil(gsize / 8.0)), len(alloc["dead"])))
    print("total bits used       : %d of %d (%d bytes of %d)"
          % (alloc["used_bits"], NUM_EVENTS,
             int(math.ceil(alloc["used_bits"] / 8.0)), NUM_EVENTS // 8))
    print("wEventFlags           : 328 -> %d bytes  (reclaim %d)"
          % (NUM_EVENTS // 8, 328 - NUM_EVENTS // 8))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="verify the file on disk matches, write nothing")
    ap.add_argument("--report", action="store_true",
                    help="print classification and byte budget")
    args = ap.parse_args()

    alloc, trainer_blocks, klass, reach_count, dead_scripts = build()
    text = emit(alloc, trainer_blocks, reach_count)

    if args.report:
        report(alloc, klass, dead_scripts, reach_count)

    if args.check:
        current = open(OUT, errors="ignore").read() if os.path.exists(OUT) else ""
        if current != text:
            print("OUT OF DATE: %s does not match the generator" % OUT)
            return 1
        print("up to date")
        return 0

    with open(OUT, "w", newline="\n") as fh:
        fh.write(text)
    if not args.report:
        report(alloc, klass, dead_scripts, reach_count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
