"""Audit: are procedural wild-encounter enemy graphics actually glitched?

PROC_GEN_NOTES.md's "What this does NOT explain" section records glitched enemy
graphics in procedural wild battles (the Magmar screenshot) and has never been
root-caused. Its suspect is an out-of-range species reaching the pic-bank
lookup out of PCRollWildEncounter / PCRollMonClass /
Random_Pokemon_Selection_Any.

This observes the thing itself rather than a proxy for it. Per encounter it
records the species, form and level, and crops the enemy pic out of the frame
buffer. All the crops go into one contact sheet so the glitch is visible at a
glance, and the per-encounter values sit beside them so a bad frame can be tied
straight to the species that produced it.

Many encounters fit in one boot because a procedural wild battle can now be
ended instantly with RUN on the debug ROM (Phase 2). Nothing here uses
call_routine beyond the single preload, so the ~10-invocations-per-boot limit
does not apply.

Usage:
    python3 tools/pyboy_smoke/audit_wild_encounter_sprites.py [--boots 3] [--per-boot 20]
                                                              [--stage cave|forest]

Reads the species range out of the ROM's own tables, so "in range" is not a
guess: a species is valid if its index is within MonsterPicPointers.
"""

from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"

STAGES = {
    "cave": ("PROCEDURAL_CAVE_1", "Procedural Cave"),
    "forest": ("PROCEDURAL_FOREST", "Procedural Forest"),
}

# The enemy mon's pic occupies the top-right of the battle screen.
CROP = (80, 0, 160, 64)


def species_names() -> dict[int, str]:
    """internal id -> constant name, from constants/pokemon_constants.asm."""
    names: dict[int, str] = {}
    index = 0
    text = (REPO_ROOT / "constants" / "pokemon_constants.asm").read_text(
        encoding="utf-8", errors="replace"
    )
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("const_def"):
            parts = stripped.replace(",", " ").split()
            index = int(parts[1]) if len(parts) > 1 else 0
        elif stripped.startswith("const "):
            names[index] = stripped.split()[1]
            index += 1
    return names


def one_boot(map_id: int, description: str, seed: int, encounters: int) -> list[dict]:
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    rows: list[dict] = []
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        for offset in range(10):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)

        menu_up = harness.hook_flag("DisplayBattleMenu")

        # Capture the species at the instant the enemy mon is BUILT from it.
        # Reading wCurPartySpecies later is worthless - by the time the battle
        # menu is up it holds the player's active mon. LoadEnemyMonData is the
        # shared entry point for procedural and ordinary wild encounters alike.
        rolled: list[dict] = []

        def on_load(_context) -> None:
            rolled.append(
                {
                    "cur_party_species": harness.read8("wCurPartySpecies"),
                    "enemy_species2": harness.read8("wEnemyMonSpecies2"),
                    "spawn_form": harness.read8("wSpawnForm"),
                    "level": harness.read8("wCurEnemyLevel"),
                }
            )

        harness.register_hook("LoadEnemyMonData", on_load)
        harness.preload_and_enter_wild_area(map_id, description)

        for index in range(encounters):
            seen = menu_up["count"]
            for step in range(600):
                if harness.read8("hIsInBattle") != 0:
                    break
                harness.move_tile(["left", "right", "up", "down"][step % 4])
            else:
                print(f"    boot {seed}: no encounter {index} after 600 steps")
                break

            # Wait for the battle MENU, not just hIsInBattle: while the "Wild X
            # appeared!" intro is running the enemy pic is mid-draw and input is
            # ignored. The menu being up is the proof the frame is settled.
            for _ in range(240):
                if menu_up["count"] > seen:
                    break
                harness.tap("a", 1)
                harness.tick(8)
            if menu_up["count"] == seen:
                print(f"    boot {seed}: battle menu never appeared for {index}")
                break
            harness.tick(24, render=True)

            at_build = rolled[-1] if rolled else {}
            rows.append(
                {
                    "species": harness.read8("wEnemyMonSpecies2"),
                    "rolled_species": at_build.get("cur_party_species", -1),
                    "rolled_enemy2": at_build.get("enemy_species2", -1),
                    "rolled_form": at_build.get("spawn_form", -1),
                    "level": harness.read8("wEnemyMonLevel"),
                    "form": harness.read8("wSpawnForm"),
                    "image": harness.pyboy.screen.image.convert("RGB").crop(CROP),
                }
            )

            # RUN: right (switch column), down (lower item), A. On the debug ROM
            # this is a minimal quick-win, so the next encounter can start.
            harness.tap("right", 2)
            harness.tick(20)
            harness.tap("down", 2)
            harness.tick(20)
            harness.tap("a", 2)
            harness.tick(60)
            for _ in range(80):
                if harness.read8("hIsInBattle") == 0:
                    break
                harness.tap("a", 1)
                harness.tick(20)
            if harness.read8("hIsInBattle") != 0:
                print(f"    boot {seed}: battle {index} would not end")
                break
            harness.tick(60)
        return rows
    finally:
        try:
            harness.close()
        except Exception:
            pass


