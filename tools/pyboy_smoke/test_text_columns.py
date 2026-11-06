"""The text box's arrow column and open strings, checked across every dialogue source.

An 18-wide bottom line loses its last letter to the arrow of the next `cont`, `para`
or `prompt`, and a `text` inside an open string stops the box at an error line. See
tools/audit_text_columns.py. The controls keep the audit from passing by finding nothing.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import audit_text_columns as audit  # noqa: E402


def findings(*lines: str, far: str | None = None) -> list[audit.Finding]:
    sources = {"a.asm": list(lines)}
    if far is not None:
        sources["b.asm"] = far.split("\n")
    return audit.audit(sources)


class ColumnControlTest(unittest.TestCase):
    def test_an_eighteen_wide_bottom_line_before_each_arrow_fails(self) -> None:
        wide = '\tline "wants to join your"'
        for after in ('\tcont "party!"', '\tpara "party!"', "\tprompt"):
            with self.subTest(after=after):
                found = findings("_A::", '\ttext "The wild"', wide, after, "\tdone")
                self.assertEqual([f.number for f in found], [3])
                self.assertFalse(found[0].dynamic)
        found = findings("_A::", '\ttext "The wild"', '\tline "wants to join your@"', "\ttext_start", "\tprompt")
        self.assertEqual([f.number for f in found], [3])

    def test_the_same_words_in_two_places_are_two_findings(self) -> None:
        body = ['\ttext "A"', '\tline "wants to join your"', '\tcont "B"', "\tdone"]
        self.assertEqual([f.number for f in findings("_A::", *body, "_B::", *body)], [3, 8])

    def test_seventeen_wide_passes_and_tile_widths_are_counted(self) -> None:
        self.assertEqual(findings("_A::", '\ttext "A"', '\tline "wants to join you"', '\tcont "B"', "\tdone"), [])
        # '#' prints four tiles, and 't is one.
        self.assertEqual(len(findings("_A::", '\ttext "A"', '\tline "#MON are pretty"', '\tcont "B"', "\tdone")), 1)
        self.assertEqual(findings("_A::", '\ttext "A"', '\tline "I can\'t go on, no."', '\tcont "B"', "\tdone"), [])

    def test_no_arrow_or_the_top_row_keeps_column_18(self) -> None:
        self.assertEqual(findings("_A::", '\ttext "A"', '\tline "wants to join your"', "\tdone"), [])
        self.assertEqual(findings("_A::", '\ttext "A"', '\tline "wants to join your@"', "\ttext_end"), [])
        self.assertEqual(findings("_A::", '\ttext "wants to join your"', '\tcont "B"', "\tdone"), [])

    def test_a_trailing_space_loses_nothing(self) -> None:
        self.assertEqual(findings("_A::", '\ttext "A"', '\tline "time to use that! "', "\tprompt"), [])

    def test_past_column_18_fails_on_either_row(self) -> None:
        self.assertEqual(len(findings("_A::", '\ttext "DIGLETT lives here."', "\tdone")), 1)
        self.assertEqual(len(findings("_A::", '\ttext "A"', '\tline "DIGLETT lives here."', "\tdone")), 1)

    def test_a_string_continued_after_a_name_stays_on_its_row(self) -> None:
        found = findings("_A::", '\ttext "A"', '\tline "@"', "\ttext_ram wNameBuffer", '\ttext " wants to"',
                         '\tcont "B"', "\tdone")
        # 10 for the name and 9 for " wants to": dynamic, so it never fails the audit.
        self.assertEqual([(f.width, f.dynamic) for f in found], [(19, True)])

    def test_a_far_body_is_followed_into_its_wrappers_arrow(self) -> None:
        body = '_B::\n\ttext "A"\n\tline "wants to join your@"\n\ttext_end'
        found = findings("B:", "\ttext_far _B", "\ttext_promptbutton", "\ttext_end", far=body)
        self.assertEqual([f.number for f in found], [3])
        self.assertEqual(findings("B:", "\ttext_far _B", "\ttext_end", far=body), [])

    def test_next_leaves_the_row_unknown(self) -> None:
        self.assertEqual(findings("_A::", '\ttext "A"', '\tnext "wants to join your"', "\tpage \"B\"", "\tdex"), [])


class OpenStringControlTest(unittest.TestCase):
    def test_a_command_in_an_open_string_fails(self) -> None:
        for command in ('\ttext "B"', "\ttext_ram wNameBuffer", "\ttext_start", "\ttext_far _C"):
            with self.subTest(command=command):
                found = findings("_A::", '\ttext "A"', command, '\tline "C"', "\tdone")
                self.assertEqual([f.number for f in found], [3])
                self.assertIn("open string", found[0].why)

    def test_a_closed_string_or_a_terminator_passes(self) -> None:
        self.assertEqual(findings("_A::", '\ttext "A@"', '\ttext "B"', "\tdone"), [])
        self.assertEqual(findings("_A::", '\ttext "A"', "\ttext_end"), [])
        self.assertEqual(findings("_A::", '\ttext "A"', "\tprompt"), [])


class UnusedTextTest(unittest.TestCase):
    BODY = ["_A::", '\ttext "A"', '\tline "wants to join your"', '\tcont "B"', "\tdone"]

    def test_only_a_listed_file_is_skipped(self) -> None:
        listed = next(iter(audit.UNUSED_TEXT))
        self.assertEqual(audit.audit({listed: self.BODY}), [])
        self.assertEqual(len(audit.audit({"a.asm": self.BODY})), 1)
        self.assertEqual(len(audit.audit({listed: self.BODY}, skip=())), 1)

    def test_every_entry_still_names_a_file_with_a_finding(self) -> None:
        # An entry with nothing left to skip is stale, and would hide the next line added there.
        sources = audit.load_sources()
        found = {f.path for f in audit.audit(sources, skip=())}
        for path in audit.UNUSED_TEXT:
            self.assertIn(path, found)


class TreeTest(unittest.TestCase):
    def test_no_literal_problem_in_any_dialogue_source(self) -> None:
        problems = [str(f) for f in audit.audit(audit.load_sources()) if not f.dynamic]
        self.assertEqual(problems, [], "\n".join(problems))


if __name__ == "__main__":
    unittest.main()
