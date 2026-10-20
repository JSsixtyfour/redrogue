"""Every code label in the debug ROM: what the coverage map can safely hook.

PyBoy installs a hook by overwriting the instruction byte with $DB, so a hook
on a label the game READS (a table, text, graphics, code copied to RAM) would
feed it $DB. Only labels that sit on an instruction are listed. The static
audit's source walker (tools/static_audit/lib.py) already knows which items
are instructions and which are data, after macro expansion and IF/ELSE for
this ROM, so a label counts as code when the first item after it is an
instruction, it is not inside LOAD ... ENDL (code that runs from RAM; its ROM
copy is read, not executed), and its section is in ROM.

The walk takes a while, so the result is cached under artifacts/ by the
symbol file's hash.

    python3 tools/pyboy_smoke/coverage_inventory.py      # build or refresh; prints counts
"""
from __future__ import annotations

import hashlib
import json
import sys
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
ROM = "pokeblue_debug"


def _walk(rom: str) -> list[dict[str, object]]:
    sys.path.insert(0, str(ROOT / "tools/static_audit"))
    from lib import Program

    program = Program(rom)
    items = program.items
    vanilla_scope = program.scope  # files changed since the pret/pokered merge-base
    labels = []
    for item in items:
        if item.kind != "label" or item.load or not item.section:
            continue
        section = program.rom.sections.get(item.section)
        if section is None or not section.region.startswith("ROM"):
            continue
        j = item.idx + 1
        while j < len(items) and (items[j].kind == "label" or
                                  items[j].kind == "directive" and not items[j].op):
            j += 1
        if j >= len(items) or items[j].kind != "instr" or items[j].load:
            continue
        located = program.rom.sym.get(item.label)
        if located is None:
            continue
        bank, address = located
        # Whether the item after the first instruction is another plain
        # instruction (not a label, not inline data such as a far call's
        # bank and address): only then may the hook move there (hook_plan).
        k = j + 1
        while k < len(items) and items[k].kind == "directive" and not items[k].op:
            k += 1
        second_is_code = k < len(items) and items[k].kind == "instr" and not items[k].load
        labels.append({"name": item.label, "bank": bank, "address": address, "file": item.file,
                       "line": item.line, "global": item.is_global,
                       "custom": item.file in vanilla_scope, "second_is_code": second_is_code})
    return labels


SCHEMA = 2  # bump when a label record gains a field, so stale caches are rebuilt


def code_labels(rom: str = ROM) -> list[dict[str, object]]:
    sym = (ROOT / f"{rom}.sym").read_bytes()
    digest = hashlib.sha256(sym).hexdigest()[:16]
    cache = ARTIFACTS / f"coverage_inventory_{rom}_v{SCHEMA}_{digest}.json"
    if cache.exists():
        return json.loads(cache.read_text(encoding="utf-8"))
    labels = _walk(rom)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    for old in ARTIFACTS.glob(f"coverage_inventory_{rom}_*.json"):
        old.unlink()
    cache.write_text(json.dumps(labels) + "\n", encoding="utf-8")
    return labels


def hook_plan(labels: list[dict[str, object]], rom: bytes) -> tuple[dict[str, tuple[int, int]],
                                                                     dict[str, str]]:
    """Where to hook each label so that no hook's own instruction leads
    straight onto another hook.

    PyBoy 2.7 steps over a hook by restoring the byte, running one
    instruction, and putting the hook back. When that one instruction lands
    on a second hook (a `call` into a hooked routine, a fall-through into a
    hooked local label) it can wedge, re-firing the second hook forever
    without executing it: measured 2026-10-20 on PCemFillAll.rowLoop
    (`call PCemFillOneRow`), which hung seed 1 at its third pass.

    A conflict is resolved by moving a hook one instruction on, which still
    means "this label ran": the hooking label's own `call` (the call returns
    to the next instruction), or the target when its first instruction falls
    through. Only where the inventory saw a plain instruction next
    (second_is_code), so a hook never lands on a label or on inline data. A
    label whose hook cannot move is left unhooked and inferred from the label
    that leads to it for certain. Returns ({label: (bank, address)}, {inferred
    label: the label it is inferred from})."""
    import sm83

    by_name = {label["name"]: label for label in labels}
    hooks = {label["name"]: (label["bank"], label["address"]) for label in labels}
    moved: set[str] = set()
    inferred: dict[str, str] = {}

    def movable(name: str, kinds: tuple[str, ...]) -> bool:
        if name in moved or not by_name[name]["second_is_code"]:
            return False
        return sm83.first_step(rom, *hooks[name]).kind in kinds

    owners: dict[tuple[int, int], set[str]] = {}
    for name, key in hooks.items():
        owners.setdefault(key, set()).add(name)

    def unhook(name: str) -> None:
        owners[hooks[name]].discard(name)
        del hooks[name]

    def move(name: str) -> None:
        bank, address = hooks[name]
        unhook(name)
        hooks[name] = (bank, address + sm83.first_step(rom, bank, address).length)
        owners.setdefault(hooks[name], set()).add(name)
        moved.add(name)

    def conflict(name: str) -> tuple[str, bool] | None:
        bank, address = hooks[name]
        for successor, certain in sm83.first_step(rom, bank, address).successors:
            key = (0 if successor < 0x4000 else bank, successor)
            others = owners.get(key, set()) - {name}
            if others and key != (bank, address):
                return min(others), certain
        return None

    for _ in range(8):
        changed = False
        for name in sorted(hooks):
            while name in hooks and (found := conflict(name)):
                target, certain = found
                if movable(name, ("call",)):
                    move(name)
                elif movable(target, ("flow", "call")):
                    move(target)
                else:
                    unhook(target)
                    if certain:
                        inferred[target] = name
                changed = True
        if not changed:
            break
    return hooks, inferred


@lru_cache(None)
def plan(rom: str = ROM) -> tuple[list[dict[str, object]], dict[str, tuple[int, int]], dict[str, str]]:
    """(labels, where to hook them, inferred labels): see hook_plan."""
    labels = code_labels(rom)
    hooks, inferred = hook_plan(labels, (ROOT / f"{rom}.gbc").read_bytes())
    return labels, hooks, inferred


def ran_labels(hits, inferred: dict[str, str]) -> set[str]:
    """Labels that ran: hooked and hit, or inferred from one that ran."""
    ran = set(hits)
    for label in inferred:
        source, seen = label, set()
        while source in inferred and source not in ran and source not in seen:
            seen.add(source)
            source = inferred[source]
        if source in ran:
            ran.add(label)
    return ran


def main() -> int:
    labels, hooks, inferred = plan()
    moved = sum(hooks[label["name"]] != (label["bank"], label["address"])
                for label in labels if label["name"] in hooks)
    print(f"hook plan: {len(hooks)} hooked ({moved} one instruction on), {len(inferred)} inferred, "
          f"{len(labels) - len(hooks) - len(inferred)} untracked")
    routines = [label for label in labels if label["global"]]
    print(f"{len(labels)} code labels ({len(routines)} routines, "
          f"{sum(label['custom'] for label in labels)} in files changed from pret/pokered)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
