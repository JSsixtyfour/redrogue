"""Run every static audit against the built ROMs.

Usage (from the repo root, after building all three ROMs):
    python3 tools/static_audit/run_all.py [--rom NAME ...] [--rule ID ...]
                                          [--info] [--json OUT]

Exits 1 if any finding of severity "bug" is not in allowlist.txt.
"info" findings are printed with --info but never fail the run.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import rules  # noqa: E402
from lib import REPO, ROMS, Program  # noqa: E402

ALLOWLIST = Path(__file__).resolve().parent / "allowlist.txt"


def load_allowlist():
    """Lines: RULE <tab> FILE <tab> LABEL <tab> reason. LABEL `*` matches any."""
    out = []
    if not ALLOWLIST.exists():
        return out
    for n, line in enumerate(ALLOWLIST.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 4 or not parts[3].strip():
            raise SystemExit(f"allowlist.txt:{n}: need RULE<TAB>FILE<TAB>LABEL<TAB>reason")
        out.append((parts[0].strip(), parts[1].strip(), parts[2].strip(), parts[3].strip()))
    return out


def allowed(f, allow):
    for rule, file, label, _ in allow:
        if rule == f["rule"] and file == f["file"] and label in ("*", f["label"]):
            return True
    return False


def run(roms, only_rules):
    merged = {}
    programs = []
    for rom in roms:
        t = time.time()
        p = Program(rom)
        programs.append(p)
        found = []
        flow_found, fl, labels = rules.run_flow(p)
        found += flow_found
        found += rules.rule_calls(p)
        found += rules.rule_b2(p)
        found += rules.rule_b7(p, fl, labels)
        found += rules.rule_c2(p)
        found += rules.rule_c3(p, fl)
        found += rules.rule_d1(p)
        found += rules.rule_d2(p)
        found += rules.rule_b9(p)
        for f in found:
            if only_rules and f["rule"] not in only_rules:
                continue
            if f["severity"] == "bug" and "idx" in f and rules.is_vanilla_routine(p, f["idx"]):
                # unchanged pret/pokered routine: same behaviour as the original game
                f["severity"] = "info"
                f["msg"] = "[vanilla] " + f["msg"]
            f.pop("idx", None)
            k = (f["rule"], f["file"], f["line"], f["msg"])
            merged.setdefault(k, dict(f, roms=[]))["roms"].append(rom)
        print(f"[{rom}] {len(found)} raw findings in {time.time() - t:.0f}s", file=sys.stderr)
    for f in rules.rule_d3(programs):
        if not only_rules or f["rule"] in only_rules:
            merged[(f["rule"], f["file"], f["line"], f["msg"])] = dict(f, roms=list(roms))
    # code is only dead if no build references it (debug-only callers exist)
    merged = {k: f for k, f in merged.items() if f["rule"] != "D1" or len(f["roms"]) == len(roms)}
    return sorted(merged.values(), key=lambda f: (f["rule"], f["file"], f["line"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rom", action="append", choices=sorted(ROMS))
    ap.add_argument("--rule", action="append")
    ap.add_argument("--info", action="store_true", help="also print info-level findings")
    ap.add_argument("--json")
    args = ap.parse_args()
    roms = args.rom or ["pokered", "pokeblue", "pokeblue_debug"]
    for r in roms:
        if not (REPO / f"{r}.sym").exists():
            raise SystemExit(f"{r}.sym missing: build the ROMs first")
    allow = load_allowlist()
    findings = run(roms, set(args.rule or []))
    for f in findings:
        f["allowlisted"] = allowed(f, allow)
    failing = [f for f in findings if f["severity"] == "bug" and not f["allowlisted"]]
    shown = [f for f in findings if not f["allowlisted"] and (args.info or f["severity"] == "bug")]
    for f in shown:
        roms_note = "" if len(f["roms"]) == len(roms) else f" [{','.join(f['roms'])}]"
        print(f"{f['rule']:4} {f['severity']:4} {f['file']}:{f['line']} ({f['label']}){roms_note}\n"
              f"          {f['msg']}")
    counts = {}
    for f in findings:
        key = f"{f['rule']}/{f['severity']}{'/allowlisted' if f['allowlisted'] else ''}"
        counts[key] = counts.get(key, 0) + 1
    print("\nsummary: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    # An entry nothing matches any more would silently excuse a NEW finding that
    # happens to land on the same rule/file/label, so surface it for deletion.
    ran_rules = set(args.rule or []) or {f["rule"] for f in findings} | {e[0] for e in allow}
    stale = [e for e in allow if e[0] in ran_rules
             and not any(allowed(f, [e]) for f in findings)]
    for rule, file, label, _ in stale:
        print(f"stale allowlist entry (matches nothing, delete it): {rule}\t{file}\t{label}")
    print(f"{len(failing)} unallowlisted bug-level finding(s)")
    if args.json:
        Path(args.json).write_text(json.dumps(findings, indent=1), encoding="utf-8")
    return 1 if failing else 0


if __name__ == "__main__":
    sys.exit(main())
