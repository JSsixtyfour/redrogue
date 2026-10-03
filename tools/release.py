#!/usr/bin/env python3
"""make release: build, check, archive, and hand the debug ROM to the playtest bot.

    make release                      asks for the notes
    make release RELEASE_ARGS='--notes "New gym" --testing "Gym 3"'
    make release RELEASE_ARGS='--save-compat supported --save-compat-from 74f82c1b'
    make release RELEASE_ARGS=--dry-run   everything except sending

In order, stopping at the first failure (nothing is sent after a failure):
1. Refuses uncommitted changes to tracked files (a -dirty build can't be rebuilt
   from git) and a commit that isn't on GitHub yet (the bot reads the commits
   since the last release from there, to link "Fixes RR-0012" and draft notes).
2. Relinks all three ROMs (so every archive is stamped with this commit), then
   runs make save_schema, make save_converter, a space report, make audit and
   make smoke. Each one's output is logged.
3. Finds this run's archived ROMs by content, not by "newest name": each
   builds/<rom>_<stamp>_<hash>.gbc must match the ROM the build just wrote,
   with its .sym and .map.
4. Keeps a release package in builds/releases/<debug ROM name>/: the three
   ROMs with .sym and .map, the check logs, and manifest.json (commit, hashes,
   tool versions, check results, save compatibility, manual acceptance:
   pending), and the patch page's save converter for this build's save
   schema (save/save-convert-<hash>.js). A package that already exists with different bytes is never
   overwritten. The debug .gbc/.sym also stay directly in builds/releases/,
   where tools/crash_lookup.py looks.
5. Posts the debug ROM, its .sym, the save converter and a release.json (notes plus the manifest) to the
   Discord webhook in RELEASE_WEBHOOK_URL (environment or this repo's untracked
   .env). The bot checks the ROM against the manifest's hash, releases it like
   /build set-current, and replies under it. sent.json in the package records it.

Notes left empty are drafted by the bot from the commit messages. Save
compatibility defaults to "unverified": say "supported" only after loading a
save from an earlier build (--save-compat-from names it).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BUILDS = REPO / "builds"
RELEASES = BUILDS / "releases"
ROM = "pokeblue_debug"                       # what testers get
ROMS = ("pokered", "pokeblue", "pokeblue_debug")  # what gets archived
MANIFEST_VERSION = 2  # 2: "save" (the save converter package and the save schema)
SAVE_COMPAT = ("supported", "new_save_required", "unverified")


class ReleaseError(Exception):
    pass


def fail(message: str) -> None:
    raise ReleaseError(message)


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=REPO, check=True, capture_output=True, text=True).stdout.strip()


def check_git() -> tuple[str, str]:
    """(full hash, short hash) being released, once it's clean and pushed."""
    if subprocess.run(["git", "diff", "--quiet", "HEAD", "--"], cwd=REPO).returncode != 0:
        fail("there are uncommitted changes. Commit them (and push), then run it again.")
    untracked = git("ls-files", "--others", "--exclude-standard")
    if untracked:
        print("Note: untracked files, not part of the commit (fine unless the build uses them):")
        for line in untracked.splitlines()[:10]:
            print(f"  {line}")
    print("Checking the commit is on GitHub...")
    subprocess.run(["git", "fetch", "--quiet", "origin"], cwd=REPO, check=False)
    if not git("branch", "-r", "--contains", "HEAD"):
        fail("this commit isn't pushed. Push it, then run it again.")
    return git("rev-parse", "HEAD"), git("rev-parse", "--short", "HEAD")


def ask(prompt: str) -> str:
    try:
        return input(prompt).strip()
    except EOFError:
        return ""


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def file_entry(path: Path) -> dict:
    data = path.read_bytes()
    return {"name": path.name, "size": len(data), "sha1": hashlib.sha1(data).hexdigest(),
            "sha256": hashlib.sha256(data).hexdigest()}


# --- checks -------------------------------------------------------------------------

def run_check(name: str, command: list[str], log_dir: Path) -> dict:
    """Run one check, echoing its output and logging it. Returns its manifest entry;
    a failing check raises after its log is written."""
    print(f"\n$ {' '.join(command)}", flush=True)
    log = log_dir / f"{name}.log"
    start = time.monotonic()
    with log.open("w", encoding="utf-8", newline="\n") as out:
        out.write(f"$ {' '.join(command)}\n")
        with subprocess.Popen(command, cwd=REPO, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                              encoding="utf-8", errors="replace") as proc:
            for line in proc.stdout:
                sys.stdout.write(line)
                out.write(line)
            code = proc.wait()
        out.write(f"\n[exit {code}]\n")
    entry = {"name": name, "command": " ".join(command), "exit_code": code,
             "seconds": round(time.monotonic() - start, 1), "log": f"logs/{log.name}", "log_sha256": sha256(log)}
    if code != 0:
        fail(f"`{' '.join(command)}` failed (log: {log}); nothing was sent.")
    return entry


