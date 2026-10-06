"""Runtime contracts for rank-priced lobby Move Tutor lessons.

The fee lookup is exercised directly in the built Debug ROM so these checks
cover the assembled rank table, tutor fee table, banked copy, and returned
BCD price together. Transaction-flow cases are below and use the tutor's
observable script seams to keep input and LearnMove outcomes deterministic.
"""
from __future__ import annotations

import io
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
MOVES = parse_rgbds_constants(REPO_ROOT / "constants" / "move_constants.asm")
ITEMS = parse_rgbds_constants(REPO_ROOT / "constants" / "item_constants.asm")
LISTS = parse_rgbds_constants(REPO_ROOT / "constants" / "list_constants.asm")

PRICE_CASES = (
    ("POUND", (0x00, 0x10, 0x00), "F"),
    ("KARATE_CHOP", (0x00, 0x20, 0x00), "D"),
    ("GUILLOTINE", (0x00, 0x30, 0x00), "C"),
    ("FIRE_PUNCH", (0x00, 0x50, 0x00), "B"),
    ("SWORDS_DANCE", (0x01, 0x00, 0x00), "A"),
    ("BODY_SLAM", (0x01, 0x50, 0x00), "S"),
    # OFFLIST means excluded from random generation, not from tutoring.
    ("SPLASH", (0x00, 0x10, 0x00), "OFFLIST -> F"),
)


def bcd3(value: int) -> list[int]:
    digits = f"{value:06d}"
    if len(digits) != 6:
        raise ValueError(f"value does not fit three-byte BCD: {value}")
    return [int(digits[index:index + 2], 16) for index in (0, 2, 4)]


def set_word(harness: RedRogueHarness, label: str, value: int) -> None:
    harness.write8(label, value)
    harness.write8(label, value >> 8, offset=1)


def return_from_call(harness: RedRogueHarness) -> None:
    """Mock a directly called routine by popping its real return address."""
    registers = harness.pyboy.register_file
    stack_pointer = registers.SP
    return_address = (
        harness.pyboy.memory[stack_pointer]
        | (harness.pyboy.memory[stack_pointer + 1] << 8)
    )
    registers.SP = (stack_pointer + 2) & 0xFFFF
    registers.PC = return_address


def run_entry(
    harness: RedRogueHarness,
    label: str,
    *,
    registers: dict[str, int] | None = None,
    setup=None,
    hooks: dict[str, object] | None = None,
    capture=None,
    limit: int = 600,
) -> dict[str, object]:
    """Directly run one assembly entry with a synthetic caller and hook seams.

    The ROM is restored after each probe. Direct entry supports routine seams
    whose input registers must reach the first instruction unchanged; hooks
    can mock direct CALLs or a local assembly label while leaving the actual
    transaction code and BCD routines executable.
    """
    harness.park_before_hijack()
    baseline = io.BytesIO()
    harness.save_state(baseline)
    bank, address = harness.symbols.get(label)
    result: dict[str, object] = {"label": label}
    # The synthetic caller returns straight into a `jr @` spin loop in WRAM, so
    # the return is observed without a hook. A hook on a home-bank padding byte
    # (the old 0:$3FFF) only fires in PyBoy 2.7 while ROM bank 1 is mapped, so
    # any routine that returned with another bank switched in ran the $FF
    # padding instead - rst $38, the debug crash screen.
    return_address = 0xC100

    installed: list[tuple[int, int]] = []
    for hook_label, callback in (hooks or {}).items():
        hook_bank, hook_address = harness.symbols.get(hook_label)
        harness.pyboy.hook_register(hook_bank, hook_address, callback, None)
        installed.append((hook_bank, hook_address))
    try:
        cpu = harness.pyboy.register_file
        stack_pointer = (cpu.SP - 2) & 0xFFFF
        harness.pyboy.memory[stack_pointer] = return_address & 0xFF
        harness.pyboy.memory[stack_pointer + 1] = return_address >> 8
        harness.pyboy.memory[0xC100:0xC102] = [0x18, 0xFE]
        cpu.SP = stack_pointer
        if bank:
            harness.pyboy.memory[0x2000] = bank
            harness.write8("hLoadedROMBank", bank)
        for name, value in (registers or {}).items():
            setattr(cpu, name, value)
        if setup is not None:
            setup(harness)
        cpu.PC = address
        harness.wait_until(lambda: cpu.PC == return_address, f"{label} return", limit)
        # The spin loop changes no register or flag, so capturing here sees
        # exactly what the routine returned with.
        if capture is not None:
            result.update(capture(harness))
        result["sp"] = cpu.SP
        result["flags"] = cpu.F
    finally:
        for hook_key in reversed(installed):
            harness.pyboy.hook_deregister(*hook_key)
        harness.load_state(baseline)
    return result


