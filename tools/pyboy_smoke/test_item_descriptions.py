"""Item names and descriptions in the bag / mart (item expansion, 2026-10-08).

TM/HM names carry their move: GetMachineName (home/names.asm) appends " " and
an abbreviation from TMHMDisplayNames (data/items/tmhm_names.asm), so the bag
reads "TM44 REST".

Descriptions: PrintBagInfoText (custom_functions/tm_bag.asm) farcalls
PrintItemDescription (custom_functions/item_descriptions.asm) on every cursor
move. Bag: pocket label on row 14, description on rows 15-16 at column 5.
Mart clerk: rows 14 and 16 at column 1. TMs/HMs show type, PP, power and
accuracy read from the move data.
"""

from pathlib import Path
import re
import unittest

from harness import RedRogueHarness


REPO_ROOT = Path(__file__).resolve().parents[2]
NUM_HMS = 5
NUM_TMS = 50
ITEM_NAME_LENGTH = 13  # including the '@'
SCREEN_WIDTH = 20

POTION = 0x14
POCKET_RECOVERY = 0
POCKET_TM_PACK = 2
BIT_PRINT_INFO_BOX = 3
PRICEDITEMLISTMENU = 3
ITEMLISTMENU = 4
BIT_NO_MENU_BUTTON_SOUND = 5

# The subset of constants/charmap.asm these screens use.
CHARS = {0x50: "@", 0x7F: " ", 0xE3: "-", 0xE9: "%", 0xBA: "e'", 0xEA: "<", 0xED: ">"}
CHARS.update({0x80 + i: chr(ord("A") + i) for i in range(26)})
CHARS.update({0xA0 + i: chr(ord("a") + i) for i in range(26)})
CHARS.update({0xF6 + i: chr(ord("0") + i) for i in range(10)})


def decode(raw) -> str:
    out = []
    for byte in raw:
        if byte == 0x50:
            return "".join(out)
        out.append(CHARS.get(byte, f"<{byte:02X}>"))
    return "".join(out) + "<unterminated>"


def decode_tiles(raw) -> str:
    return "".join(CHARS.get(byte, f"<{byte:02X}>") for byte in raw)


def machine_moves() -> list[str]:
    """Move constants of HM01-HM05 then TM01-TM50, from the add_hm/add_tm lists."""
    constants = (REPO_ROOT / "constants" / "item_constants.asm").read_text()
    hms = re.findall(r"^\s*add_hm\s+(\w+)", constants, re.MULTILINE)
    tms = re.findall(r"^\s*add_tm\s+(\w+)", constants, re.MULTILINE)
    assert len(hms) == NUM_HMS and len(tms) == NUM_TMS
    return hms + tms


def move_data() -> dict[str, tuple[int, str, int, int]]:
    """move -> (power, type name, displayed accuracy %, pp) from data/moves/moves.asm."""
    source = (REPO_ROOT / "data" / "moves" / "moves.asm").read_text()
    rows = {}
    for move, power, mtype, acc, pp in re.findall(
        r"^\s*move\s+(\w+),\s*\w+,\s*(\d+),\s*(\w+),\s*(\d+),\s*(\d+)", source, re.MULTILINE
    ):
        acc_byte = int(acc) * 0xFF // 100  # the `percent` macro
        shown = (acc_byte * 100 + 255) >> 8  # PrintItemDescription's conversion
        rows[move] = (int(power), mtype.removesuffix("_TYPE"), shown, int(pp))
    return rows


def expected_tm_lines(move: str) -> tuple[str, str]:
    power, type_name, accuracy, pp = move_data()[move]
    line1 = f"{type_name:<10}PP{pp:>2}"
    power_text = f"{power:>3}" if power >= 2 else "  -"
    line2 = f"PWR{power_text} ACC{accuracy:>3}%"
    return line1, line2


def expected_machine_names() -> list[str]:
    source = (REPO_ROOT / "data" / "items" / "tmhm_names.asm").read_text()
    parts = re.findall(r'^\s*tmhm_name\s+\w+,\s*"([^"]*)"', source, re.MULTILINE)
    assert len(parts) == NUM_HMS + NUM_TMS, len(parts)
    prefixes = [f"HM{n:02d}" for n in range(1, NUM_HMS + 1)]
    prefixes += [f"TM{n:02d}" for n in range(1, NUM_TMS + 1)]
    return [f"{prefix} {part}" for prefix, part in zip(prefixes, parts)]


