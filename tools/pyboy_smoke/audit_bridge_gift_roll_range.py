"""Audit: every bridge gift roll must pick entry indices inside its giver's list.

MEASURED BUG this guards (2026-10-06, playtest report RR-0011, "Oak's Lab gift
menu showed PIKACHU, TRAINING and a blank row; hovering the blank row crashed"):

  rogue_gift_randomized_batch cached the giver's gift count in wBuffer+0 and
  used it as the Rangerandom range for every slot. HOME's FarCopyData stores
  its source bank in wBuffer+0, and the GIFT_MON_EVOLVE eligibility check
  reaches FarCopyData twice (GetRewardMonLevel, LoadEvoListForSpecies). After
  the first evolve-entry check the "count" was 56 or 49 - those banks - so the
  remaining slots rolled indices past the end of the list. The menu then read
  a garbage GiftEntry: a blank name, and a description pointer whose PrintText
  jumped into VRAM. Measured on build 8e6ca844: Oak's Lab rolled [3, 37, 21]
  against a 7-entry list. The fix re-reads the count with GetGiverCount at
  every use instead of caching it.

The bug is probabilistic (it needs an evolve entry checked before a later slot
is rolled), so this enters every bridge room from one saved lobby state under
several RNG seeds, and asserts on EVERY GetGiftEntry call (roll + menu share
it) that the index is below that giver's count read from the built ROM, plus
that wGift1-3 end in range.

Usage:
    python3 tools/pyboy_smoke/audit_bridge_gift_roll_range.py [--seeds N]
    python3 tools/pyboy_smoke/audit_bridge_gift_roll_range.py --archived <build tag>
        (runs against builds/releases/<tag>.gbc/.sym, e.g. to prove it fails
        on pokeblue_debug_2026-10-05_233457_8e6ca844)
"""

from __future__ import annotations

import argparse
import io
import shutil
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

BRIDGE_MAPS = (
    "COPYCATS_HOUSE_2F", "BILLS_HOUSE", "MR_FUJIS_HOUSE",
    "SS_ANNE_CAPTAINS_ROOM", "CINNABAR_LAB_FOSSIL_ROOM",
    "POKEMON_FAN_CLUB", "WARDENS_HOUSE", "VIRIDIAN_SCHOOL_HOUSE",
    "VIRIDIAN_NICKNAME_HOUSE", "CERULEAN_TRASHED_HOUSE",
    "REDS_HOUSE_1F", "IGAS_DOJO", "FLORAS_GROTTO", "OAKS_LAB",
)


def rom_byte(rom: bytes, bank: int, address: int) -> int:
    if address < 0x4000:
        return rom[address]
    return rom[bank * 0x4000 + address - 0x4000]


def giver_counts(h: RedRogueHarness, rom: bytes) -> dict[int, int]:
    """map id -> gift count, read from BridgeGiverMapTable/BridgeGiverLists."""
    map_bank, map_table = h.symbols.get("BridgeGiverMapTable")
    list_bank, list_table = h.symbols.get("BridgeGiverLists")
    counts: dict[int, int] = {}
    for index in range(len(BRIDGE_MAPS)):
        map_id = rom_byte(rom, map_bank, map_table + index)
        low = rom_byte(rom, list_bank, list_table + index * 2)
        high = rom_byte(rom, list_bank, list_table + index * 2 + 1)
        counts[map_id] = rom_byte(rom, list_bank, (high << 8) | low)
    return counts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=4)
    parser.add_argument("--archived", help="builds/releases tag to test instead of the current build")
    args = parser.parse_args()

    root = REPO_ROOT
    tmp = None
    if args.archived:
        tmp = tempfile.TemporaryDirectory()
        root = Path(tmp.name)
        src = REPO_ROOT / "builds" / "releases"
        shutil.copy(src / (args.archived + ".sym"), root / "pokeblue_debug.sym")
        shutil.copy(src / (args.archived + ".gbc"), root / "pokeblue_debug.gbc")

    maps = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
    h = RedRogueHarness(root, REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts")
    rom = h.rom_path.read_bytes()
    counts = giver_counts(h, rom)
    expected = {maps[name] for name in BRIDGE_MAPS}
    if set(counts) != expected:
        print(f"FAIL: giver table maps {sorted(counts)} != bridge maps {sorted(expected)}")
        return 1

    bad: list[str] = []
    calls = {"n": 0}

    def on_get_gift_entry(_context) -> None:
        index = h.pyboy.register_file.A
        cur_map = h.read8("hCurMap")
        count = counts.get(cur_map)
        calls["n"] += 1
        if count is not None and index >= count:
            bad.append(f"map {cur_map}: GetGiftEntry index {index} >= count {count}")

    h.register_hook("GetGiftEntry", on_get_gift_entry)
    h.boot_to_lobby(battle_count=6, encounter_kind=2)
    lobby = io.BytesIO()
    h.save_state(lobby)

    entries = 0
    for name in BRIDGE_MAPS:
        map_id = maps[name]
        for seed in range(args.seeds):
            lobby.seek(0)
            h.load_state(lobby)
            h.seed_rng([seed * 37 + 11, map_id, seed, 0xA5])
            h.enter_stage_door1(map_id, description=name)
            gifts = h.read_bytes("wGift1", 3)
            entries += 1
            if any(g >= counts[map_id] for g in gifts):
                bad.append(f"{name} seed {seed}: wGift1-3 = {gifts}, count {counts[map_id]}")

    h.close()
    if tmp:
        tmp.cleanup()
    print(f"{entries} bridge entries, {calls['n']} GetGiftEntry calls checked")
    if bad:
        print("FAIL:")
        for line in bad[:30]:
            print("  " + line)
        return 1
    print("OK: every bridge gift index is inside its giver's list")
    return 0


if __name__ == "__main__":
    sys.exit(main())
