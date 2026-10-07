"""Mini-bosses on banded party specs (party roster Phase 4, 2026-10-07).

The Rival, Giovanni and the Karate Master build from miniboss_records
(data/trainers/party_specs.asm) on PARTY_ROSTER.md's "## Mini-bosses" pools.
This drives the real ReadTrainer and checks, per round:

  size     MINIBOSS_R<n>_MONS
  levels   MINIBOSS_R<n>_BASE + slot * MINIBOSS_R<n>_STEP, exactly
  ace      Giovanni: the last slot is from his band's Ace pool
           Rival: the last slot is his own starter, evolved to the ace's
           level, and no other slot holds that line (NO_RIVAL_STARTER)

The record is chosen by the ROUND (wBattleCount), never by the set number:
a stage hands Giovanni a set of 1-3 and Victory Road hands the rival set 1,
so the set number is deliberately not 1 here.

One boot_fight2 per test method (a second one in the same method does not
reach the debug menu), three ReadTrainer calls each, well under the harness's
~10-call limit.
"""

from __future__ import annotations

import sys

from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_smoke import HarnessTestCase, REPO_ROOT

sys.path.insert(0, str(REPO_ROOT / "tools" / "balance"))
import parse  # noqa: E402

MON_LEVEL = 0x21
PARTYMON_STRUCT_LENGTH = 0x2C
ROUND = parse_rgbds_constants(REPO_ROOT / "constants/round_constants.asm")
BALANCE = parse_rgbds_constants(REPO_ROOT / "constants/balance_constants.asm", ROUND)
SPECIES = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
CLASSES = parse_trainer_class_indexes(REPO_ROOT / "constants/trainer_constants.asm")
POOLS = parse.load_pools()
CHARMANDER_LINE = {SPECIES[s] for s in ("CHARMANDER", "CHARMELEON", "CHARIZARD")}


def band_of(tier: int) -> int:
    return min((tier - 1) // 2 + 1, 4)


def expected_levels(tier: int) -> list[int]:
    n = BALANCE[f"MINIBOSS_R{tier}_MONS"]
    base, step = BALANCE[f"MINIBOSS_R{tier}_BASE"], BALANCE[f"MINIBOSS_R{tier}_STEP"]
    return [base + slot * step for slot in range(n)]


def battle_count(tier: int) -> int:
    """A wBattleCount inside round `tier` (round 9 is the clamp)."""
    return (tier - 1) * ROUND["ROUND_BATTLES"] + 4


class MiniBossBandTest(HarnessTestCase):
    def _build(self, cls: str, tier: int, trainer_no: int):
        h = self.harness
        h.write8("wBattleCount", battle_count(tier))
        h.write8("wTrainerClass", CLASSES[cls])
        h.write8("wTrainerNo", trainer_no)
        h.call_routine("ReadTrainer", limit=60000)
        count = h.read8("wEnemyPartyCount")
        party = list(h.read_bytes("wEnemyPartySpecies", count))
        levels = [h.read8("wEnemyMons", offset=i * PARTYMON_STRUCT_LENGTH + MON_LEVEL)
                  for i in range(count)]
        return party, levels

    def test_giovanni_rolls_his_band_ace_on_the_round_curve(self):
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        for tier in (2, 5, 9):
            with self.subTest(tier=tier):
                party, levels = self._build("GIOVANNI_MINIBOSS", tier, 3)
                self.assertEqual(levels, expected_levels(tier))
                runs = POOLS[f"POOL_BAND_GiovanniMiniBoss_Ace{band_of(tier)}"]
                aces = {SPECIES[s] for run in runs.values() for s in run}
                self.assertIn(party[-1], aces, f"tier {tier} last slot is not an ace: {party}")

    def test_rival_ace_is_his_starter_on_the_round_curve(self):
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        h.write8("wRivalStarter", SPECIES["CHARMANDER"])
        # Tier 2's ace is level 13, below Charmeleon's 16; tier 9's is 58.
        for tier, ace in ((2, "CHARMANDER"), (9, "CHARIZARD")):
            with self.subTest(tier=tier):
                party, levels = self._build("RIVAL_MINIBOSS", tier, 1)
                self.assertEqual(levels, expected_levels(tier))
                self.assertEqual(party[-1], SPECIES[ace], f"the ace must be his starter: {party}")
                for slot, mon in enumerate(party[:-1]):
                    self.assertNotIn(mon, CHARMANDER_LINE, f"slot {slot} doubled up on his starter line")
