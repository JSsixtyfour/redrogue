"""A bridge tutor gift refuses a move the mon already knows.

LearnMove never checks for a move already known (the TM path and level-up do
it first), so BridgeTeachMoveToCurrent wrote a duplicate: autoplay branching
found Exeggutor with SURF twice after a type-change gift's Water move and Mew
with TRANSFORM twice after Copycat's tutor gift, each taught to a non-lead mon.

The routine prints text, which only works inside a live DisplayTextID (a
PrintText injected from the bare overworld loop crashes the same way with or
without the gift code, measured 2026-10-20). So the test opens the lobby
witch's text box the way talking to her does and swaps her text_asm handler
for the gift routine, returning through TextScriptEnd like a gift text.
"""
import re

import autoplay
from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

MOVES = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
PARTYMON_STRUCT_LENGTH, MON_MOVES = 0x2C, 0x08
CARRY = 0x10
SLOT = 1  # party slot 2: real gifts reached the duplicate on a non-lead mon


def lobby_text_id(name: str) -> int:
    """TEXT_* value from the lobby's text pointer table (def_text_pointers starts at 1)."""
    source = (REPO_ROOT / "scripts/IndigoPlateauLobby.asm").read_text(encoding="utf-8")
    table = source.split("IndigoPlateauLobby_TextPointers:", 1)[1]
    names = re.findall(r"^\s*dw_const\s+\w+,\s*(TEXT_\w+)", table, re.M)
    return names.index(name) + 1


class BridgeTeachKnownMoveTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        autoplay.boot(self.harness, seed=1)
        h = self.harness
        self.assertGreater(h.read8("wPartyCount"), SLOT)
        self.moves_at = h.address("wPartyMon1Moves") + SLOT * PARTYMON_STRUCT_LENGTH
        witch = lobby_text_id("TEXT_PC_WITCH")
        sprite_texts = h.read_bytes("wMapSpriteData", 2 * h.read8("wNumSprites"))
        self.witch_slot = next(i // 2 + 1 for i in range(1, len(sprite_texts), 2)
                               if sprite_texts[i] == witch)

    def moves(self) -> list[int]:
        return [self.harness.pyboy.memory[self.moves_at + i] for i in range(4)]

    def teach(self, move: int) -> int:
        """Teach `move` to party slot 2 through BridgeTeachMoveToCurrent, run as
        the witch's text_asm; return F as it returns."""
        h = self.harness
        registers = h.pyboy.register_file
        memory = h.pyboy.memory
        bank, routine = h.symbols.get("BridgeTeachMoveToCurrent")
        _, text_end = h.symbols.get("TextScriptEnd")
        state = {"opened": False, "swapped": False, "flags": None}

        def open_box(_context) -> None:
            # The overworld loop's poll: call DisplayTextID instead, as an A
            # press facing the witch does.
            if not state["opened"]:
                state["opened"] = True
                h.write8("hSpriteIndex", self.witch_slot)
                registers.PC = h.symbols.get("DisplayTextID")[1]

        def swap_handler(_context) -> None:
            # Her text_asm: run the gift routine with TextScriptEnd as its
            # return, which hands the text engine its ending text as she would.
            if state["swapped"]:
                return
            state["swapped"] = True
            sp = registers.SP - 2
            memory[sp] = text_end & 0xFF
            memory[sp + 1] = text_end >> 8
            registers.SP = sp
            h.write8("hWhichPokemon", SLOT)
            memory[0x2000] = bank
            h.write8("hLoadedROMBank", bank)
            registers.A = move
            registers.PC = routine

        def returned(_context) -> None:
            if state["swapped"] and state["flags"] is None:
                state["flags"] = registers.F

        hooks = (("JoypadOverworld", open_box), ("TextScriptEnd", returned))
        for label, callback in hooks:
            h.register_hook(label, callback)
        # The label is the text_asm byte; her code starts after it.
        witch_bank, witch_text = h.symbols.get("PCWitchText")
        h.pyboy.hook_register(witch_bank, witch_text + 1, swap_handler, None)
        try:
            for frame in range(3000):
                h.tick(1)
                if state["flags"] is not None:
                    break
                if state["swapped"] and frame % 20 == 0:
                    h.tap("a", 2)
        finally:
            for label, callback in hooks:
                h.unregister_hook(label, callback)
            h.pyboy.hook_deregister(witch_bank, witch_text + 1)
        self.assertTrue(state["swapped"], "the witch's text never ran")
        self.assertIsNotNone(state["flags"], "the gift routine never returned")
        return state["flags"]

    def test_known_move_is_refused(self) -> None:
        before = self.moves()
        self.assertTrue(before[0])
        flags = self.teach(before[0])
        self.assertEqual(self.moves(), before)
        self.assertFalse(flags & CARRY, "a refused teach returns carry clear")

    def test_new_move_is_still_taught(self) -> None:
        # The control: with an empty slot, a move it does not know is learned.
        for i in range(1, 4):
            self.harness.pyboy.memory[self.moves_at + i] = 0
        new = next(MOVES[name] for name in ("TACKLE", "SURF") if MOVES[name] != self.moves()[0])
        flags = self.teach(new)
        self.assertEqual(self.moves()[1], new)
        self.assertTrue(flags & CARRY, "a taught move returns carry set")
