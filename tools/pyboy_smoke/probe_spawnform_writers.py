"""Which writer leaves a stale wSpawnForm behind for a wild encounter?

Phase 6.5. 2 of 60 forest wild encounters were built with `wSpawnForm = 1` and
genuinely drew a different pic, while the cave saw 0 on all 36.
`Random_Pokemon_Selection_Any` deliberately writes nothing to `wSpawnForm` for
wild mons, and `GetEnemySpawnForm`'s `.wild` branch reads it straight out with
nothing on the wild path clearing it - so a wild mon inherits whatever wrote it
last. This names that writer instead of guessing at it.

WHY THE PREVIOUS PROBE DID NOT COUNT. The 2026-09-16 attempt hooked the same
writers but delimited battles by polling, and its loop re-counted a single battle
14 times while `LoadEnemyMonData` fired once. Nothing could be read from it in
either direction, and the defect was in the delimiting, not the hooks. So here:

  * `LoadEnemyMonData` is the delimiter and the ONLY delimiter. One hook hit is
    one enemy build. No dedupe, no inferred boundaries, no polling.
  * Every write site appends `(site, value in A)` to one shared list, in
    execution order, interleaved with the delimiters. The result is a stream, not
    a set of per-site counters, so "what happened last before this build" is
    directly readable rather than reconstructed.
  * The verdict is computed, not eyeballed: for each delimiter where `wSpawnForm`
    was nonzero, report the last write that preceded it.

The hooks are on temporary local labels inserted before each `ld [wSpawnForm], a`
by `spawnform_probe_labels.py`. Labels emit no bytes, so nothing moves. Run that
script (and rebuild) before this one; any probe missing from the .sym is reported
and skipped rather than silently ignored - two of them, in
`IF FORCE_TRAINER_FORM_TEST` / `IF FORCE_WILD_FORM_TEST` blocks, are legitimately
absent because that code is not assembled at all.

Usage:
    python3 tools/pyboy_smoke/spawnform_probe_labels.py        # insert labels
    make
    python3 tools/pyboy_smoke/probe_spawnform_writers.py --stage forest --boots 6
    python3 tools/pyboy_smoke/spawnform_probe_labels.py --remove

Always exits 0: this is a measurement, not a contract.
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"
PROBE_INDEX = REPO_ROOT / "tools" / "pyboy_smoke" / "spawnform_probes.json"

STAGES = {
    "cave": ("PROCEDURAL_CAVE_1", "Procedural Cave"),
    "forest": ("PROCEDURAL_FOREST", "Procedural Forest"),
}

DELIMITER = "LoadEnemyMonData"


def load_probe_index() -> list[dict]:
    """Probe metadata from the index, plus each one's FULL symbol from the .sym.

    A local label assembles as "EnclosingRoutine.spawnFormProbeNN" and the index
    only knows the short name, so the enclosing routine is recovered by matching
    the suffix in the symbol file the harness itself validates against. A probe
    with no match is not an error to swallow: two of them live inside
    IF FORCE_*_FORM_TEST blocks that are not assembled, so they are genuinely not
    writers in this ROM, and the runner reports them rather than hiding them.
    """
    if not PROBE_INDEX.exists():
        print("no %s - run spawnform_probe_labels.py first" % PROBE_INDEX.name)
        return []
    entries = json.loads(PROBE_INDEX.read_text(encoding="utf-8"))

    sym_path = REPO_ROOT / "pokeblue_debug.sym"
    resolved: dict[str, str] = {}
    for line in sym_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        symbol = parts[1]
        _, _, tail = symbol.rpartition(".")
        if tail.startswith("spawnFormProbe"):
            resolved[tail] = symbol

    for entry in entries:
        entry["symbol"] = resolved.get(entry["probe"])
    return entries


def one_boot(map_id: str, description: str, seed: int, encounters: int,
             probes: list[dict]) -> tuple[list[tuple], list[str]]:
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    stream: list[tuple] = []
    missing: list[str] = []
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        for offset in range(10):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)

        def writer(name):
            def callback(_context) -> None:
                # The label sits immediately BEFORE `ld [wSpawnForm], a`, so A
                # still holds the value about to be stored. wCurPartySpecies is
                # captured alongside it because a form index is only meaningful
                # relative to a species: if the species at the write differs from
                # the species the mon is finally built as, a form legitimately
                # rolled for one mon has been applied to another.
                stream.append(("write", name, harness.pyboy.register_file.A,
                               harness.read8("wCurPartySpecies")))

            return callback

        for entry in probes:
            if not entry.get("symbol"):
                missing.append("%s (%s:%d)" % (entry["probe"], entry["file"], entry["line"]))
                continue
            try:
                harness.register_hook(entry["symbol"], writer(entry["probe"]))
            except KeyError:
                missing.append("%s (%s:%d)" % (entry["probe"], entry["file"], entry["line"]))

        def on_build(_context) -> None:
            stream.append(("BUILD", harness.read8("wSpawnForm"),
                           harness.read8("wEnemyMonSpecies2")))

        harness.register_hook(DELIMITER, on_build)

        menu_up = harness.hook_flag("DisplayBattleMenu")
        harness.preload_and_enter_wild_area(map_id, description)

        for index in range(encounters):
            seen = menu_up["count"]
            for step in range(600):
                if harness.read8("hIsInBattle") != 0:
                    break
                harness.move_tile(["left", "right", "up", "down"][step % 4])
            else:
                break
            for _ in range(240):
                if menu_up["count"] > seen:
                    break
                harness.tap("a", 1)
                harness.tick(8)
            if menu_up["count"] == seen:
                break
            # RUN out of the battle: right, down, A (see the harness notes on
            # hCurrentMenuItem never reading 2/3).
            harness.tap("right")
            harness.tap("down")
            harness.tap("a")
            for _ in range(180):
                if harness.read8("hIsInBattle") == 0:
                    break
                harness.tap("a", 1)
                harness.tick(8)
    finally:
        try:
            harness.close()
        except Exception:
            pass
    return stream, missing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", choices=sorted(STAGES), default="forest")
    parser.add_argument("--boots", type=int, default=6)
    parser.add_argument("--per-boot", type=int, default=20)
    parser.add_argument("--show-stream", action="store_true",
                        help="dump the raw interleaved stream for the first boot")
    args = parser.parse_args()

    probes = load_probe_index()
    if not probes:
        return 0

    map_name, description = STAGES[args.stage]
    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")[map_name]

    builds = 0
    leaked = 0
    blamed: Counter[str] = Counter()
    clean_last: Counter[str] = Counter()
    writes: Counter[str] = Counter()
    orphaned: Counter[str] = Counter()
    orphaned_nonzero: Counter[str] = Counter()
    never_fired = set(entry["probe"] for entry in probes)
    reported_missing: list[str] = []
    detail: list[str] = []

    for boot in range(args.boots):
        stream, missing = one_boot(map_id, description, boot, args.per_boot, probes)
        if missing and not reported_missing:
            reported_missing = missing
        if args.show_stream and boot == 0:
            print("--- raw stream, boot 0 ---")
            for item in stream[:200]:
                print("   ", item)
            print("--- end ---")
            print()

        last_write = None
        for item in stream:
            if item[0] == "write":
                # A write that is NOT consumed by the very next build is the only
                # shape a stale-value leak can have: it means the value sat in
                # wSpawnForm across something else. Counting these separates "this
                # routine legitimately publishes a form right before the mon is
                # built" from "a value was left lying around".
                if last_write is not None:
                    orphaned[last_write[0]] += 1
                    if last_write[1]:
                        orphaned_nonzero[last_write[0]] += 1
                last_write = (item[1], item[2], item[3])
                writes[item[1]] += 1
                never_fired.discard(item[1])
                continue
            # a BUILD delimiter
            builds += 1
            form = item[1]
            if form:
                leaked += 1
                who = last_write[0] if last_write else "<no write at all>"
                value = last_write[1] if last_write else -1
                blamed[who] += 1
                at_write = last_write[2] if last_write else -1
                flag = "" if at_write == item[2] else "   <-- SPECIES CHANGED AFTER THE ROLL"
                if len(detail) < 16:
                    detail.append(
                        "  build #%d: wSpawnForm=%d, species at write=%d, at build=%d,"
                        " writer %s (A=%d)%s"
                        % (builds, form, at_write, item[2], who, value, flag)
                    )
            else:
                clean_last[last_write[0] if last_write else "<none>"] += 1
            last_write = None       # consumed by this build

    print()
    print("=== wSpawnForm writer probe: %s ===" % args.stage)
    print("%d boots x %d encounters requested" % (args.boots, args.per_boot))
    print("%d enemy builds observed (LoadEnemyMonData hits)" % builds)
    print("%d built with a NONZERO wSpawnForm (%.1f%%)"
          % (leaked, 100.0 * leaked / max(builds, 1)))
    print()
    if reported_missing:
        print("probes absent from the .sym (not assembled, so not writers):")
        for line in reported_missing:
            print("   ", line)
        print()
    if builds == 0:
        print("NO BUILDS OBSERVED - the probe measured nothing, so it proves nothing.")
        print("Check that the stage is reachable and the delimiter label exists.")
        return 0
    if leaked:
        print("BLAMED - last writer before a leaked build:")
        for name, count in blamed.most_common():
            entry = next((e for e in probes if e["probe"] == name), None)
            where = "%s:%d" % (entry["file"], entry["line"]) if entry else "?"
            print("   %-20s %3d  %s" % (name, count, where))
        print()
        for line in detail:
            print(line)
    else:
        print("No leak observed. At the recorded ~3.3%% rate, %d builds would miss"
              % builds)
        print("it anyway with probability %.1f%% - so this is only evidence at all"
              % (100.0 * (1 - 0.033) ** builds))
        print("once that percentage is small.")
    print()
    print("last writer before a CLEAN build (context, not blame):")
    for name, count in clean_last.most_common(8):
        print("   %-20s %3d" % (name, count))
    fired = [entry["probe"] for entry in probes if entry["probe"] not in never_fired]
    print()
    print("writers that fired at all: %s" % (", ".join(sorted(fired)) or "none"))
    print()
    print("writes vs consumption - THE staleness test. An 'orphaned' write is one")
    print("not consumed by the very next enemy build, which is the only shape a")
    print("stale-value leak can take. Orphaned-nonzero is the dangerous subset.")
    print("   %-20s %8s %9s %9s" % ("writer", "writes", "orphaned", "orph!=0"))
    for name in sorted(writes):
        print("   %-20s %8d %9d %9d"
              % (name, writes[name], orphaned[name], orphaned_nonzero[name]))
    total_orphan_nonzero = sum(orphaned_nonzero.values())
    print()
    if total_orphan_nonzero == 0:
        print("NO STALE NONZERO VALUE was ever left across a build in this run:")
        print("every nonzero wSpawnForm was written immediately before the mon that")
        print("consumed it. On this evidence the nonzero values are forms being")
        print("rolled as designed, not a value inherited from an earlier writer.")
    else:
        print("%d nonzero write(s) were left unconsumed across a build - that IS"
              % total_orphan_nonzero)
        print("the leak shape, and the writer above is where it comes from.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
