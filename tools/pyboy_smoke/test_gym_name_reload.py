"""Statue names are right after Continue, and Continue does not reroll gym setup.

The names are unsaved buffers. Since FOLLOWUPS #101 the statue fills them when it
is read (LoadGymStatueNames), so the check calls that loader, as GymStatues does,
before the save and again after a cold Continue."""
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_trainer_class_indexes
import save_reload

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).parent / "artifacts" / "gym_name_reload"
MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
TRAINERS = parse_trainer_class_indexes(ROOT / "constants/trainer_constants.asm")
GYMS = (
    ("PEWTER_GYM", "PewterCity", "Brock"),
    ("CERULEAN_GYM", "CeruleanCity", "Misty"),
    ("VERMILION_GYM", "VermilionCity", "LtSurge"),
    ("CELADON_GYM", "CeladonCity", "Erika"),
    ("FUCHSIA_GYM", "FuchsiaCity", "Koga"),
    ("SAFFRON_GYM", "SaffronCity", "Sabrina"),
    ("CINNABAR_GYM", "CinnabarIsland", "Blaine"),
    ("VIRIDIAN_GYM", "ViridianCity", "Giovanni"),
    ("VIOLET_GYM", "VioletCity", "Falkner"),
    ("AZALEA_GYM", "AzaleaTown", "Bugsy"),
    ("GOLDENROD_GYM", "GoldenrodCity", "Whitney"),
    ("ECRUTEAK_GYM", "EcruteakCity", "Morty"),
    ("CIANWOOD_GYM", "CianwoodCity", "Chuck"),
    ("OLIVINE_GYM", "OlivineCity", "Jasmine"),
    ("MAHOGANY_GYM", "MahoganyTown", "Pryce"),
    ("BLACKTHORN_GYM", "BlackthornCity", "Clair"),
)


class GymNameReloadTest(unittest.TestCase):
    cgb = False

    @staticmethod
    def terminated(values):
        return list(values[:values.index(0x50) + 1])

    def statue_names(self, h, expected):
        """Run the statue's loader (as GymStatues does) and read both buffers."""
        return h.call_routine("LoadGymStatueNames", capture=lambda x: {
            destination: self.terminated(x.read_bytes(destination, 17 if destination == "wGymCityName" else 11))
            for destination in expected})

    def check_gym(self, entry, janine=False):
        map_name, city, leader = entry
        leader = "Janine" if janine else leader
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=self.cgb)
        try:
            h.register_hook("DebugMenu.startDebugGame",
                            lambda _: setattr(h.pyboy.register_file, "A", MAPS[map_name]))
            if janine:
                selected = {"done": False}
                def select(_):
                    if not selected["done"]:
                        selected["done"] = True
                        h.write8("wRunGymLineup", TRAINERS["JANINE"])
                h.register_hook("FuchsiaGym_Script", select)
            setups = h.hook_flag("GymLeaderRandomItem")
            h.boot_debug1(MAPS[map_name])
            self.assertTrue(save_reload.settle(h))
            self.assertEqual(setups["count"], 1, "initial setup must run once")
            expected = {}
            for destination, label, size in (("wGymCityName", city, 17), ("wGymLeaderName", leader, 11)):
                bank, address = h.symbols.get("GymStatueNames_" + label)
                expected[destination] = self.terminated(list(h.pyboy.memory[bank, address:address + size]))
            self.assertEqual(self.statue_names(h, expected), expected)
            h.tick(30)
            self.assertEqual(setups["count"], 1, "ordinary updates must not reroll setup")
            save_reload.save_now(h)
            boot = save_reload.Reboot(save_reload.sram_image(h), cgb_mode=self.cgb)
            try:
                rerolls = boot.h.hook_flag("GymLeaderRandomItem")
                boot.load()
                self.assertEqual(boot.status, 2)
                self.assertTrue(boot.overworld)
                boot.h.tick(30)
                self.assertEqual(rerolls["count"], 0, "Continue must not rerun one-time setup")
                self.assertEqual(self.statue_names(boot.h, expected), expected)
                self.assertFalse(boot.h.hook_errors)
            finally:
                boot.close()
            self.assertFalse(h.hook_errors)
        finally:
            h.close()

    def test_all_gym_names_survive_cold_continue(self):
        for entry in GYMS:
            with self.subTest(gym=entry[0]):
                self.check_gym(entry)

    def test_fuchsia_janine_name_survives_cold_continue(self):
        self.check_gym(next(e for e in GYMS if e[0] == "FUCHSIA_GYM"), janine=True)
