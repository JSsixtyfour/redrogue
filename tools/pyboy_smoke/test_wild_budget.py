"""Exercise the actual four generator budget loops without generating maps.

Each probe enters at the division loop with the same A/B inputs as the native
initializer, executes the real clamp and WRAM store, then returns immediately
through the harness trampoline. The parked machine is restored between probes.
This verifies arithmetic and initialization, not map choreography or encounters.
"""

import io
import unittest

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT


SEAMS = (
    ("PCFinalizeCave", "budgetDivLoop", "budgetNoClamp", "wProcCaveWildBudget"),
    ("PFPreloadForest", "budgetDivLoop", "budgetNoClamp", "wProcForestWildBudget"),
    ("PCemGenerateMaps", "cemBudgetDiv", "cemBudgetNoClamp", "wProcCemWildBudget"),
    ("PFacPreload", "budgetDivLoop", "budgetNoClamp", "wProcFacilityWildBudget"),
)


class WildBudgetTest(HarnessTestCase):
    def test_each_area_consumes_budget_and_blocks_at_zero(self):
        h = self.harness
        assert h is not None
        events = parse_rgbds_constants(REPO_ROOT / "constants/event_constants.asm")
        h.boot_fight2(seed=1)
        h.park_before_hijack()
        baseline = io.BytesIO()
        h.save_state(baseline)
        seams = (
            ("checkCaveBudget", "wProcCaveWildBudget", "EVENT_PC_BUDGET_ENDED"),
            ("checkForestBudget", "wProcForestWildBudget", "EVENT_PC_BUDGET_ENDED"),
            ("checkCemBudget", "wProcCemWildBudget", "EVENT_PC_CEM_BUDGET_ENDED"),
            ("checkFacilityBudget", "wProcFacilityWildBudget", "EVENT_PC_BUDGET_ENDED"),
        )
        try:
            for seam, budget, event_name in seams:
                event = events[event_name]
                event_address = h.address("wEventFlags") + event // 8
                event_mask = 1 << (event % 8)
                for remaining in range(18, -1, -1):
                    with self.subTest(area=seam, remaining=remaining):
                        h.load_state(baseline)
                        h.write8(budget, remaining)
                        h.write8("wIsTrainerBattle", 1)  # cleared only by successful commit
                        h.pyboy.memory[event_address] &= ~event_mask & 0xFF
                        h.call_routine(f"TryDoWildEncounter.{seam}", limit=300)
                        self.assertEqual(h.read8(budget), max(0, remaining - 1))
                        self.assertEqual(h.read8("wIsTrainerBattle"), int(remaining == 0))
                        self.assertEqual(h.event_is_set(event), remaining == 1)
        finally:
            h.load_state(baseline)

    def test_all_generator_budget_initializers_cover_every_count(self):
        h = self.harness
        assert h is not None
        rounds = parse_rgbds_constants(REPO_ROOT / "constants/round_constants.asm")
        knobs = parse_rgbds_constants(REPO_ROOT / "constants/balance_constants.asm", rounds)
        self.assertEqual((knobs["WILD_BUDGET_BASE"], knobs["WILD_BUDGET_MAX"],
                          knobs["WILD_BUDGET_DIVISOR"]), (8, 18, 4))
        h.boot_fight2(seed=1)
        h.park_before_hijack()
        baseline = io.BytesIO()
        h.save_state(baseline)
        return_bank, return_address = h.symbols.get("Bankswitch.Return")
        self.assertEqual(return_bank, 0)

        for scope, divide, store, budget in SEAMS:
            entry = f"{scope}.{divide}"
            bank, entry_address = h.symbols.get(entry)
            store_bank, store_address = h.symbols.get(f"{scope}.{store}")
            self.assertEqual(bank, store_bank)
            destination = h.address(budget)
            # LD [a16], A is three bytes. Observe after that instruction rather
            # than merely trusting the candidate A at the pre-store seam.
            expected_store = [0xEA, destination & 0xFF, destination >> 8]
            self.assertEqual([h.pyboy.memory[bank, store_address + offset] for offset in range(3)],
                             expected_store)
            result = {}

            def inputs(_context):
                if result.get("entered"):
                    return
                result["entered"] = True
                h.pyboy.register_file.A = h.read8("wBattleCount")
                h.pyboy.register_file.B = 0

            def finish(_context):
                if "value" in result:
                    return
                result["value"] = h.read8(budget)
                registers = h.pyboy.register_file
                sp = registers.SP
                stacked_return = h.pyboy.memory[sp] | h.pyboy.memory[sp + 1] << 8
                self.assertEqual(stacked_return, return_address)
                # Skip the generator remainder. Equivalent to RET, using its
                # real trampoline return; no ROM patch or map generation.
                registers.SP = (sp + 2) & 0xFFFF
                registers.PC = return_address

            h.pyboy.hook_register(bank, entry_address, inputs, None)
            h.pyboy.hook_register(bank, store_address + 3, finish, None)
            try:
                for count in range(256):
                    with self.subTest(area=scope, battle_count=count):
                        h.load_state(baseline)
                        h.write8("wBattleCount", count)
                        h.write8(budget, 0xA5)
                        result.clear()
                        h.call_routine(entry, limit=300)
                        self.assertEqual(result.get("value"), min(18, 8 + count // 4))
            finally:
                h.pyboy.hook_deregister(bank, entry_address)
                h.pyboy.hook_deregister(bank, store_address + 3)
                h.load_state(baseline)


if __name__ == "__main__":
    unittest.main()
