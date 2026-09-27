"""Scratch probe: buy an item from lobby Clerk 2 through the real UI.

usage: python3 probe_hm_purchase_ui.py <item_hex> <outdir>
Not part of make smoke.
"""
import sys
from pathlib import Path

from harness import RedRogueHarness
from test_smoke import REPO_ROOT, ARTIFACTS

ITEM = int(sys.argv[1], 16)
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)

h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
h.boot_to_lobby()
shot = [0]


def snap(tag):
    shot[0] += 1
    h.tick(1, render=True)
    h.pyboy.screen.image.save(OUT / f"{shot[0]:02d}_{tag}.png")
    print(f"[{shot[0]:02d} {tag}] xy=({h.read8('wXCoord')},{h.read8('wYCoord')}) "
          f"battle={h.read8('wIsInBattle' if False else 'wBattleType')} bank={h.read8('hLoadedROMBank'):02x} "
          f"pc={h.pyboy.register_file.PC:04x} sp={h.pyboy.register_file.SP:04x} "
          f"money={h.read_bytes('wPlayerMoney', 3)} list={[hex(b) for b in h.read_bytes('wItemList', 6)]}")


snap("lobby")
# Walk to (1,7) then face left toward Clerk 2 at (0,7).
for _ in range(20):
    x, y = h.read8("wXCoord"), h.read8("wYCoord")
    if (x, y) == (1, 7):
        break
    if y < 7:
        h.move_tile("down")
    elif y > 7:
        h.move_tile("up")
    elif x > 1:
        h.move_tile("left")
    elif x < 1:
        h.move_tile("right")
    h.tick(8)
snap("at_clerk")
h.move_tile("left")  # face (blocked by the clerk)
h.tick(10)

items = [0xD0, 0xD3, 0xD5, 0xE2, 0xE0, 0xEE, 0xF7, 0xF5, 0xE5, ITEM, 0xFF]
for i, b in enumerate(items):
    h.write8("PCClerkText2Items", b, offset=i)
h.write8("wPlayerMoney", 0x99, 0)
h.write8("wPlayerMoney", 0x99, 1)
h.write8("wPlayerMoney", 0x99, 2)

h.tap("a"); h.tick(90); snap("greeting")
h.tap("a"); h.tick(60); snap("buy_sell_menu")
for _ in range(9):
    h.tap("down"); h.tick(12)
snap("scrolled")
h.tap("a"); h.tick(60); snap("quantity")
h.tap("a"); h.tick(90); snap("confirm_price")
h.tap("a"); h.tick(120); snap("after_yes")
for i in range(8):
    h.tap("a"); h.tick(90); snap(f"after_{i}")
print("TMBitfield", h.read_sram_bytes("sTMBitfield", 7))
h.close()
