import re
from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
FORM_EVOS_MOVES_DIR = REPO_ROOT / "data" / "pokemon" / "form_evos_moves"
CONSTANTS_FILE = REPO_ROOT / "constants" / "pokemon_data_constants.asm"
WRAM_FILE = REPO_ROOT / "ram" / "wram.asm"
FUNC_FUSION_FILE = REPO_ROOT / "custom_functions" / "func_fusion.asm"
EXP_BAR_FILE = REPO_ROOT / "engine" / "battle" / "exp_bar.asm"


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


class FusionSecondaryFormByteTest(unittest.TestCase):
    # wFusionSecondaryForm must live inside wGameProgressFlags..wGameProgressFlagsEnd
    # to get SAVED (a fusion persists across saves) and run-boundary CLEARED
    # (the FillMemory in custom_functions/credit_popup.asm) for free. See
    # ram/wram.asm's own comment above the declaration.
    def test_fusion_secondary_form_byte_is_inside_game_progress_flags(self) -> None:
        source = WRAM_FILE.read_text()

        start = source.index("wGameProgressFlags::")
        end = source.index("wGameProgressFlagsEnd::", start)
        span = source[start:end]

        self.assertIn("wFusionSecondaryForm:: db", span)


class FusionSecondaryFormContextPublishTest(unittest.TestCase):
    # The secondary mon is released from the party at fusion creation, so
    # every later consumer of its attributes (base stats, front pic, back
    # pic) must publish (wFusionSecondarySpecies, wFusionSecondaryForm) via
    # PublishFusionSecondaryFormContext before it calls GetMonHeader - a bare
    # GetMonHeader falls back to the base species' row and silently drops the
    # secondary's form (type, stats, front/back pic all come from the row).
    def _routine(self, source: str, name: str, next_name: str) -> str:
        start = source.index(name + "::")
        end = source.index("\n" + next_name, start)
        return source[start:end]

    def test_post_creation_consumers_publish_before_get_mon_header(self) -> None:
        source = FUNC_FUSION_FILE.read_text()

        routines = [
            ("CacheFusionSecondaryBaseStats", "PrepareFusionCalcStats"),
            ("PreloadFusionSecondaryPic", "OverlayFusionSecondaryPic"),
        ]
        for name, next_name in routines:
            body = self._routine(source, name, next_name)
            publish_at = body.index("call PublishFusionSecondaryFormContext")
            header_at = body.index("call GetMonHeader")
            self.assertLess(
                publish_at,
                header_at,
                f"{name} must call PublishFusionSecondaryFormContext before GetMonHeader",
            )

        # MergeFusionBackPic runs to end of file, so slice by GetMonHeader
        # count instead of a following label.
        merge_start = source.index("MergeFusionBackPic::")
        merge_body = source[merge_start:]
        publish_at = merge_body.index("call PublishFusionSecondaryFormContext")
        header_at = merge_body.index("call GetMonHeader")
        self.assertLess(
            publish_at,
            header_at,
            "MergeFusionBackPic must call PublishFusionSecondaryFormContext before GetMonHeader",
        )


class ExpBarFormContextPublishTest(unittest.TestCase):
    # CalcEXPBarPixelLength loads a struct's species into wCurSpecies from
    # either the battler or the active party mon, both of which may carry a
    # form. Without publishing first, GetMonHeader can strip that form when
    # the previously loaded header was a different species.
    def test_calc_exp_bar_pixel_length_publishes_before_get_mon_header(self) -> None:
        source = EXP_BAR_FILE.read_text()

        start = source.index("CalcEXPBarPixelLength:")
        end = source.index("\nCalcAndLoadExpBarDynamicTile::", start)
        body = source[start:end]

        publish_at = body.index("call PublishFormContext")
        header_at = body.index("call GetMonHeader")
        self.assertLess(
            publish_at,
            header_at,
            "CalcEXPBarPixelLength must call PublishFormContext before GetMonHeader",
        )


if __name__ == "__main__":
    unittest.main()
