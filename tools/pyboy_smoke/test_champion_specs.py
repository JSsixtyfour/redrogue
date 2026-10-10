"""Champion Lance and Prof. Oak on party specs (party roster Phase 5, 2026-10-07).

Drives the real ReadTrainer with the numbers ChampionsRoom.asm hands out:

  LANCE     wTrainerNo LANCE_CHAMPION_TEAM, the record after the Elite Four
            Lance's twelve: six mons at the Champion curve, the last from
            ChampionLance's Ace pool (not the E4 tier-4 team he used to field)
  PROF_OAK  wTrainerNo 1-3, one record: six mons at the Champion curve, the
            last from ProfOak's Ace pool

The Champion rival's record is held by test_trainer_revamp_specs.py and
test_party_spec_coverage.py. One boot_fight2, three ReadTrainer calls.
"""

from __future__ import annotations

import sys

from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_smoke import HarnessTestCase, REPO_ROOT

sys.path.insert(0, str(REPO_ROOT / "tools" / "balance"))
import parse  # noqa: E402

MON_LEVEL = 0x21
PARTYMON_STRUCT_LENGTH = 0x2C
BALANCE = parse_rgbds_constants(REPO_ROOT / "constants/balance_constants.asm")
SPEC = parse_rgbds_constants(REPO_ROOT / "constants/party_spec_constants.asm")
SPECIES = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
CLASSES = parse_trainer_class_indexes(REPO_ROOT / "constants/trainer_constants.asm")
POOLS = parse.load_pools()


def aces(prefix: str) -> set[int]:
    runs = POOLS[f"POOL_BAND_{prefix}_Ace1"]
    return {SPECIES[s] for run in runs.values() for s in run}


def champion_levels() -> list[int]:
    base, step = BALANCE["CHAMPION_BASE_LEVEL"], BALANCE["CHAMPION_LEVEL_STEP"]
    return [base + slot * step for slot in range(6)]


class ChampionSpecTest(HarnessTestCase):
    def _build(self, cls: str, trainer_no: int):
        h = self.harness
        h.write8("wTrainerClass", CLASSES[cls])
        h.write8("wTrainerNo", trainer_no)
        h.call_routine("ReadTrainer", limit=60000)
        count = h.read8("wEnemyPartyCount")
        party = list(h.read_bytes("wEnemyPartySpecies", count))
        levels = [h.read8("wEnemyMons", offset=i * PARTYMON_STRUCT_LENGTH + MON_LEVEL)
                  for i in range(count)]
        return party, levels

    def test_champion_lance_and_oak_build_their_own_records(self):
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        h.set_difficulty("HARD")  # expected levels are the 0% knobs
        cases = [("LANCE", SPEC["LANCE_CHAMPION_TEAM"], "ChampionLance")]
        cases += [("PROF_OAK", n, "ProfOak") for n in (1, 3)]
        for cls, number, prefix in cases:
            with self.subTest(trainer=cls, trainer_no=number):
                party, levels = self._build(cls, number)
                self.assertEqual(levels, champion_levels())
                self.assertIn(party[-1], aces(prefix), f"{cls} last slot is not an ace: {party}")
