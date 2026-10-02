#!/usr/bin/env python3
r"""Gather one playtest report into a local reproduction bundle.

    py tools\repro_bundle.py RR-0012 --export export.json --evidence C:\Downloads\rr12

Inputs: the playtest bot's JSON export (/export format:JSON), the report ID, and
optionally a folder of files you downloaded for it (screenshots, video, .sav,
BGB .sn1 states). Nothing is fetched from the internet and no archive is
unpacked; files are copied byte for byte.

Writes builds/repro/RR-0012/ (git-ignored; never overwritten):
  report.json       the report as exported: events, attachments, fix attempts, retests
  reproduction.md   steps / expected / actual to fill in, environment, artifact identity,
                    save-state verdicts, retest history, and every missing piece of evidence
  evidence/         your files, unchanged
  rom/              the report's build's debug .gbc and .sym, if found and matching
  manifest.json     SHA-256 of every file in the bundle

Artifact identity: the build the report was filed on is looked up in builds/releases/
and builds/ by its stamp and checked against the SHA-1 the bot recorded. A BGB state
records the MD5 of the ROM it was made with; it's compared with that build's ROM, and a
mismatch or an unknown ROM is said loudly at the top of reproduction.md. A seed alone
does not reproduce a session; the state or save is what puts you back there.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional

REPO = Path(__file__).resolve().parents[1]
REPORT_ID = re.compile(r"^\s*(?:RR)?[\s#-]*(\d+)\s*$", re.IGNORECASE)
STATE_SUFFIX = re.compile(r"\.sn\d$", re.IGNORECASE)


class BundleError(Exception):
    pass


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# --- BGB save states ---------------------------------------------------------------

def bgb_records(data: bytes) -> Dict[str, bytes]:
    """A BGB save state is a run of records: name, NUL, 32-bit little-endian length,
    data. The first is the "BGB1.0" header; "rommd5" is the ROM's MD5. Measured on
    BGB 1.6.6 states: every record parses and the last ends exactly at the file's end."""
    if not data.startswith(b"BGB"):
        raise ValueError("not a BGB save state")
    records, pos = {}, 0
    while pos < len(data):
        end = data.index(b"\0", pos)
        (size,) = struct.unpack_from("<I", data, end + 1)
        start = end + 5
        if start + size > len(data):
            raise ValueError("truncated record")
        records.setdefault(data[pos:end].decode("latin-1"), data[start:start + size])
        pos = start + size
    return records


def state_verdict(path: Path, rom: Optional[Path]) -> dict:
    try:
        records = bgb_records(path.read_bytes())
    except (ValueError, struct.error) as e:
        return {"file": path.name, "verdict": "unreadable", "detail": f"not a readable BGB state ({e})"}
    md5 = records.get("rommd5", b"").hex()
    info = {"file": path.name, "rommd5": md5 or None,
            "romfile": records.get("romfile", b"").decode("latin-1") or None,
            "bgb": records.get("version", b"").decode("latin-1") or None}
    if not md5:
        return {**info, "verdict": "unverifiable", "detail": "the state doesn't record its ROM's MD5"}
    if rom is None:
        return {**info, "verdict": "unverifiable", "detail": "the report's build ROM wasn't found to compare with"}
    rom_md5 = hashlib.md5(rom.read_bytes()).hexdigest()
    if rom_md5 == md5:
        return {**info, "verdict": "matched", "detail": f"made with {rom.name}"}
    return {**info, "verdict": "MISMATCH", "detail": f"made with a different ROM than {rom.name} (MD5 {rom_md5})"}


# --- artifacts ------------------------------------------------------------------------

