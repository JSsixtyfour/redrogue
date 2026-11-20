"""The Cemetery resurrection NPC's talk (CEMETERY_RESURRECTION_NPC_SPEC.md, "Talk").

A real Cemetery floor 1 with him forced there, the player talking through
DisplayTextID as an A press does. Ironman: the fallen list sorted by fee and
the offer, charge and restore through the real routines. Otherwise: reviving a
fainted party Pokemon. A small driver reads the screen state from hooks on the
real labels (the list draw, the menu, the yes/no box, the party menu) and
answers each from a plan.

The fees are read from balance_constants.asm, not repeated here.
"""

from __future__ import annotations

import io
import re
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
SLOT = 5                                # CEMETERY_RESURRECTOR
PARTYMON_STRUCT_LENGTH = 44
NAME_LENGTH = 11
FALLEN_ENTRY_SIZE = PARTYMON_STRUCT_LENGTH + 2 * NAME_LENGTH
FALLEN_LOG_BANK = 2
FALLEN_STAMP = 0xF0
MON_HP, MON_BOX_LEVEL, MON_STATUS, MON_LEVEL, MON_MAXHP = 1, 3, 4, 33, 34
BIT_IRONMAN = 0
DONE_BIT = 0x80                         # sProcCemeteryItemGot bit 7
CHAR_A = 0x80                           # the charmap "A"
NICK = PARTYMON_STRUCT_LENGTH + NAME_LENGTH


def knob(name: str) -> int:
    text = (ROOT / "constants/balance_constants.asm").read_text(encoding="utf-8")
    return int(re.search(rf"DEF {name}\s+EQU (\d+)", text).group(1))


FEES = [knob("RESURRECT_FEE_POKEBALL"), knob("RESURRECT_FEE_GREATBALL"), knob("RESURRECT_FEE_ULTRABALL")]
REVIVE_FEE = knob("RESURRECT_REVIVE_FEE")


def bcd(value: int) -> list[int]:
    digits = f"{value:06d}"
    return [int(digits[i]) << 4 | int(digits[i + 1]) for i in range(0, 6, 2)]


def money(raw: list[int]) -> int:
    return int("".join(f"{b:02x}" for b in raw))


