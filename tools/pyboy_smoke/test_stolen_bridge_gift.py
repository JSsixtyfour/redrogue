"""A stolen mon keeps its Bridge selected effect: on the villain's team, back in the
party, back in the box, and the record does not outlive a mon that never comes back.

Selected effects live in a sparse owner registry, not on the mon, so a theft has to move
the record the way daycare does. All eight effects go through the one registry, so all
eight are checked, including the five that change no stat and would otherwise lose it
without a visible trace.

Each trial runs the real routines: BridgeGrantSelectedEffect, StageEventStealMon,
StageEventInjectStolenMon, StageEventGiveBack and _MoveMon. The victim is forced to the
middle slot by marking its neighbours fused (the theft skips fused mons), because the
middle slot is the case where compaction also moves a surviving owner.
"""
from __future__ import annotations

import io
import json
import re
import sys
import unittest
from pathlib import Path

from harness import RedRogueHarness

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"

EFFECTS = ("CRITICAL_RATE", "SHRINK_RAY", "GROWTH_RAY", "FLINCH", "BODY_ARMOR",
           "POISON_IMMUNITY", "LIFE_ORB", "STATUS_IMMUNITY")
RAYS = ("SHRINK_RAY", "GROWTH_RAY", "BODY_ARMOR")
PARTY_LENGTH = 6
NUM_BOXES = 12
MONS_PER_BOX = 20
BOX_BASE = 1 + PARTY_LENGTH
DAYCARE2 = BOX_BASE + NUM_BOXES * MONS_PER_BOX + 1
STOLEN = DAYCARE2 + 1
MON = 44
BOX_MON = 33
CATCH_RATE = 7
FUSION_BIT = 1
HP, LEVEL, MAX_HP = 1, 33, 34
PSYCHIC_TR = 0x13
STAGE_EVENT_PSYCHIC = 2
BOX_TO_PARTY = 0


def stats(memory, base):
    """(HP, max HP, attack, defense, speed, special) of a party-layout struct."""
    words = [memory[base + MAX_HP + i] << 8 | memory[base + MAX_HP + i + 1] for i in range(0, 10, 2)]
    return [memory[base + HP] << 8 | memory[base + HP + 1], *words]


class Trial:
    """One booted party of three identical mons with a gift on the middle one."""

    def __init__(self, h, baseline, effect):
        self.h = h
        self.effect = effect
        h.load_state(baseline)
        memory = h.pyboy.memory
        first = h.address("wPartyMons")
        struct = list(memory[first:first + MON])
        h.write8("wPartyCount", 3)
        species = h.address("wPartySpecies")
        for slot in range(3):
            memory[first + slot * MON:first + (slot + 1) * MON] = struct
            memory[species + slot] = struct[0]
        memory[species + 3] = 0xFF
        h.pyboy.memory[h.address("wBridgeSelectedEffects"):h.address("wBridgeSelectedEffects") + 4] = [0, 0, 0, 0]
        # The survivor's gift has to differ from the victim's only so a mix-up would show.
        self.other = 4 if effect != 4 else 1
        self.grant(2, self.other)
        self.grant(1, effect)
        self.gifted = stats(memory, first + MON)

    def grant(self, slot, effect):
        h = self.h
        h.write8("hWhichPokemon", slot)
        h.pyboy.register_file.E = effect
        h.call_routine("BridgeGrantSelectedEffect")

    def records(self):
        return self.h.read_bytes("wBridgeSelectedEffects", 4)

    def owner_of(self, effect):
        records = self.records()
        for index in (0, 2):
            if records[index + 1] == effect:
                return records[index]
        return 0

    def steal_middle(self):
        h = self.h
        memory = h.pyboy.memory
        first = h.address("wPartyMons")
        for slot in (0, 2):
            memory[first + slot * MON + CATCH_RATE] |= 1 << FUSION_BIT
        h.call_routine("StageEventStealMon")
        for slot in (0, 1):
            memory[first + slot * MON + CATCH_RATE] &= ~(1 << FUSION_BIT) & 0xFF

    def fill_party(self):
        """The player found more mons before recovering: the party is full again."""
        h = self.h
        memory = h.pyboy.memory
        first = h.address("wPartyMons")
        species = h.address("wPartySpecies")
        struct = list(memory[first:first + MON])
        for slot in range(h.read8("wPartyCount"), PARTY_LENGTH):
            memory[first + slot * MON:first + (slot + 1) * MON] = struct
            memory[species + slot] = struct[0]
        memory[species + PARTY_LENGTH] = 0xFF
        h.write8("wPartyCount", PARTY_LENGTH)

    def inject_villain(self):
        """Run the real injection the Psychic's ReadTrainer uses, and read its copy."""
        h = self.h
        memory = h.pyboy.memory
        h.write8("wStageEvent", STAGE_EVENT_PSYCHIC)
        h.write8("wTrainerClass", PSYCHIC_TR)
        was_map = h.read8("hCurMap")
        h.write8("hCurMap", self.cave_map())
        h.write8("wEnemyPartyCount", 1)
        h.call_routine("StageEventInjectStolenMon")
        h.write8("hCurMap", was_map)
        return stats(memory, h.address("wEnemyMons"))

    @staticmethod
    def cave_map():
        from source_constants import parse_map_constants
        return parse_map_constants(ROOT / "constants/map_constants.asm")["PROCEDURAL_CAVE_1"]


