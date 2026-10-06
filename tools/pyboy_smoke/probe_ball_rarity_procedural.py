"""Checkpoint 4 probe: rarity-colored item balls on procedural stages (CGB).

For the cave, forest, cemetery, Facility, Fighting Dojo and Game Corner: enter the map for real, then check
wBallRarityPal against the tier of the item each ball's pickup would hand over
(RandomPickUpItem: cemetery slot 1 -> wRogueItem; wild-area slots 2-5 ->
wRogueItem + 2*(slot-2)). Facility's fake balls (slots 6-9) must stay 0. Then
zero the cache and re-run ProcStageLoadDispatch (what a battle return or
Continue does) and require the identical cache. Cache-level only: the
renderer and palette paths are covered by probe_ball_rarity.py.
"""
import re
import sys
from pathlib import Path

REPO = Path("/mnt/c/Users/justi/redrogue")
sys.path.insert(0, str(REPO / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_rgbds_constants, parse_map_constants  # noqa: E402

ARTIFACTS = REPO / "tools" / "pyboy_smoke" / "artifacts"
SPRITES = parse_rgbds_constants(REPO / "constants" / "sprite_constants.asm")
STD = 7  # untiered balls are the red OBJ palette 7
MAPS = parse_map_constants(REPO / "constants" / "map_constants.asm")
ITEMS = parse_rgbds_constants(REPO / "constants" / "item_constants.asm")
ID_TO_NAME = {v: k for k, v in ITEMS.items() if v < 0xC4}
_const = (REPO / "constants" / "item_constants.asm").read_text()
for _i, _n in enumerate(re.findall(r"^	add_hm (\w+)", _const, re.M)):
    ID_TO_NAME[0xC4 + _i] = "HM_" + _n
for _i, _n in enumerate(re.findall(r"^	add_tm (\w+)", _const, re.M)):
    ID_TO_NAME[0xC9 + _i] = "TM_" + _n
RARITY = (REPO / "engine/items/item_rarity.asm").read_text()
TIERS = ("pokeball", "greatball", "ultraball", "masterball")
GROUPS = ("healing", "stat", "tm", "money")


def pool(label):
    m = re.search(rf"^{label}:\s*\n((?:db [^\n]*(?:\n|$))+)", RARITY, re.M)
    return [ln.split(";")[0].split()[1] for ln in m.group(1).splitlines()]


def item_tier(item_id):
    """Independent re-implementation of BallRarityItemPalette from the source."""
    name = ID_TO_NAME.get(item_id)
    for ti, tier in enumerate(TIERS):
        for group in GROUPS:
            n = re.search(rf"DEF NUM_{group.upper()}_{tier.upper()}_CLASS EQU (\$?\w+)", RARITY).group(1)
            n = max(1, int(n[1:], 16) if n.startswith("$") else int(n))
            if name in pool(f"{group}_{tier}_class")[:n]:
                return ti
    return 0


CASES = [
    ("cave", "PROCEDURAL_CAVE_1", "wild"),
    ("forest", "PROCEDURAL_FOREST", "wild"),
    ("cemetery", "PROCEDURAL_CEMETERY_1", "cem"),
    ("facility", "PROCEDURAL_FACILITY", "wild"),
    ("fighting dojo", "FIGHTING_DOJO", "item6"),  # .normalPickup maps, one item ball at slot 6
    ("game corner", "GAME_CORNER", "item6"),
]


def run(label, map_name, kind):
    failures = []
    h = RedRogueHarness(REPO, ARTIFACTS, cgb_mode=True)
    try:
        h.boot_to_lobby()
        if kind == "item6":
            h.enter_stage_door1(MAPS[map_name], description=label)
        else:
            h.preload_and_enter_wild_area(MAPS[map_name], label)
        items = h.read_bytes("wRogueItem", 8)[::2]
        cache = h.read_bytes("wBallRarityPal", 16)
        pics = h.read_bytes("wSpriteStateData1", 256)[::16]
        want = [STD if p == SPRITES["SPRITE_POKE_BALL"] else 0 for p in pics]

        def slot(n, tier):  # untiered ball slots keep the standard red
            if want[n]:
                want[n] = tier or STD

        if kind == "cem":
            slot(1, item_tier(items[0]))
        elif kind == "item6":
            slot(6, item_tier(items[0]))
        else:
            for i in range(4):
                slot(2 + i, item_tier(items[i]))
        names = [ID_TO_NAME.get(i, hex(i)) for i in items]
        print(f"[{label}] items={names} cache={cache} want={want}")
        if cache != want:
            failures.append(f"{label}: cache {cache} != {want}")
        # Reload (battle return / Continue): rebuild from scratch, same answer.
        for i in range(16):
            h.write8("wBallRarityPal", 0, offset=i)
        h.call_routine("ProcStageLoadDispatch", limit=400000)
        again = h.read_bytes("wBallRarityPal", 16)
        print(f"[{label}] after reload cache={again}")
        if again != want:
            failures.append(f"{label}: reload cache {again} != {want}")
    finally:
        h.close()
    return failures


all_failures = []
for case in CASES:
    all_failures += run(*case)
print("FAILURES:" if all_failures else "ALL CHECKS PASSED")
for f in all_failures:
    print("  " + f)
