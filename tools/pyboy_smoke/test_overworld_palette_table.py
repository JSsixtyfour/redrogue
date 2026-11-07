"""GetOverworldPalette gives each map vanilla's colour when a run enters it from the lobby.

Vanilla colours an indoor map by the town its door is in, read from wLastMap. A
run walks in from the lobby instead, whose id falls through to PAL_ROUTE, so a
map needs its own MapPalettes row to keep its town colour with Enhanced off.
"""
from pathlib import Path
import io
import re
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT = Path(__file__).resolve().parents[2]

# Maps a run enters, by the town whose door leads in on vanilla.
TOWN_MAPS = {
    "PAL_PALLET": ["REDS_HOUSE_1F", "OAKS_LAB"],
    "PAL_VIRIDIAN": ["VIRIDIAN_GYM", "VIRIDIAN_SCHOOL_HOUSE", "OLD_MANS_HOUSE"],
    "PAL_PEWTER": ["PEWTER_GYM"],
    "PAL_CERULEAN": ["CERULEAN_GYM", "CERULEAN_TRASHED_HOUSE"],
    "PAL_LAVENDER": ["MR_FUJIS_HOUSE"],
    "PAL_VERMILION": ["VERMILION_GYM", "POKEMON_FAN_CLUB", "SS_ANNE_B1F",
                      "SS_ANNE_B1F_ROOMS", "SS_ANNE_CAPTAINS_ROOM"],
    "PAL_CELADON": ["CELADON_GYM", "GAME_CORNER", "ROCKET_HIDEOUT_B1F"],
    "PAL_FUCHSIA": ["FUCHSIA_GYM", "WARDENS_HOUSE"],
    "PAL_CINNABAR": ["CINNABAR_GYM", "POKEMON_MANSION_1F", "CINNABAR_LAB_FOSSIL_ROOM"],
    "PAL_INDIGO": ["INDIGO_PLATEAU_LOBBY", "LANCES_ROOM", "CHAMPIONS_ROOM", "HALL_OF_FAME"],
    "PAL_SAFFRON": ["SAFFRON_GYM", "FIGHTING_DOJO", "COPYCATS_HOUSE_2F"],
}
# Vanilla's door is on a route, so these inherit PAL_ROUTE and have no row.
# Azalea's gym and Flora's Grotto have no vanilla colour and are chosen green.
ROUTE_MAPS = ["BILLS_HOUSE", "POWER_PLANT", "VIRIDIAN_FOREST", "AZALEA_GYM", "FLORAS_GROTTO"]
# Maps with no vanilla colour, chosen per map.
CHOSEN_MAPS = {
    "VIOLET_GYM": "PAL_CERULEAN",
    "GOLDENROD_GYM": "PAL_PINKMON",
    "ECRUTEAK_GYM": "PAL_CAVE",  # beats its CEMETERY tileset
    "CIANWOOD_GYM": "PAL_CAVE",
    "OLIVINE_GYM": "PAL_PEWTER",
    "MAHOGANY_GYM": "PAL_CYANMON",
    "BLACKTHORN_GYM": "PAL_CERULEAN",  # beats its CEMETERY tileset
    "IGAS_DOJO": "PAL_FUCHSIA",
    "KOGAS_ROOM": "PAL_INDIGO",
    "WILLS_ROOM": "PAL_INDIGO",
}


def const_ids(path, first):
    """Ids from a `const` list, counted from the const_def holding `first`."""
    ids, on = {}, False
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(r"\s*const (\w+)", line)
        if not match:
            continue
        on = on or match.group(1) == first
        if on:
            ids[match.group(1)] = len(ids)
    return ids


def map_tilesets():
    found = {}
    for path in (ROOT / "data/maps/headers").glob("*.asm"):
        match = re.search(r"map_header\s+\w+,\s*(\w+),\s*(\w+)", path.read_text(encoding="utf-8"))
        if match:
            found[match.group(1)] = match.group(2)
    return found


class OverworldPaletteTableTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = RedRogueHarness(ROOT, ROOT / "builds/overworld_palette_table/tests")
        cls.h.boot_to_lobby(battle_count=37)
        cls.baseline = io.BytesIO()
        cls.h.save_state(cls.baseline)
        cls.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        cls.pals = const_ids(ROOT / "constants/palette_constants.asm", "PAL_ROUTE")
        cls.tilesets = const_ids(ROOT / "constants/tileset_constants.asm", "OVERWORLD")
        cls.map_tilesets = map_tilesets()

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def palette(self, name, last_map="INDIGO_PLATEAU_LOBBY"):
        self.h.load_state(self.baseline)
        self.h.write8("hCurMap", self.maps[name])
        self.h.write8("wCurMapTileset", self.tilesets[self.map_tilesets[name]])
        self.h.write8("wLastMap", self.maps[last_map])
        self.h.call_routine("GetOverworldPalette", limit=2000)
        return self.h.last_call_registers["A"]

    def test_town_maps_keep_their_town_colour_from_the_lobby(self):
        wrong = {}
        for pal, names in TOWN_MAPS.items():
            for name in names:
                got = self.palette(name)
                if got != self.pals[pal]:
                    wrong[name] = (got, pal)
        self.assertEqual(wrong, {})

    def test_maps_without_a_vanilla_colour_get_their_chosen_one(self):
        wrong = {}
        for name, pal in CHOSEN_MAPS.items():
            got = self.palette(name)
            if got != self.pals[pal]:
                wrong[name] = (got, pal)
        self.assertEqual(wrong, {})

    def test_route_door_maps_stay_route_coloured(self):
        for name in ROUTE_MAPS:
            with self.subTest(name):
                self.assertEqual(self.palette(name), self.pals["PAL_ROUTE"])

    def test_a_map_without_a_row_still_inherits_wlastmap(self):
        # Control: the fallback path is untouched.
        self.assertEqual(self.palette("BILLS_HOUSE", last_map="CINNABAR_ISLAND"),
                         self.pals["PAL_CINNABAR"])

    def test_a_row_does_not_depend_on_the_way_in(self):
        self.assertEqual(self.palette("POKEMON_MANSION_1F", last_map="PALLET_TOWN"),
                         self.pals["PAL_CINNABAR"])


if __name__ == "__main__":
    unittest.main()
