"""Exercise the earned shop discount through the actual BCD ROM routine."""
from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

RAM = parse_rgbds_constants(REPO_ROOT / 'constants/ram_constants.asm')


class WitchShopDiscountTest(HarnessTestCase):
    def test_purchase_totals(self):
        h = self.harness
        h.boot_to_lobby()
        h.tick(180)
        h.park_before_hijack()
        mask = 1 << (RAM['PRIZE_CHEAP_ITEMS'] - 9)
        for earned in (False, True):
            h.write8('wWitchPrizesEarned', mask if earned else 0, offset=1)
            for total in (0, 1, 9, 10, 11, 250, 1500, 148500, 999999):
                with self.subTest(earned=earned, total=total):
                    digits = f'{total:06d}'
                    for i in range(3):
                        h.write8('hMoney', int(digits[2*i:2*i+2], 16), offset=i)
                    h.call_routine('RogueWitchDiscountBuyPrice')
                    actual = int(''.join(f'{v:02x}' for v in h.read_bytes('hMoney', 3)))
                    self.assertEqual(actual, total - total // 10 if earned else total)
