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


class FakeMemory:
    """h.read8 / h.read_bytes over a few labels, for button-sequence tests."""

    def __init__(self, **labels):
        self.labels = {name: bytearray(value if isinstance(value, (bytes, bytearray, list)) else [value])
                       for name, value in labels.items()}

    def read8(self, label, offset=0):
        return self.labels[label][offset]

    def read_bytes(self, label, length, offset=0):
        return list(self.labels[label][offset:offset + length])

    def set(self, label, value, offset=0):
        self.labels[label][offset] = value


def fake_agent(**labels):
    return SimpleNamespace(h=FakeMemory(**labels), last_wait_caller="", last_menu_caller="")


YES_NO = ("HandleMenuInput_+$12", "DisplayTwoOptionMenu.noYesNoSwap+$5")


class LobbyNPCErrandTest(unittest.TestCase):
    def errand(self, target, run_index=1):
        return errands.LobbyNPCErrand(kind="lobby", run_index=run_index, start_frame=0, before={}, target=target)

    def press(self, errand, agent, menu=None, cursor=0):
        agent.last_wait_caller, agent.last_menu_caller = menu or ("JoypadLowSensitivity+$4", "")
        agent.h.set("hCurrentMenuItem", cursor)
        return errand.next_button(agent)

    def test_text_is_answered_a(self):
        agent = fake_agent(hCurrentMenuItem=0)
        self.assertEqual(self.press(self.errand("sign1"), agent), "a")

    def test_psychic_says_yes_then_no_to_any_later_box(self):
        errand, agent = self.errand("psychic"), fake_agent(hCurrentMenuItem=0)
        self.assertEqual(self.press(errand, agent, YES_NO, cursor=0), "a")
        self.assertIn("accepted", errand.reached)
        self.assertEqual(self.press(errand, agent, YES_NO, cursor=0), "down")
        self.assertEqual(self.press(errand, agent, YES_NO, cursor=1), "a")

    def test_salesman_declines_on_the_first_run_and_buys_later(self):
        errand, agent = self.errand("salesman", run_index=1), fake_agent(hCurrentMenuItem=0)
        self.assertEqual(self.press(errand, agent, YES_NO, cursor=0), "down")
        self.assertEqual(self.press(errand, agent, YES_NO, cursor=1), "a")
        self.assertIn("declined", errand.reached)
        errand = self.errand("salesman", run_index=2)
        self.assertEqual(self.press(errand, agent, YES_NO, cursor=0), "a")
        self.assertIn("accepted", errand.reached)

    def test_trader_declines(self):
        errand, agent = self.errand("trader"), fake_agent(hCurrentMenuItem=0)
        self.assertEqual(self.press(errand, agent, YES_NO, cursor=0), "down")

    def test_tutor_cancels_its_party_menu_and_any_unknown_menu(self):
        errand, agent = self.errand("tutor"), fake_agent(hCurrentMenuItem=0)
        self.assertEqual(self.press(errand, agent, YES_NO, cursor=0), "a")
        agent.party_menu_waiting = True  # HandlePartyMenuInput's hook
        self.assertEqual(self.press(errand, agent, ("HandleMenuInput_+$12", ""), cursor=0), "b")
        self.assertIn("party_menu", errand.reached)
        agent.party_menu_waiting = False
        other = ("HandleMenuInput_+$12", "DisplayListMenuID.loop+$3")
        self.assertEqual(self.press(errand, agent, other, cursor=0), "b")

    def test_party_menu_that_skips_the_menu_hook_is_cancelled(self):
        # HandlePartyMenuInput enters HandleMenuInput_ directly, so the hook
        # never refreshes last_menu_caller: the YES/NO caller would be stale.
        errand, agent = self.errand("tutor"), fake_agent(hCurrentMenuItem=0)
        self.assertEqual(self.press(errand, agent, YES_NO, cursor=0), "a")
        self.assertEqual(agent.last_menu_caller, "")
        agent.last_wait_caller = "HandleMenuInput_+$40"  # the party menu polls; caller not refreshed
        self.assertEqual(errand.next_button(agent), "b")

    def test_only_an_accepted_salesman_may_add_a_mon(self):
        mon = party_record(1, 5, 5, b"\x80")
        new = party_record(2, 5, 5, b"\x81")
        before = {"party_count": 1, "party": (mon,), "box_count": 0, "box": ()}
        after = {"party_count": 2, "party": tuple(sorted((mon, new))), "box_count": 0, "box": ()}
        buyer = errands.LobbyNPCErrand(kind="lobby", run_index=2, start_frame=0, before=before, target="salesman")
        buyer.reached.add("accepted")
        self.assertEqual(buyer.contract_violations(after), [])
        psychic = errands.LobbyNPCErrand(kind="lobby", run_index=2, start_frame=0, before=before, target="psychic")
        psychic.reached.add("accepted")
        self.assertEqual(psychic.contract_violations(after), ["a mon arrived without a YES"])


