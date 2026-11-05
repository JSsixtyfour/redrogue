#!/bin/bash
# Build all three ROMs from the live tree, archive them and the sources as a new
# witch-autoplay snapshot, create its frozen tree and point witch_snapshot.txt at it.
# Prints the snapshot id. Run from WSL:
#
#   bash tools/pyboy_smoke/witch_new_snapshot.sh
set -eu
live=$(cd "$(dirname "$0")/../.." && pwd)
cd "$live"
make -j6 all_roms > /tmp/witch_new_snapshot_build.log 2>&1 || { tail -30 /tmp/witch_new_snapshot_build.log; exit 1; }
head=$(git rev-parse HEAD)
diff=$(mktemp)
git diff HEAD --binary > "$diff"
snapshot="${head:0:8}_$(sha256sum "$diff" | cut -c1-8)"
evidence="builds/witch_autoplay/$snapshot"
mkdir -p "$evidence/roms" "$evidence/source"
cp pokered.gbc pokeblue.gbc pokeblue_debug.gbc pokered.sym pokeblue.sym pokeblue_debug.sym "$evidence/roms/"
(cd "$evidence/roms" && sha256sum *.gbc *.sym) > "$evidence/SHA256SUMS"
mkdir -p "$evidence/roms/maps"
cp pokered.map pokeblue.map pokeblue_debug.map "$evidence/roms/maps/"
git log -1 --format='%H %s' > "$evidence/source/head.txt"
git status --short > "$evidence/source/status.txt"
mv "$diff" "$evidence/source/working.diff"
bash tools/pyboy_smoke/witch_freeze.sh "$snapshot"
printf '%s\n' "$snapshot" > tools/pyboy_smoke/witch_snapshot.txt
echo "$snapshot"
