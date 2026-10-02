#!/usr/bin/env python3
"""make release: build, test, and hand the debug ROM to the playtest bot.

    make release                      asks for the notes
    make release RELEASE_ARGS='--notes "New gym" --testing "Gym 3"'
    make release RELEASE_ARGS=--dry-run   everything except sending

In order, stopping at the first failure:
1. Refuses uncommitted changes to tracked files (a -dirty build can't be rebuilt
   from git) and a commit that isn't on GitHub yet (the bot reads the commits
   since the last release from there, to link "Fixes RR-0012" and draft notes).
2. Builds all three ROMs, then runs `make smoke`.
3. Keeps that build's pokeblue_debug .gbc and .sym in builds/releases/, which
   BUILD_KEEP never prunes, so tools/crash_lookup.py can always read a tester's
   crash screen.
4. Posts the ROM and a release.json to the Discord webhook in RELEASE_WEBHOOK_URL
   (from the environment or this repo's untracked .env). The bot releases it
   exactly like /build set-current and replies under it in that channel.

Notes left empty are drafted by the bot from the commit messages.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BUILDS = REPO / "builds"
RELEASES = BUILDS / "releases"
ROM = "pokeblue_debug"


def fail(message: str) -> None:
    sys.exit(f"\nmake release stopped: {message}")


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=REPO, check=True, capture_output=True, text=True).stdout.strip()


def check_git() -> str:
    """The short hash being released, once it's clean and pushed."""
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
    return git("rev-parse", "--short", "HEAD")


def ask(prompt: str) -> str:
    try:
        return input(prompt).strip()
    except EOFError:
        return ""


def run(*command: str) -> None:
    print(f"\n$ {' '.join(command)}", flush=True)
    if subprocess.run(command, cwd=REPO).returncode != 0:
        fail(f"`{' '.join(command)}` failed; nothing was sent.")


def newest_build(short_hash: str) -> Path:
    matches = sorted(BUILDS.glob(f"{ROM}_*_{short_hash}.gbc"))
    if not matches:
        fail(f"no {ROM}_*_{short_hash}.gbc in builds/ after building (dirty build?).")
    return matches[-1]


def keep(rom: Path) -> None:
    RELEASES.mkdir(parents=True, exist_ok=True)
    for path in (rom, rom.with_suffix(".sym")):
        if path.is_file():
            shutil.copy2(path, RELEASES / path.name)
    print(f"Kept {rom.stem} .gbc/.sym in builds/releases/")


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


def send(url: str, rom: Path, meta: dict) -> None:
    payload = {"content": f"Release request from `make release`: **{rom.name}**",
               "allowed_mentions": {"parse": []}}
    body, ctype = multipart([
        ("payload_json", "", json.dumps(payload).encode(), "application/json"),
        ("files[0]", rom.name, rom.read_bytes(), None),
        ("files[1]", "release.json", json.dumps(meta).encode(), "application/json"),
    ])
    request = urllib.request.Request(url + ("&" if "?" in url else "?") + "wait=true", data=body, method="POST",
                                     headers={"Content-Type": ctype, "User-Agent": "redrogue-release (tools/release.py)"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            response.read()
    except urllib.error.HTTPError as e:
        fail(f"Discord said {e.code}: {e.read().decode(errors='replace')[:300]}")
    except urllib.error.URLError as e:
        fail(f"couldn't reach Discord: {e.reason}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--notes", help="What's new (default: ask; empty lets the bot draft it from commits)")
    parser.add_argument("--testing", help="What testers should focus on (default: ask)")
    parser.add_argument("--no-announce", action="store_true", help="set the build without announcing it")
    parser.add_argument("--dry-run", action="store_true", help="do everything except sending to Discord")
    args = parser.parse_args(argv)

    url = None if args.dry_run else webhook_url()  # fail before the long build, not after
    short_hash = check_git()
    print(f"Releasing commit {short_hash}: {git('log', '-1', '--format=%s')}")
    notes = args.notes if args.notes is not None else ask("What's new (Enter: drafted from the commits): ")
    testing = args.testing if args.testing is not None else ask("What to test (Enter: nothing): ")

    run("make", "-j8")
    run("make", "smoke")
    rom = newest_build(short_hash)
    keep(rom)
    meta = {"release_notes": notes, "testing_notes": testing, "announce": not args.no_announce}
    if args.dry_run:
        print(f"\nDry run: would send {rom.name} with {json.dumps(meta)}")
        return 0
    send(url, rom, meta)
    print(f"\nSent {rom.name}. The bot replies under it in the release channel.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