def find_build_rom(build: Optional[dict], builds_dir: Path) -> dict:
    """The report's build's debug ROM and .sym, checked against the hashes the bot recorded."""
    if not build:
        return {"status": "build_unknown", "detail": "the tester didn't know which build they played"}
    stamp = build.get("build_stamp")
    if not stamp:
        return {"status": "no_stamp", "detail": f"build {build.get('version')!r} has no archive stamp to look up"}
    places = [builds_dir / "releases" / stamp / f"{stamp}.gbc", builds_dir / "releases" / f"{stamp}.gbc",
              builds_dir / f"{stamp}.gbc"]
    rom = next((p for p in places if p.is_file()), None)
    if rom is None:
        return {"status": "not_found", "detail": f"{stamp}.gbc is in neither builds/releases/ nor builds/"}
    data = rom.read_bytes()
    want_sha1, want_sha256 = build.get("rom_sha1"), build.get("rom_sha256")
    if want_sha256 and hashlib.sha256(data).hexdigest() != want_sha256.lower():
        return {"status": "hash_mismatch", "detail": f"{rom} doesn't match the SHA-256 the bot recorded", "rom": rom}
    if want_sha1 and hashlib.sha1(data).hexdigest() != want_sha1.lower():
        return {"status": "hash_mismatch", "detail": f"{rom} doesn't match the SHA-1 the bot recorded", "rom": rom}
    sym = rom.with_suffix(".sym")
    verified = "SHA-256" if want_sha256 else "SHA-1" if want_sha1 else None
    return {"status": "matched" if verified else "unverified", "rom": rom, "sym": sym if sym.is_file() else None,
            "detail": f"{rom.name}, " + (f"{verified} matches the bot's record" if verified
                                         else "but the bot recorded no hash to check it against")}


# --- the bundle -----------------------------------------------------------------------

def load_report(export_path: Path, report_text: str) -> tuple[dict, Optional[dict]]:
    m = REPORT_ID.match(report_text)
    if not m:
        raise BundleError(f"{report_text!r} isn't a report ID like RR-0012")
    number = int(m.group(1))
    doc = json.loads(export_path.read_text(encoding="utf-8"))
    report = next((r for r in doc.get("reports", []) if int(r["id"]) == number), None)
    if report is None:
        raise BundleError(f"RR-{number:04d} isn't in {export_path.name} (export again, or without a build filter)")
    build = next((b for b in doc.get("builds", []) if report.get("build_id") is not None
                  and int(b["id"]) == int(report["build_id"])), None)
    return report, build


def copy_evidence(evidence_dir: Optional[Path], dest: Path) -> List[dict]:
    copied = []
    if evidence_dir is None:
        return copied
    for src in sorted(p for p in evidence_dir.rglob("*") if p.is_file()):
        target = dest / src.relative_to(evidence_dir)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, target)
        if sha256(src) != sha256(target):
            raise BundleError(f"copying {src} changed its bytes")
        copied.append({"path": str(target.relative_to(dest.parent)).replace("\\", "/"), "source": str(src),
                       "sha256": sha256(target)})
    return copied


def md_lines(report: dict, build: Optional[dict], artifact: dict, states: List[dict], missing: List[str],
             evidence: List[dict]) -> List[str]:
    code = report.get("report_code") or f"RR-{int(report['id']):04d}"
    warn = []
    if artifact["status"] not in ("matched",):
        warn.append(f"> **Build identity: {artifact['status']}.** {artifact['detail']}")
    for s in states:
        if s["verdict"] != "matched":
            warn.append(f"> **Save state {s['file']}: {s['verdict']}.** {s['detail']}")
    lines = [f"# {code}: {report.get('summary') or report.get('report_type')}", ""]
    if warn:
        lines += warn + [""]
    lines += [
        f"- Type: {report.get('report_type')}, status {report.get('status')}",
        f"- Tester: {report.get('tester_name_snapshot')} (Discord {report.get('discord_user_id')})",
        f"- Filed: {report.get('created_at')}",
        f"- Build: {build.get('version') if build else 'not sure'}"
        + (f" (`{build.get('build_stamp')}`, commit {build.get('git_commit')})" if build else ""),
        f"- Area: {report.get('area_label') or report.get('area') or '-'}; "
        f"reproducibility: {report.get('reproducibility') or '-'}",
        f"- Run ID: {report.get('run_id') or '-'}",
        "", "## What the tester said", "", (report.get("details") or "(no details)").strip(), "",
        "## Steps", "", "1. (fill in from the above and the evidence)", "",
        "## Expected", "", "(fill in)", "",
        "## Actual", "", (report.get("summary") or "(fill in)").strip(), "",
        "## Environment", "",
    ]
    envs = [t.get("environment") for t in report.get("retests", []) if t.get("environment")]
    replies = [e.get("note") for e in report.get("events", []) if e.get("event_type") == "tester_reply"]
    lines += [f"- From retests: {', '.join(envs)}" if envs else "- No environment recorded; check the notes and replies."]
    lines += [f"- Tester reply: {r}" for r in replies[:5]]
    lines += ["", "## Artifacts", "", f"- ROM: {artifact['detail']}"]
    lines += [f"- Save state `{s['file']}`: {s['verdict']} ({s['detail']})" for s in states]
    lines += ["", "## Evidence", ""]
    lines += [f"- `{e['path']}` sha256 `{e['sha256'][:16]}`" for e in evidence] or ["- none given"]
    if missing:
        lines += ["", "**Missing:** these files are on the report but weren't in the evidence folder:"]
        lines += [f"- {name}" for name in missing]
    lines += ["", "## History", ""]
    lines += [f"- {e.get('created_at')} {e.get('event_type')} {e.get('new_status') or ''} {e.get('note') or ''}".rstrip()
              for e in report.get("events", [])]
    if report.get("fix_attempts") or report.get("retests"):
        lines += ["", "## Fixes and retests", ""]
        lines += [f"- fix attempt {a['id']}: build {a.get('released_build_id') or 'not released'}"
                  f"{', superseded ' + a['superseded_at'] if a.get('superseded_at') else ', live'}"
                  for a in report.get("fix_attempts", [])]
        lines += [f"- retest {t['id']}: {t['outcome']} on build {t.get('tested_build_id') or 'not sure'} -> "
                  f"{t['effect']}" for t in report.get("retests", [])]
    return lines