def measure(effect_names=EFFECTS):
    h = RedRogueHarness(ROOT, ARTIFACTS)
    rows = []
    try:
        h.boot_to_lobby()
        h.write8("wBoxCount", 0)
        h.pyboy.memory[h.address("wBoxSpecies")] = 0xFF
        baseline = io.BytesIO()
        h.save_state(baseline)
        for index, name in enumerate(effect_names):
            effect = EFFECTS.index(name) + 1
            row = {"effect": name, "id": effect}

            # Party return, with the villain's copy measured on the way.
            row["plain"] = plain_stats(h, baseline)
            trial = Trial(h, baseline, effect)
            row["gifted"] = trial.gifted
            trial.steal_middle()
            row["after_theft_owner"] = trial.owner_of(effect)
            row["survivor_owner_after_theft"] = trial.owner_of(trial.other)
            row["villain"] = trial.inject_villain()
            h.call_routine("StageEventGiveBack")
            row["party_owner"] = trial.owner_of(effect)
            row["party_count"] = h.read8("wPartyCount")
            row["party_stats"] = stats(h.pyboy.memory, h.address("wPartyMons") + (row["party_count"] - 1) * MON)

            # Box return, then withdrawn through the real _MoveMon.
            trial = Trial(h, baseline, effect)
            trial.steal_middle()
            trial.fill_party()
            h.call_routine("StageEventGiveBack")
            row["box_count"] = h.read8("wBoxCount")
            row["box_owner"] = trial.owner_of(effect)
            h.write8("wPartyCount", 2)
            h.pyboy.memory[h.address("wPartySpecies") + 2] = 0xFF
            h.write8("hWhichPokemon", 0)
            h.write8("wMoveMonType", BOX_TO_PARTY)
            h.call_routine("_MoveMon")
            row["withdrawn_owner"] = trial.owner_of(effect)
            row["withdrawn_stats"] = stats(h.pyboy.memory, h.address("wPartyMons") + 2 * MON)

            # Never recovered: the lobby-time clear ends it.
            trial = Trial(h, baseline, effect)
            trial.steal_middle()
            h.call_routine("StageEventClearStolenRecord")
            row["abandoned_records"] = trial.records()
            rows.append(row)
    finally:
        h.close()
    return rows


def plain_stats(h, baseline):
    """The same mon with no gift, as the control for what a gift changes."""
    h.load_state(baseline)
    return stats(h.pyboy.memory, h.address("wPartyMons"))