class RoomTablesTest(unittest.TestCase):
    def test_vendor_ids_from_source(self):
        ids = errands.room_vendor_ids(ROOT)
        self.assertEqual(ids["RoomVendorTopIds"], [0, 1, 2, 3, 4, 5, 6, 7, 25])
        self.assertEqual(ids["RoomVendorMiddleIds"], [9, 10, 11, 12, 26])
        self.assertEqual(ids["RoomVendorDeskIds"], [8])
        self.assertEqual(ids["RoomVendorPlantIds"], [13, 61])
        self.assertEqual(len(ids["RoomVendorPalsIds"]), 45)
        self.assertEqual(ids["RoomVendorPalsIds"][:2], [14, 15])
        self.assertEqual(ids["RoomVendorPalsIds"][-1], 60)

    def test_current_choice_decodes_sram(self):
        state = [0x5 | 0x30 | 0x80, 0x01 | 0x02, 0, 0, 0, 7, 0, 0, 9, 0]
        self.assertEqual(errands.room_current_choice(state, "f_top"), 5)
        self.assertEqual(errands.room_current_choice(state, "f_mid"), 3)
        self.assertEqual(errands.room_current_choice(state, "f_pc"), 1)
        self.assertEqual(errands.room_current_choice(state, "f_bot"), 2)  # STATUE
        self.assertEqual(errands.room_current_choice([0, 0x02] + [0] * 8, "f_bot"), 0)  # bit 7 decides
        self.assertEqual(errands.room_current_choice(state, "d3"), 7)
        self.assertEqual(errands.room_current_choice(state, "d6"), 9)

    def test_pick_row_counts_owned_entries_before_the_choice(self):
        ids = [0, 1, 2, 3, 4, 5, 6, 7, 25]  # TOP
        owned = [0b0000_0101, 0, 0, 0b0000_0010, 0, 0, 0, 0]  # pieces 0, 2, 25
        self.assertEqual(errands.room_pick_row(0, ids, owned), 0)  # WALL always shows
        self.assertEqual(errands.room_pick_row(1, ids, owned), 1)  # piece 0
        self.assertEqual(errands.room_pick_row(3, ids, owned), 2)  # piece 2, piece 1 hidden
        self.assertEqual(errands.room_pick_row(9, ids, owned), 3)  # piece 25
        self.assertIsNone(errands.room_pick_row(2, ids, owned))  # piece 1 not owned


class RoomPCErrandTest(unittest.TestCase):
    TOP = ("HandleMenuInput_+$12", "RoomPC.descTableSet+$8")
    FURNITURE = ("HandleMenuInput_+$12", "RoomFurnitureMenu+$40")
    PICK = ("HandleMenuInput_+$12", "RoomDrawPickList.noDescriptions+$3")
    OTHER = ("HandleMenuInput_+$12", "PlayerPC.loop+$10")

    def setUp(self):
        self.agent = fake_agent(hCurrentMenuItem=0, wMaxMenuItem=4, wBuffer=bytearray(32))
        self.agent.room_vendor_ids = errands.room_vendor_ids(ROOT)
        self.errand = errands.RoomPCErrand(kind="roompc", run_index=1, start_frame=0, before={})
        self.errand.room_before = [0, 0x01] + [0] * 8  # LONG DESK at the PC, the rest default

    def press(self, screen, cursor=0):
        self.agent.last_wait_caller, self.agent.last_menu_caller = screen
        self.agent.h.set("hCurrentMenuItem", cursor)
        return self.errand.next_button(self.agent)

    def test_key_items_then_the_desk_is_re_picked_where_it_is(self):
        self.assertEqual(self.press(self.TOP, 0), "a")  # KEY ITEMS
        self.assertEqual(self.press(self.OTHER), "b")  # PlayerPC: leave it
        self.assertEqual(self.press(self.TOP, 0), "down")  # back: KEY ITEMS done, on to FURNITURE
        self.assertIn("key_items", self.errand.reached)
        self.assertEqual(self.press(self.TOP, 1), "a")
        self.assertEqual(self.press(self.FURNITURE, 0), "a")  # PC is the furniture menu's row 0
        memory = self.agent.h
        memory.set("wBuffer", 1, offset=27)  # a filtered list
        memory.set("wBuffer", 0x01, offset=19 + 1)  # owns piece 8, the LONG DESK
        self.assertEqual(self.press(self.PICK, 0), "down")  # row 0 is DESK: not the current choice
        self.assertEqual(self.press(self.PICK, 1), "a")
        self.assertIn("picked:f_pc", self.errand.reached)

    def test_spot_picker_takes_spot_one(self):
        self.errand.visit = 9  # decor_pc
        self.errand.entered = True
        self.errand.visit_presses = 0
        self.assertEqual(self.press(self.PICK, 0), "a")  # unfiltered: wBuffer + 27/28 are 0
        self.assertIn("spot_picker", self.errand.reached)

    def test_toggles_row_is_skipped_when_absent_and_log_off_is_last(self):
        self.errand.visit = 11  # toggles
        self.assertEqual(self.press(self.TOP, 0), "down")  # wMaxMenuItem 4: LOG OFF is row 4
        self.assertEqual(self.press(self.TOP, 4), "a")
        self.assertIn("log_off", self.errand.reached)

    def test_an_unknown_choice_backs_out_instead_of_picking(self):
        self.errand.visit, self.errand.entered = 1, True  # furniture_pc, in progress
        self.errand.room_before = [0, 0x01] + [0] * 8
        self.agent.h.set("wBuffer", 1, offset=27)  # filtered, but nothing owned
        self.assertEqual(self.press(self.PICK, 0), "b")
        self.assertEqual(self.press(self.TOP, 0), "down")
        self.assertNotIn("furniture_pc", self.errand.reached)
        self.assertTrue(self.errand.notes)


if __name__ == "__main__":
    unittest.main()
