"""The gym statue loads its own names (FOLLOWUPS #101).

Every gym script used to copy its city and leader names into wGymCityName /
wGymLeaderName on every map-script tick. GymStatues now calls
LoadGymStatueNames when the statue is read. This checks every gym's row, the
Fuchsia leader choice, and that a non-gym map leaves the buffers alone.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_trainer_class_indexes
from test_eevee_form_gate import CHAR_TO_BYTE

ROOT = Path(__file__).resolve().parents[2]
TEXT_END = 0x50

NAMES = {
    "PEWTER_GYM": ("PEWTER CITY", "BROCK"),
    "CERULEAN_GYM": ("CERULEAN CITY", "MISTY"),
    "VERMILION_GYM": ("VERMILION CITY", "LT.SURGE"),
    "CELADON_GYM": ("CELADON CITY", "ERIKA"),
    "FUCHSIA_GYM": ("FUCHSIA CITY", "KOGA"),
    "SAFFRON_GYM": ("SAFFRON CITY", "SABRINA"),
    "CINNABAR_GYM": ("CINNABAR ISLAND", "BLAINE"),
    "VIRIDIAN_GYM": ("VIRIDIAN CITY", "GIOVANNI"),
    "VIOLET_GYM": ("VIOLET CITY", "FALKNER"),
    "AZALEA_GYM": ("AZALEA TOWN", "BUGSY"),
    "GOLDENROD_GYM": ("GOLDENROD CITY", "WHITNEY"),
    "ECRUTEAK_GYM": ("ECRUTEAK CITY", "MORTY"),
    "CIANWOOD_GYM": ("CIANWOOD CITY", "CHUCK"),
    "OLIVINE_GYM": ("OLIVINE CITY", "JASMINE"),
    "MAHOGANY_GYM": ("MAHOGANY TOWN", "PRYCE"),
    "BLACKTHORN_GYM": ("BLACKTHORN CITY", "CLAIR"),
}


def encoded(text):
    return [CHAR_TO_BYTE[c] for c in text] + [TEXT_END]


class GymStatueNamesTest(unittest.TestCase):
    def test_every_gym_and_the_fuchsia_leader(self):
        maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        janine = parse_trainer_class_indexes(ROOT / "constants/trainer_constants.asm")["JANINE"]
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        try:
            h.boot_to_lobby()
            home_map = h.read8("hCurMap")
            lineup = h.read_bytes("wRunGymLineup", 8)

            def load(map_id):
                for i in range(17):
                    h.write8("wGymCityName", 0xAA, offset=i)
                for i in range(11):
                    h.write8("wGymLeaderName", 0xAA, offset=i)
                h.write8("hCurMap", map_id)
                result = h.call_routine("LoadGymStatueNames", capture=lambda x: (
                    x.read_bytes("wGymCityName", 17), x.read_bytes("wGymLeaderName", 11)))
                h.write8("hCurMap", home_map)
                return result

            for i in range(8):
                h.write8("wRunGymLineup", 0, offset=i)
            for name, (city, leader) in NAMES.items():
                with self.subTest(gym=name):
                    got_city, got_leader = load(maps[name])
                    want_city, want_leader = encoded(city), encoded(leader)
                    self.assertEqual(list(got_city[:len(want_city)]), want_city)
                    self.assertEqual(list(got_leader[:len(want_leader)]), want_leader)

            with self.subTest(gym="FUCHSIA_GYM with Janine"):
                h.write8("wRunGymLineup", janine, offset=5)
                got_city, got_leader = load(maps["FUCHSIA_GYM"])
                self.assertEqual(list(got_city[:13]), encoded("FUCHSIA CITY"))
                self.assertEqual(list(got_leader[:7]), encoded("JANINE"))

            with self.subTest(gym="not a gym"):
                got_city, got_leader = load(home_map)
                self.assertEqual(list(got_city), [0xAA] * 17, "a non-gym map writes nothing")
                self.assertEqual(list(got_leader), [0xAA] * 11)

            for i, value in enumerate(lineup):
                h.write8("wRunGymLineup", value, offset=i)
        finally:
            h.close()


if __name__ == "__main__":
    unittest.main()
