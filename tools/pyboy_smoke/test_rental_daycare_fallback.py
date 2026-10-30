"""Automatic owned-daycare recovery and no-owned run-end settlement."""
import unittest
import io

import test_rental_settlement as boxed
from routine_session import isolated_routine_calls
from test_move_tutor_prices import run_entry, return_from_call
from source_constants import parse_map_constants, parse_rgbds_constants
from test_save_header import REPO_ROOT


class RentalDaycareFallbackTest(boxed.RentalSettlementTest):
    # Reuse the coherent box fixture without inheriting its test cases.
    test_inactive_rental_removed_and_boxed_owned_mon_recovered_before_save = None
    test_party_rental_uses_current_box_and_saves_healthy_replacement = None
    test_current_box_recovery_has_priority = None
    test_invalid_owner_returns_without_mutation = None

    def live_entry(self, setup, finished=None):
        """Inject at a live main-loop seam, with interrupts available for UI."""
        h = self.h
        entered = []
        returned = []
        def enter(_):
            if entered:
                returned.append(True)
                return
            entered.append(True)
            setup(h)
            bank, address = h.symbols.get("RentalSettleAndSave")
            cpu = h.pyboy.register_file
            cpu.SP -= 2
            destination = h.address("OverworldLoop")
            h.pyboy.memory[cpu.SP] = destination & 255
            h.pyboy.memory[cpu.SP + 1] = destination >> 8
            h.pyboy.memory[0x2000] = bank
            h.write8("hLoadedROMBank", bank)
            cpu.PC = address
        bank, address = h.symbols.get("OverworldLoop")
        h.pyboy.hook_register(bank, address, enter, None)
        try:
            h.wait_until(lambda: entered and (finished() if finished else returned),
                         "live rental settlement", 2000)
        finally:
            h.pyboy.hook_deregister(bank, address)

    def test_earned_growth_uses_real_experience_and_upgrade_path(self):
        species = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
        def setup(h):
            self.seed(h, 5, {}, 0)
            h.write8("wDayCareInUse2", 0)
            self.daycare(h, 0, 30)
            h.write8("wDayCareMonSpecies", species["DITTO"])
            h.write8("wDayCareMonBoxLevel", 1)
            start = h.address("wDayCareMonExp")
            h.pyboy.memory[start:start+3] = [0,0,1]
            h.write8("wBattleCount", 1)
        def target(_):
            self.h.write8("wCurEnemyLevel", 6)
            return_from_call(self.h)
        h = self.h
        h.register_hook("GetRewardMonLevel", target)
        self.live_entry(setup)
        self.assertEqual(h.read8("wPartyMon1Level"), 6)
        self.assertEqual(h.read_bytes("wPartyMon1Exp", 3), [0,0,216])
        self.assertEqual(h.read8("wPartySpecies"), species["DITTO"])

    def test_retained_deposit_after_three_continuations_grows_once_and_bills_the_cap(self):
        species = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
        max_level = parse_rgbds_constants(REPO_ROOT / "constants/battle_constants.asm")["MAX_LEVEL"]
        h = self.h
        # Real continuations first, on the clean lobby; seed the box afterwards.
        groups = parse_rgbds_constants(REPO_ROOT / "constants/rogue_species_groups.asm")
        h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [1 << groups["BIT_GROUP_KANTO"]], bank=1)
        h.write8("wEndlessDepth", 0)
        h.write8("wDayCareInUse", 1)
        h.write8("wDayCareDepositBattleCount", 1)
        with isolated_routine_calls(h):
            for _ in range(3):
                h.write8("wBattleCount", 73)
                h.call_routine("EndlessContinue")
            carried = h.read8("wDayCareDepositBattleCount")
            self.assertEqual(h.read8("wEndlessDepth"), 3)
            self.assertEqual((1 - carried) & 0xFF, 183)
        self.seed(h, 5, {}, 0)
        h.write8("wDayCareInUse2", 0)
        self.daycare(h, 0, 30, deposit=carried)
        h.write8("wDayCareMonSpecies", species["DITTO"])
        h.write8("wDayCareMonBoxLevel", 5)
        h.write8("wEndlessDepth", 3)
        h.write8("wBattleCount", 1)
        h.write8("wPartyCount", 0)
        start = h.address("wPlayerMoney")
        h.pyboy.memory[start:start + 3] = [0x02, 0x00, 0x00]  # 20000
        self.live_entry(lambda h: None)
        self.assertEqual(h.read8("wPartyCount"), 1)
        self.assertEqual(h.read8("wPartyMons", offset=12), 30)
        level = h.read8("wPartyMon1Level")
        self.assertGreater(level, 5)
        self.assertLessEqual(level, max_level)
        self.assertEqual(h.read_bytes("wPlayerMoney", 3), [0x01, 0x00, 0x01])  # 20000 - 9999
        self.assertEqual(h.read8("wDayCareInUse"), 0)

    def daycare(self, h, slot, marker, deposit=0):
        suffix = "2" if slot else ""
        h.write8("wDayCareInUse" + suffix, 1)
        mon = self.mon[:]
        # The boxed level is refreshed on real deposit; party bytes alone
        # retain an old boxed-level field and are not a valid daycare fixture.
        mon[3] = h.read8("wPartyMon1Level")
        mon[12] = marker
        start = h.address("wDayCareMon2" if slot else "wDayCareMon")
        h.pyboy.memory[start:start + 33] = mon
        h.write8("wDayCareDepositBattleCount" + suffix, deposit)

    def test_daycare_finder_prioritizes_first_slot_and_excludes_rental(self):
        for owner, expected in ((0,0), (247,1), (248,0)):
            def setup(h):
                self.seed(h, 5, {}, owner)
                self.daycare(h, 0, 30)
                self.daycare(h, 1, 31)
            result = run_entry(self.h, "RentalFindDaycareFallback", setup=setup,
                               capture=lambda h: {"slot": h.pyboy.register_file.E})
            self.assertTrue(result["flags"] & 16)
            self.assertEqual(result["slot"], expected)

    def test_box_fallback_precedes_daycare_in_full_settlement(self):
        def setup(h):
            self.seed(h, 5, {0:[20], 5:[25], 8:[30]}, 167)
            self.daycare(h, 0, 40)
            self.daycare(h, 1, 41)
        result = run_entry(self.h, "RentalSettleAndSave", setup=setup,
                           capture=lambda h: {"marker": h.read8("wPartyMons", offset=12),
                               "daycare": [h.read8("wDayCareInUse"),h.read8("wDayCareInUse2")]})
        self.assertTrue(result["flags"] & 16)
        self.assertEqual(result["marker"], 25)
        self.assertEqual(result["daycare"], [1,1])

    def test_daycare_priority_billing_preservation_and_save_reload(self):
        species = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
        baseline = io.BytesIO()
        self.h.save_state(baseline)
        for slot in (0, 1):
            h = self.h
            h.load_state(baseline)
            self.seed(h, 5, {}, 0)
            h.write8("wDayCareInUse", 0)
            h.write8("wDayCareInUse2", 0)
            self.daycare(h, slot, 30 + slot)
            h.write8("wDayCareMon2Species" if slot else "wDayCareMonSpecies", species["DITTO"])
            h.write8("wBattleCount", 0)  # no earned growth or fee
            # Real upgrade code may wait for frames, so use a live seam.
            self.live_entry(lambda h: None)
            self.assertEqual(h.read8("wPartyCount"), 1)
            self.assertEqual(h.read8("wPartyMons", offset=12), 30 + slot)
            self.assertEqual(h.read8("wPartySpecies"), species["DITTO"])
            self.assertEqual(h.read8("wDayCareInUse" + ("2" if slot else "")), 0)
            self.assertEqual(h.read_bytes("wRentalRecord", 4), [0, 0, 0, 3])
            h.write8("wPartyCount", 0)
            h.call_routine("LoadMainData")
            h.call_routine("LoadPartyAndDexData")
            self.assertEqual(h.read8("wPartyCount"), 1)
            self.assertEqual(h.read8("wPartyMons", offset=12), 30 + slot)

    def test_rental_daycare_then_owned_daycare_are_billed_independently(self):
        effect_offset = self.h.address("wBridgeSelectedEffects") - self.h.address("wMainDataStart")
        for rental in (0, 1):
            for balance, expected in ((200, 0), (1000, 0), (1200, 200)):
                def setup(h):
                    self.seed(h, 5, {}, 247 + rental)
                    self.daycare(h, 0, 30)
                    self.daycare(h, 1, 31)
                    h.write8("wBridgeSelectedEffectOwner1", 247 + rental)
                    h.write8("wBridgeSelectedEffect1", 3)
                    h.write8("wBridgeSelectedEffectOwner2", 248 - rental)
                    h.write8("wBridgeSelectedEffect2", 4)
                    h.write8("wBattleCount", 1)
                    digits = f"{balance:06d}"
                    start = h.address("wPlayerMoney")
                    h.pyboy.memory[start:start + 3] = [int(digits[i:i+2], 16) for i in (0,2,4)]
                # Growth is exercised separately; this isolates real billing,
                # MoveMon ownership and clearing, without interactive upgrades.
                result = run_entry(self.h, "RentalSettleAndSave", setup=setup,
                    hooks={"DaycareRetrieveUpgrade": lambda _: return_from_call(self.h)},
                    capture=lambda h: {"money": h.read_bytes("wPlayerMoney",3),
                        "marker": h.read8("wPartyMons", offset=12),
                        "effects": h.read_bytes("wBridgeSelectedEffects", 4),
                        "saved_effects": h.read_sram_bytes("sMainData", effect_offset + 4)[effect_offset:],
                        "occupied": [h.read8("wDayCareInUse"), h.read8("wDayCareInUse2")]})
                self.assertTrue(result["flags"] & 16)
                self.assertEqual(result["marker"], 31 - rental)
                self.assertEqual(result["occupied"], [0,0])
                self.assertEqual(result["money"], [0, expected // 100, 0])
                self.assertEqual(result["effects"], [0, 0, 1, 4])
                # run_entry restores its baseline after capture, so inspect
                # the transaction's saved bytes before that fixture rollback.
                self.assertEqual(result["saved_effects"], [0, 0, 1, 4])

    def test_no_owned_mon_follows_blackout_to_dorm_and_saves_once(self):
        h = self.h
        maps = parse_map_constants(REPO_ROOT / "constants/map_constants.asm")
        self.seed(h, 5, {}, 1)
        h.write8("wPartyCount", 1)
        h.write8("wPartySpecies", self.mon[0])
        h.write8("wPartySpecies", 255, offset=1)
        h.write8("wDayCareInUse", 0)
        h.write8("wDayCareInUse2", 0)
        h.write8("wCreditsEarnedThisRun", 0)
        h.write8("wPlayerCoins", 0x12)
        h.write8("wPlayerCoins", 0x34, offset=1)
        trace = []
        for label in ("HandleBlackOut", "RogueOnBlackout", "HealParty", "SaveGameData", "CrashScreen", "RentalSettlementPopup.restored"):
            h.register_hook(label, lambda _, label=label: trace.append(label))
        # Enter the normal nonreturning path from a live overworld frame. The
        # synthetic farcall return is never reached, just like a zone caller.
        self.live_entry(lambda h: None, lambda: "RentalSettlementPopup.restored" in trace
                        and h.read8("hCurMap") == maps["SILPH_CO_DORM"]
                        and h.read8("wRentalState") == 0 and h.read8("hJoyIgnore") == 0)
        h.tick(20)
        self.assertEqual(trace.count("HandleBlackOut"), 1)
        self.assertEqual(trace.count("RogueOnBlackout"), 1)
        self.assertEqual(trace.count("SaveGameData"), 1)
        self.assertNotIn("HealParty", trace)
        self.assertNotIn("CrashScreen", trace)
        self.assertEqual(h.read8("wPartyCount"), 0)
        self.assertEqual(h.read_bytes("wPlayerCoins", 2), [0x12,0x34])
        self.assertEqual(h.read_bytes("wRentalRecord", 16), [0] * 16)
        h.call_routine("LoadMainData")
        self.assertEqual(h.read8("hCurMap"), maps["SILPH_CO_DORM"])
        self.assertEqual(h.read_bytes("wRentalRecord", 16), [0] * 16)
