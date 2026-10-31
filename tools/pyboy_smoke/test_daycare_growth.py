"""Exercise daycare growth quotes, deferred commits, and elapsed-time fees."""
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_save_header import ARTIFACTS, REPO_ROOT
from test_move_tutor_prices import run_entry, return_from_call, bcd3


class DaycareGrowthTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        cls.h.boot_to_lobby()
        cls.species = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")["DITTO"]
        cls.cap = parse_rgbds_constants(REPO_ROOT / "constants/battle_constants.asm")["MAX_LEVEL"]

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def probe(self, entry, level, target, elapsed, outcome="accept"):
        h = self.h
        second = entry == "LobbyDaycareLady"
        suffix = "2" if second else ""
        mon = "wDayCareMon2" if second else "wDayCareMon"
        level_label = mon + "BoxLevel"
        exp_label = mon + "Exp"
        result = {}

        def setup(h):
            data = h.read_bytes("wPartyMons", 33)
            data[0] = self.species
            data[3] = level
            data[14:17] = list((level ** 3).to_bytes(3, "big"))
            start = h.address(mon)
            h.pyboy.memory[start:start + 33] = data
            h.write8("wDayCareDepositBattleCount" + suffix, 48)
            h.write8("wBattleCount", (48 + elapsed) & 255)
            h.write8("wPartyCount", 6 if outcome == "full" else 2)
            start = h.address("wPlayerMoney")
            h.pyboy.memory[start:start + 3] = bcd3(20000)

        def reward(_):
            h.write8("wCurEnemyLevel", target)
            return_from_call(h)

        def choice(_):
            h.write8("hCurrentMenuItem", int(outcome == "decline"))
            return_from_call(h)

        def funds(_):
            h.pyboy.register_file.F = 0x10 if outcome == "poor" else 0
            return_from_call(h)

        def moved(_):
            result["moved"] = True
            return_from_call(h)
            h.pyboy.register_file.PC = h.address(entry + ".done")

        def capture(h):
            return {"level": h.read8(level_label), "exp": h.read_bytes(exp_label, 3),
                    "grown": h.read8("wDayCareNumLevelsGrown" + suffix),
                    "cost": h.read_bytes("wDayCareTotalCost" + suffix, 2),
                    "money": h.read_bytes("wPlayerMoney", 3)}

        hooks = {"GetRewardMonLevel": reward, "YesNoChoice": choice,
                 "HasEnoughMoney": funds, "MoveMon": moved}
        for label in ("PrintText", "GetPartyMonName", "PlaySoundWaitForCurrent",
                      "DisplayTextBoxID"):
            hooks[label] = lambda _: return_from_call(h)
        if entry == "DaycareGentlemanText":
            hooks["TextScriptEnd"] = lambda _: return_from_call(h)
        result.update(run_entry(h, entry + ".daycareInUse", setup=setup,
                                hooks=hooks, capture=capture))
        return result

    def test_minimum_growth_catchup_cap_and_time_prices(self):
        cases = [(60, 45, 8, 61), (45, 45, 8, 46), (30, 45, 8, 45),
                 (60, 45, 9, 61), (60, 45, 1, 61), (30, 45, 0, 30),
                 (self.cap - 1, self.cap, 8, self.cap),
                 (self.cap, 45, 8, self.cap)]
        for entry in ("LobbyDaycareLady", "LobbyDaycareGentleman", "DaycareGentlemanText"):
            for level, target, elapsed, expected in cases:
                with self.subTest(entry=entry, level=level, elapsed=elapsed):
                    result = self.probe(entry, level, target, elapsed)
                    self.assertTrue(result.get("moved"))
                    self.assertEqual(result["level"], expected)
                    self.assertEqual(result["exp"], list((expected ** 3).to_bytes(3, "big")))
                    fee = ((elapsed + 7) // 8) * 500
                    self.assertEqual(result["cost"], bcd3(fee)[1:])
                    self.assertEqual(result["money"], bcd3(20000 - fee))

    def test_unsuccessful_withdrawal_preserves_level_experience_and_money(self):
        for entry in ("LobbyDaycareLady", "LobbyDaycareGentleman", "DaycareGentlemanText"):
            for outcome in ("decline", "poor", "full"):
                with self.subTest(entry=entry, outcome=outcome):
                    result = self.probe(entry, 60, 45, 8, outcome)
                    self.assertFalse(result.get("moved", False))
                    self.assertEqual(result["grown"], 1)
                    self.assertEqual(result["level"], 60)
                    self.assertEqual(result["exp"], list((60 ** 3).to_bytes(3, "big")))
                    self.assertEqual(result["money"], bcd3(20000))

    def test_automatic_owned_recovery_matches_minimum_growth(self):
        h = self.h
        for slot in (0, 1):
            for level, target, elapsed, expected in (
                    (60, 45, 8, 61), (45, 45, 8, 46), (30, 45, 8, 45),
                    (60, 45, 0, 60), (self.cap, 45, 8, self.cap)):
                with self.subTest(slot=slot, level=level, elapsed=elapsed):
                    def setup(h):
                        data = h.read_bytes("wPartyMons", 33)
                        data[0] = self.species
                        data[3] = level
                        data[14:17] = list((level ** 3).to_bytes(3, "big"))
                        start = h.address("wDayCareMon2" if slot else "wDayCareMon")
                        h.pyboy.memory[start:start + 33] = data
                        h.write8("wDayCareInUse" + ("2" if slot else ""), 1)
                        h.write8("wDayCareDepositBattleCount" + ("2" if slot else ""), 48)
                        h.write8("wBattleCount", 48 + elapsed)
                        h.write8("wPartyCount", 0)
                        h.write8("wPartySpecies", 255)
                    def reward(_):
                        h.write8("wCurEnemyLevel", target)
                        return_from_call(h)
                    result = run_entry(h, "RentalRetrieveDaycare", registers={"E": slot},
                        setup=setup, hooks={"GetRewardMonLevel": reward,
                            "DaycareRetrieveUpgrade": lambda _: return_from_call(h)},
                        capture=lambda h: {"level": h.read8("wPartyMon1Level"),
                            "exp": h.read_bytes("wPartyMon1Exp", 3),
                            "count": h.read8("wPartyCount")})
                    self.assertEqual(result["count"], 1)
                    self.assertEqual(result["level"], expected)
                    self.assertEqual(result["exp"], list((expected ** 3).to_bytes(3, "big")))