def contact_sheet(rows: list[dict], path: Path) -> None:
    from PIL import Image, ImageDraw

    if not rows:
        return
    columns = 8
    crop_w = CROP[2] - CROP[0]
    crop_h = CROP[3] - CROP[1]
    cell_h = crop_h + 12
    sheet_rows = (len(rows) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * crop_w, sheet_rows * cell_h), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    for index, row in enumerate(rows):
        x = (index % columns) * crop_w
        y = (index // columns) * cell_h
        sheet.paste(row["image"], (x, y))
        draw.text((x + 2, y + crop_h + 1), f"{index} #{row['species']}", fill=(220, 220, 220))
    sheet.save(path)
    print(f"contact sheet: {path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--boots", type=int, default=3)
    parser.add_argument("--per-boot", type=int, default=20)
    parser.add_argument("--stage", choices=list(STAGES), default="cave")
    args = parser.parse_args()

    map_name, description = STAGES[args.stage]
    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")[map_name]
    names = species_names()
    highest = max(names)

    rows: list[dict] = []
    for seed in range(args.boots):
        rows.extend(one_boot(map_id, description, seed, args.per_boot))

    print(f"\n{len(rows)} encounters in {description}")
    unknown = []
    for index, row in enumerate(rows):
        species = row["species"]
        label = names.get(species)
        flag = "" if label else "   <-- NOT A KNOWN SPECIES CONSTANT"
        if not label:
            unknown.append(index)
        print(
            f"  {index:3d} species={species:3d} ({label or '???'}) "
            f"lvl={row['level']:3d} "
            f"at-build: wCurPartySpecies={row['rolled_species']:3d} "
            f"wEnemyMonSpecies2={row['rolled_enemy2']:3d} "
            f"wSpawnForm={row['rolled_form']}{flag}"
        )

    distinct = sorted({row["species"] for row in rows})
    print(f"\ndistinct species: {len(distinct)} -> {distinct}")
    print(f"highest species constant in the ROM's table: {highest}")
    print(f"species with no constant: {len(unknown)}")
    mismatch = [i for i, r in enumerate(rows) if r["rolled_species"] != r["rolled_enemy2"]]
    print(f"at build, wCurPartySpecies != wEnemyMonSpecies2: {len(mismatch)} {mismatch}")
    drifted = [i for i, r in enumerate(rows) if r["species"] != r["rolled_enemy2"]]
    print(f"species changed between build and the battle menu: {len(drifted)} {drifted}")
    forms = sorted({r["rolled_form"] for r in rows})
    print(f"wSpawnForm values seen at build: {forms}")

    contact_sheet(rows, ARTIFACTS / f"wild_encounter_sprites_{args.stage}.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
