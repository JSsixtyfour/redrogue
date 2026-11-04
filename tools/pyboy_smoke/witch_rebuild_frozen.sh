#!/bin/bash
# Rebuild all three ROMs inside an isolated copy of a snapshot's source and compare
# them to the archive, to prove the snapshot reproduces its ROMs and to get the .map
# files the static walker needs (the shared tree's may be from another build).
#
# BUILD_ID is passed explicitly because the debug ROM embeds it and this copy has no
# git metadata: "nogit-dirty" is 3 bytes shorter and shifts the whole layout. The
# debug ROM also embeds the build date, so it reproduces when its symbols are
# identical and only a few bytes differ. Release ROMs must match exactly.
set -u
snapshot=$1
live=$(cd "$(dirname "$0")/../.." && pwd)
evidence="$live/builds/witch_autoplay/$snapshot"
tree="$HOME/witch_frozen/$snapshot"
build="$HOME/witch_frozen/${snapshot}_build"
rm -rf "$build"
mkdir -p "$build"
head=$(cut -d' ' -f1 "$evidence/source/head.txt")
git -C "$live" archive "$head" | tar -x -C "$build"
(cd "$build" && git init -q && git apply --whitespace=nowarn --ignore-whitespace "$evidence/source/working.diff") || exit 3
rm -rf "$build/.git"
cd "$build" || exit 1
make -j6 all_roms BUILD_ID="${head:0:8}-dirty" > build.log 2>&1
status=$?
tail -2 build.log
echo "make status=$status"
[ "$status" = 0 ] || exit "$status"
ok=1
for rom in pokered pokeblue; do
  want=$(grep "$rom.gbc" "$evidence/SHA256SUMS" | cut -d' ' -f1)
  have=$(sha256sum "$rom.gbc" | cut -d' ' -f1)
  echo "$rom archived=${want:0:12} rebuilt=${have:0:12}"
  [ "$want" = "$have" ] || ok=0
done
want=$(grep "pokeblue_debug.sym" "$evidence/SHA256SUMS" | cut -d' ' -f1)
have=$(sha256sum pokeblue_debug.sym | cut -d' ' -f1)
differing=$(cmp -l pokeblue_debug.gbc "$evidence/roms/pokeblue_debug.gbc" | wc -l)
echo "pokeblue_debug sym archived=${want:0:12} rebuilt=${have:0:12}, $differing ROM bytes differ"
cmp -l pokeblue_debug.gbc "$evidence/roms/pokeblue_debug.gbc" | head -20
[ "$want" = "$have" ] && [ "$differing" -le 24 ] || ok=0
if [ "$ok" = 1 ]; then
  cp pokered.map pokeblue.map pokeblue_debug.map "$tree/"
  mkdir -p "$evidence/roms/maps"
  cp pokered.map pokeblue.map pokeblue_debug.map "$evidence/roms/maps/"
  echo "REPRODUCED: maps copied to the frozen tree and the archive"
else
  echo "NOT REPRODUCED: see $build"
  exit 4
fi