class TalkBase(unittest.TestCase):
    CGB = False

    def setUp(self) -> None:
        self.start()

    def start(self) -> None:
        """A fresh Cemetery floor 1 with him on it."""
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=self.CGB)
        h = self.h
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)

        def force(_context) -> None:
            h.pyboy.register_file.A = 0       # ordinal 0: floor 1

        h.register_hook("CemResurrectorRoll.store", force)
        try:
            h.preload_and_enter_wild_area(self.maps["PROCEDURAL_CEMETERY_1"], "cemetery")
        finally:
            h.unregister_hook("CemResurrectorRoll.store", force)
        self.assertNotEqual(h.read8(f"wSprite{SLOT:02d}StateData1PictureID"), 0, "he is not here")
        self.template = h.read_bytes("wPartyMons", PARTYMON_STRUCT_LENGTH)
        self.ot = h.read_bytes("wPartyMonOT", NAME_LENGTH)
        self.reward = self.reward_level()

    def restart(self) -> None:
        """Another fresh Cemetery inside one test (a sub-case each)."""
        self.h.close()
        self.start()

    def tearDown(self) -> None:
        self.h.close()

    # --- fixtures --------------------------------------------------------------

    def reward_level(self) -> int:
        self.h.park_before_hijack()
        self.h.call_routine("GetRewardMonLevel")
        return self.h.read8("wCurEnemyLevel")

    def species_of_class(self) -> dict[int, int]:
        """One species of each legacy class (1 Poke, 2 Great, 3 Ultra, 4 Master),
        as the ROM's own classifier reports it."""
        h = self.h
        found: dict[int, int] = {}
        for species in range(1, 191):
            h.park_before_hijack()
            h.pyboy.register_file.D = 0
            h.pyboy.register_file.E = species
            cls = h.call_routine("RogueClassifyIdentityFar",
                                 capture=lambda hh: hh.pyboy.register_file.E)
            found.setdefault(cls, species)
        return found

    def entry(self, species: int, level: int, marker: int) -> list[int]:
        mon = list(self.template)
        mon[0] = species
        mon[MON_LEVEL] = level
        mon[MON_BOX_LEVEL] = FALLEN_STAMP
        mon[MON_HP] = mon[MON_HP + 1] = 0
        mon[MON_STATUS] = 0x08
        nick = [marker, marker + 1, 0x50] + [0x50] * (NAME_LENGTH - 3)
        return mon + list(self.ot) + nick

    def fill_log(self, entries: list[list[int]]) -> None:
        h = self.h
        h.write_sram_bytes("sFallenLog", [b for e in entries for b in e], bank=FALLEN_LOG_BANK)
        h.write8("wFallenCount", len(entries))

    def set_ironman(self, on: bool) -> None:
        self.h.write8("wOptions3", (1 << BIT_IRONMAN) if on else 0)

    def set_money(self, value: int) -> None:
        for i, b in enumerate(bcd(value)):
            self.h.write8("wPlayerMoney", b, offset=i)

    def player_money(self) -> int:
        return money(self.h.read_bytes("wPlayerMoney", 3))

    def served(self) -> bool:
        return bool(self.h.read_sram_bytes("sProcCemeteryItemGot", 1, bank=0)[0] & DONE_BIT)

    def party_nick(self, slot: int) -> list[int]:
        return self.h.read_bytes("wPartyMonNicks", 3, offset=slot * NAME_LENGTH)

    def party_mon(self, slot: int) -> list[int]:
        return self.h.read_bytes("wPartyMons", PARTYMON_STRUCT_LENGTH,
                                 offset=slot * PARTYMON_STRUCT_LENGTH)

    def log_nicks(self) -> list[int]:
        """The first nickname byte of every entry still in the log."""
        h = self.h
        count = h.read8("wFallenCount")
        raw = h.read_sram_bytes("sFallenLog", FALLEN_ENTRY_SIZE * count, bank=FALLEN_LOG_BANK)
        return [raw[i * FALLEN_ENTRY_SIZE + NICK] for i in range(count)]

    def fill_party(self, count: int) -> None:
        """Exactly `count` copies of the first Pokemon (the boot party is full)."""
        h = self.h
        for slot in range(1, count):
            for i, byte in enumerate(self.template):
                h.write8("wPartyMons", byte, offset=slot * PARTYMON_STRUCT_LENGTH + i)
            h.write8("wPartySpecies", self.template[0], offset=slot)
        h.write8("wPartyCount", count)
        h.write8("wPartySpecies", 0xFF, offset=count)

    def faint(self, slot: int) -> None:
        base = slot * PARTYMON_STRUCT_LENGTH
        self.h.write8("wPartyMons", 0, offset=base + MON_HP)
        self.h.write8("wPartyMons", 0, offset=base + MON_HP + 1)
        self.h.write8("wPartyMons", 0x08, offset=base + MON_STATUS)

    # --- the driver -------------------------------------------------------------

    def talk(self, plan: list, *, shot: str | None = None, frames: int = 6000) -> dict:
        """Press A at him, then answer each prompt from `plan`: ("list", rank),
        ("yes",), ("no",), ("party", slot) or ("b",). A is pressed only where the
        engine waits for it (a prompt, the text's close); a menu is answered
        after it has been up for a few frames. Returns the PrintText pointers
        seen, in order. Runs until the text has closed and the map polls again."""
        h = self.h
        state = {"phase": "text", "opened": False, "printed": [], "done": False,
                 "settled": False, "wait": False, "at": 0, "n": 0, "plan": list(plan)}

        def now() -> int:
            return state["n"]        # the loop's own frame count (frame_count stalls unrendered)

        def open_box(_context) -> None:
            if not state["opened"]:
                state["opened"] = True
                h.write8("hSpriteIndex", SLOT)
                h.pyboy.register_file.PC = h.symbols.get("DisplayTextID")[1]
            elif state["done"]:
                state["settled"] = True

        def printing(_context) -> None:
            state["printed"].append(h.pyboy.register_file.HL)

        def listing(_context) -> None:
            state["phase"], state["at"] = "list_drawing", now()

        def menu(_context) -> None:
            if state["phase"] == "list_drawing":
                state["phase"], state["at"] = "list", now()

        def yesno(_context) -> None:
            state["phase"], state["at"] = "yesno", now()

        def party(_context) -> None:
            state["phase"], state["at"] = "party", now()

        def waiting(_context) -> None:
            state["wait"] = True

        def finished(_context) -> None:
            state["done"] = True

        hooks = (("JoypadOverworld", open_box), ("PrintText", printing),
                 ("CRIronman.list", listing), ("HandleMenuInput", menu),
                 ("YesNoChoice", yesno), ("DisplayPartyMenu", party),
                 ("ManualTextScroll", waiting), ("WaitForTextScrollButtonPress", waiting),
                 ("TextScriptEnd", finished))
        for label, callback in hooks:
            h.register_hook(label, callback)
        try:
            for _ in range(frames):
                h.tick(1)
                state["n"] += 1
                if state["settled"]:
                    break
                if not state["opened"]:
                    continue
                phase = state["phase"]
                if phase in ("list", "yesno", "party"):
                    if now() - state["at"] < (90 if phase == "party" else 8):
                        continue                 # the party menu fades in before it reads a key
                    step = state["plan"].pop(0) if state["plan"] else ("a",)
                    state["phase"] = "text"      # before the taps: the next menu may open during them
                    if phase == "list":
                        if shot and not state.get("shot"):
                            state["shot"] = True
                            h.pyboy.tick(render=True)
                            h.pyboy.screen.image.save(shot)
                        if step[0] == "b":
                            h.tap("b", 2)
                        else:
                            rank = step[1]
                            for _ in range(rank - h.read8("hCurrentMenuItem")):
                                h.tap("down", 2)
                            for _ in range(h.read8("hCurrentMenuItem") - rank):
                                h.tap("up", 2)
                            h.tap("a", 2)
                    elif phase == "yesno":
                        if step[0] == "no":
                            h.tap("down", 2)
                        h.tap("a", 2)
                    else:
                        if step[0] == "b":
                            h.tap("b", 2)
                        else:
                            for _ in range(step[1]):
                                h.tap("down", 2)
                            h.tap("a", 2)
                elif state["wait"]:
                    state["wait"] = False
                    h.tick(6)
                    h.tap("a", 2)
            else:
                self.fail(f"the talk never ended: {state['phase']} printed "
                          f"{[hex(p) for p in state['printed']]}")
        finally:
            for label, callback in hooks:
                h.unregister_hook(label, callback)
        return state

    def says(self, state: dict, label: str) -> bool:
        return self.h.symbols.get(label)[1] in state["printed"]