def checks(log_dir: Path, space_json: Path) -> list[dict]:
    # Touching buildid.asm (mtime only; git sees no change) makes make relink all
    # three ROMs, so their archives carry this commit's hash and one shared stamp.
    (REPO / "buildid.asm").touch()
    # Fastest checks first, so a quick failure doesn't wait out smoke and audit.
    return [
        run_check("build", ["make", "-j8"], log_dir),
        # Also keeps this build's constants in the package, so the next check protects what testers' saves hold.
        run_check("save_schema", ["python3", "tools/save_schema.py", "check",
                                  "--save-values", str(log_dir.parent / "save_values.json")], log_dir),
        run_check("save_converter", ["make", "save_converter"], log_dir),
        run_check("space", ["python3", "tools/space_report.py", "pokered.map", "pokeblue.map", "pokeblue_debug.map",
                            "--save", str(space_json)], log_dir),
        run_check("audit", ["make", "audit"], log_dir),
        run_check("smoke", ["make", "smoke"], log_dir),
    ]


def tool_versions() -> dict:
    def version(*command: str) -> str | None:
        try:
            out = subprocess.run(command, cwd=REPO, capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            return None
        return (out.stdout or out.stderr).strip().splitlines()[0] if out.returncode == 0 else None

    return {"rgbasm": version("rgbasm", "--version"), "rgblink": version("rgblink", "--version"),
            "rgbfix": version("rgbfix", "--version"), "python": platform.python_version(),
            "pyboy": version("python3", "-c", "import pyboy; print(pyboy.__version__)"),
            "git": version("git", "--version"), "make": version("make", "--version"),
            "rgbds_pinned": (REPO / ".rgbds-version").read_text().strip() if (REPO / ".rgbds-version").is_file() else None}


# --- artifacts ------------------------------------------------------------------------

def find_artifacts(short_hash: str, since: float) -> tuple[str, dict[str, dict[str, Path]]]:
    """(build stamp, rom -> {"gbc", "sym", "map"}) for the ROMs this run linked.

    The debug archive is found by content: it must equal the pokeblue_debug.gbc
    the build just wrote and carry this commit's hash. The other two must share
    its stamp and also equal their freshly built files."""
    built = REPO / f"{ROM}.gbc"
    if not built.is_file():
        fail(f"{ROM}.gbc is missing after the build.")
    want = sha256(built)
    matches = [p for p in BUILDS.glob(f"{ROM}_*_{short_hash}.gbc") if p.stat().st_mtime >= since and sha256(p) == want]
    if len(matches) != 1:
        fail(f"expected exactly one archive in builds/ matching the {ROM}.gbc just built for {short_hash}, "
             f"found {len(matches)} (was it relinked?).")
    stamp = matches[0].stem[len(ROM) + 1:-(len(short_hash) + 1)]
    found = {}
    for rom in ROMS:
        archive = BUILDS / f"{rom}_{stamp}_{short_hash}.gbc"
        paths = {"gbc": archive, "sym": archive.with_suffix(".sym"), "map": REPO / f"{rom}.map"}
        for kind, path in paths.items():
            if not path.is_file():
                fail(f"{path.relative_to(REPO)} is missing; a release needs every ROM's .gbc, .sym and .map.")
        if sha256(archive) != sha256(REPO / f"{rom}.gbc"):
            fail(f"{archive.name} doesn't match the {rom}.gbc just built.")
        if sha256(paths["sym"]) != sha256(REPO / f"{rom}.sym"):
            fail(f"{paths['sym'].name} doesn't match the {rom}.sym just built.")
        if paths["map"].stat().st_mtime < since:
            fail(f"{rom}.map is older than this release run; it wasn't written by this build.")
        found[rom] = paths
    return stamp, found


def place(src: Path, dest: Path) -> None:
    """Copy, unless dest already holds exactly these bytes. Never overwrites different bytes."""
    if dest.exists():
        if sha256(dest) != sha256(src):
            fail(f"{dest} already exists with different contents; releases are never overwritten.")
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)


