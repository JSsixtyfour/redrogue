"""Directed errands (FOLLOWUPS #87): flag, source tables, roster contract."""
from pathlib import Path
from types import SimpleNamespace
import unittest

import autoplay_errands as errands
from autoplay import AutoplayAgent

ROOT = Path(__file__).resolve().parents[2]


def party_record(species, box_level, level, nick):
    struct = bytearray(errands.PARTYMON_STRUCT_LENGTH)
    struct[0], struct[3], struct[0x21] = species, box_level, level
    return bytes(struct) + nick.ljust(errands.NAME_LENGTH, b"\x50")


def box_record(party, box_level):
    struct = bytearray(party[:errands.BOXMON_STRUCT_LENGTH])
    struct[3] = box_level
    return bytes(struct) + party[errands.PARTYMON_STRUCT_LENGTH:]


class ParseErrandsTest(unittest.TestCase):
    def test_default_is_none(self):
        self.assertEqual(errands.parse_errands(None), frozenset())
        self.assertEqual(errands.parse_errands(""), frozenset())

    def test_list_and_all(self):
        self.assertEqual(errands.parse_errands("pc, rental"), {"pc", "rental"})
        self.assertEqual(errands.parse_errands("all"), set(errands.ERRAND_KINDS))

    def test_rental_implies_its_forest_schedule(self):
        self.assertEqual(errands.expand_kinds(frozenset({"rental"})), {"rental", "rental_forest"})
        self.assertEqual(errands.expand_kinds(frozenset({"pc"})), {"pc"})
        with self.assertRaises(ValueError):
            errands.parse_errands("rental_forest")  # internal, not a flag value

    def test_unknown_kind_is_refused(self):
        with self.assertRaises(ValueError):
            errands.parse_errands("pc,bogus")


class BridgePCTilesTest(unittest.TestCase):
    def test_reads_bridge_pcs_from_source(self):
        tiles = errands.bridge_pc_tiles(ROOT)
        self.assertIn((2, 1), tiles["OAKS_LAB"])
        self.assertNotIn((0, 1), tiles["OAKS_LAB"])  # the email, not the PC
        self.assertEqual(tiles["SS_ANNE_CAPTAINS_ROOM"], [(5, 5)])
        self.assertNotIn("VIRIDIAN_POKECENTER", tiles)  # an ordinary PC, not a bridge PC


class RosterContractTest(unittest.TestCase):
    def errand(self, before):
        return errands.DirectedErrand(kind="pc", run_index=0, start_frame=0, before=before)

    def identity(self, party, box):
        return {"party_count": len(party), "party": tuple(sorted(party)),
                "box_count": len(box), "box": tuple(sorted(box))}

    def test_deposit_keeps_the_mon(self):
        lead, other = party_record(1, 9, 30, b"A"), party_record(4, 9, 31, b"B")
        before = self.identity([lead, other], [])
        after = self.identity([lead], [box_record(other, 31)])  # box level rewritten
        self.assertEqual(self.errand(before).contract_violations(after), [])

    def test_lost_mon_is_reported(self):
        lead, other = party_record(1, 9, 30, b"A"), party_record(4, 9, 31, b"B")
        before = self.identity([lead, other], [])
        self.assertTrue(self.errand(before).contract_violations(self.identity([lead], [])))

    def test_changed_mon_is_reported(self):
        lead = party_record(1, 9, 30, b"A")
        changed = bytearray(lead)
        changed[0x0C] ^= 1  # a move byte
        before = self.identity([lead], [])
        self.assertTrue(self.errand(before).contract_violations(self.identity([bytes(changed)], [])))


class BillsPCCursorTest(unittest.TestCase):
    def test_moves_mirror_the_rom(self):
        moves = errands.bills_pc_moves
        self.assertEqual(moves(0, 6), {"down": 1, "right": 6})
        self.assertEqual(moves(5, 6), {"up": 4})  # row 5 has no box row to its right
        self.assertNotIn("down", moves(2, 3))  # past the last party mon
        self.assertEqual(moves(11, 6)["left"], 1)  # box row 1, column 0 -> party row 1
        self.assertEqual(moves(16, 2)["left"], 1)  # clamped to the last party mon
        self.assertNotIn("right", moves(10, 6))  # last column
        self.assertNotIn("down", moves(21, 6))  # last box row

    def test_route_reaches_every_slot(self):
        for party in range(1, 7):
            for start in range(party):
                for target in list(range(party)) + list(range(6, 26)):
                    item, presses = start, 0
                    while (button := errands.bills_pc_route(item, target, party)) is not None:
                        item = errands.bills_pc_moves(item, party)[button]
                        presses += 1
                        self.assertLess(presses, 30)
                    self.assertEqual(item, target)

    def test_tasks_never_release_and_respect_the_roster(self):
        names = [name for name, _ in errands.bills_pc_tasks(1, 0)]
        self.assertEqual(names, ["party_stats"])  # no deposit of the last mon
        names = [name for name, _ in errands.bills_pc_tasks(6, 20)]
        self.assertNotIn("deposit", names)  # box full
        for _, steps in errands.bills_pc_tasks(6, 5):
            for step in steps:
                self.assertNotEqual(step, ("sub", 3))  # RELEASE


class DefaultRunsUntouchedTest(unittest.TestCase):
    def test_no_kinds_means_no_goals_and_no_reads(self):
        agent = AutoplayAgent.__new__(AutoplayAgent)
        agent.directed_kinds = frozenset()
        agent.h = SimpleNamespace()  # any read would raise AttributeError
        self.assertEqual(agent.directed_goals(grid=None), [])


if __name__ == "__main__":
    unittest.main()
