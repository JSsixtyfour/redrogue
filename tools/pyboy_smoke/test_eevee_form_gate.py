"""Eeveelution forms obey the species-group gate (2026-10-11).

Espeon, Umbreon, Leafeon, Glaceon and Sylveon are FORMS of Flareon, Jolteon and
Vaporeon, which are Kanto species. The evolution gate checked only the target
species' group, so in a Kanto-only run a Leaf Stone made Leafeon and a Moon
Stone made Sylveon, and the Mist Stone rolled all eight Eevee branches with no
gate at all. Both paths now ask IsFormAllowed, the gate the reward roller uses:
Espeon/Umbreon are Johto (FormJohtoPairs), the other three are Time Warp.
"""
from pathlib import Path
import re
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

REPO_ROOT = Path(__file__).resolve().parents[2]
ITEMS = parse_rgbds_constants(REPO_ROOT / "constants" / "item_constants.asm")
SPECIES = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")
EVENTS = parse_rgbds_constants(REPO_ROOT / "constants" / "event_constants.asm")
GROUPS = parse_rgbds_constants(REPO_ROOT / "constants" / "rogue_species_groups.asm")
RAM = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")

KANTO = 1 << GROUPS["BIT_GROUP_KANTO"]
JOHTO = 1 << GROUPS["BIT_GROUP_JOHTO"]
WARP = 1 << GROUPS["BIT_GROUP_WARP"]
FLAG_C = 0x10
MON_CATCH_RATE = 7
FORM_MASK = 0x60  # MON_CATCH_RATE bits 5-6
TEXT_END = 0x50   # '@'


def _charmap() -> dict[str, int]:
    text = (REPO_ROOT / "constants" / "charmap.asm").read_text(encoding="utf-8")
    chars: dict[str, int] = {}
    for char, value in re.findall(r'charmap "(.)",\s*\$([0-9a-fA-F]{2})', text):
        chars.setdefault(char, int(value, 16))
    return chars


CHAR_TO_BYTE = _charmap()
BYTE_TO_CHAR = {v: k for k, v in reversed(list(CHAR_TO_BYTE.items()))}

# (stone, target species, group the resulting form needs)
FORM_EVOLUTIONS = (
    ("LEAF_STONE", "FLAREON", WARP),   # Leafeon
    ("SUN_STONE", "JOLTEON", JOHTO),   # Espeon
    ("DUSK_STONE", "JOLTEON", JOHTO),  # Umbreon
    ("ICE_STONE", "VAPOREON", WARP),   # Glaceon
    ("MOON_STONE", "VAPOREON", WARP),  # Sylveon
)
BASE_STONES = {ITEMS[n] for n in ("FIRE_STONE", "THUNDER_STONE", "WATER_STONE")}
STONE_GROUP = {ITEMS[stone]: group for stone, _, group in FORM_EVOLUTIONS}


# wEvoNewForm after EvoEntryTakeForm reads a plain (non-FORM) evolution entry
PLAIN_ENTRY = 0xFF


class EeveeFormGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(REPO_ROOT, Path(__file__).parent / "artifacts")
        self.h.boot_to_lobby()
        # Unlock both groups, then pick the active set through the SRAM toggles.
        flags = self.h.read8("wStatusFlags6")
        self.h.write8("wStatusFlags6", flags & ~(1 << RAM["BIT_DEBUG2_MODE"]) & 0xFF)
        self.h.set_event(EVENTS["EVENT_JOHTO_ACTIVATED"])
        self.h.set_event(EVENTS["EVENT_KANTO_TIMEWARP_ACTIVATED"])

    def tearDown(self) -> None:
        self.h.close()

    def set_groups(self, enabled: int) -> None:
        self.h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [enabled], bank=1)

    def run_routine(self, label: str, **regs_in: int) -> dict[str, int]:
        """test_item_descriptions.run_routine, plus register inputs/outputs."""
        h = self.h
        regs = h.pyboy.register_file
        memory = h.pyboy.memory
        names = ("A", "B", "C", "D", "E", "F", "HL", "PC", "SP")
        saved = {name: getattr(regs, name) for name in names}
        saved_bank = h.read8("hLoadedROMBank")
        stub = h.address("wStringBuffer") + 16
        saved_stub = [memory[stub], memory[stub + 1]]
        saved_ie = memory[0xFFFF]
        bank, address = h.symbols.get(label)
        memory[stub], memory[stub + 1] = 0x18, 0xFE  # jr @
        memory[0xFFFF] = 0
        if bank:
            h.write8("hLoadedROMBank", bank)
            memory[0x2000] = bank
        sp = (saved["SP"] - 2) & 0xFFFF
        memory[sp], memory[sp + 1] = stub & 0xFF, stub >> 8
        regs.SP = sp
        for name, value in regs_in.items():
            setattr(regs, name, value)
        regs.PC = address
        try:
            for _ in range(10):
                h.pyboy.tick()
                if regs.PC == stub:
                    break
            self.assertEqual(regs.PC, stub, f"{label} did not return (PC ${regs.PC:04X})")
            self.assertEqual(regs.SP, (sp + 2) & 0xFFFF, f"{label} unbalanced the stack")
            return {name: getattr(regs, name) for name in ("A", "E", "F")}
        finally:
            memory[0xFFFF] = saved_ie
            memory[stub], memory[stub + 1] = saved_stub
            h.write8("hLoadedROMBank", saved_bank)
            memory[0x2000] = saved_bank
            for name, value in saved.items():
                setattr(regs, name, value)

    def stone_allowed(self, stone: int, species: int) -> bool:
        self.h.write8("wEvoStoneItemID", stone)
        # As the evolution loop leaves it for a PLAIN entry (EvoEntryTakeForm):
        # these rows all come from base species' lists.
        self.h.write8("wEvoNewForm", PLAIN_ENTRY)
        out = self.run_routine("IsEvoStoneFormAllowed", C=species)
        return bool(out["F"] & FLAG_C)

    def test_stone_evolution_checks_the_form_group(self) -> None:
        for enabled in (KANTO, KANTO | JOHTO, KANTO | WARP, KANTO | JOHTO | WARP):
            self.set_groups(enabled)
            self.assertEqual(self.stone_allowed(ITEMS['DUSK_STONE'], SPECIES['MAROWAK']),
                             bool(enabled & WARP))
            for target in ('RAICHU', 'EXEGGUTOR', 'WEEZING'):
                self.assertEqual(self.stone_allowed(ITEMS['MOON_STONE'], SPECIES[target]),
                                 bool(enabled & WARP))
            for stone, target, needs in FORM_EVOLUTIONS:
                with self.subTest(enabled=enabled, stone=stone):
                    self.assertEqual(
                        self.stone_allowed(ITEMS[stone], SPECIES[target]),
                        bool(enabled & needs),
                    )
            with self.subTest(enabled=enabled, stone="FIRE_STONE"):
                # Form-preserving and plain evolutions are never blocked.
                self.assertTrue(self.stone_allowed(ITEMS["FIRE_STONE"], SPECIES["FLAREON"]))
                self.assertTrue(self.stone_allowed(ITEMS["MOON_STONE"], SPECIES["NIDOKING"]))
                self.assertTrue(self.stone_allowed(0, SPECIES["VAPOREON"]))

    def test_cubone_stone_sets_alolan_form_only(self) -> None:
        self.h.pyboy.memory[self.h.address('wLoadedMon') + MON_CATCH_RATE] = 0
        for stone, expected in ((ITEMS['DUSK_STONE'], 1), (0, 0)):
            self.h.write8('wEvoStoneItemID', stone)
            self.h.write8('wEvoNewForm', PLAIN_ENTRY)
            out = self.run_routine('GetEvolvedForm', C=SPECIES['MAROWAK'])
            self.assertEqual(out['A'], expected)

    def test_moon_stone_sets_regional_forms(self) -> None:
        self.h.pyboy.memory[self.h.address('wLoadedMon') + MON_CATCH_RATE] = 0
        for target, normal_stone in (('RAICHU', 'THUNDER_STONE'),
                                     ('EXEGGUTOR', 'LEAF_STONE'), ('WEEZING', None)):
            for stone, expected in (('MOON_STONE', 1), (normal_stone, 0)):
                self.h.write8('wEvoStoneItemID', ITEMS[stone] if stone else 0)
                self.h.write8('wEvoNewForm', PLAIN_ENTRY)
                out = self.run_routine('GetEvolvedForm', C=SPECIES[target])
                self.assertEqual(out['A'], expected, (target, stone))

    def test_mist_stone_eevee_rolls_only_unlocked_forms(self) -> None:
        h = self.h
        party_slot = 0
        h.write8("wPartySpecies", SPECIES["EEVEE"], offset=party_slot)
        h.write8("hWhichPokemon", party_slot)
        for enabled in (KANTO, KANTO | JOHTO, KANTO | WARP, KANTO | JOHTO | WARP):
            self.set_groups(enabled)
            allowed = BASE_STONES | {s for s, g in STONE_GROUP.items() if enabled & g}
            seen = set()
            for _ in range(60):
                h.write8("wEvoStoneItemID", ITEMS["MIST_STONE"])
                self.run_routine("MistStoneChooseEvolution")
                seen.add(h.read8("wEvoStoneItemID"))
            with self.subTest(enabled=enabled):
                self.assertTrue(seen <= allowed, f"locked branch rolled: {sorted(seen - allowed)}")
                # 60 uniform rolls over 3-8 branches: missing one is < 1e-3.
                self.assertEqual(seen, allowed)

    def rename_evolved(self, nick: str, old: str, old_form: int, new: str, stone: str) -> str:
        """Run RenameEvolvedMon on party slot 0 and return the resulting nickname."""
        h = self.h
        memory = h.pyboy.memory
        h.write8("hWhichPokemon", 0)
        h.write8("wNameListType", 1)  # MONSTER_NAME
        h.write8("wMonHIndex", SPECIES[old])  # the pre-evolution header
        h.write8("wCurSpecies", SPECIES[new])
        h.write8("wEvoStoneItemID", ITEMS[stone] if stone else 0)
        # What EvoEntryTakeForm leaves for the entry evolved through: a form
        # evolves through its OWN list, whose entry names the target form (both
        # form cases here carry form 1 forward); a base mon's entry is plain.
        h.write8("wEvoNewForm", old_form if old_form else PLAIN_ENTRY)
        h.write8("wFormContextSpecies", 0)
        catch_rate = h.address("wLoadedMon") + MON_CATCH_RATE
        memory[catch_rate] = (memory[catch_rate] & ~FORM_MASK & 0xFF) | (old_form << 5)
        nicks = h.address("wPartyMonNicks")
        encoded = [CHAR_TO_BYTE[c] for c in nick] + [TEXT_END]
        # The routine compares against wStringBuffer, where the evolution loop
        # copied the nick before the animation (CopyToStringBuffer).
        for buffer in (nicks, h.address("wStringBuffer")):
            for i in range(11):
                memory[buffer + i] = encoded[i] if i < len(encoded) else TEXT_END
        self.run_routine("RenameEvolvedMon")
        out = ""
        for i in range(11):
            byte = memory[nicks + i]
            if byte == TEXT_END:
                break
            out += BYTE_TO_CHAR.get(byte, "?")
        return out

    def test_evolution_renames_to_the_form_name(self) -> None:
        # Playtester report 2026-10-11: Eevee + Moon Stone became Sylveon but
        # was renamed "VAPOREON", because RenameEvolvedMon used species-only
        # names. Regional forms broke the other way: "A-VULPIX" never matched
        # plain "VULPIX", so it was misread as a nickname and kept forever.
        self.set_groups(KANTO | JOHTO | WARP)
        cases = (
            ("EEVEE", "EEVEE", 0, "VAPOREON", "MOON_STONE", "SYLVEON"),
            ("EEVEE", "EEVEE", 0, "VAPOREON", "ICE_STONE", "GLACEON"),
            ("EEVEE", "EEVEE", 0, "JOLTEON", "SUN_STONE", "ESPEON"),
            ("EEVEE", "EEVEE", 0, "VAPOREON", "WATER_STONE", "VAPOREON"),
            ("A-VULPIX", "VULPIX", 1, "NINETALES", "ICE_STONE", "ANINETALES"),
            ("A-MEOWTH", "MEOWTH", 1, "PERSIAN", None, "A-PERSIAN"),
            ("VULPIX", "VULPIX", 0, "NINETALES", "FIRE_STONE", "NINETALES"),
            ("FLUFFY", "EEVEE", 0, "VAPOREON", "MOON_STONE", "FLUFFY"),  # nickname kept
        )
        for nick, old, form, new, stone, expected in cases:
            with self.subTest(nick=nick, stone=stone):
                self.assertEqual(self.rename_evolved(nick, old, form, new, stone), expected)


if __name__ == "__main__":
    unittest.main()