def package(stamp: str, short_hash: str, artifacts: dict, staging: Path, manifest: dict) -> Path:
    """Copy everything into builds/releases/<debug ROM name>/ and write manifest.json."""
    pkg = RELEASES / f"{ROM}_{stamp}_{short_hash}"
    if pkg.exists() and (pkg / "manifest.json").is_file():
        old = json.loads((pkg / "manifest.json").read_text(encoding="utf-8"))
        if old.get("artifacts") != manifest["artifacts"]:
            fail(f"{pkg} already holds a different release; releases are never overwritten.")
        print(f"{pkg.name} is already packaged with identical ROMs; reusing it.")
        return pkg
    for paths in artifacts.values():
        for path in paths.values():
            name = path.name if path.suffix != ".map" else f"{paths['gbc'].stem}.map"
            place(path, pkg / name)
    for item in staging.iterdir():
        if item.is_file():
            place(item, pkg / item.name)
        else:
            shutil.copytree(item, pkg / item.name, dirs_exist_ok=True)
    (pkg / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    # Where crash_lookup.py and older tooling look.
    debug = artifacts[ROM]
    place(debug["gbc"], RELEASES / debug["gbc"].name)
    place(debug["sym"], RELEASES / debug["sym"].name)
    print(f"Kept the release in builds/releases/{pkg.name}/")
    return pkg


def build_converter(out_dir: Path, artifacts: dict) -> dict:
    """Build the patch page's save converter for this build's save schema
    (tools/save_compat/build_package.py) into out_dir/save/. Returns the
    manifest's "save" entry: the schema, the converter file and its hash, and
    the ROM it converts saves for."""
    sys.path.insert(0, str(Path(__file__).resolve().parent / "save_compat"))
    import build_package  # noqa: E402  (tools/save_compat, same interpreter)

    path = build_package.build(out_dir / "save", None)
    return {"schema": build_package.schema_id(), "converter": f"save/{path.name}", "converter_sha256": sha256(path),
            "target_rom_sha256": sha256(artifacts[ROM]["gbc"]), "recovery": False}


def build_manifest(full_hash: str, short_hash: str, stamp: str, artifacts: dict, check_results: list[dict],
                   save: dict, tools: dict, converter: dict | None = None) -> dict:
    rel = {}
    for rom, paths in artifacts.items():
        rel[rom] = {kind: file_entry(path) for kind, path in paths.items()}
        rel[rom]["map"]["name"] = f"{paths['gbc'].stem}.map"
    return {
        "manifest_version": MANIFEST_VERSION,
        "commit": full_hash,
        "short_commit": short_hash,
        "dirty": False,
        "build_stamp": stamp,
        "variant": ROM,
        "release_rom": rel[ROM]["gbc"]["name"],
        "artifacts": rel,
        "checks": check_results,
        "tools": tools,
        "save_compatibility": save,
        "save": converter,
        "manual_acceptance": {"status": "pending",
                              "note": "Playing the build is separate from these automated checks."},
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


# --- save compatibility ---------------------------------------------------------------

def save_compat(args) -> dict:
    status = args.save_compat
    if status is None:
        answer = ask("Save compatibility: supported / new_save_required / unverified (Enter: unverified): ")
        status = answer or "unverified"
    if status not in SAVE_COMPAT:
        fail(f"save compatibility must be one of {', '.join(SAVE_COMPAT)}, not {status!r}.")
    tested_from = args.save_compat_from
    if status == "supported" and not tested_from:
        tested_from = ask("Which earlier build's save did you load in this one (e.g. 74f82c1b)? ")
        if not tested_from:
            fail("'supported' needs the earlier build you tested a save from (--save-compat-from).")
    return {"status": status, "tested_from": tested_from or None, "notes": args.save_compat_notes or None}


# --- sending --------------------------------------------------------------------------

def webhook_url() -> str:
    url = os.environ.get("RELEASE_WEBHOOK_URL", "").strip()
    env = REPO / ".env"
    if not url and env.is_file():
        for line in env.read_text(encoding="utf-8").splitlines():
            key, _, value = line.partition("=")
            if key.strip() == "RELEASE_WEBHOOK_URL":
                url = value.strip().strip('"')
    if not url.startswith("https://"):
        fail("RELEASE_WEBHOOK_URL isn't set. Put RELEASE_WEBHOOK_URL=<the webhook's URL> in this repo's .env.")
    return url


def multipart(fields: list[tuple[str, str, bytes, str | None]]) -> tuple[bytes, str]:
    """(name, filename or "", data, content type) parts -> body, Content-Type."""
    boundary = uuid.uuid4().hex
    body = bytearray()
    for name, filename, data, ctype in fields:
        body += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"".encode()
        if filename:
            body += f"; filename=\"{filename}\"".encode()
        body += f"\r\nContent-Type: {ctype or 'application/octet-stream'}\r\n\r\n".encode()
        body += data + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return bytes(body), f"multipart/form-data; boundary={boundary}"


def send(url: str, rom: Path, meta: dict, sym: Path | None = None, converter: Path | None = None) -> dict:
    """POST the ROM, release.json, the ROM's .sym (so the bot can look up crash
    screens) and the save converter to the webhook; returns Discord's message object."""
    payload = {"content": f"Release request from `make release`: **{rom.name}**",
               "allowed_mentions": {"parse": []}}
    body, ctype = multipart([
        ("payload_json", "", json.dumps(payload).encode(), "application/json"),
        ("files[0]", rom.name, rom.read_bytes(), None),
        ("files[1]", "release.json", json.dumps(meta).encode(), "application/json"),
        *([("files[2]", sym.name, sym.read_bytes(), "text/plain")] if sym is not None else []),
        *([("files[3]", converter.name, converter.read_bytes(), "text/javascript")] if converter is not None else []),
    ])
    request = urllib.request.Request(url + ("&" if "?" in url else "?") + "wait=true", data=body, method="POST",
                                     headers={"Content-Type": ctype, "User-Agent": "redrogue-release (tools/release.py)"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
    except urllib.error.HTTPError as e:
        fail(f"Discord said {e.code}: {e.read().decode(errors='replace')[:300]}")
    except urllib.error.URLError as e:
        fail(f"couldn't reach Discord: {e.reason}")
    try:
        return json.loads(raw or b"{}")
    except ValueError:
        return {}


# --- main -----------------------------------------------------------------------------

def release(args) -> int:
    save = save_compat(args)
    url = None if args.dry_run else webhook_url()  # fail before the long build, not after
    full_hash, short_hash = check_git()
    print(f"Releasing commit {short_hash}: {git('log', '-1', '--format=%s')}")
    notes = args.notes if args.notes is not None else ask("What's new (Enter: drafted from the commits): ")
    testing = args.testing if args.testing is not None else ask("What to test (Enter: nothing): ")

    RELEASES.mkdir(parents=True, exist_ok=True)
    staging = RELEASES / f".staging-{uuid.uuid4().hex[:8]}"
    (staging / "logs").mkdir(parents=True)
    try:
        since = time.time() - 2  # filesystem timestamps can be coarse
        results = checks(staging / "logs", staging / "space.json")
        stamp, artifacts = find_artifacts(short_hash, since)
        converter = build_converter(staging, artifacts)
        manifest = build_manifest(full_hash, short_hash, stamp, artifacts, results, save, tool_versions(), converter)
        pkg = package(stamp, short_hash, artifacts, staging, manifest)
    finally:
        shutil.rmtree(staging, ignore_errors=True)

    rom = artifacts[ROM]["gbc"]
    meta = {"release_notes": notes, "testing_notes": testing, "announce": not args.no_announce,
            "save_compatibility": save["status"], "save_compat_from": save["tested_from"],
            "save_compat_notes": save["notes"], "manifest": manifest}
    if args.dry_run:
        print(f"\nDry run: would send {rom.name} (sha256 {manifest['artifacts'][ROM]['gbc']['sha256'][:16]}...), "
              f"save compatibility {save['status']}. Nothing was sent.")
        return 0
    message = send(url, rom, meta, artifacts[ROM]["sym"], pkg / manifest["save"]["converter"])
    (pkg / "sent.json").write_text(json.dumps({"sent_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                                               "message_id": message.get("id"),
                                               "channel_id": message.get("channel_id")}, indent=2) + "\n",
                                   encoding="utf-8", newline="\n")
    print(f"\nSent {rom.name}. The bot replies under it in the release channel.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--notes", help="What's new (default: ask; empty lets the bot draft it from commits)")
    parser.add_argument("--testing", help="What testers should focus on (default: ask)")
    parser.add_argument("--save-compat", choices=SAVE_COMPAT,
                        help="whether saves from earlier builds load (default: ask; Enter means unverified)")
    parser.add_argument("--save-compat-from", help="for 'supported': the earlier build whose save you loaded")
    parser.add_argument("--save-compat-notes", help="anything testers should know about their saves")
    parser.add_argument("--no-announce", action="store_true", help="set the build without announcing it")
    parser.add_argument("--dry-run", action="store_true", help="do everything except sending to Discord")
    args = parser.parse_args(argv)
    try:
        return release(args)
    except ReleaseError as e:
        print(f"\nmake release stopped: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
