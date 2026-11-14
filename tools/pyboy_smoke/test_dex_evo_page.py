"""Pokedex page 3: what a mon evolves into, and how (2026-11-14).

DexShowEvoPage (custom_functions/dex_evo_page.asm) walks the mon's own
evolution list and lists only the targets IsEvolutionTargetAllowed would let it
evolve into this run, so a locked species group hides its branches.

The page waits for A/B between pages, so it needs frames and live interrupts:
call_routine's VBlank park cannot run it. Each case instead enters the real
page (ShowPokedexData or FormDexShowData) from the lobby's map script, a
mainline call with the engine's own stack, by faking the frame Bankswitch
would have pushed, then presses A through the pages.
"""
from pathlib import Path
import re
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_eevee_form_gate import BYTE_TO_CHAR, KANTO, JOHTO, WARP

REPO_ROOT = Path(__file__).resolve().parents[2]
SPECIES = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")
EVENTS = parse_rgbds_constants(REPO_ROOT / "constants" / "event_constants.asm")
RAM = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")
DEX = parse_rgbds_constants(REPO_ROOT / "constants" / "pokedex_constants.asm")
MON_CATCH_RATE = 7
FIRST_ROW, ROWS, METHOD_X = 11, 6, 12


class DexEvoPageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.h = RedRogueHarness(REPO_ROOT, Path(__file__).parent / "artifacts")
        h = cls.h
        h.boot_to_lobby()
        flags = h.read8("wStatusFlags6")
        h.write8("wStatusFlags6", flags & ~(1 << RAM["BIT_DEBUG2_MODE"]) & 0xFF)
        h.set_event(EVENTS["EVENT_GOT_POKEDEX"])
        h.set_event(EVENTS["EVENT_JOHTO_ACTIVATED"])
        h.set_event(EVENTS["EVENT_KANTO_TIMEWARP_ACTIVATED"])
        h.tick(30)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.h.close()

    # --- helpers -----------------------------------------------------------

    def set_owned(self, owned: bool) -> None:
        for label, size in (("wPokedexSeen", 32), ("wPokedexFormSeen", 7),
                            ("wPokedexOwned", 32), ("wPokedexFormOwned", 7)):
            value = 0xFF if owned or "Seen" in label else 0
            for i in range(size):
                self.h.write8(label, value, offset=i)

    def set_groups(self, enabled: int) -> None:
        self.h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [enabled], bank=1)

    def row(self, row: int, col: int = 1, length: int = 18) -> str:
        data = self.h.read_bytes("wTileMap", length, offset=row * 20 + col)
        return "".join(BYTE_TO_CHAR.get(b, "?") for b in data)

    def lines(self) -> list[tuple[str, str]]:
        out = []
        for r in range(FIRST_ROW, FIRST_ROW + ROWS):
            name = self.row(r, 1, 10).strip()
            method = self.row(r, METHOD_X, 7).strip()
            if name or method:
                out.append((name, method))
        return out

    def show(self, label: str, c: int | None = None) -> list[list[tuple[str, str]]]:
        """Open `label`'s page from the lobby script, press A through it, and
        return every evolution page's lines ([] if page 3 never appears)."""
        h = self.h
        bank, address = h.symbols.get(label)
        bankswitch_return = h.address("Bankswitch.Return")
        state = {"started": False}
        pages: list[list[tuple[str, str]]] = []
        snapshot: dict[str, int] = {}
        watched = (("wPokedexNum", 0), ("wLoadedMon", MON_CATCH_RATE),
                   ("wEvoStoneItemID", 0), ("wEvoNewForm", 0))

        def start(_context) -> None:
            if state["started"]:
                return
            state["started"] = True
            rf = h.pyboy.register_file
            memory = h.pyboy.memory
            current = h.read8("hLoadedROMBank")
            sp = rf.SP - 2  # Bankswitch.Return pops bc: b = the bank to restore
            memory[sp], memory[sp + 1] = 0, current
            sp -= 2
            memory[sp], memory[sp + 1] = bankswitch_return & 0xFF, bankswitch_return >> 8
            rf.SP = sp
            h.write8("hLoadedROMBank", bank)
            memory[0x2000] = bank
            if c is not None:
                rf.C = c
            rf.PC = address

        def entered(_context) -> None:
            for name, offset in watched:
                snapshot[name] = h.read8(name, offset)

        def page_full(_context) -> None:
            pages.append(self.lines())  # the mid-list page turn

        def listed(_context) -> None:
            pages.append(self.lines())
            self.header = self.row(4, 9, 9)
            self.first_row = self.row(FIRST_ROW).rstrip()

        mismatches: list[str] = []

        def restored(_context) -> None:
            for name, offset in watched:
                if h.read8(name, offset) != snapshot[name]:
                    mismatches.append(name)

        lobby = h.hook_flag("IndigoPlateauLobby_Script")
        h.register_hook("IndigoPlateauLobby_Script", start)
        evo = h.hook_flag("DexShowEvoPage")
        h.register_hook("DexShowEvoPage", entered)
        h.register_hook("DexShowEvoPage.pageFull", page_full)
        h.register_hook("DexShowEvoPage.listed", listed)
        restores = h.hook_flag("DexShowEvoPage.restored")
        h.register_hook("DexShowEvoPage.restored", restored)
        try:
            h.wait_until(lambda: state["started"], "the lobby script", 600)
            seen_lobby = lobby["count"]
            for _ in range(60):
                h.tick(40)
                if lobby["count"] > seen_lobby:
                    break
                h.tap("a", 4)
            self.assertGreater(lobby["count"], seen_lobby, "the page closed")
        finally:
            h.unregister_hook("IndigoPlateauLobby_Script", start)
            h.unregister_hook("DexShowEvoPage", entered)
            h.unregister_hook("DexShowEvoPage.pageFull", page_full)
            h.unregister_hook("DexShowEvoPage.listed", listed)
            h.unregister_hook("DexShowEvoPage.restored", restored)
        self.assertEqual(restores["count"], evo["count"], "every page 3 returned")
        self.assertEqual(mismatches, [], "state DexShowEvoPage must preserve")
        return pages

    def species_page(self, name: str) -> list[list[tuple[str, str]]]:
        self.h.write8("wRewardInfoSlot", 0)
        self.h.write8("wPokedexNum", SPECIES[name])
        return self.show("ShowPokedexData")

    # --- tests -------------------------------------------------------------

    def test_every_evolution_stone_has_a_label(self) -> None:
        stones = set()
        for path in [REPO_ROOT / "data" / "pokemon" / "evos_moves.asm",
                     *(REPO_ROOT / "data" / "pokemon" / "form_evos_moves").glob("*.asm")]:
            text = path.read_text(encoding="utf-8")
            stones |= set(re.findall(r"^\s*db EVOLVE_ITEM(?:_FORM)?,\s*([A-Z_]+)", text, re.M))
            stones |= set(re.findall(r"^\s*evo_item_form\s+\d+,\s*([A-Z_]+)", text, re.M))
        page = (REPO_ROOT / "custom_functions" / "dex_evo_page.asm").read_text(encoding="utf-8")
        labelled = set(re.findall(r"^\s*db (\w+),\s*\"", page, re.M))
        self.assertTrue(stones)
        self.assertEqual(stones - labelled, set(), "stones without a DexEvoStoneNames label")

    def test_level_trade_and_none(self) -> None:
        self.set_owned(True)
        self.set_groups(KANTO | JOHTO | WARP)
        self.assertEqual(self.species_page("BULBASAUR"), [[("IVYSAUR", "LV 16")]])
        self.assertEqual(self.species_page("KADABRA"), [[("ALAKAZAM", "LV42/TR")]])
        self.assertEqual(len(self.species_page("VENUSAUR")), 1)
        self.assertEqual(self.first_row, "NO EVOLUTION")
        self.assertEqual(self.header, "EVOLUTION", "header replaces TYPE/")

    def test_locked_group_hides_its_branch(self) -> None:
        self.set_owned(True)
        self.set_groups(KANTO)
        self.assertEqual(self.species_page("SLOWPOKE"), [[("SLOWBRO", "LV 37")]])
        self.set_groups(KANTO | JOHTO)
        self.assertEqual(self.species_page("SLOWPOKE"),
                         [[("SLOWBRO", "LV 37"), ("SLOWKING", "WATER")]])

    def test_eevee_branches_follow_the_groups_and_overflow(self) -> None:
        self.set_owned(True)
        kanto = [("FLAREON", "FIRE"), ("JOLTEON", "THUNDER"), ("VAPOREON", "WATER")]
        self.set_groups(KANTO)
        self.assertEqual(self.species_page("EEVEE"), [kanto])
        self.set_groups(KANTO | JOHTO)
        self.assertEqual(self.species_page("EEVEE"),
                         [kanto + [("ESPEON", "SUN"), ("UMBREON", "DUSK")]])
        self.set_groups(KANTO | JOHTO | WARP)
        everything = kanto + [("LEAFEON", "LEAF"), ("ESPEON", "SUN"), ("UMBREON", "DUSK"),
                              ("GLACEON", "ICE"), ("SYLVEON", "MOON")]
        self.assertEqual(self.species_page("EEVEE"), [everything[:6], everything[6:]])

    def test_forms_list_page(self) -> None:
        self.set_owned(True)
        self.set_groups(KANTO)  # a form carries its own form forward regardless
        self.assertEqual(self.show("FormDexShowData", c=DEX["DEX_FORM_A_VULPIX"]),
                         [[("ANINETALES", "ICE")]])

    def test_reward_preview_uses_the_offer_s_form(self) -> None:
        self.set_owned(True)
        self.set_groups(KANTO)
        h = self.h
        h.write8("wRoguePokemon1", SPECIES["VULPIX"])
        h.write8("wRoguePokemonForm1", 1)
        h.write8("wRewardInfoSlot", 1)
        h.write8("wPokedexNum", SPECIES["VULPIX"])
        try:
            self.assertEqual(self.show("ShowPokedexData"), [[("ANINETALES", "ICE")]])
        finally:
            h.write8("wRewardInfoSlot", 0)

    def test_not_owned_never_reaches_the_page(self) -> None:
        self.set_owned(False)
        self.assertEqual(self.species_page("BULBASAUR"), [])
        self.assertEqual(self.show("FormDexShowData", c=DEX["DEX_FORM_A_VULPIX"]), [])


if __name__ == "__main__":
    unittest.main()
