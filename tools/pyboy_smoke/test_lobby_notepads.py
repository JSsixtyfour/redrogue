"""Source contracts for the lobby's tile-based door notepads.

These tests guard object/text IDs and map assets, not emulator choreography.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LobbyNotepadTests(unittest.TestCase):
    def test_notepads_are_background_events_after_thirteen_service_texts(self):
        source = (ROOT / "data/maps/objects/IndigoPlateauLobby.asm").read_text()
        objects = re.findall(r"(?m)^\s*object_event\s+(.+)", source)
        self.assertEqual(len(objects), 13)
        self.assertFalse(any("SPRITE_CLIPBOARD" in obj for obj in objects))
        self.assertRegex(source, r"bg_event\s+9,\s*0,\s*TEXT_PC_DOOR1_SIGN")
        self.assertRegex(source, r"bg_event\s+11,\s*0,\s*TEXT_PC_DOOR2_SIGN")
        script = (ROOT / "scripts/IndigoPlateauLobby.asm").read_text()
        table = script.split("IndigoPlateauLobby_TextPointers:")[1].split("LobbyKeySwapAttendantText:")[0]
        ids = re.findall(r"dw_const\s+\w+,\s*(\w+)", table)
        self.assertEqual(len(ids), 16)
        service_ids = [obj.partition(";")[0].split(",")[-1].strip() for obj in objects]
        self.assertEqual(ids[:13], service_ids)
        self.assertEqual(ids[13:], ["TEXT_PC_DOOR1_SIGN", "TEXT_PC_DOOR2_SIGN",
                                   "TEXT_LOBBY_KEY_SWAP_ANNOUNCEMENT"])

    def test_closed_notepad_uses_sign_count_not_sprite_toggle(self):
        script = (ROOT / "scripts/IndigoPlateauLobby.asm").read_text()
        self.assertNotIn("TOGGLE_PC_DOOR2_SIGN", script)
        normal = script.split("\n.normal\n", 1)[1].split("IndigoPlateauLobby_TextPointers:", 1)[0]
        self.assertRegex(normal, r"call Lobby_IsDoor2Blocked\s+ld a, 1\s+jr nz, \.setSignCount\s+inc a\s+\.setSignCount\s+ld \[wNumSigns\], a")
        table = (ROOT / "data/maps/toggleable_objects.asm").read_text()
        lobby = table.split("toggleable_objects_for INDIGO_PLATEAU_LOBBY", 1)[1].split("toggleable_objects_for", 1)[0]
        rows = re.findall(r"toggle_object_state\s+([^;\n]+)", lobby)
        self.assertEqual(len(rows), 6)  # Preserve later saved toggle indices.
        self.assertEqual(rows[-1].strip(), "PC_RENTAL_OFFICIAL, OFF")

    def test_open_door_retains_user_notepad_block(self):
        script = (ROOT / "scripts/IndigoPlateauLobby.asm").read_text()
        self.assertRegex(script, r"jr nz, \.blockExitToSecondDoor\s+ld a, \$08")
        self.assertRegex(script, r"\.blockExitToSecondDoor\s+ld a, \$C")
        blocks = (ROOT / "gfx/blocksets/pokecenter.bst").read_bytes()
        open_block = blocks[8 * 16:9 * 16]
        closed_block = blocks[12 * 16:13 * 16]
        self.assertEqual(len(open_block), 16)
        # Right-hand upper quadrant is the notepad; closed is a plain wall.
        self.assertNotEqual(open_block[2:4] + open_block[6:8], closed_block[2:4] + closed_block[6:8])

    def test_stage_selection_precedes_door_presentation(self):
        script = (ROOT / "scripts/IndigoPlateauLobby.asm").read_text()
        selection = script.index("farcall SelectAndPatchLobbyExit")
        door_block = script.index("; update exit door tile")
        sign_count = script.index("\n.normal\n")
        self.assertLess(selection, door_block)
        self.assertLess(selection, sign_count)


if __name__ == "__main__":
    unittest.main()
