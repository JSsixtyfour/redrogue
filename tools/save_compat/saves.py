#!/usr/bin/env python3
"""Make and check real battery saves with PyBoy (WSL: python3).

    python3 tools/save_compat/saves.py make --root DIR --out OUT [--contexts lobby route cave]
    python3 tools/save_compat/saves.py continue --root DIR SAVE.sav [...]

`make` boots the pokeblue_debug.gbc/.sym in DIR (this repo, or a worktree of an
older release), plays to each context through the debug menus, saves with the
game's own SaveGameData, and writes OUT/<context>.sav (raw 32 KiB SRAM, the
.sav format emulators use for this cartridge) plus OUT/<context>.json
describing it.

`continue` is the acceptance gate for a save in a build: a fresh emulator boots
from the .sav, presses through the title, picks CONTINUE and enters the map;
then saves again, and a second fresh boot continues from that. It checks the
map and party match what the .json (or the first boot) recorded. No emulator
state is injected: only the battery save carries over between boots.

Contexts: lobby, route (an ordinary map), cave, forest, cemetery, facility
(procedural wild areas, entered with the stage generated).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "pyboy_smoke"))
from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

REPO = HERE.parents[1]
CONTEXTS = ("lobby", "route", "cave", "forest", "cemetery", "facility")
WILD = {"cave": "PROCEDURAL_CAVE_1", "forest": "PROCEDURAL_FOREST", "cemetery": "PROCEDURAL_CEMETERY_1",
        "facility": "PROCEDURAL_FACILITY"}


def dump_sram(h: RedRogueHarness) -> bytes:
    data = bytearray()
    for bank in range(4):
        h.pyboy.memory[0x0000] = 0x0A
        h.pyboy.memory[0x4000] = bank
        data += bytes(h.pyboy.memory[0xA000:0xC000])
    h.pyboy.memory[0x0000] = 0
    return bytes(data)


def snapshot(h: RedRogueHarness) -> dict:
    return {"map": h.read8("hCurMap"), "party_count": h.read8("wPartyCount"),
            "party_species": h.read_bytes("wPartySpecies", 6), "x": h.read8("wXCoord"), "y": h.read8("wYCoord"),
            "player_id": h.read8("wPlayerID") << 8 | h.read8("wPlayerID", 1)}


STAGE_EVENT_TYPE_MASK = 0x07
STAGE_EVENT_PHASE_MASK = 0x18


def settle_stage_event(h: RedRogueHarness) -> None:
    """Press through a wild area's arrival cutscene, as a player must before the
    Start menu opens. Saving mid-cutscene (theft done, phase still WAITING) makes
    the one-shot fire again on Continue, which no real save can do."""
    for _ in range(400):
        event = h.read8("wStageEvent")
        if not event & STAGE_EVENT_TYPE_MASK or event & STAGE_EVENT_PHASE_MASK:
            break
        h.tap("b", 2)
        h.tick(6)
    else:
        raise AssertionError(f"the stage event never left WAITING (wStageEvent ${h.read8('wStageEvent'):02x})")
    h.tick(240)


def make(root: Path, out: Path, contexts: list[str]) -> None:
    out.mkdir(parents=True, exist_ok=True)
    ids = parse_map_constants(root / "constants" / "map_constants.asm")
    rom = root / "pokeblue_debug.gbc"
    for context in contexts:
        h = RedRogueHarness(root, out / "artifacts")
        try:
            h.boot_to_lobby(battle_count=11, encounter_kind=4 if context in WILD else 1)
            if context == "route":
                h.enter_route_door1()
            elif context in WILD:
                h.preload_and_enter_wild_area(ids[WILD[context]], context)
                settle_stage_event(h)
            state = snapshot(h)
            h.call_routine("SaveGameData")
            if h.read8("wSaveFileStatus") != 2:
                raise AssertionError(f"{context}: SaveGameData did not run")
            sav = dump_sram(h)
        finally:
            h.close()
        (out / f"{context}.sav").write_bytes(sav)
        meta = {"context": context, "rom": rom.name, "rom_sha256": hashlib.sha256(rom.read_bytes()).hexdigest(),
                "rom_md5": hashlib.md5(rom.read_bytes()).hexdigest(), "sav_sha256": hashlib.sha256(sav).hexdigest(),
                **state}
        (out / f"{context}.json").write_text(json.dumps(meta, indent=1) + "\n", encoding="utf-8", newline="\n")
        print(f"{context}: map ${state['map']:02x}, party {state['party_count']} -> {out / (context + '.sav')}")


class Boot:
    def __init__(self, root: Path, sav: bytes, artifacts: Path):
        self.tmp = tempfile.TemporaryDirectory()
        ram = Path(self.tmp.name) / "game.sav"
        ram.write_bytes(sav)
        self.h = RedRogueHarness(root, artifacts, ram_path=ram)
        self.menu = self.h.hook_flag("MainMenu.mainMenuLoop")
        self.chose = self.h.hook_flag("MainMenu.choseContinue")
        self.pressed = self.h.hook_flag("MainMenu.pressedA")
        self.entered = self.h.hook_flag("SpecialEnterMap")

    def continue_game(self) -> int:
        """Returns wSaveFileStatus at the menu; continues if it offers CONTINUE."""
        h = self.h
        h.tick(240)
        for _ in range(300):
            h.tap("start", 2)
            h.tick(2)
            if self.menu["count"]:
                break
        status = h.read8("wSaveFileStatus")
        if status != 2:
            return status
        h.tick(30)
        for _ in range(60):
            h.tap("a", 2)
            h.tick(4)
            if self.chose["count"]:
                break
        for _ in range(120):
            h.tap("a", 2)
            h.tick(4)
            if self.pressed["count"]:
                break
        h.wait_until(lambda: self.entered["count"] > 0, "entering the saved map", 900)
        h.tick(120)
        return status

    def close(self):
        self.h.close()
        self.tmp.cleanup()


def check_continue(root: Path, sav_path: Path) -> list[str]:
    """[] if the save continues, saves, and continues again; otherwise what went wrong."""
    meta_path = sav_path.with_suffix(".json")
    expected = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.is_file() else None
    artifacts = sav_path.parent / "artifacts"
    problems = []
    first = Boot(root, sav_path.read_bytes(), artifacts)
    try:
        status = first.continue_game()
        if status != 2:
            return [f"first boot: the menu offered no CONTINUE (wSaveFileStatus {status})"]
        got = snapshot(first.h)
        if expected:
            for key in ("map", "party_count", "party_species", "player_id"):
                if got[key] != expected[key]:
                    problems.append(f"first boot: {key} is {got[key]}, the save recorded {expected[key]}")
        first.h.call_routine("SaveGameData")
        resaved = dump_sram(first.h)
    finally:
        first.close()
    second = Boot(root, resaved, artifacts)
    try:
        status = second.continue_game()
        if status != 2:
            return problems + [f"second boot: the menu offered no CONTINUE (wSaveFileStatus {status})"]
        again = snapshot(second.h)
        for key in ("map", "party_count", "party_species", "player_id"):
            if again[key] != got[key]:
                problems.append(f"second boot: {key} is {again[key]}, the first boot had {got[key]}")
    finally:
        second.close()
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    mk = sub.add_parser("make")
    mk.add_argument("--root", type=Path, default=REPO)
    mk.add_argument("--out", type=Path, required=True)
    mk.add_argument("--contexts", nargs="+", choices=CONTEXTS, default=list(CONTEXTS))
    ct = sub.add_parser("continue")
    ct.add_argument("--root", type=Path, default=REPO)
    ct.add_argument("saves", nargs="+", type=Path)
    args = parser.parse_args(argv)
    if args.cmd == "make":
        make(args.root, args.out, args.contexts)
        return 0
    failed = 0
    for sav in args.saves:
        problems = check_continue(args.root, sav)
        print(f"{sav.name}: " + ("continues, saves and continues again" if not problems else "; ".join(problems)))
        failed += bool(problems)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
