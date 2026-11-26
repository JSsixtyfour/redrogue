"""What you are shown is what you get, for shiny Pokemon (custom_functions/shiny_rolls.asm).

A reward offer's INFO screen, the party mon and the box mon use one stored roll; a wild
mon is rolled as its battle starts and keeps it when caught or when it joins; a gift that
copies an existing mon into the box is the exact copy. Every roll is forced at its one
comparison (ShinyFromRoll, b = the byte), never by waiting for a 1/256.
"""
from __future__ import annotations

import io
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
SPECIES = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
TRANSFORMED = 1 << parse_rgbds_constants(ROOT / "constants/battle_constants.asm")["TRANSFORMED"]
MAX_LEVEL = parse_rgbds_constants(ROOT / "constants/battle_constants.asm")["MAX_LEVEL"]
SHINY = 1 << 4
DECIDED = 1 << 7
MARK = 0xD4            # <HUD_SHINY>
PARTY, BOX = 44, 33    # struct lengths
CATCH_RATE, BOX_LEVEL, LEVEL = 7, 3, 33


class ShinyRollsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        cls.h.boot_to_lobby()
        cls.h.park_before_hijack(idle=True)
        cls.state = io.BytesIO()
        cls.h.save_state(cls.state)
        cls.rolls: list[int] = []
        cls.force = None

        def roll(_context) -> None:
            cls.rolls.append(cls.h.pyboy.register_file.B)
            if cls.force is not None:
                cls.h.pyboy.register_file.B = cls.force

        cls.h.register_hook("ShinyFromRoll", roll)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.h.close()

    def setUp(self) -> None:
        self.state.seek(0)
        self.h.load_state(self.state)
        type(self).force = None
        self.rolls.clear()

    def offer(self, slot: int, species: str, raw: int) -> None:
        h, i = self.h, slot - 1
        h.write8("wRoguePokemon1", SPECIES[species], offset=i)
        h.write8("wRoguePokemonForm1", 0, offset=i)
        for label, value in (("sRogueOfferDVTag", SPECIES[species]), ("sRogueOfferShiny", raw)):
            bank = h.symbols.bank(label)
            data = h.read_sram_bytes(label, 3, bank=bank)
            data[i] = value
            h.write_sram_bytes(label, data, bank=bank)

    def add_party_mon(self, species: str, **wram) -> int:
        h = self.h
        h.write8("wPartyCount", 1)
        h.write8("wPartySpecies", 0xFF, offset=1)
        h.write8("wCurPartySpecies", SPECIES[species])
        h.write8("wCurEnemyLevel", 20)
        h.write8("wMonDataLocation", 0x10)  # player party, no naming screen
        for label in ("wSpawnForm", "wSpawnDVSlot", "wSpawnShiny", "hIsInBattle"):
            h.write8(label, wram.get(label, 0))
        flags = h.call_routine("_AddPartyMon", limit=60000, capture=lambda h: (
            h.read8("wPartyMon1", offset=PARTY + CATCH_RATE), h.read8("wPartyMon1", offset=PARTY),
            h.read8("wCurPartySpecies"), h.read8("wSpawnShiny")))
        self.assertEqual(flags[1:], (SPECIES[species], SPECIES[species], 0),
                         "species, the wCurItem alias, the one-shot request")
        return flags[0]

    def load_enemy(self, species: str, **wram) -> int:
        h = self.h
        h.write8("wEnemyMonSpecies2", SPECIES[species])
        h.write8("wCurEnemyLevel", 20)
        h.write8("wOptionalEncounterBattle", 0)
        h.write8("wProcCemBossBattle", 0)
        for label in ("wSpawnForm", "wSpawnDVSlot", "wSpawnShiny", "hIsInBattle", "wEnemyBattleStatus3"):
            h.write8(label, wram.get(label, 0))
        return h.call_routine("LoadEnemyMonData", limit=60000, capture=lambda h: h.read8("wEnemyMonCatchRate"))

    # ---------------------------------------------------------------- offers
    def test_an_offers_stored_roll_decides_party_box_and_info(self) -> None:
        h = self.h
        for raw, shiny in ((0, True), (1, False)):  # the base rate is 1/256
            for slot in (1, 2, 3):
                with self.subTest(raw=raw, slot=slot):
                    self.setUp()
                    self.offer(slot, "MEOWTH", raw)
                    want = SHINY if shiny else 0
                    self.assertEqual(self.load_enemy("MEOWTH", wSpawnDVSlot=slot), want, "box path")
                    h.write8("wRewardInfoSlot", slot)
                    plain = 0x18
                    h.write8("wPalPacket", plain, offset=3)
                    palette = h.call_routine("RewardInfoPalette", capture=lambda h: h.read8("wPalPacket", offset=3))
                    self.assertEqual(palette != plain, shiny, "INFO palette")
                    h.write8("wTileMap", 0x7F, offset=2 * 20 + 8)
                    mark = h.call_routine("PrintRewardOfferDetails", limit=30000, capture=lambda h: h.read8(
                        "wTileMap", offset=2 * 20 + 8))
                    self.assertEqual(mark, MARK if shiny else 0x7F, "INFO mark")
                    h.write8("wRewardInfoSlot", 0)
                    self.assertEqual(self.add_party_mon("MEOWTH", wSpawnDVSlot=slot), want, "party path")
                    self.assertEqual(set(self.rolls), {raw}, "something rolled instead of using the stored byte")

    def test_no_preview_means_no_shiny_info(self) -> None:
        for slot in (0, 0x85):  # closed; the Pokedex Forms page
            with self.subTest(slot=slot):
                self.setUp()
                self.force = 0
                self.h.write8("wRewardInfoSlot", slot)
                self.h.call_routine("RewardInfoPalette")
                self.assertEqual(self.rolls, [])

    def test_a_new_set_of_offers_forgets_the_old_rolls(self) -> None:
        h = self.h
        self.offer(1, "MEOWTH", 0)
        h.write8("wRoguePokemonForm1", 2, offset=2)
        h.call_routine("RogueOffersReset")
        self.assertEqual(h.read_bytes("wRoguePokemon1", 6), [0] * 6)
        bank = h.symbols.bank("sRogueOfferDVTag")
        self.assertEqual(h.read_sram_bytes("sRogueOfferDVs", 12, bank=bank), [0] * 12)

    def test_looking_twice_does_not_roll_twice(self) -> None:
        h = self.h
        h.call_routine("RogueOffersReset")
        h.write8("wRoguePokemon2", SPECIES["MEOWTH"])
        seen = []
        for _ in range(2):
            h.pyboy.register_file.E = 2
            h.call_routine("GetRogueOfferDVs", limit=2000)
            seen.append((h.last_call_registers["E"], h.last_call_registers["HL"]))
        self.assertEqual(seen[0], seen[1])
        self.assertEqual(h.read_sram_bytes("sRogueOfferShiny", 3, bank=h.symbols.bank("sRogueOfferShiny"))[1], seen[0][0])

    # ------------------------------------------------------------------ wild
    def test_a_wild_mon_is_rolled_once_and_kept_when_caught(self) -> None:
        for force, want in ((0, SHINY), (200, 0)):
            with self.subTest(force=force):
                self.setUp()
                type(self).force = force
                self.assertEqual(self.load_enemy("RATTATA", hIsInBattle=1), want)
                self.assertEqual(len(self.rolls), 1)
                # The capture rebuilds it under TRANSFORMED; the opposite roll must not be taken.
                type(self).force = 200 - force
                self.assertEqual(self.load_enemy("RATTATA", hIsInBattle=1, wEnemyBattleStatus3=TRANSFORMED), want,
                                 "lost in the capture rebuild (what SendNewMonToBox copies)")
                self.assertEqual(self.add_party_mon("RATTATA", hIsInBattle=1) & SHINY, want, "caught into the party")
                self.assertEqual(len(self.rolls), 1, "rolled again")

    def test_a_mon_that_joins_keeps_the_flag_it_was_fought_with(self) -> None:
        h = self.h
        for flags, force in ((SHINY, 200), (0, 0)):
            for box in (False, True):
                with self.subTest(flags=flags, box=box):
                    self.setUp()
                    type(self).force = force
                    h.write8("wEnemyMonCatchRate", flags)
                    h.call_routine("JoiningMonKeepShiny")
                    request = h.read8("wSpawnShiny")
                    self.assertEqual(request, DECIDED | flags)
                    got = (self.load_enemy if box else self.add_party_mon)("RATTATA", wSpawnShiny=request)
                    self.assertEqual(got & SHINY, flags)
                    self.assertEqual(self.rolls, [])

    def test_boss_gift_level_also_keeps_the_flag(self) -> None:
        h = self.h
        h.call_routine("PCGetBossLevel")
        level = h.read8("wCurEnemyLevel")
        h.write8("wEnemyMonCatchRate", SHINY)
        h.write8("wCurEnemyLevel", 0)
        after = h.call_routine("PCGetBossGiftLevel", capture=lambda h: (
            h.read8("wCurEnemyLevel"), h.read8("wSpawnShiny")))
        self.assertEqual(after, (level, DECIDED | SHINY))

    # ------------------------------------------------- other box deliveries
    def test_a_plain_gift_rolls_in_the_box_too(self) -> None:
        for force, want in ((0, SHINY), (200, 0)):
            with self.subTest(force=force):
                self.setUp()
                type(self).force = force
                self.assertEqual(self.load_enemy("EEVEE"), want)

    def make_source(self, label: str, flags: int) -> list[int]:
        """A party struct full of distinct bytes: cur HP 5/300, status set, level 44."""
        mon = [(i * 7 + 3) & 0xFF for i in range(PARTY)]
        mon[0], mon[1:3], mon[4], mon[CATCH_RATE] = SPECIES["DITTO"], [0, 5], 8, flags
        mon[LEVEL], mon[34:36] = 44, [1, 44]
        base = self.h.address(label)
        self.h.pyboy.memory[base:base + PARTY] = mon
        return mon

    def boxed(self, h) -> list[int]:
        return h.read_bytes("wBoxMon1", BOX)

    def test_bills_duplicate_in_the_box_is_the_exact_copy(self) -> None:
        h, regs = self.h, self.h.pyboy.register_file
        source = self.make_source("wPartyMon3", SHINY | 0x20)

        def select(_context) -> None:
            h.write8("hWhichPokemon", 2)
            finish(carry=False)

        def give(_context) -> None:
            h.write8("wAddedToParty", 0)
            finish(carry=True)

        def finish(carry: bool) -> None:
            regs.F = 0x10 if carry else 0
            sp = regs.SP
            regs.PC = h.pyboy.memory[sp] | h.pyboy.memory[sp + 1] << 8
            regs.SP = sp + 2

        h.register_hook("BridgeSelectPartyMon", select)
        h.register_hook("GivePokemon", give)
        try:
            got = h.call_routine("BridgeBillDuplicate", limit=30000, capture=self.boxed)
        finally:
            h.unregister_hook("BridgeSelectPartyMon", select)
            h.unregister_hook("GivePokemon", give)
        want = source[:BOX]
        want[BOX_LEVEL] = 44
        self.assertEqual(got, want)

    def test_pokemaniacs_prize_in_the_box_is_his_mon(self) -> None:
        h = self.h
        source = self.make_source("wEnemyMon6", SHINY | 0x02)
        h.write8("wAddedToParty", 0)
        got = h.call_routine("FacManiacBoxPrize", limit=30000, capture=self.boxed)
        want = source[:BOX]
        want[BOX_LEVEL] = 44
        want[1:3] = [1, 44]                     # healed
        want[4] = 0                             # cured
        want[CATCH_RATE] = SHINY                # never a fusion
        want[12:14] = h.read_bytes("wPlayerID", 2)
        self.assertEqual(got, want)

    def test_pokemaniacs_prize_leaves_a_fresh_mon_alone(self) -> None:
        h = self.h
        for name, added, level in (("party", 1, 44), ("over the level cap", 0, MAX_LEVEL + 1)):
            with self.subTest(name):
                self.setUp()
                self.make_source("wEnemyMon6", SHINY)
                h.write8("wEnemyMon6", level, offset=LEVEL)
                h.write8("wAddedToParty", added)
                before = self.boxed(h)
                self.assertEqual(h.call_routine("FacManiacBoxPrize", limit=30000, capture=self.boxed), before)


if __name__ == "__main__":
    unittest.main()