class IronmanTalkTest(TalkBase):
    def start(self) -> None:
        super().start()
        self.set_ironman(True)
        self.fill_party(2)
        self.by_class = self.species_of_class()
        for cls in (1, 2, 3):
            self.assertIn(cls, self.by_class, f"no species of class {cls}")

    def three(self) -> list[list[int]]:
        # Oldest first: a Great, an Ultra, and the newest, a Poke.
        return [self.entry(self.by_class[2], 30, CHAR_A),
                self.entry(self.by_class[3], 40, CHAR_A + 2),
                self.entry(self.by_class[1], 12, CHAR_A + 4)]

    def test_the_list_is_drawn_sorted_by_fee_for_the_screenshot(self) -> None:
        self.fill_log(self.three())
        self.set_money(99999)
        shot = ARTIFACTS / "cemetery_resurrector_list.png"
        state = self.talk([("b",)], shot=str(shot))
        self.assertTrue(shot.exists())
        self.assertFalse(self.served(), "backing out must not serve")
        self.assertEqual(self.h.read8("wFallenCount"), 3)
        self.assertEqual(self.player_money(), 99999)
        self.assertTrue(self.says(state, "CRWhichText"))

    def test_the_cheapest_first_and_a_pick_charges_its_own_fee(self) -> None:
        h = self.h
        for rank, fee_index, entry in ((0, 0, 2), (1, 1, 0), (2, 2, 1)):
            with self.subTest(rank=rank):
                if rank:
                    self.restart()
                    self.set_ironman(True)
                    self.fill_party(2)
                    self.by_class = self.species_of_class()
                h = self.h
                entries = self.three()
                self.fill_log(entries)
                self.set_money(99999)
                count = h.read8("wPartyCount")
                level = entries[entry][MON_LEVEL]
                state = self.talk([("list", rank), ("yes",)])
                self.assertEqual(self.player_money(), 99999 - FEES[fee_index])
                self.assertEqual(h.read8("wPartyCount"), count + 1)
                self.assertEqual(self.party_nick(count)[0], entries[entry][NICK])
                mon = self.party_mon(count)
                self.assertEqual(mon[MON_LEVEL], max(level, self.reward))
                self.assertEqual(mon[MON_BOX_LEVEL], mon[MON_LEVEL])
                self.assertEqual(mon[MON_HP:MON_HP + 2], mon[MON_MAXHP:MON_MAXHP + 2])
                self.assertEqual(mon[MON_STATUS], 0)
                self.assertEqual(h.read8("wFallenCount"), 2)
                self.assertEqual(self.log_nicks(),
                                 [e[NICK] for i, e in enumerate(entries) if i != entry])
                self.assertTrue(self.served())
                self.assertIn(h.symbols.get("CVReturnedText")[1], state["printed"])

    def test_equal_fees_list_the_newest_first(self) -> None:
        h = self.h
        poke = self.by_class[1]
        self.fill_log([self.entry(poke, 10, CHAR_A), self.entry(poke, 11, CHAR_A + 2),
                       self.entry(self.by_class[2], 20, CHAR_A + 4)])
        self.set_money(99999)
        count = h.read8("wPartyCount")
        self.talk([("list", 0), ("yes",)])
        self.assertEqual(self.party_nick(count)[0], CHAR_A + 2, "rank 0 is the newer of two equal fees")

    def test_every_no_leaves_everything_alone(self) -> None:
        h = self.h
        self.fill_log(self.three())
        self.set_money(99999)
        count = h.read8("wPartyCount")
        self.talk([("list", 0), ("no",), ("list", 1), ("no",), ("list", 2), ("no",), ("b",)])
        self.assertEqual(h.read8("wPartyCount"), count)
        self.assertEqual(h.read8("wFallenCount"), 3)
        self.assertEqual(self.player_money(), 99999)
        self.assertFalse(self.served())

    def test_a_second_talk_after_a_service_gives_the_after_line(self) -> None:
        h = self.h
        self.fill_log(self.three())
        self.set_money(99999)
        self.talk([("list", 0), ("yes",)])
        spent = self.player_money()
        count = h.read8("wPartyCount")
        state = self.talk([])
        self.assertTrue(self.says(state, "CRAfterText"))
        self.assertEqual((self.player_money(), h.read8("wPartyCount"), h.read8("wFallenCount")),
                         (spent, count, 2))

    def test_an_empty_log(self) -> None:
        self.fill_log([])
        state = self.talk([])
        self.assertTrue(self.says(state, "CRNoSoulsText"))
        self.assertFalse(self.served())

    def test_not_enough_money(self) -> None:
        h = self.h
        self.fill_log(self.three())
        self.set_money(FEES[0] - 1)
        count = h.read8("wPartyCount")
        state = self.talk([("list", 0), ("yes",)])
        self.assertTrue(self.says(state, "CRNoMoneyText"))
        self.assertEqual((self.player_money(), h.read8("wPartyCount"), h.read8("wFallenCount")),
                         (FEES[0] - 1, count, 3))
        self.assertFalse(self.served())

    def test_a_full_party_sends_it_to_the_box(self) -> None:
        h = self.h
        self.fill_party(6)
        self.fill_log(self.three())
        self.set_money(99999)
        boxes = h.read8("wBoxCount")
        state = self.talk([("list", 0), ("yes",)])
        self.assertEqual((h.read8("wPartyCount"), h.read8("wBoxCount")), (6, boxes + 1))
        self.assertIn(h.symbols.get("CVToBoxText")[1], state["printed"])
        self.assertEqual(self.player_money(), 99999 - FEES[0])
        self.assertTrue(self.served())

    def test_party_and_box_both_full_refuses(self) -> None:
        h = self.h
        self.fill_party(6)
        h.write8("wBoxCount", 20)
        self.fill_log(self.three())
        self.set_money(99999)
        state = self.talk([("list", 0), ("yes",)])
        self.assertTrue(self.says(state, "CRBoxFullText"))
        self.assertEqual((self.player_money(), h.read8("wFallenCount"), h.read8("wBoxCount")),
                         (99999, 3, 20))
        self.assertFalse(self.served())


