"""Stage-event classes use their specs only on a Wild Area map (2026-10-06).

JESSIE_JAMES, PSYCHIC_TR, BURGLAR, NURSE_JOY and OFFICER_JENNY carry
9-entry spec lists indexed by ROUND: StageEventApplyTrainers writes the round
into wTrainerNo. PSYCHIC_TR and BURGLAR are also vanilla map trainers with a
FIXED set number (Saffron Gym's Psychics are set 1, the Mansion 2F/3F/B1F
Burglars 7/8/9), and PartyGenFindSpec used to look only at (class, set). So a
Saffron Gym Psychic always fielded the round-1 ambush team, two mons at
Lv5-6, whatever round the run was in. Reported by two players as "3 trainers
with a level 6 Psyduck" in Sabrina's gym as the 4th gym.

StageEventSpecAllowed now declines the spec off a Wild Area map, so those
trainers roll a GetRandRoster team at the run's own level again.

StageEventDisarmOnOtherStage covers the matching state leak: wStageEvent is
armed at lobby selection, and stayed armed through a stage reached by the
OTHER door until the next selection.

At most four call_routine invocations per boot (harness limit is about ten).
"""

from __future__ import annotations

from source_constants import (
    parse_map_constants,
    parse_rgbds_constants,
    parse_trainer_class_indexes,
)
from test_smoke import HarnessTestCase, REPO_ROOT

CLASSES = parse_trainer_class_indexes(REPO_ROOT / "constants/trainer_constants.asm")
MAPS = parse_map_constants(REPO_ROOT / "constants/map_constants.asm")
ROUND = parse_rgbds_constants(REPO_ROOT / "constants/round_constants.asm")
BALANCE = parse_rgbds_constants(REPO_ROOT / "constants/balance_constants.asm", ROUND)
RAM = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")

# Round 4 (0-based round index 3), first gym trainer: Sabrina as the 4th gym.
ROUND4_GYM_TRAINER = 3 * ROUND["ROUND_BATTLES"] + ROUND["FIRST_GYM_STEP"]


class StageEventClassMapGateTest(HarnessTestCase):
    def _read_trainer(self, cls, trainer_no, map_name, battle_count):
        h = self.harness
        h.write8("wBattleCount", battle_count)
        h.write8("hCurMap", MAPS[map_name])
        h.write8("wTrainerClass", CLASSES[cls])
        h.write8("wTrainerNo", trainer_no)
        h.call_routine("ReadTrainer", limit=40000)
        count = h.read8("wEnemyPartyCount")
        stride = h.address("wEnemyMon2Level") - h.address("wEnemyMon1Level")
        return [h.read8("wEnemyMon1Level", i * stride) for i in range(count)]

    def test_vanilla_map_trainers_do_not_use_round_specs(self):
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        r1_top = BALANCE["STAGE_EVENT_R1_BASE"] + BALANCE["STAGE_EVENT_R1_MONS"] - 1
        r7_base = BALANCE["STAGE_EVENT_R7_BASE"]

        # The report: Saffron Gym Psychic, set 1, round 4. Before the fix this
        # was the round-1 spec, levels 5 and 6.
        levels = self._read_trainer("PSYCHIC_TR", 1, "SAFFRON_GYM", ROUND4_GYM_TRAINER)
        print("Saffron Gym Psychic, round 4:", levels)
        self.assertTrue(levels)
        self.assertGreater(min(levels), r1_top,
                           "a Saffron Gym Psychic got the round-1 ambush team")

        # The opposite direction: a Mansion 2F Burglar is set 7, which was the
        # round-7 spec (Lv39+) even in round 4.
        levels = self._read_trainer("BURGLAR", 7, "POKEMON_MANSION_2F", ROUND4_GYM_TRAINER)
        print("Mansion 2F Burglar, round 4:", levels)
        self.assertTrue(levels)
        self.assertLess(max(levels), r7_base,
                        "a Mansion Burglar got the round-7 ambush team in round 4")

        # Control: on a Wild Area map the same class and set still take the
        # spec, so the gate is not simply switching specs off.
        levels = self._read_trainer("PSYCHIC_TR", 1, "PROCEDURAL_CAVE_1", ROUND4_GYM_TRAINER)
        print("Wild Area Psychic, spec 1:", levels)
        self.assertEqual(
            levels,
            [BALANCE["STAGE_EVENT_R1_BASE"] + i * BALANCE["STAGE_EVENT_R1_STEP"]
             for i in range(BALANCE["STAGE_EVENT_R1_MONS"])],
        )

    def test_event_disarms_only_on_the_other_doors_stage(self):
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        armed = RAM["STAGE_EVENT_PSYCHIC"]
        h.write8("wLobbyDoor1StageMap", MAPS["PROCEDURAL_CAVE_1"])
        h.write8("wLobbyDoor2StageMap", MAPS["ROUTE_6"])

        def load(map_name):
            h.write8("wStageEvent", armed)
            h.write8("hCurMap", MAPS[map_name])
            h.call_routine("StageEventDisarmOnOtherStage")
            return h.read8("wStageEvent")

        self.assertEqual(load("PROCEDURAL_CAVE_1"), armed, "entered the Wild Area itself")
        self.assertEqual(load("SILPH_CO_DORM"), armed, "a lobby side room, not a door")
        self.assertEqual(load("ROUTE_6"), 0, "took the other door")
