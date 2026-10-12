"""Complete stable offers reuse ordinary trainer source proportions safely."""
import io
import unittest
from collections import Counter
from pathlib import Path
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_move_tutor_prices import return_from_call
from test_save_header import ColdBoot, dump_sram

ROOT = Path(__file__).resolve().parents[2]


class RentalOfferMovesTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, Path(__file__).parent / "artifacts")
        self.h.boot_to_lobby()
        self.h.call_routine("RentalResetRecord")
        self.h.write8("hIsInBattle", 0)
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")

    def tearDown(self):
        self.h.close()

    def identity(self, species="EXEGGUTOR", form=0, level=50):
        h = self.h
        for label, value in (("wRentalOfferSpecies", self.species[species]),
                             ("wRentalOfferForm", form), ("wRentalOfferLevel", level),
                             ("wRentalOfferClass", 2), ("wRentalOfferFlags", 1)):
            h.write8(label, value)

    def rom(self, label, offset, size):
        bank, addr = self.h.symbols.get(label)
        return [self.h.pyboy.memory[bank, addr + offset + i] for i in range(size)]

    def test_every_representative_slot_uses_full_team_quotas_and_fallback(self):
        h = self.h
        self.sampling = False
        def begin(_):
            self.sampling = True
        def pick(_):
            if self.sampling:
                self.sampling = False
                h.pyboy.register_file.A = self.ordinal
                return_from_call(h)
        h.register_hook("RentalChooseTrainerSource.sampleSlot", begin)
        h.register_hook("Rangerandom", pick)
        for round_index in range(9):
            for step, table in ((0, "trainer_difficulty_settings"),
                                (4, "trainer_difficulty_settings_gym")):
                h.write8("wBattleCount", round_index * 8 + step)
                counts = self.rom(table, round_index * 11 + 7, 4)
                count = min(6, sum(counts))
                mix = self.rom("RosterMixByKindAndBand", 4 + min(round_index // 2, 3), 1)[0]
                row = self.rom("MovesetMixTable", mix * 14, 14)
                expected = Counter()
                remaining = count
                for source in reversed(range(6)):
                    units = min(remaining, row[source])
                    expected[source] += units
                    remaining -= units
                expected[row[13]] += remaining
                expected = +expected
                for self.ordinal in range(count):
                    with self.subTest(round=round_index, step=step, ordinal=self.ordinal):
                        h.call_routine("RentalChooseTrainerSource")
                        actual = h.read_bytes("wPartyGenSlotSource", count)
                        self.assertEqual(h.read8("wPartyGenNMons"), count)
                        self.assertEqual(Counter(actual), expected)
                        self.assertEqual(h.read8("wPartyGenSource"), actual[self.ordinal])

    def test_rental_only_fifty_percent_boundaries_rounds_five_through_eight(self):
        h = self.h
        phase = {"value": None}
        h.register_hook("RentalChooseTrainerSource.sampleSlot", lambda _: phase.update(value="original"))
        h.register_hook("RentalChooseOfferSource.stadiumRoll", lambda _: phase.update(value="coin"))
        h.register_hook("RentalChooseOfferSource.generatedRoll", lambda _: phase.update(value="generated"))
        def coin(_):
            if phase["value"] == "coin":
                phase["value"] = None
                h.pyboy.register_file.A = self.coin
                return_from_call(h)
        def ordinal(_):
            if phase["value"] in ("original", "generated"):
                value = self.ordinal if phase["value"] == "generated" else 0
                phase["value"] = None
                h.pyboy.register_file.A = value
                return_from_call(h)
        h.register_hook("Random", coin)
        h.register_hook("Rangerandom", ordinal)
        for round_index in range(9):
            h.write8("wBattleCount", round_index * 8)
            for self.coin in (0, 127, 128, 255):
                for self.ordinal in range(4):
                    h.call_routine("RentalChooseOfferSource")
                    slots = h.read_bytes("wPartyGenSlotSource", h.read8("wPartyGenNMons"))
                    if 4 <= round_index < 8:
                        generated = [source for source in slots if source != 5]
                        expected = 5 if self.coin >= 128 else generated[self.ordinal]
                    else:
                        expected = slots[0]
                    with self.subTest(round=round_index, coin=self.coin, ordinal=self.ordinal):
                        self.assertEqual(h.read8("wPartyGenSource"), expected)

    def test_complete_offer_restores_scratch_enemy_context_party_money_and_stack(self):
        h = self.h
        self.identity()
        contexts = {"wCurEnemyLevel": 17, "wCurPartySpecies": self.species["PIKACHU"],
                    "wCurSpecies": self.species["MEW"], "wFormContextSpecies": self.species["MEW"],
                    "wFormContextForm": 2, "wEnemyPartyCount": 5, "wEnemyMoveOrigins": 201}
        for label, value in contexts.items():
            h.write8(label, value)
        for i in range(44):
            h.write8("wEnemyMon1", (i * 13) & 255, offset=i)
        for i in range(32):
            h.write8("wPartyGenScratch", (i * 7) & 255, offset=i)
        before = {label: h.read_bytes(label, length) for label, length in
                  (("wEnemyMon1", 44), ("wPartyGenScratch", 32),
                   ("wPartyMons", 264), ("wPlayerMoney", 3))}
        stack_min = [0xffff]
        for label in ("PartyGenDrawCandidate", "GetMoveMaxPPFar", "GetLevelUpMovesFar",
                      "RentalIsStadiumOrigin", "Rangerandom"):
            h.register_hook(label, lambda _: stack_min.__setitem__(
                0, min(stack_min[0], h.pyboy.register_file.SP)))
        h.call_routine("RentalPrepareOfferMoves")
        self.assertTrue(h.last_call_registers["F"] & 0x10)
        self.assertEqual(h.read8("wRentalOfferFlags"), 3)
        self.assertGreater(h.read8("wRentalOfferMoves"), 0)
        self.assertGreaterEqual(stack_min[0], 0xdf00)
        for label, value in contexts.items():
            self.assertEqual(h.read8(label), value)
        for label, value in before.items():
            self.assertEqual(h.read_bytes(label, len(value)), value)

    def test_generated_fallback_handles_missing_species_and_special_form(self):
        h = self.h
        h.write8("wBattleCount", 48)  # final band includes a curated-source quota
        pending = [False]
        def begin(_):
            pending[0] = True
        def force_curated(_):
            if pending[0]:
                pending[0] = False
                sources = h.read_bytes("wPartyGenSlotSource", h.read8("wPartyGenNMons"))
                h.pyboy.register_file.A = sources.index(5)
                return_from_call(h)
        h.register_hook("RentalChooseTrainerSource.sampleSlot", begin)
        h.register_hook("Rangerandom", force_curated)
        bias = [False]
        h.register_hook("RentalChooseOfferSource.stadiumRoll", lambda _: bias.__setitem__(0, True))
        def force_bias(_):
            if bias[0]:
                bias[0] = False
                h.pyboy.register_file.A = 128
                return_from_call(h)
        h.register_hook("Random", force_bias)
        for species, form in (("BAYLEEF", 0), ("EXEGGUTOR", 1)):
            self.identity(species, form)
            h.call_routine("RentalPrepareOfferMoves")
            self.assertTrue(h.last_call_registers["F"] & 0x10)
            self.assertEqual(h.read8("wRentalOfferFlags"), 3)
            self.assertEqual(h.read8("wRentalOfferSource"), 3)  # final fallback RANDOM_TM
            self.assertGreater(h.read8("wRentalOfferMoves"), 0)

    def test_curated_offer_and_very_easy_fallback_use_the_same_sampled_source(self):
        h = self.h
        h.write8("wBattleCount", 32)
        pending = [False]
        def begin(_):
            pending[0] = True
        def force_curated(_):
            if pending[0]:
                pending[0] = False
                sources = h.read_bytes("wPartyGenSlotSource", h.read8("wPartyGenNMons"))
                h.pyboy.register_file.A = sources.index(5)
                return_from_call(h)
        h.register_hook("RentalChooseTrainerSource.sampleSlot", begin)
        h.register_hook("Rangerandom", force_curated)
        bias = [False]
        h.register_hook("RentalChooseOfferSource.stadiumRoll", lambda _: bias.__setitem__(0, True))
        def force_bias(_):
            if bias[0]:
                bias[0] = False
                h.pyboy.register_file.A = 128
                return_from_call(h)
        h.register_hook("Random", force_bias)
        # Pikachu has an eligible normal-tier official rental at level 50.
        self.identity("PIKACHU", 0, 50)
        h.write8("wOptions2", h.read8("wOptions2") & ~7)
        h.call_routine("RentalPrepareOfferMoves")
        self.assertTrue(h.last_call_registers["F"] & 0x10)
        self.assertEqual(h.read8("wRentalOfferSource"), 5)
        self.identity("PIKACHU", 0, 50)
        h.write8("wOptions2", (h.read8("wOptions2") & ~7) | 2)
        h.call_routine("RentalPrepareOfferMoves")
        self.assertTrue(h.last_call_registers["F"] & 0x10)
        self.assertEqual(h.read8("wRentalOfferSource"), 2)

    def test_completed_offer_has_no_rng_and_survives_cold_continue(self):
        h = self.h
        h.call_routine("RentalPrepareOfferMoves")
        self.assertEqual(h.read8("wRentalOfferFlags"), 3)
        offer = h.read_bytes("wRentalOfferSpecies", 12)
        generation = []
        h.register_hook("RentalGenerateMovesForSlot", lambda _: generation.append(True))
        for _ in range(3):
            h.call_routine("RentalPrepareOfferMoves")
            self.assertEqual(h.read_bytes("wRentalOfferSpecies", 12), offer)
        self.assertFalse(generation)
        h.call_routine("SaveGameData")
        boot = ColdBoot(dump_sram(h))
        self.addCleanup(boot.close)
        self.assertEqual(boot.to_menu(), 2)
        boot.continue_game()
        boot.h.call_routine("RentalPrepareOfferMoves")
        self.assertEqual(boot.h.read_bytes("wRentalOfferSpecies", 12), offer)

    def test_battle_active_contract_and_corrupt_complete_offer_fail_closed(self):
        h = self.h
        self.identity()
        for state, battle in ((1, 0), (2, 0), (0, 1)):
            h.write8("wRentalState", state)
            h.write8("hIsInBattle", battle)
            before = h.read_bytes("wRentalOfferSpecies", 12)
            h.call_routine("RentalPrepareOfferMoves")
            self.assertFalse(h.last_call_registers["F"] & 0x10)
            self.assertEqual(h.read_bytes("wRentalOfferSpecies", 12), before)
        h.write8("wRentalState", 0)
        h.write8("hIsInBattle", 0)
        h.write8("wRentalOfferFlags", 3)
        h.write8("wRentalOfferMoves", 255)
        h.call_routine("RentalPrepareOfferMoves")
        self.assertFalse(h.last_call_registers["F"] & 0x10)
        self.assertEqual(h.read8("wRentalOfferMoves"), 255)
