#!/bin/bash
# Sync, then run witch_diagnose.py from the frozen tree: witch_diag.sh <rom> <seed> [options]
set -u
live_default=$(cat "$(dirname "$0")/witch_snapshot.txt")
snapshot=${WITCH_SNAPSHOT:-$live_default}
live=$(cd "$(dirname "$0")/../.." && pwd)
bash "$live/tools/pyboy_smoke/witch_freeze.sh" "$snapshot" --sync >/dev/null || exit 1
cd "$HOME/witch_frozen/$snapshot/tools/pyboy_smoke" || exit 1
rom=$1
seed=$2
shift 2
exec python3 witch_diagnose.py "$rom" "$seed" "$live/builds/witch_autoplay/$snapshot" "$@"
