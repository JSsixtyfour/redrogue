#!/bin/bash
# Sync test code into the frozen tree, then run witch_autoplay.py from it, with
# evidence going to builds/witch_autoplay/<snapshot>/. From PowerShell:
#
#   wsl bash /mnt/c/Users/justi/redrogue/tools/pyboy_smoke/witch_run.sh run --rom pokeblue_debug --case C03
#
# WITCH_SNAPSHOT overrides the snapshot.
set -u
live_default=$(cat "$(dirname "$0")/witch_snapshot.txt")
snapshot=${WITCH_SNAPSHOT:-$live_default}
live=$(cd "$(dirname "$0")/../.." && pwd)
bash "$live/tools/pyboy_smoke/witch_freeze.sh" "$snapshot" --sync || exit 1
cd "$HOME/witch_frozen/$snapshot" || exit 1
command=$1
shift
exec python3 tools/pyboy_smoke/witch_autoplay.py "$command" \
  --evidence "$live/builds/witch_autoplay/$snapshot" "$@"
