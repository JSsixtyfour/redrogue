"""The coverage map may only hook code (coverage_inventory.py).

PyBoy hooks by writing $DB over the instruction byte, so a data label in the
inventory would feed the game $DB wherever it reads that table or text. Known
data, text and LOAD-block labels must be absent and known code (routines and
their local branch labels) present. Source-only (make audit): the walk takes
about a minute when the symbol file changed.
"""
import unittest

import coverage_inventory


class CoverageInventoryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.labels = {label["name"]: label for label in coverage_inventory.code_labels()}

    def test_code_labels_are_listed(self) -> None:
        for name in ("BridgeTeachMoveToCurrent", "CheckIfMoveIsKnown",
                     "CheckIfMoveIsKnown.alreadyKnown", "LearnMove", "JoypadOverworld", "VBlank"):
            self.assertIn(name, self.labels)

    def test_data_text_and_ram_code_are_not(self) -> None:
        for name in ("Moves", "ItemPrices", "TextCommandSounds", "_WitchChallenge7Text",
                     "AlreadyKnowsText", "PCWitchText", "MapHeaderBanks",
                     "DMARoutine"):  # the ROM copy WriteDMACodeToHRAM reads into HRAM
            self.assertNotIn(name, self.labels)

    def test_no_hook_leads_straight_onto_another(self) -> None:
        # PyBoy 2.7 can wedge when the instruction it steps over at one hook
        # lands on another (it hung seed 1 at PCemFillAll.rowLoop ->
        # PCemFillOneRow); hook_plan must leave no such pair.
        import sm83

        _, hooks, inferred = coverage_inventory.plan()
        rom = (coverage_inventory.ROOT / f"{coverage_inventory.ROM}.gbc").read_bytes()
        hooked = set(hooks.values())
        pairs = []
        for name, (bank, address) in hooks.items():
            for successor, _ in sm83.first_step(rom, bank, address).successors:
                key = (0 if successor < 0x4000 else bank, successor)
                if key in hooked and key != (bank, address):
                    pairs.append(name)
        self.assertEqual(pairs, [])
        self.assertNotIn("PCemFillOneRow", inferred)  # moved, still hooked
        self.assertGreater(len(hooks), 0.98 * len(self.labels))

    def test_every_label_is_in_rom(self) -> None:
        for label in self.labels.values():
            self.assertLess(label["address"], 0x8000, label["name"])
            self.assertEqual(label["bank"] == 0, label["address"] < 0x4000, label["name"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
