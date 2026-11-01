"""Unsaved statue names rebuild after Continue without rerolling gym setup."""
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
    ("PEWTER_GYM", "PewterGym", "PewterGymNames", "initial"),
    ("CERULEAN_GYM", "CeruleanGym", "CeruleanGym_Script", "CeruleanGym_Script"),
    ("VERMILION_GYM", "VermilionGym", "VermilionGym_Script", "VermilionGym_Script"),
    ("CELADON_GYM", "CeladonGym", "CeladonGym_Script", "CeladonGym_Script"),
    ("FUCHSIA_GYM", "FuchsiaGym", "FuchsiaGym_Script", "FuchsiaGym_Script"),
    ("SAFFRON_GYM", "SaffronGym", "SaffronGym_Script", "SaffronGym_Script"),
    ("CINNABAR_GYM", "CinnabarGym", "CinnabarGymSetMapAndTiles", "CinnabarGymSetMapAndTiles"),
    ("VIRIDIAN_GYM", "ViridianGym", "ViridianGym_Script", "ViridianGym_Script"),
    *[(name.upper() + "_GYM", name + "Gym", name + "GymNames", "initial" + name)
      for name in ("Violet", "Azalea", "Goldenrod", "Ecruteak", "Cianwood", "Olivine", "Mahogany", "Blackthorn")],
)


class GymNameReloadTest(unittest.TestCase):
    cgb = False

    @staticmethod
    def terminated(values):
        return list(values[:values.index(0x50) + 1])

    def check_gym(self, entry, janine=False):
        map_name, stem, current_owner, old_owner = entry
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
            owner = current_owner if current_owner + ".CityName" in h.symbols._symbols else old_owner
            expected = {}
            for destination, suffix, size in (("wGymCityName", ".CityName", 17),
                                               ("wGymLeaderName", ".JanineName" if janine else ".LeaderName", 11)):
                bank, address = h.symbols.get(owner + suffix)
                expected[destination] = self.terminated(list(h.pyboy.memory[bank, address:address + size]))
                self.assertEqual(self.terminated(h.read_bytes(destination, size)), expected[destination])
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
                for destination, value in expected.items():
                    self.assertEqual(boot.h.read_bytes(destination, len(value)), value)
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
