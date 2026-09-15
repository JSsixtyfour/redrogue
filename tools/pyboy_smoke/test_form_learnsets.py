import re
from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
FORM_EVOS_MOVES_DIR = REPO_ROOT / "data" / "pokemon" / "form_evos_moves"
CONSTANTS_FILE = REPO_ROOT / "constants" / "pokemon_data_constants.asm"


def _learndex_record_size() -> int:
    source = CONSTANTS_FILE.read_text()
    match = re.search(r"DEF\s+LEARNDEX_RECORD_SIZE\s+EQU\s+(\d+)", source)
    if not match:
        raise AssertionError("LEARNDEX_RECORD_SIZE not found in " + str(CONSTANTS_FILE))
    return int(match.group(1))


def _record_byte_count(source: str) -> int:
    total = 0
    for line in source.splitlines():
        line = line.split(";", 1)[0]  # strip comments before counting operands
        stripped = line.strip()
        if not re.match(r"db\b", stripped):
            continue
        operands = stripped[len("db"):]
        total += len([o for o in operands.split(",") if o.strip()])
    return total


class FormLearnsetRecordSizeTest(unittest.TestCase):
    # Guards the hand-edits Form Learnsets Phase 3 invites: LearndexLoadRecordFar
    # (engine/pokemon/get_levelup_moves.asm) copies a fixed LEARNDEX_RECORD_SIZE
    # window regardless of a record's real length. Every form record must fit
    # inside that window or the copy spills into the next record / link padding.
    def test_every_form_record_fits_learndex_record_size(self) -> None:
        limit = _learndex_record_size()
        files = sorted(FORM_EVOS_MOVES_DIR.glob("*.asm"))
        self.assertTrue(files, "no form_evos_moves records found")

        for path in files:
            size = _record_byte_count(path.read_text())
            self.assertLessEqual(
                size,
                limit,
                f"{path.name} is {size} bytes, over LEARNDEX_RECORD_SIZE ({limit})",
            )


class LearndexLevelUpTutorAsymmetryTest(unittest.TestCase):
    # The asymmetry is deliberate (see LearndexPrepareLevelUpWalk's header
    # comment in status_view.asm): the level-up view must be form-aware and the
    # tutor view must stay species-keyed, because form records carry no tutor
    # block. A future "unification" of the two callers would silently break the
    # tutor bound (LearndexPrepareTutorWalk's next-record comparison assumes
    # every record it walks is a real, table-indexed species record).
    def test_levelup_walk_is_far_and_tutor_walk_is_not(self) -> None:
        source = (REPO_ROOT / "engine" / "pokemon" / "status_view.asm").read_text()

        levelup_start = source.index("LearndexPrepareLevelUpWalk:")
        levelup_end = source.index("\nLearndexCountLevelUpEntries:", levelup_start)
        levelup_walk = source[levelup_start:levelup_end]

        tutor_start = source.index("LearndexPrepareTutorWalk:")
        tutor_end = source.index("\nLearndexCountTutorEntries:", tutor_start)
        tutor_walk = source[tutor_start:tutor_end]

        self.assertIn("farcall LearndexLoadRecordFar", levelup_walk)
        self.assertNotIn("call LearndexLoadRecord\n", levelup_walk)

        self.assertIn("call LearndexLoadRecord\n", tutor_walk)
        self.assertNotIn("LearndexLoadRecordFar", tutor_walk)


if __name__ == "__main__":
    unittest.main()
