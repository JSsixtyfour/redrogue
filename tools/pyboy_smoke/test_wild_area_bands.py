"""Wild-area trainers on banded pools (party roster Phase 3, 2026-10-07).

Jessie & James and Officer Jenny (all five characters are banded since Phase 3b)
run on PARTY_ROSTER.md's banded
pools (stage_event_banded_records, data/trainers/party_specs.asm). Their band 1
lists no Aces, bands 2-4 roll Arbok or Weezing. This drives the real
ReadTrainer on a Wild Area map (StageEventSpecAllowed) and checks:

  tier 1 (band 1, ace-less)  2 mons, neither one an ace species: at levels 5-6
                             no fodder can evolve into Arbok (L22) or Weezing
                             (L35), so an ace species here could only be a
                             leaked ace slot
  tier 3 (band 2)            4 mons, the last is Arbok or Weezing
  tier 9 (band 4)            6 mons, the last is Arbok or Weezing

The ace-less record shape (no last-slot override, BIT_PSPEC_ACE_LAST cleared)
is a build-time property of banded_round_spec; this is the runtime half.

Three ReadTrainer calls per boot, well under the harness's ~10-call limit.
"""

from __future__ import annotations

from source_constants import parse_map_constants, parse_rgbds_constants, parse_trainer_class_indexes
from test_smoke import HarnessTestCase, REPO_ROOT

CLASSES = parse_trainer_class_indexes(REPO_ROOT / "constants/trainer_constants.asm")
MAPS = parse_map_constants(REPO_ROOT / "constants/map_constants.asm")
SPECIES = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
ROUND = parse_rgbds_constants(REPO_ROOT / "constants/round_constants.asm")
BALANCE = parse_rgbds_constants(REPO_ROOT / "constants/balance_constants.asm", ROUND)
ACES = {SPECIES["ARBOK"], SPECIES["WEEZING"]}
JENNY_ACES = {SPECIES["ARCANINE"]}


class WildAreaBandTest(HarnessTestCase):
    def _team(self, tier, cls="JESSIE_JAMES"):
        h = self.harness
        h.write8("hCurMap", MAPS["PROCEDURAL_CAVE_1"])
        h.write8("wTrainerClass", CLASSES[cls])
        h.write8("wTrainerNo", tier)
        h.write8("wEnemyPartySpecies", 0xFF)
        h.call_routine("ReadTrainer", limit=40000)
        count = h.read8("wEnemyPartyCount")
        return list(h.read_bytes("wEnemyPartySpecies", count))

    def test_jessie_james_ace_only_in_ace_bands(self):
        # One boot per test: a second boot_fight2 after call_routine does not
        # reach the debug menu (harness limit, measured 2026-10-07).
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)

        team = self._team(1)
        self.assertEqual(len(team), BALANCE["STAGE_EVENT_R1_MONS"])
        self.assertFalse(ACES & set(team), f"band 1 has no Aces, got {team}")

        for tier in (3, 9):
            team = self._team(tier)
            self.assertEqual(len(team), BALANCE[f"STAGE_EVENT_R{tier}_MONS"])
            self.assertIn(team[-1], ACES, f"tier {tier} last slot is not an ace: {team}")

    def test_officer_jenny_ace_only_in_ace_bands(self):
        # Jenny's only ace is Arcanine. Her fodder holds Growlithe, which evolves
        # by stone at the engine's level-35 floor, so at tier 1 (levels 5-6) an
        # Arcanine could only be a leaked ace slot.
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)

        team = self._team(1, "OFFICER_JENNY")
        self.assertEqual(len(team), BALANCE["STAGE_EVENT_R1_MONS"])
        self.assertFalse(JENNY_ACES & set(team), f"band 1 has no Aces, got {team}")

        for tier in (3, 9):
            team = self._team(tier, "OFFICER_JENNY")
            self.assertEqual(len(team), BALANCE[f"STAGE_EVENT_R{tier}_MONS"])
            self.assertIn(team[-1], JENNY_ACES, f"tier {tier} last slot is not an ace: {team}")
