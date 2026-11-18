"""Expected rental quotes, derived from constants/balance_constants.asm.

A rental costs half the lobby salesman's price for the same ball class
(RentalPriceTable in custom_functions/rental_core.asm). The salesman knobs
are BCD thousands ($18 = Y18,000), and they get retuned, so tests derive
their prices here instead of hardcoding yen amounts that go stale.
"""
from pathlib import Path

from source_constants import parse_rgbds_constants
from test_move_tutor_prices import bcd3

ROOT = Path(__file__).resolve().parents[2]
_BALL_BY_RARITY = {1: "POKEBALL", 2: "GREATBALL", 3: "ULTRABALL"}


def rental_price(rarity: int) -> int:
    """Rental quote in yen for wRentalOfferClass 1..3."""
    constants = parse_rgbds_constants(ROOT / "constants/balance_constants.asm")
    knob = constants[f"SALESMAN_PRICE_{_BALL_BY_RARITY[rarity]}_BCD"]
    thousands = (knob >> 4) * 10 + (knob & 0x0F)
    return thousands * 1000 // 2


def rental_price_bcd(rarity: int) -> list[int]:
    """Rental quote as the 3-byte BCD that hMoney/wPlayerMoney hold."""
    return bcd3(rental_price(rarity))
