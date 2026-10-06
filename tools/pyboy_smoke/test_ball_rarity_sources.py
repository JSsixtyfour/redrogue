"""Source guard for rarity-colored overworld Poke Balls (RARITY_COLORED_POKEBALLS_PLAN.md).

Pure Python, no ROM. custom_functions/ball_rarity.asm colors an item ball by
scanning item_rarity.asm's pools, so it must agree with the roller on three things:
- no item sits in two tiers' counted prefixes (else "first tier wins" would
  misreport what the roller can produce);
- BallRarityPools lists all 16 (tier, group) pools and counts in the same
  order as item_*ball_classes (tier-major, HEALING/STAT/TM/MONEY);
- the sprite slots it colors match the slots RandomPickUpItem really pays out.
"""
import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
RARITY = (ROOT / "engine/items/item_rarity.asm").read_text()
BALL = (ROOT / "custom_functions/ball_rarity.asm").read_text()
PICKUP = (ROOT / "engine/events/pick_up_item.asm").read_text()

TIERS = ("pokeball", "greatball", "ultraball", "masterball")
GROUPS = ("healing", "stat", "tm", "money")


def pool_items(label):
    m = re.search(rf"^{label}:\s*\n((?:db [^\n]*(?:\n|$))+)", RARITY, re.M)
    assert m, label
    return [ln.split(";")[0].split()[1] for ln in m.group(1).splitlines()]


def pool_count(group, tier):
    m = re.search(rf"DEF NUM_{group.upper()}_{tier.upper()}_CLASS EQU (\$?\w+)", RARITY)
    assert m, (group, tier)
    v = m.group(1)
    return int(v[1:], 16) if v.startswith("$") else int(v)


def pools_table():
    body = BALL.split("BallRarityPools:")[1]
    return re.findall(r"ball_rarity_pool (\w+), (\w+)", body)


class BallRaritySources(unittest.TestCase):
    def test_no_item_in_two_tiers_counted_prefixes(self):
        seen = {}
        for ti, tier in enumerate(TIERS):
            for group in GROUPS:
                items = pool_items(f"{group}_{tier}_class")[: max(1, pool_count(group, tier))]
                for it in items:
                    self.assertNotIn(it, seen, f"{it} in tier {seen.get(it)} and {ti}")
                    seen[it] = ti

    def test_pool_table_matches_class_arrays_and_defs(self):
        rows = pools_table()
        self.assertEqual(len(rows), 16)
        want = [
            (f"{g}_{t}_class", f"NUM_{g.upper()}_{t.upper()}_CLASS")
            for t in TIERS
            for g in GROUPS
        ]
        self.assertEqual(rows, want)
        for t in TIERS:
            m = re.search(rf"item_{t}_classes::\s*\n((?:dw \w+\s*\n){{4}})", RARITY)
            self.assertIsNotNone(m, t)
            self.assertEqual(re.findall(r"dw (\w+)", m.group(1)),
                             [f"{g}_{t}_class" for g in GROUPS])

    def test_money_pools_hold_one_item_despite_zero_count(self):
        # The roller's index is floor(rand * count / 256) = 0 for count 0 and it
        # still loads the pool's first item, so the table must use length 1.
        for t in TIERS:
            self.assertEqual(pool_count("money", t), 0)
            self.assertEqual(len(pool_items(f"money_{t}_class")), 1)

    def test_slots_match_random_pick_up_item(self):
        self.assertRegex(PICKUP, r"cp 1\s*\n\s*jr nz, \.notCemetery")          # cemetery slot 1
        self.assertRegex(PICKUP, r"sub 2[^\n]*\n\s*bit 7, a")                   # wild slots 2-5
        self.assertRegex(PICKUP, r"cp 4\s*\n\s*jr nc, \.normalRoguePath")
        self.assertRegex(PICKUP, r"IsRogueStageMap\s*\n\s*jr z, \.normalPickup\s*\n"
                                 r"\s*ldh a, \[hSpriteIndex\]\s*\n\s*cp 6")     # item slot 6
        self.assertIn("DEF BALL_RARITY_ITEM_SLOT EQU 6", BALL)


if __name__ == "__main__":
    unittest.main()
