from __future__ import annotations

from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]


class BoxFullReminderContractTest(unittest.TestCase):
    def test_capture_only_call_is_after_transfer_text(self) -> None:
        source = (REPO_ROOT / "engine" / "items" / "item_effects.asm").read_text()
        capture = source[source.index("ItemUseBall:"):source.index("ItemUseBallText00:")]
        send_index = capture.index("call SendNewMonToBox")
        reminder_index = capture.index("farcall BridgeMaybePrintBoxFullReminder")

        self.assertEqual(capture.count("farcall BridgeMaybePrintBoxFullReminder"), 1)
        self.assertLess(send_index, capture.index("call PrintText", send_index))
        self.assertLess(
            capture.index("call PrintText", send_index),
            reminder_index,
        )
        self.assertLess(reminder_index, capture.index("jr .done", reminder_index))
        send_to_box = source[source.index("SendNewMonToBox:"):source.index("IsNextTileShoreOrWater:")]
        self.assertNotIn("BridgeMaybePrintBoxFullReminder", send_to_box)

    def test_helper_gates_exactly_one_print_on_final_slot(self) -> None:
        source = (REPO_ROOT / "custom_functions" / "bridge_selected_effects.asm").read_text()
        helper = source[
            source.index("BridgeMaybePrintBoxFullReminder::"):
            source.index("; Party-menu swap.")
        ]
        self.assertIn("ld a, [wBoxCount]", helper)
        self.assertIn("cp MONS_PER_BOX", helper)
        self.assertIn("ret nz", helper)
        self.assertEqual(helper.count("call PrintText"), 1)
        self.assertIn("text_far _BoxIsFullReminderText", helper)

    def test_reminder_text_matches_donor_paragraph_and_line_width(self) -> None:
        source = (REPO_ROOT / "data" / "text" / "text_6.asm").read_text()
        text = source[source.index("_BoxIsFullReminderText::"):source.index("_SurfingGotOnText::")]
        expected = (
            'text "The #MON BOX"',
            'line "is now full."',
            'cont "It won\'t hold"',
            'cont "more #MON."',
            'para "Change the BOX at"',
            'line "a #MON CENTER!"',
            "prompt",
        )
        for line in expected:
            self.assertIn(line, text)
        self.assertNotIn("@", text)
        for literal in re.findall(r'\b(?:text|line|cont|para) "([^"]*)"', text):
            self.assertLessEqual(len(literal), 17, literal)


if __name__ == "__main__":
    unittest.main()