class ReviveTalkTest(TalkBase):
    def start(self) -> None:
        super().start()
        self.set_ironman(False)
        self.fill_party(2)
        self.h.write8("wPartyAndBillsPCSavedMenuItem", 0)     # the menu opens on slot 0

    def test_reviving_a_fainted_pokemon(self) -> None:
        h = self.h
        self.faint(0)
        self.set_money(50000)
        state = self.talk([("party", 0), ("yes",)])
        mon = self.party_mon(0)
        self.assertEqual(mon[MON_HP:MON_HP + 2], mon[MON_MAXHP:MON_MAXHP + 2])
        self.assertNotEqual(mon[MON_MAXHP:MON_MAXHP + 2], [0, 0])
        self.assertEqual(mon[MON_STATUS], 0)
        self.assertEqual(self.player_money(), 50000 - REVIVE_FEE)
        self.assertTrue(self.served())
        self.assertIn(h.symbols.get("CVRevivedText")[1], state["printed"])

    def test_a_healthy_one_is_refused(self) -> None:
        h = self.h
        self.fill_party(2)
        self.faint(0)                                   # slot 0 faints so the offer opens
        self.set_money(50000)
        state = self.talk([("party", 1)])
        self.assertIn(h.symbols.get("CVNotFaintedText")[1], state["printed"])
        self.assertEqual(self.player_money(), 50000)
        self.assertFalse(self.served())

    def test_no_fainted_pokemon(self) -> None:
        h = self.h
        state = self.talk([])
        self.assertIn(h.symbols.get("CVNoFaintedText")[1], state["printed"])
        self.assertFalse(self.served())

    def test_not_enough_money(self) -> None:
        h = self.h
        self.faint(0)
        self.set_money(REVIVE_FEE - 1)
        state = self.talk([("party", 0), ("yes",)])
        self.assertIn(h.symbols.get("CVNoMoneyText")[1], state["printed"])
        self.assertEqual(self.player_money(), REVIVE_FEE - 1)
        self.assertEqual(self.party_mon(0)[MON_HP:MON_HP + 2], [0, 0])
        self.assertFalse(self.served())

    def test_declining_keeps_everything(self) -> None:
        self.faint(0)
        self.set_money(50000)
        self.talk([("party", 0), ("no",)])
        self.assertEqual(self.player_money(), 50000)
        self.assertEqual(self.party_mon(0)[MON_HP:MON_HP + 2], [0, 0])
        self.assertFalse(self.served())


if __name__ == "__main__":
    unittest.main()
