"""PC Move Tutor list must come from the species' OWN tutor block (2026-10-20).

A record in data/pokemon/evos_moves.asm is: evolutions, db 0; level-up
learnset, db 0; then an OPTIONAL tutor list, db 0. PrepareMoveTutorList skips
the first two sections by scanning for their zero terminators and then reads
tutor entries until the next zero, with no notion of where its own record
ends. 106 records had no tutor section at all, so the walk ran on into the
NEXT record: `db EVOLVE_LEVEL, 18, CROCONAW` read as "level 1, move 18" and
offered Typhlosion WHIRLWIND. LearndexPrepareTutorWalk had already guarded the
dex view against the same landmine (LEARNDEX_DESIGN.md); the real tutor did not.

This drives the real routine for every species index and compares the offered
list with the tutor section parsed from that species' own source record.
"""
from __future__ import annotations

import re
import unittest

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

MOVES = parse_rgbds_constants(REPO_ROOT / "constants" / "move_constants.asm")
EVOS_MOVES = REPO_ROOT / "data" / "pokemon" / "evos_moves.asm"
PARTY_LEVEL = 100  # every tutor entry is level 2, so a high level offers all of them


def parse_records() -> tuple[list[str], dict[str, list[str] | None]]:
    """Return (pointer table labels in species order, label -> tutor moves).

    A record with no tutor section maps to None; one with an empty tutor
    section (a bare third `db 0`) maps to [].
    """
    text = EVOS_MOVES.read_text(encoding="utf-8")
    table: list[str] = []
    records: dict[str, list[str] | None] = {}
    complete: set[str] = set()
    in_table = False
    current: str | None = None
    zeros = 0
    for raw in text.splitlines():
        code = raw.split(";", 1)[0].strip()
        if code.startswith("EvosMovesPointerTable:"):
            in_table = True
            continue
        label = re.match(r"^(\w+EvosMoves):", code)
        if label:
            in_table = False
            current = label.group(1)
            records[current] = None
            zeros = 0
            continue
        if in_table:
            ptr = re.match(r"^dw\s+(\w+)", code)
            if ptr:
                table.append(ptr.group(1))
            continue
        if current is None or not code.startswith("db"):
            continue
        if re.fullmatch(r"db\s+0", code):
            zeros += 1
            if zeros == 2:
                records[current] = []
            elif zeros == 3:
                complete.add(current)
                current = None  # record complete; ignore anything until the next label
            continue
        if zeros == 2:
            entry = re.fullmatch(r"db\s+(\d+)\s*,\s*(\w+)", code)
            assert entry, f"unparsed tutor entry in {current}: {code!r}"
            if int(entry.group(1)) <= PARTY_LEVEL:
                tutor = records[current]
                assert tutor is not None
                tutor.append(entry.group(2))
    # The tutor list only exists once its own terminator is seen; two zeros
    # alone are what the bug looked like.
    for label in records:
        if label not in complete:
            records[label] = None
    return table, records


class MoveTutorListBoundsTest(HarnessTestCase):
    def test_every_species_reads_only_its_own_tutor_block(self) -> None:
        table, records = parse_records()
        self.assertGreater(len(table), 150, "pointer table parse failed")
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        for move_slot in range(4):
            h.write8("wPartyMon1Moves", 0, offset=move_slot)
        h.write8("wPartyMon1Level", PARTY_LEVEL)
        h.write8("hWhichPokemon", 0)

        wrong: list[str] = []
        for index, label in enumerate(table):
            species = index + 1
            expected_names = records[label] or []
            expected = [MOVES[name] for name in expected_names]
            h.write8("wPartySpecies", species)
            h.call_routine("PrepareMoveTutorList")
            count = h.read8("wMoveBuffer")
            offered = [h.read8("wMoveBuffer", offset=1 + i) for i in range(min(count, 40))]
            if offered != expected:
                names = {v: k for k, v in MOVES.items()}
                wrong.append(
                    f"{label[:-len('EvosMoves')]} (species ${species:02x}): offered "
                    f"{[names.get(m, f'${m:02x}') for m in offered]}, "
                    f"its own block has {expected_names}"
                )
        self.assertEqual(wrong, [], f"{len(wrong)} species offered the wrong tutor list:\n  "
                         + "\n  ".join(wrong))

    def test_every_record_has_a_tutor_section(self) -> None:
        """Source guard: a record without its third `db 0` reads the next record."""
        table, records = parse_records()
        missing = sorted({label for label in table if records.get(label) is None})
        self.assertEqual(missing, [], "records with no tutor section (add a bare `db 0`): "
                         + ", ".join(missing))


if __name__ == "__main__":
    unittest.main()
