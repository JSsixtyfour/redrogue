"""Automatic rental daycare billing caps payment and clears only its holder."""
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_save_header import ARTIFACTS, REPO_ROOT
from test_move_tutor_prices import run_entry, bcd3


class RentalDaycareTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.h.boot_to_lobby()
        self.round = parse_rgbds_constants(REPO_ROOT / "constants/round_constants.asm")["ROUND_BATTLES"]

    def tearDown(self):
        self.h.close()

    def money(self, h, amount):
        start = h.address("wPlayerMoney")
        h.pyboy.memory[start:start + 3] = bcd3(amount)

    def test_fee_rounding_shortfall_exact_surplus_and_battle_wrap(self):
        for slot in (0, 1):
            deposit = "wDayCareDepositBattleCount" + ("2" if slot else "")
            for elapsed in (0, 1, self.round, self.round + 1, 2 * self.round + 1, 255):
                # Capped at Y9999, where the lobby's 2-byte fee saturates (user, 2026-10-29).
                fee = min(9999, ((elapsed + self.round - 1) // self.round) * 500)
                for balance in (0, max(0, fee - 1), fee, fee + 800):
                    with self.subTest(slot=slot, elapsed=elapsed, balance=balance):
                        def setup(h):
                            self.money(h, balance)
                            h.write8(deposit, 250)
                            h.write8("wBattleCount", (250 + elapsed) & 255)
                        result = run_entry(self.h, "RentalChargeDaycare", registers={"E": slot},
                                           setup=setup, capture=lambda h: {
                                               "money": h.read_bytes("wPlayerMoney", 3),
                                               "quote": h.read_bytes("hMoney", 3),
                                           })
                        self.assertEqual(result["quote"], bcd3(fee))
                        self.assertEqual(result["money"], bcd3(max(0, balance - fee)))

    def test_quote_table_at_the_endless_carry_boundaries(self):
        # Elapsed values around the Endless carry (up to 183+72) and the Y9999 cap.
        table = {0: 0, 1: 500, 7: 500, 8: 500, 9: 1000, 152: 9500,
                 153: 9999, 160: 9999, 255: 9999}
        for slot in (0, 1):
            deposit = "wDayCareDepositBattleCount" + ("2" if slot else "")
            for elapsed, fee in table.items():
                with self.subTest(slot=slot, elapsed=elapsed):
                    def setup(h):
                        self.money(h, 10000)
                        h.write8(deposit, 1)
                        h.write8("wBattleCount", (1 + elapsed) & 255)
                    result = run_entry(self.h, "RentalChargeDaycare", registers={"E": slot},
                                       setup=setup, capture=lambda h: {
                                           "money": h.read_bytes("wPlayerMoney", 3),
                                           "quote": h.read_bytes("hMoney", 3)})
                    self.assertEqual(result["quote"], bcd3(fee))
                    self.assertEqual(result["money"], bcd3(10000 - fee))

    def test_depth_zero_full_circuit_hold_still_bills_nine_rounds(self):
        # Ordinary run: deposited at count 1, Champion at 73: elapsed 72, 9 rounds.
        for slot in (0, 1):
            deposit = "wDayCareDepositBattleCount" + ("2" if slot else "")
            def setup(h):
                self.money(h, 5000)
                h.write8("wEndlessDepth", 0)
                h.write8(deposit, 1)
                h.write8("wBattleCount", 73)
            result = run_entry(self.h, "RentalChargeDaycare", registers={"E": slot},
                               setup=setup, capture=lambda h: {
                                   "money": h.read_bytes("wPlayerMoney", 3),
                                   "quote": h.read_bytes("hMoney", 3)})
            self.assertEqual(result["quote"], bcd3(4500))
            self.assertEqual(result["money"], bcd3(500))

    def test_reclaim_clears_rental_holder_and_preserves_other_daycare_and_contract(self):
        for slot in (0, 1):
            first = self.h.address("wDayCareInUse")
            second = self.h.address("wDayCareInUse2")
            end = self.h.address("wStolenSaveSnapshot")
            start, stop = (first, second) if slot == 0 else (second, end)
            other_start, other_stop = (second, end) if slot == 0 else (first, second)
            suffix = "2" if slot else ""
            before = {}
            def setup(h):
                h.pyboy.memory[first:end] = [0x25] * (end - first)
                record = [1, 247 + slot, 42, 3] + list(range(12))
                h.pyboy.memory[h.address("wRentalRecord"):h.address("wRentalRecord") + 16] = record
                h.write8("wDayCareDepositBattleCount" + suffix, 1)
                h.write8("wDayCareDepositBattleCount" + ("" if slot else "2"), 77)
                h.write8("wBattleCount", 2)
                self.money(h, 200)
                before["record"] = record
                before["other"] = list(h.pyboy.memory[other_start:other_stop])
                before["snapshot"] = h.read_bytes("wStolenSaveSnapshot", 57)
            result = run_entry(self.h, "RentalReclaimDaycare", setup=setup, capture=lambda h: {
                "record": h.read_bytes("wRentalRecord", 16),
                "holder": list(h.pyboy.memory[start:stop]),
                "other": list(h.pyboy.memory[other_start:other_stop]),
                "deposit": h.read8("wDayCareDepositBattleCount" + suffix),
                "other_deposit": h.read8("wDayCareDepositBattleCount" + ("" if slot else "2")),
                "cost": h.read_bytes("wDayCareStartLevel" + suffix, 6),
                "snapshot": h.read_bytes("wStolenSaveSnapshot", 57),
                "money": h.read_bytes("wPlayerMoney", 3),
            })
            self.assertTrue(result["flags"] & 0x10)
            before["record"][1] = 0
            self.assertEqual(result["record"], before["record"])
            self.assertEqual(result["holder"], [0] * (stop - start))
            self.assertEqual(result["other"], before["other"])
            self.assertEqual(result["deposit"], 0)
            self.assertEqual(result["other_deposit"], 77)
            self.assertEqual(result["cost"], [0] * 6)
            self.assertEqual(result["snapshot"], before["snapshot"])
            self.assertEqual(result["money"], [0] * 3)

    def test_reclaim_clears_only_rental_effect_before_daycare_reuse(self):
        for slot in (0, 1):
            with self.subTest(slot=slot):
                h = self.h
                owner = 247 + slot
                h.write8("wRentalState", 2)
                h.write8("wRentalOwner", owner)
                h.write8("wDayCareInUse" + ("2" if slot else ""), 1)
                h.write8("wDayCareDepositBattleCount" + ("2" if slot else ""),
                         h.read8("wBattleCount"))
                h.write8("wBridgeSelectedEffectOwner1", owner)
                h.write8("wBridgeSelectedEffect1", 3)
                h.write8("wBridgeSelectedEffectOwner2", 248 - slot)
                h.write8("wBridgeSelectedEffect2", 4)
                h.call_routine("RentalReclaimDaycare")
                expected = [0, 0, 248 - slot, 4]
                self.assertEqual(h.read_bytes("wBridgeSelectedEffects", 4), expected)
                self.assertEqual(h.read8("wRentalOwner"), 0)
                # Reuse the real deposit/withdraw ownership seams. The next
                # occupant must neither inherit the expired effect nor move
                # the other daycare's effect.
                for source, target in ((1, owner), (owner, 1)):
                    result = run_entry(h, "BridgeMoveSelectedOwner",
                        registers={"B": source, "C": target},
                        capture=lambda h: {"effects": h.read_bytes("wBridgeSelectedEffects", 4)})
                    self.assertEqual(result["effects"], expected)

    def test_other_owner_and_empty_repeated_reclaim_never_charge(self):
        for owner in (0, 1, 7, 246, 247, 248, 249):
            def setup(h):
                self.money(h, 1234)
                h.write8("wRentalOwner", owner)
                h.write8("wDayCareInUse", 0)
                h.write8("wDayCareInUse2", 0)
            result = run_entry(self.h, "RentalReclaimDaycare", setup=setup, capture=lambda h: {
                "money": h.read_bytes("wPlayerMoney", 3), "owner": h.read8("wRentalOwner"),
            })
            self.assertEqual(result["money"], bcd3(1234))
            self.assertEqual(result["owner"], 0 if owner in (247, 248) else owner)
            self.assertEqual(bool(result["flags"] & 0x10), owner in (247, 248))
