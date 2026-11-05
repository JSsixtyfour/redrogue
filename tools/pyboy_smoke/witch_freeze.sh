#!/bin/bash
# Bind a witch-autoplay campaign to one frozen build. Run from WSL:
#
#   bash tools/pyboy_smoke/witch_freeze.sh <snapshot-id>         # (re)create the tree
#   bash tools/pyboy_smoke/witch_freeze.sh <snapshot-id> --sync  # refresh test code only
#
# The source tree is shared with other sessions, and a rebuild there replaces the
# root ROMs mid-run (measured 2026-11-04: pokeblue_debug.gbc changed hash during a
# one-minute test pass). Every tool resolves ROOT from its own file path, so running
# them from a copy binds harness, autoplay, constants and ROM to one snapshot with no
# code change. The copy lives in the WSL home rather than under builds/: audits rglob
# the repo for sources, and /mnt/c reads are the slowest part of a harness run.
#
# builds/witch_autoplay/<snapshot>/ must already hold roms/, SHA256SUMS and
# source/{head.txt,working.diff}. Evidence stays there; only the runnable tree is here.
set -eu
snapshot=$1
mode=${2:-}
live=$(cd "$(dirname "$0")/../.." && pwd)
evidence="$live/builds/witch_autoplay/$snapshot"
tree="$HOME/witch_frozen/$snapshot"

[ -d "$evidence/roms" ] || { echo "no archived ROMs in $evidence"; exit 1; }

if [ "$mode" != "--sync" ]; then
  rm -rf "$tree"
  mkdir -p "$tree"
  head=$(cut -d' ' -f1 "$evidence/source/head.txt")
  git -C "$live" archive "$head" \
    | tar -x -C "$tree" --exclude='*.png' --exclude='*.wav' --exclude='*.pdf' --exclude='*.mid'
  if [ -s "$evidence/source/working.diff" ]; then
    git -C "$tree" init -q 2>/dev/null || true
    (cd "$tree" && git apply --whitespace=nowarn --ignore-whitespace "$evidence/source/working.diff") \
      || echo "WARNING: working.diff did not apply; sources differ, ROMs are still the frozen ones"
    rm -rf "$tree/.git"
  fi
  cp "$evidence/roms/"*.gbc "$evidence/roms/"*.sym "$tree/"
  if [ -d "$evidence/roms/maps" ]; then cp "$evidence/roms/maps/"*.map "$tree/"; fi
fi

# Test code may move on while the game stays frozen. Copy it, and say which.
cp "$live"/tools/pyboy_smoke/*.py "$live"/tools/pyboy_smoke/*.json "$tree/tools/pyboy_smoke/"
(cd "$tree" && sha256sum pokered.gbc pokeblue.gbc pokeblue_debug.gbc) > "$tree/ROM_SHA256"
(cd "$live/tools/pyboy_smoke" && cat witch_*.py 2>/dev/null | sha256sum | cut -c1-12) > "$tree/TESTCODE_HASH"

# Refuse to hand back a tree whose ROMs are not the archived ones.
for rom in pokered pokeblue pokeblue_debug; do
  want=$(grep "$rom.gbc" "$evidence/SHA256SUMS" | cut -d' ' -f1)
  have=$(grep " $rom.gbc" "$tree/ROM_SHA256" | cut -d' ' -f1)
  [ "$want" = "$have" ] || { echo "HASH MISMATCH $rom: $want vs $have"; exit 2; }
done
echo "frozen tree ok: $tree (test code $(cat "$tree/TESTCODE_HASH"))"
