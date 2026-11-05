#!/bin/bash
# Sync test code into the frozen tree, then run a probe script from it:
#   wsl bash /mnt/c/Users/justi/redrogue/tools/pyboy_smoke/witch_probe.sh witch_probe_c01.py <rom>
# The probe gets the evidence directory first, then the remaining arguments.
set -u
live_default=$(cat "$(dirname "$0")/witch_snapshot.txt")
snapshot=${WITCH_SNAPSHOT:-$live_default}
live=$(cd "$(dirname "$0")/../.." && pwd)
bash "$live/tools/pyboy_smoke/witch_freeze.sh" "$snapshot" --sync >/dev/null || exit 1
cd "$HOME/witch_frozen/$snapshot/tools/pyboy_smoke" || exit 1
script=$1
shift
exec python3 "$script" "$live/builds/witch_autoplay/$snapshot" "$@"