def bundle(report_text: str, export_path: Path, evidence_dir: Optional[Path], out: Optional[Path],
           builds_dir: Path) -> Path:
    report, build = load_report(export_path, report_text)
    code = report.get("report_code") or f"RR-{int(report['id']):04d}"
    out = out or builds_dir / "repro" / code
    if out.exists() and any(out.iterdir()):
        raise BundleError(f"{out} already exists; bundles are never overwritten (pass --out somewhere new)")
    if evidence_dir is not None and not evidence_dir.is_dir():
        raise BundleError(f"{evidence_dir} isn't a folder")
    out.mkdir(parents=True, exist_ok=True)

    evidence = copy_evidence(evidence_dir, out / "evidence")
    artifact = find_build_rom(build, builds_dir)
    rom = artifact.get("rom") if artifact["status"] in ("matched", "unverified") else None
    if rom is not None:
        (out / "rom").mkdir()
        shutil.copyfile(rom, out / "rom" / rom.name)
        if artifact.get("sym"):
            shutil.copyfile(artifact["sym"], out / "rom" / artifact["sym"].name)
    states = [state_verdict(out / e["path"], rom) for e in evidence if STATE_SUFFIX.search(e["path"])]
    have = {Path(e["path"]).name.lower() for e in evidence}
    missing = [a["filename"] for a in report.get("attachments", []) if a["filename"].lower() not in have]

    (out / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    (out / "reproduction.md").write_text("\n".join(md_lines(report, build, artifact, states, missing, evidence))
                                         + "\n", encoding="utf-8", newline="\n")
    files = sorted(p for p in out.rglob("*") if p.is_file())
    manifest = {
        "report": code,
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "export": export_path.name,
        "build": {k: build.get(k) for k in ("version", "build_stamp", "git_commit", "rom_sha1", "rom_sha256")}
        if build else None,
        "artifact": {k: (str(v) if isinstance(v, Path) else v) for k, v in artifact.items()},
        "save_states": states,
        "missing_evidence": missing,
        "files": {str(p.relative_to(out)).replace("\\", "/"): sha256(p) for p in files},
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    return out


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("report", help="report ID, e.g. RR-0012")
    parser.add_argument("--export", type=Path, required=True, help="the bot's JSON export")
    parser.add_argument("--evidence", type=Path, help="folder of files you downloaded for this report")
    parser.add_argument("--out", type=Path, help="bundle folder (default: builds/repro/<report>)")
    parser.add_argument("--builds-dir", type=Path, default=REPO / "builds")
    args = parser.parse_args(argv)
    try:
        out = bundle(args.report, args.export, args.evidence, args.out, args.builds_dir)
    except (BundleError, OSError, ValueError) as e:
        print(f"repro_bundle: {e}", file=sys.stderr)
        return 2
    print(f"Wrote {out}")
    print((out / "reproduction.md").read_text(encoding="utf-8").split("\n## ")[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