def capture_bcd_and_de(harness: RedRogueHarness) -> dict[str, object]:
    cpu = harness.pyboy.register_file
    return {
        "price": harness.read_bytes("hItemPrice", 3),
        "de": (cpu.D << 8) | cpu.E,
    }


class TutorMovePriceRomTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        cls.harness.boot_fight2(seed=1)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.harness.close()

    def test_rank_fees_and_offlist_fallback(self) -> None:
        h = self.harness
        for move_name, expected_bcd, rank_name in PRICE_CASES:
            with self.subTest(move=move_name, rank=rank_name):
                actual = run_entry(
                    h,
                    "GetTutorMovePrice",
                    registers={"E": MOVES[move_name]},
                    capture=capture_bcd_and_de,
                )
                self.assertEqual(actual["price"], list(expected_bcd))
                self.assertEqual(actual["de"], h.address("hItemPrice"))

    def _list_price(self, menu_id: int, price_flag: int, item_id: int,
                    item_table: int | None = None) -> dict[str, object]:
        h = self.harness

        def setup(harness: RedRogueHarness) -> None:
            set_word(harness, "wItemPrices", item_table or 0)
            harness.write8("wListMenuID", menu_id)
            harness.write8("wPrintItemPrices", price_flag)
            harness.write8("wCurListMenuItem", item_id)
            harness.write8("hItemPrice", 0xAA)
            harness.write8("hItemPrice", 0xBB, offset=1)
            harness.write8("hItemPrice", 0xCC, offset=2)

        return run_entry(
            h,
            "GetListEntryPrice",
            setup=setup,
            capture=capture_bcd_and_de,
        )

    def test_list_price_routing_preserves_clerks_and_credit_exchange(self) -> None:
        h = self.harness
        moves_menu = LISTS["MOVESLISTMENU"]
        unpriced = self._list_price(moves_menu, 0, MOVES["SWORDS_DANCE"])
        self.assertEqual(unpriced["price"], [0xAA, 0xBB, 0xCC])

        priced_move = self._list_price(moves_menu, 1, MOVES["SWORDS_DANCE"])
        self.assertEqual(priced_move["price"], [0x01, 0x00, 0x00])
        self.assertEqual(priced_move["de"], h.address("hItemPrice"))

        item_price = self._list_price(
            LISTS["PRICEDITEMLISTMENU"], 1, ITEMS["POTION"], h.address("ItemPrices")
        )
        self.assertEqual(item_price["price"], [0x00, 0x02, 0x00])

        credit_prices = h.address("CreditItemPrices") - (ITEMS["SHINY_CHARM"] - 1) * 3
        credit_price = self._list_price(
            LISTS["CREDITLISTMENU"], 2, ITEMS["SHINY_CHARM"], credit_prices
        )
        self.assertEqual(credit_price["price"], [0x00, 0x00, 0x30])


class TutorTransactionRomTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        cls.harness.boot_fight2(seed=2)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.harness.close()

    def _try_teach(self, *, confirm_choice: int, learned: int,
                    balance: int, corrupt_scratch: bool = True) -> dict[str, object]:
        h = self.harness
        move_id = MOVES["BODY_SLAM"]
        quote = bcd3(15000)
        observed: dict[str, object] = {"learn_calls": 0, "confirm_quotes": []}

        def print_text(_context) -> None:
            if h.pyboy.register_file.HL == h.address("PCMoveTutorConfirmText"):
                observed["confirm_quotes"].append(h.read_bytes("hMoney", 3))
            return_from_call(h)

        def yes_no(_context) -> None:
            h.write8("hCurrentMenuItem", confirm_choice)
            return_from_call(h)

        def learn_move(_context) -> None:
            observed["learn_calls"] += 1
            observed["learn_predef_bytes"] = list(
                h.pyboy.memory[h.address("PCMoveTutorText.learnMove"):
                               h.address("PCMoveTutorText.learnMove") + 3]
            )
            h.pyboy.register_file.B = learned
            if corrupt_scratch:
                for label in ("hItemPrice", "hMoney", "wPriceTemp"):
                    for offset in range(3):
                        h.write8(label, 0x99, offset=offset)
            # `predef LearnMove` is ld a, id / rst $28, exactly three bytes.
            # The byte pattern assertion below catches a changed macro shape.
            h.pyboy.register_file.PC = h.address("PCMoveTutorText.learnMove") + 3

        def capture(harness: RedRogueHarness) -> dict[str, object]:
            return {
                "money": harness.read_bytes("wPlayerMoney", 3),
                "price_temp": harness.read_bytes("wPriceTemp", 3),
                "item_price": harness.read_bytes("hItemPrice", 3),
                "which_pokemon": harness.read8("hWhichPokemon"),
                "move_num": harness.read8("wMoveNum"),
                "letter_flags": harness.read8("wLetterPrintingDelayFlags"),
                "confirm_quotes": list(observed["confirm_quotes"]),
                "learn_calls": observed["learn_calls"],
                "learn_predef_bytes": observed.get("learn_predef_bytes"),
            }

        def setup(harness: RedRogueHarness) -> None:
            for offset, value in enumerate(quote):
                harness.write8("hItemPrice", value, offset=offset)
            for offset, value in enumerate(bcd3(balance)):
                harness.write8("wPlayerMoney", value, offset=offset)
            harness.write8("wLetterPrintingDelayFlags", 0x5A)

        actual = run_entry(
            h,
            "PCMoveTutorText.tryTeach",
            registers={"D": 3, "E": move_id},
            setup=setup,
            hooks={
                "PrintText": print_text,
                "YesNoChoice": yes_no,
                "PCMoveTutorText.learnMove": learn_move,
            },
            capture=capture,
            limit=1200,
        )
        actual["success"] = bool(int(actual["flags"]) & 0x10)
        return actual

    def test_exact_balance_success_charges_preserved_quote_once(self) -> None:
        actual = self._try_teach(confirm_choice=0, learned=1, balance=15000)
        self.assertEqual(actual["confirm_quotes"], [bcd3(15000)])
        self.assertEqual(actual["learn_calls"], 1)
        self.assertEqual(actual["learn_predef_bytes"][0], 0x3E)
        self.assertEqual(actual["learn_predef_bytes"][2], 0xEF)
        self.assertTrue(actual["success"])
        self.assertEqual(actual["money"], [0, 0, 0])
        self.assertEqual(actual["price_temp"], bcd3(15000))
        self.assertEqual(actual["which_pokemon"], 3)
        self.assertEqual(actual["move_num"], MOVES["BODY_SLAM"])
        self.assertEqual(actual["letter_flags"], 0x5A)

    def test_insufficient_balance_returns_to_list_without_learning_or_charge(self) -> None:
        actual = self._try_teach(confirm_choice=0, learned=1, balance=14999)
        self.assertEqual(actual["confirm_quotes"], [bcd3(15000)])
        self.assertEqual(actual["learn_calls"], 0)
        self.assertFalse(actual["success"])
        self.assertEqual(actual["money"], bcd3(14999))

    def test_declined_quote_returns_without_learning_or_charge(self) -> None:
        actual = self._try_teach(confirm_choice=1, learned=1, balance=15000)
        self.assertEqual(actual["confirm_quotes"], [bcd3(15000)])
        self.assertEqual(actual["learn_calls"], 0)
        self.assertFalse(actual["success"])
        self.assertEqual(actual["money"], bcd3(15000))

    def test_abandoned_move_replacement_does_not_charge(self) -> None:
        actual = self._try_teach(confirm_choice=0, learned=0, balance=15000)
        self.assertEqual(actual["confirm_quotes"], [bcd3(15000)])
        self.assertEqual(actual["learn_calls"], 1)
        self.assertFalse(actual["success"])
        self.assertEqual(actual["money"], bcd3(15000))

    def test_wrapper_restores_price_flag_and_text_cursor(self) -> None:
        h = self.harness
        initial_bc = 0x1234

        def fake_teach(_context) -> None:
            h.write8("wPrintItemPrices", 1)
            h.pyboy.register_file.B = 0xAA
            h.pyboy.register_file.C = 0xBB
            return_from_call(h)

        def setup(harness: RedRogueHarness) -> None:
            harness.write8("wPrintItemPrices", 2)

        def capture(harness: RedRogueHarness) -> dict[str, object]:
            cpu = harness.pyboy.register_file
            return {
                "price_flag": harness.read8("wPrintItemPrices"),
                "bc": (cpu.B << 8) | cpu.C,
            }

        # PCMoveTutorText points at TX_START_ASM; execute the following byte as
        # the text engine does, then let the real finish/TextScriptEnd unwind.
        h.park_before_hijack()
        baseline = io.BytesIO()
        h.save_state(baseline)
        bank, entry = h.symbols.get("PCMoveTutorText")
        h.pyboy.memory[0x2000] = bank
        h.write8("hLoadedROMBank", bank)
        if h.pyboy.memory[entry] != 0x08:
            self.fail("PCMoveTutorText no longer starts with TX_START_ASM")
        h.load_state(baseline)
        # Use the generic entry runner from one byte past TX_START_ASM by
        # temporarily selecting that direct address in a local equivalent.
        result = self._run_wrapper_from_asm(entry + 1, bank, initial_bc, setup, fake_teach, capture)
        self.assertEqual(result["price_flag"], 2)
        self.assertEqual(result["bc"], initial_bc)

    def _run_wrapper_from_asm(self, address: int, bank: int, initial_bc: int,
                              setup, fake_teach, capture) -> dict[str, object]:
        h = self.harness
        h.park_before_hijack()
        baseline = io.BytesIO()
        h.save_state(baseline)
        result: dict[str, object] = {}
        ret_addr = 0xC100  # WRAM spin loop; see run_entry for why not 0:$3FFF

        bank_teach, address_teach = h.symbols.get("PCMoveTutorText.teach")
        h.pyboy.hook_register(bank_teach, address_teach, fake_teach, None)
        try:
            cpu = h.pyboy.register_file
            stack_pointer = (cpu.SP - 2) & 0xFFFF
            h.pyboy.memory[stack_pointer] = ret_addr & 0xFF
            h.pyboy.memory[stack_pointer + 1] = ret_addr >> 8
            h.pyboy.memory[0xC100:0xC102] = [0x18, 0xFE]
            cpu.SP = stack_pointer
            h.pyboy.memory[0x2000] = bank
            h.write8("hLoadedROMBank", bank)
            cpu.B = initial_bc >> 8
            cpu.C = initial_bc & 0xFF
            setup(h)
            cpu.PC = address
            h.wait_until(lambda: cpu.PC == ret_addr, "PCMoveTutorText wrapper return", 500)
            result.update(capture(h))
            result["sp"] = cpu.SP
        finally:
            h.pyboy.hook_deregister(bank_teach, address_teach)
            h.load_state(baseline)
        return result


if __name__ == "__main__":
    unittest.main(verbosity=2)
