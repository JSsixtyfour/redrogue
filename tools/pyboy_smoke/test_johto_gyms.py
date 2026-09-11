"""Runtime contract for the Phase 6 Johto gym maps.

Why this exists
---------------
A Johto gym is NOT reachable in normal play until Phase 7 swaps GymMapByBadge
for GymMapByLeader, so a clean build and link proves nothing about whether the
map actually loads. Everything that typically goes wrong when adding a map -
a map_header_pointers / map_header_banks row pointing at the wrong header, a
songs row left on the old music, an object list whose count disagrees with the
text pointer table, a .blk of the wrong size for the map_const dimensions -
assembles and links perfectly and only shows up on entry.

So each gym is entered for real: boot to the lobby, repoint a lobby exit warp
at the gym, walk through it, then assert what the map header and object file
promised. Adding a gym is one row in GYMS.

Mirrors the warp-repointing trick in RedRogueHarness.preload_and_enter_wild_area,
minus the wild-area preload, which gyms do not use.
"""

from __future__ import annotations

import re
import unittest

from test_smoke import REPO_ROOT, HarnessTestCase, parse_map_constants

# parse_map_constants() returns NAME -> id only; it drops the width/height
# operands. Reading them here rather than via maps.get(f"{name}_WIDTH"), which
# silently returns None and turns the bounds assertion below into a check that
# can never fail.
MAP_DIMS_RE = re.compile(
    r"^\s*map_const\s+([A-Z0-9_]+)\s*,\s*(\d+)\s*,\s*(\d+)", re.M
)


def parse_map_dimensions(path) -> dict[str, tuple[int, int]]:
    """NAME -> (width, height) in blocks, from map_const declarations."""
    text = path.read_text(encoding="utf-8")
    return {
        match.group(1): (int(match.group(2)), int(match.group(3)))
        for match in MAP_DIMS_RE.finditer(text)
    }

# map constant -> (expected object count, leader name for the failure message)
# One row per gym. The object count is Falkner + 4 trainers + the gym guide.
GYMS = {
    "VIOLET_GYM": (6, "FALKNER"),
}

LOBBY_MAP = "INDIGO_PLATEAU_LOBBY"
WARP_NO_RETURN = 0xFD


class JohtoGymMapContracts(HarnessTestCase):
    def enter_gym(self, map_id: int, description: str) -> None:
        harness = self.harness
        assert harness is not None
        harness.boot_to_lobby()
        doors = {
            harness.read8("wLobbyDoor1StageMap"),
            harness.read8("wLobbyDoor2StageMap"),
        }
        candidates = [
            index
            for index, entry in enumerate(harness.warp_entries())
            if entry[3] in doors
        ]
        self.assertTrue(
            candidates,
            f"No lobby stage warp to repoint for {description}; doors={sorted(doors)}",
        )

        def repoint() -> None:
            harness.write8("wLobbyDoor1StageMap", map_id)
            harness.write8("wLobbyDoor2StageMap", map_id)
            for index in candidates:
                harness.write8("wWarpEntries", map_id, offset=index * 4 + 3)

        repoint()
        # SelectAndPatchLobbyExit can move the passable exit block without
        # touching the destination table, so sweep the lobby row outward from
        # the start position rather than assuming where the open door is.
        offsets = [0]
        for distance in range(1, 7):
            offsets.extend((distance, -distance))
        for offset in offsets:
            direction = "right" if offset > 0 else "left"
            for _ in range(abs(offset)):
                harness.move_tile(direction)
            harness.move_tile("up")
            for _ in range(6):
                if harness.read8("hCurMap") == map_id:
                    break
                harness.pyboy.button_press("down")
                harness.tick(40)
                harness.pyboy.button_release("down")
                harness.tick(6)
            if harness.read8("hCurMap") == map_id:
                harness.tick(120)
                return
            harness.boot_to_lobby()
            repoint()
        self.fail(
            f"Could not enter {description} (map ${map_id:02X}) through any lobby exit"
        )

    def test_johto_gyms_load_with_their_objects(self) -> None:
        constants_path = REPO_ROOT / "constants" / "map_constants.asm"
        maps = parse_map_constants(constants_path)
        dimensions = parse_map_dimensions(constants_path)
        lobby_id = maps[LOBBY_MAP]
        for name, (objects, leader) in sorted(GYMS.items()):
            with self.subTest(gym=name):
                map_id = maps[name]
                self.assertIn(
                    name, dimensions, f"{name} has no map_const width/height to check against"
                )
                width, height = dimensions[name]
                self.enter_gym(map_id, f"{name} ({leader})")

                self.assertEqual(self.harness.read8("hCurMap"), map_id)
                self.assertEqual(
                    self.harness.read8("wNumSprites"),
                    objects,
                    f"{name} loaded a different object count than its object file declares",
                )

                warps = self.harness.warp_entries()
                self.assertGreaterEqual(len(warps), 4, f"{name} lost warp entries")
                destinations = {entry[3] for entry in warps}
                self.assertIn(
                    lobby_id,
                    destinations,
                    f"{name} has no way back to the lobby; check its warp_events",
                )
                self.assertIn(
                    WARP_NO_RETURN,
                    destinations,
                    f"{name} lost its WARP_NO_RETURN entrance blockers",
                )

                # Every sprite must sit inside the map_const dimensions. A .blk
                # copied from a differently sized gym shows up here and nowhere
                # else in the build.
                for y, x in self.harness.sprite_positions(objects):
                    self.assertIn(y, range(height * 2), f"{name} sprite y out of map")
                    self.assertIn(x, range(width * 2), f"{name} sprite x out of map")


if __name__ == "__main__":
    unittest.main()
