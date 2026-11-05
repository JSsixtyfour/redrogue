"""No text label may fall through into the next one.

_VioletGymTrainer3AfterBattleText had no `done`: talking to that beaten trainer ran on into the gym
guide's speech, with a <NULL> glyph at the join. Only a played run found it, on a map few runs reach.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEXT_LINE = re.compile(r"^(text|line|cont|para|next|page)\b")
LABEL = re.compile(r"^([._A-Za-z0-9]+)::?$")


def fall_throughs(lines: list[str]) -> list[str]:
    found, label, last = [], None, None
    for raw in lines:
        line = raw.split(";")[0].strip()
        if not line:
            continue
        match = LABEL.match(line)
        if match:
            if label and last and TEXT_LINE.match(last) and not last.endswith('@"'):
                found.append(f"{label} ends on `{last}`, falls into {match.group(1)}")
            label, last = match.group(1), None
        else:
            last = line
    return found


class TextTerminatorTest(unittest.TestCase):
    def test_the_check_catches_a_missing_terminator(self) -> None:
        self.assertEqual(len(fall_throughs(["_A::", '\ttext "one"', "_B::", '\ttext "two"', "\tdone"])), 1)
        self.assertEqual(fall_throughs(["_A::", '\ttext "one"', "\tdone", "_B::", '\ttext "two@"', "_C::"]), [])

    def test_no_text_falls_through(self) -> None:
        for path in sorted((ROOT / "text").glob("*.asm")):
            self.assertEqual(fall_throughs(path.read_text(errors="replace").splitlines()), [], path.name)


if __name__ == "__main__":
    unittest.main()