def machine_item_id() -> int:
    constants = (REPO_ROOT / "constants" / "item_constants.asm").read_text()
    match = re.search(r"add_hm CUT\s*; \$([0-9A-F]{2})", constants)
    assert match is not None
    return int(match.group(1), 16)


class ItemDescriptionRuntimeBase(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(REPO_ROOT, Path(__file__).parent / "artifacts")
        self.h.boot_to_lobby()

    def tearDown(self) -> None:
        self.h.close()

    def run_routine(self, label: str) -> None:
        """Run a routine to its ret with no Bankswitch frame of our own.

        call_routine enters through Bankswitch and recognises the return by
        nesting depth, and a HOME target returns into ROM padding there (see
        the call_routine memory). Here the return address is a `jr @` stub in
        scratch WRAM, IE is masked, and a ROMX target's bank is mapped by hand.
        """
        h = self.h
        regs = h.pyboy.register_file
        memory = h.pyboy.memory
        saved = {name: getattr(regs, name) for name in ("A", "B", "C", "D", "E", "F", "HL", "PC", "SP")}
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
        regs.PC = address
        try:
            for _ in range(10):
                h.pyboy.tick()
                if regs.PC == stub:
                    break
            self.assertEqual(regs.PC, stub, f"{label} did not return (PC ${regs.PC:04X})")
            self.assertEqual(regs.SP, (sp + 2) & 0xFFFF, f"{label} unbalanced the stack")
        finally:
            memory[0xFFFF] = saved_ie
            memory[stub], memory[stub + 1] = saved_stub
            h.write8("hLoadedROMBank", saved_bank)
            memory[0x2000] = saved_bank
            for name, value in saved.items():
                setattr(regs, name, value)

    def tile_row(self, x: int, y: int, width: int) -> str:
        base = self.h.address("wTileMap") + y * SCREEN_WIDTH + x
        return decode_tiles(self.h.pyboy.memory[base:base + width]).rstrip()

    def fill_screen(self, tile: int = 0x96) -> None:
        """Pre-fill rows 13-17 with junk ('W') so a missed clear is visible."""
        base = self.h.address("wTileMap") + 13 * SCREEN_WIDTH
        self.h.pyboy.memory[base:base + 5 * SCREEN_WIDTH] = [tile] * (5 * SCREEN_WIDTH)

    def set_list(self, items: list[int], *, two_byte: bool, cursor: int) -> None:
        """A list menu over `items` in wItemList (count, entries, $FF)."""
        h = self.h
        data = [len(items)]
        for item in items:
            data += [item, 1] if two_byte else [item]
        data.append(0xFF)
        base = h.address("wItemList")
        h.pyboy.memory[base:base + len(data)] = data
        h.write8("wListPointer", base & 0xFF)
        h.write8("wListPointer", base >> 8, offset=1)
        h.write8("wListScrollOffset", 0)
        h.write8("hCurrentMenuItem", cursor)

    def open_bag(self, pocket: int, items: list[int], cursor: int) -> None:
        h = self.h
        h.write8("wBagPocketsFlags", (1 << BIT_PRINT_INFO_BOX) | pocket)
        h.write8("wListMenuID", ITEMLISTMENU)
        self.set_list(items, two_byte=True, cursor=cursor)
        self.fill_screen()

    def open_mart(self, items: list[int], cursor: int, *, in_pc: bool = False) -> None:
        h = self.h
        h.write8("wBagPocketsFlags", 0)
        h.write8("wMenuWatchMovingOutOfBounds", 1)
        h.write8("wListMenuID", PRICEDITEMLISTMENU)
        flags = h.read8("wMiscFlags") & ~(1 << BIT_NO_MENU_BUTTON_SOUND)
        if in_pc:
            flags |= 1 << BIT_NO_MENU_BUTTON_SOUND
        h.write8("wMiscFlags", flags)
        self.set_list(items, two_byte=False, cursor=cursor)
        self.fill_screen()


class MachineNameRuntimeTest(ItemDescriptionRuntimeBase):
    def test_every_machine_name_carries_its_move(self) -> None:
        h = self.h
        first = machine_item_id()
        bank_before = h.read8("hLoadedROMBank")
        for index, expected in enumerate(expected_machine_names()):
            with self.subTest(expected=expected):
                h.write8("wNamedObjectIndex", first + index)
                self.run_routine("GetItemName")
                buffer = h.address("wNameBuffer")
                raw = [h.pyboy.memory[buffer + i] for i in range(ITEM_NAME_LENGTH)]
                self.assertEqual(decode(raw), expected)
                self.assertLessEqual(len(expected), ITEM_NAME_LENGTH - 1)
                # the item id is restored for the caller, and the bank too
                self.assertEqual(h.read8("wNamedObjectIndex"), first + index)
                self.assertEqual(h.read8("hLoadedROMBank"), bank_before)

    def test_ordinary_item_names_unchanged(self) -> None:
        h = self.h
        h.write8("wNamedObjectIndex", POTION)
        self.run_routine("GetItemName")
        buffer = h.address("wNameBuffer")
        raw = [h.pyboy.memory[buffer + i] for i in range(ITEM_NAME_LENGTH)]
        self.assertEqual(decode(raw), "POTION")


class BagDescriptionRuntimeTest(ItemDescriptionRuntimeBase):
    def test_item_description_under_the_pocket_label(self) -> None:
        self.open_bag(POCKET_RECOVERY, [POTION], cursor=0)
        self.run_routine("PrintBagInfoText")
        self.assertEqual(self.tile_row(5, 14, 14), "< RECOVERY   >")
        self.assertEqual(self.tile_row(5, 15, 14), "Restores 20 HP")
        self.assertEqual(self.tile_row(5, 16, 14), "to one POKe'MON")

    def test_cancel_row_shows_the_label_alone(self) -> None:
        self.open_bag(POCKET_RECOVERY, [POTION], cursor=1)
        self.run_routine("PrintBagInfoText")
        self.assertEqual(self.tile_row(5, 14, 14), "< RECOVERY   >")
        self.assertEqual(self.tile_row(5, 15, 14), "")
        self.assertEqual(self.tile_row(5, 16, 14), "")

    def test_every_machine_shows_its_move_data(self) -> None:
        first = machine_item_id()
        for index, move in enumerate(machine_moves()):
            with self.subTest(move=move):
                self.open_bag(POCKET_TM_PACK, [first + index], cursor=0)
                self.run_routine("PrintBagInfoText")
                line1, line2 = expected_tm_lines(move)
                self.assertEqual(self.tile_row(5, 14, 14), "< TM PACK    >")
                self.assertEqual(self.tile_row(5, 15, 14), line1)
                self.assertEqual(self.tile_row(5, 16, 14), line2)
                # nothing spills past the box's right border at column 19
                self.assertEqual(self.tile_row(19, 15, 1), "W")
                self.assertEqual(self.tile_row(19, 16, 1), "W")


class MartDescriptionRuntimeTest(ItemDescriptionRuntimeBase):
    def test_clerk_box_describes_the_item(self) -> None:
        self.open_mart([POTION], cursor=0)
        self.run_routine("PrintBagInfoText")
        self.assertEqual(self.tile_row(1, 14, 18), "Restores 20 HP")
        self.assertEqual(self.tile_row(1, 15, 18), "")
        self.assertEqual(self.tile_row(1, 16, 18), "to one POKe'MON")

    def test_clerk_box_describes_a_tm(self) -> None:
        first = machine_item_id()
        thunderbolt = first + machine_moves().index("THUNDERBOLT")
        self.open_mart([thunderbolt], cursor=0)
        self.run_routine("PrintBagInfoText")
        line1, line2 = expected_tm_lines("THUNDERBOLT")
        self.assertEqual(self.tile_row(1, 14, 18), line1)
        self.assertEqual(self.tile_row(1, 16, 18), line2)

    def test_players_pc_list_keeps_its_plain_box(self) -> None:
        h = self.h
        saved = h.address("wTextBoxBuffer")
        h.pyboy.memory[saved:saved + 36] = [0x7F] * 36
        self.open_mart([POTION], cursor=0, in_pc=True)
        self.run_routine("PrintBagInfoText")
        self.assertEqual(self.tile_row(1, 14, 18), "")
        self.assertEqual(self.tile_row(1, 16, 18), "")


if __name__ == "__main__":
    unittest.main()
