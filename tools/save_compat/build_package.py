#!/usr/bin/env python3
"""Build the save-converter package for the current save schema.

    python3 tools/save_compat/build_package.py --out DIR [--template post_reset.sav]

Writes DIR/save-convert-<sha256 first 12>.js: the engine
(tools/save_compat/converter/engine.js) plus, embedded as data, the target
schema (the one constants/save_constants.asm declares), every source schema
and migration in tools/save_compat/registry.json, and the recovery template
and keep-lists when --template is given. Named by its own content, so a
published package is immutable: a different converter is a different file.
Prints the file name. The package does not name a build; builds.json does,
so one package serves every build that shares the save format.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
SCHEMAS = REPO / "tools" / "save_schemas"


def schema_id() -> int:
    text = (REPO / "constants" / "save_constants.asm").read_text(encoding="utf-8")
    return int(re.search(r"DEF SAVE_SCHEMA_ID EQU (\d+)", text).group(1))


# Saved-WRAM fields the engine reads: its structure checks (engine.js boundsProblems) and event flags.
ENGINE_WRAM = {"wPlayerName", "wPartyCount", "wPartySpecies", "wBoxCount", "wCurrentBoxNum", "wEventFlags",
               # migration itemCountSlots (schema 1 -> 2)
               "wRecoveryItemCounts", "wStatItemCounts", "wValuableItemCounts", "wNumBagItems",
               # migration legacyInventoriesRemoved (schema 2 -> 3)
               "wBagPocketsFlags", "wNumBoxItems",
               # migration playerStarterFormAdded (schema 4 -> 5)
               "wFossilMon", "wPlayerStarterForm",
               # migration x7MenuPageReserved (schema 5 -> 6): clamped to the new fallen log capacity
               "wFallenCount",
               # migration gymChoiceAdded (schema 6 -> 7)
               "wCreditsEarnedThisRun", "wGymChoice",
               # migration dayCareDepositCountsSaved (schema 7 -> 8)
                 "wCurMapScript", "wBattleCount", "wDayCareDepositBattleCount", "wDayCareDepositBattleCount2",
                 "wStolenSaveSnapshot", "wRentalRecord",
               # migration tradeFormAdded (schema 10 -> 11)
               "wOptions3", "wroguenpctradeform",
               # migration flagsRenumbered (schema 10 -> 11)
               "wToggleableObjectFlags"}

# Steps whose per-migration table flag_translation() computes and attaches to the target schema.
FLAG_STEP = "flagsRenumbered"
FLAG_ARRAYS = (("EVENT_", "NUM_EVENTS", "wEventFlags"),
               ("TOGGLE_", "NUM_TOGGLEABLE_OBJECTS", "wToggleableObjectFlags"))


def toggles_off_at_new_game() -> set[str]:
    """TOGGLE_* names whose object starts hidden (bit set) on a new game, read from the tree this
    package is built from. Only consulted for toggles a migration ADDS, which by construction exist
    in this tree's target schema."""
    text = (REPO / "data" / "maps" / "toggleable_objects.asm").read_text(encoding="utf-8")
    return {"TOGGLE_" + m.group(1)
            for m in re.finditer(r"^\s*toggle_object_state\s+(\w+)\s*,\s*OFF\b", text, re.M)}


