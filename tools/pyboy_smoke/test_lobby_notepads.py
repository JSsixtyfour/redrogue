"""Source contracts for the lobby's tile-based door notepads.

These tests guard object/text IDs and map assets, not emulator choreography.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LobbyNotepadTests(unittest.TestCase):
    def test_notepads_are_background_events_after_eleven_service_texts(self):
        source = (ROOT / "data/maps/objects/IndigoPlateauLobby.asm").read_text()
        objects = re.findall(r"(?m)^\s*object_event\s+(.+)", source)
        self.assertEqual(len(objects), 11)
        self.assertFalse(any("SPRITE_CLIPBOARD" in obj for obj in objects))
        self.assertRegex(source, r"bg_event\s+9,\s*0,\s*TEXT_PC_DOOR1_SIGN")
        self.assertRegex(source, r"bg_event\s+11,\s*0,\s*TEXT_PC_DOOR2_SIGN")
        script = (ROOT / "scripts/IndigoPlateauLobby.asm").read_text()
        table = script.split("IndigoPlateauLobby_TextPointers:")[1].split("LobbyDoor1SignText:")[0]
        ids = re.findall(r"dw_const\s+\w+,\s*(\w+)", table)
        self.assertEqual(len(ids), 13)
        self.assertEqual(ids[-2:], ["TEXT_PC_DOOR1_SIGN", "TEXT_PC_DOOR2_SIGN"])

    def test_closed_notepad_uses_sign_count_not_sprite_toggle(self):
        script = (ROOT / "scripts/IndigoPlateauLobby.asm").read_text()
        self.assertNotIn("TOGGLE_PC_DOOR2_SIGN", script)
        prefix = script.split("CheckEvent EVENT_ENTER_ROOM", 1)[0]
        self.assertRegex(prefix, r"call Lobby_IsDoor2Blocked\s+ld a, 1\s+jr nz, \.setSignCount\s+inc a\s+\.setSignCount\s+ld \[wNumSigns\], a")
        table = (ROOT / "data/maps/toggleable_objects.asm").read_text()
        lobby = table.split("toggleable_objects_for INDIGO_PLATEAU_LOBBY", 1)[1].split("toggleable_objects_for", 1)[0]
        rows = re.findall(r"toggle_object_state\s+([^;\n]+)", lobby)
        self.assertEqual(len(rows), 6)  # Preserve later saved toggle indices.
        self.assertEqual(rows[-1].strip(), "0, OFF")

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


if __name__ == "__main__":
    unittest.main()
