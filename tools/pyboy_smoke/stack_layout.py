"""Where the stack and the unused WRAM0 gap below it sit in a built ROM.

Read from the .map, not hard-coded: the gap is whatever the linker left between
the last WRAM0 section and SECTION "Stack" ($DEB2-$DEFF on 2026-11-18, 78 B),
and it moves whenever a WRAM0 variable is added or removed.

The stack section is wStack - $FF .. wStack ($DF00-$DFFF). SP never legitimately
goes below its low end, so a byte written in the gap means the stack overflowed.
"""
from __future__ import annotations

from pathlib import Path
import re

SECTION_RE = re.compile(r'^\s*SECTION: \$(?P<start>[0-9a-f]{4})-\$(?P<end>[0-9a-f]{4}) .*\["Stack"\]')
EMPTY_RE = re.compile(r"^\s*EMPTY: \$(?P<start>[0-9a-f]{4})-\$(?P<end>[0-9a-f]{4})")

# Below this many bytes between the deepest observed SP and the stack's low end,
# a post-KO or gameplay path is close enough to overflowing to fail the check.
MIN_SPARE_BYTES = 48


def stack_layout(map_path: Path) -> tuple[int, int]:
    """(gap_low, stack_low): the first unused byte below the stack, and the
    stack section's lowest byte. gap_low == stack_low when nothing is free."""
    previous = ""
    for line in map_path.read_text(encoding="utf-8").splitlines():
        section = SECTION_RE.match(line)
        if section:
            stack_low = int(section.group("start"), 16)
            empty = EMPTY_RE.match(previous)
            if empty and int(empty.group("end"), 16) + 1 == stack_low:
                return int(empty.group("start"), 16), stack_low
            return stack_low, stack_low
        previous = line
    raise ValueError(f'SECTION "Stack" not found in {map_path}')