def measure_gifts_stored_elsewhere():
    """Gifts outside the registry, as the control: a taught move and a form live in
    the mon's struct, and global effects are run-wide flags."""
    h = RedRogueHarness(ROOT, ARTIFACTS)
    try:
        h.boot_to_lobby()
        baseline = io.BytesIO()
        h.save_state(baseline)
        trial = Trial(h, baseline, 1)
        memory = h.pyboy.memory
        middle = h.address("wPartyMons") + MON
        taught, form = 0x55, 0b01000000
        memory[middle + 11] = taught
        memory[middle + CATCH_RATE] |= form
        global_effects = h.address("wBridgeGlobalEffects")
        memory[global_effects] = 0xA5
        trial.steal_middle()
        h.call_routine("StageEventGiveBack")
        returned = h.address("wPartyMons") + (h.read8("wPartyCount") - 1) * MON
        return {"move": memory[returned + 11], "form": memory[returned + CATCH_RATE] & form,
                "global": memory[global_effects], "taught": taught, "form_bits": form}
    finally:
        h.close()


class StolenBridgeGiftTest(unittest.TestCase):
    rows: list = []

    def test_gifts_stored_elsewhere_survive_a_theft(self) -> None:
        got = measure_gifts_stored_elsewhere()
        self.assertEqual(got["move"], got["taught"])
        self.assertEqual(got["form"], got["form_bits"])
        self.assertEqual(got["global"], 0xA5)

    @classmethod
    def setUpClass(cls) -> None:
        cls.rows = measure()

    def test_constants_match_this_test(self) -> None:
        text = (ROOT / "constants/pokemon_data_constants.asm").read_text()
        self.assertEqual(tuple(re.findall(r"const BRIDGE_SELECTED_EFFECT_(\w+)", text)), EFFECTS)
        self.assertRegex(text, r"DEF BRIDGE_SELECTED_OWNER_STOLEN\s+EQU BRIDGE_SELECTED_OWNER_MAX \+ 1")

    def test_a_ray_changes_stats_so_the_stat_checks_can_fail(self) -> None:
        for row in self.rows:
            with self.subTest(row["effect"]):
                self.assertEqual(row["gifted"] != row["plain"], row["effect"] in RAYS)

    def test_theft_parks_the_record_and_compacts_the_survivor(self) -> None:
        for row in self.rows:
            with self.subTest(row["effect"]):
                self.assertEqual(row["after_theft_owner"], STOLEN)
                self.assertEqual(row["survivor_owner_after_theft"], 2)

    def test_the_villain_fields_a_legal_mon(self) -> None:
        for row in self.rows:
            with self.subTest(row["effect"]):
                self.assertLessEqual(row["villain"][0], row["villain"][1], "HP above max HP")
                self.assertEqual(row["villain"], row["gifted"], "the villain's copy differs from the mon it stole")

    def test_party_return_keeps_the_gift_and_its_stats(self) -> None:
        for row in self.rows:
            with self.subTest(row["effect"]):
                self.assertEqual(row["party_owner"], row["party_count"])
                self.assertEqual(row["party_stats"], row["gifted"])

    def test_box_return_keeps_the_gift_through_a_withdrawal(self) -> None:
        for row in self.rows:
            with self.subTest(row["effect"]):
                self.assertEqual(row["box_count"], 1)
                self.assertEqual(row["box_owner"], BOX_BASE)
                self.assertEqual(row["withdrawn_owner"], 3)
                self.assertEqual(row["withdrawn_stats"], row["gifted"])

    def test_a_mon_that_never_returns_frees_its_record_only(self) -> None:
        for row in self.rows:
            with self.subTest(row["effect"]):
                other = 4 if row["id"] != 4 else 1
                self.assertEqual(sorted(zip(row["abandoned_records"][::2], row["abandoned_records"][1::2])),
                                 [(0, 0), (2, other)])


if __name__ == "__main__":
    if sys.argv[1:] == ["--measure"]:
        for measured in measure():
            print(json.dumps(measured), flush=True)
    else:
        unittest.main()