def flag_translation(old: dict, new: dict) -> dict:
    """Event and toggle bits translated BY NAME between two full schemas.

    Returns {label: {"bytes": n, "bits": [[new_bit, [old_bits] | None, default], ...]}} listing only
    the bits whose meaning changed; every other bit stays where it is (the arrays did not move).
    A new bit takes the OR of its names' old bits (names can alias one bit); a bit whose names are
    all new takes the new-game default (events clear, toggles per toggleable_objects.asm); a bit
    that lost every name is cleared. Refuses a renumbering it can't express."""
    oc, nc = old["constants"], new["constants"]
    off = toggles_off_at_new_game()
    out = {}
    for prefix, count, label in FLAG_ARRAYS:
        # The arrays are declared at a fixed size (wToggleableObjectFlags is
        # flag_array $100), so a count that grows inside it moves nothing; only
        # a different array size needs a layout step. Bits past the old count
        # were never used, so an old save holds 0 there.
        sizes = [next((f["size"] for f in s["saved_wram"] if f["label"] == label), None) for s in (old, new)]
        if sizes[0] != sizes[1] or sizes[1] is None:
            raise SystemExit(f"{label} is {sizes[0]} -> {sizes[1]} bytes: {FLAG_STEP} can't resize it")
        n = max(oc[count], nc[count])
        if n > 8 * sizes[1]:
            raise SystemExit(f"{count} {n} overflows {label} ({sizes[1]} bytes)")
        def named(c):
            groups = {}
            for k, v in c.items():
                if k.startswith(prefix) and isinstance(v, int) and 0 <= v < n:
                    groups.setdefault(v, []).append(k)
            return groups
        old_bits, new_bits = named(oc), named(nc)
        bits = []
        for nb in sorted(set(new_bits) | set(old_bits)):
            names = new_bits.get(nb, [])
            sources = sorted({oc[k] for k in names if k in oc and 0 <= oc[k] < n})
            if not names:
                bits.append([nb, None, 0])            # lost every name: nothing reads it now
            elif sources == [nb]:
                continue                              # same meaning, already in place
            elif sources:
                bits.append([nb, sources, 0])
            else:
                default = 1 if prefix == "TOGGLE_" and any(k in off for k in names) else 0
                bits.append([nb, None, default])
        out[label] = {"bytes": (n + 7) // 8, "bits": bits}
    return out


def trim(schema: dict) -> dict:
    """Only what the engine reads: header, checksums, SRAM labels, and the saved-WRAM fields it uses."""
    policy = json.loads((SCHEMAS / "policy.json").read_text(encoding="utf-8"))
    wanted = ENGINE_WRAM | set(policy["recovery_keep_wram"]["labels"])
    return {
        "schema_id": schema["schema_id"],
        "source": schema["source"],
        "header": schema["header"],
        "checksums": schema["checksums"],
        "sram": [{k: f[k] for k in ("label", "bank", "address", "size")} for f in schema["sram"]],
        "saved_wram": [{k: f[k] for k in ("label", "block", "offset", "size")} for f in schema["saved_wram"]
                       if f["label"] in wanted],
    }


def recovery_section(template: Path, target: dict) -> dict:
    data = template.read_bytes()
    if len(data) != 0x8000:
        raise SystemExit(f"{template} is {len(data)} bytes, not a 32 KiB save")
    policy = json.loads((SCHEMAS / "policy.json").read_text(encoding="utf-8"))
    labels = [f["label"] for f in target["sram"]]
    keep_sram = [label for label in labels
                 if any(re.fullmatch(p, label) and rule["recovery"] == "keep" for p, rule in policy["sram"].items())]
    keep_wram = policy["recovery_keep_wram"]["labels"]
    events = json.loads((SCHEMAS / "events.json").read_text(encoding="utf-8")) if (SCHEMAS / "events.json").is_file() \
        else None
    return {"template": base64.b64encode(data).decode(), "template_sha256": hashlib.sha256(data).hexdigest(),
            "keep_sram": keep_sram, "keep_wram": keep_wram,
            "keep_event_bytes": events["persistent_byte_ranges"] if events else [],
            "recompute_checksums": ["main"],
            "always_lost": ["party", "PC boxes", "bag items and money", "badges", "the current run's progress"]}


def build(out_dir: Path, template: Path | None) -> Path:
    target_id = schema_id()
    registry = json.loads((HERE / "registry.json").read_text(encoding="utf-8"))
    schemas = {str(target_id): trim(json.loads((SCHEMAS / f"schema_{target_id}.json").read_text(encoding="utf-8")))}
    for source in registry["sources"]:
        name = source["schema"]
        path = SCHEMAS / (f"{name}.json" if not name.isdigit() else f"schema_{name}.json")
        schemas[name] = trim(json.loads(path.read_text(encoding="utf-8")))
    for m in registry["migrations"]:
        for end in (m["from"], m["to"]):
            if end not in schemas:
                path = SCHEMAS / (f"schema_{end}.json" if end.isdigit() else f"{end}.json")
                schemas[end] = trim(json.loads(path.read_text(encoding="utf-8")))
    for m in registry["migrations"]:
        if FLAG_STEP in m["steps"]:
            full = [json.loads((SCHEMAS / f"schema_{end}.json").read_text(encoding="utf-8")) for end in (m["from"], m["to"])]
            schemas[m["to"]].setdefault("flag_translation", {})[m["from"]] = flag_translation(*full)
    package = {
        "format": 1,
        "target": {"schema": target_id},
        "schemas": schemas,
        "sources": [{k: s[k] for k in ("id", "label", "schema", "rom_sha256")} for s in registry["sources"]],
        "migrations": [{k: m[k] for k in ("from", "to", "steps")} for m in registry["migrations"]],
        "recovery": recovery_section(template, schemas[str(target_id)]) if template else None,
    }
    engine = (HERE / "converter" / "engine.js").read_text(encoding="utf-8")
    text = (engine.rstrip() + "\n;(function (root) {\n  var api = (typeof module === \"object\" && module.exports) "
            "? module.exports : root.RRSaveConvert;\n  api.PACKAGE = " + json.dumps(package, separators=(",", ":"))
            + ";\n})(typeof self !== \"undefined\" ? self : this);\n")
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"save-convert-{digest[:12]}.js"
    if path.exists() and path.read_text(encoding="utf-8") != text:
        raise SystemExit(f"{path} exists with different contents")
    path.write_text(text, encoding="utf-8", newline="\n")
    return path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--template", type=Path, help="verified post-reset Dorm save of this schema (enables recovery)")
    args = parser.parse_args(argv)
    path = build(args.out, args.template)
    print(path.name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
