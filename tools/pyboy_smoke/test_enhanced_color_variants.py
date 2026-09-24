"""Source contracts for the Forest/Facility/Mansion CGB palettes (2B, 2026-09-22).

Wires sProcForestPalette and sProcFacilityPalette onto the Enhanced Colours
(CGB) path in custom_functions/func_enhancedcolor.asm, following the same
six-part pattern the Cave already used. These do not run the ROM - the
enhanced path is only reachable with cgb_mode=True (CLAUDE.md), so the actual
on-screen colours are a hardware/BGB screenshot pass, not a harness check.
What IS checkable here is that the wiring is the shape the plan specifies:
one roll per stage, both new base-set tables sized to their PAL_COUNT
constants, and the resolver actually reaching every new branch.
"""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
ENHANCED_COLOR = REPO_ROOT / "custom_functions" / "func_enhancedcolor.asm"
PALETTE_CONSTANTS = REPO_ROOT / "constants" / "palette_constants.asm"
FOREST_GEN = REPO_ROOT / "custom_functions" / "procedural_forest_gen.asm"
FACILITY_GEN = REPO_ROOT / "custom_functions" / "procedural_facility_gen.asm"
SGB_PALETTES = REPO_ROOT / "data" / "sgb" / "sgb_palettes.asm"
CGB_PALETTES = REPO_ROOT / "data" / "gfx" / "cgb_palettes.asm"
SGB_PATH = REPO_ROOT / "engine" / "gfx" / "palettes.asm"

SPRING_ROW = [(28, 31, 26), (25, 14, 14), (27, 16, 16), (6, 0, 0)]
FALL_ROW = [(28, 31, 26), (25, 15, 0), (31, 10, 3), (6, 0, 0)]


def enh_source() -> str:
    return ENHANCED_COLOR.read_text()


def const(name: str, path: Path = PALETTE_CONSTANTS) -> int:
    m = re.search(r"^DEF %s\s+EQU\s+(\d+)" % re.escape(name), path.read_text(), re.M)
    if m is None:
        raise AssertionError("no DEF %s" % name)
    return int(m.group(1))


def routine(label: str, end: str | None = None) -> str:
    src = enh_source()
    start = src.index(label)
    rest = src[start + len(label):]
    if end is not None:
        rest = rest[:rest.index(end)]
    else:
        m = re.search(r"\n(?=[A-Za-z_.][A-Za-z0-9_]*::?\s*$)", rest, re.M)
        rest = rest[:m.start()] if m else rest
    return rest


class ForestRollTest(unittest.TestCase):
    def test_forest_palette_is_rolled_not_forced(self) -> None:
        src = FOREST_GEN.read_text()
        write = "ld [sProcForestPalette], a"
        self.assertIn(write, src)
        preceding = src[:src.index(write)]
        # The roll (`call Random` / `and 1`) must be the last thing before the
        # write, not a leftover `xor a` forcing variant 0 every visit.
        window = preceding[-120:]
        self.assertIn("call Random", window)
        self.assertIn("and 1", window)
        self.assertNotIn("xor a", window)

    def test_forest_palette_is_written_exactly_once(self) -> None:
        self.assertEqual(
            FOREST_GEN.read_text().count("ld [sProcForestPalette], a"), 1,
            "a second writer would break 'stable for the whole visit'")


class FacilityRollUnchangedTest(unittest.TestCase):
    def test_facility_palette_still_written_exactly_once(self) -> None:
        # 2B only adds a CGB reader for the existing roll; the roll itself
        # (and its SGB reader) predate this change and must not move.
        self.assertEqual(
            FACILITY_GEN.read_text().count("ld [sProcFacilityPalette], a"), 1)


class BaseSetTableTest(unittest.TestCase):
    def test_enh_base_set_count_matches_the_pointer_table(self) -> None:
        src = enh_source()
        start = src.index("EnhBasePalSetPointers:")
        end = src.index("EnhBasePalSetPointers_End:")
        rows = src[start:end].count("\tdw ")
        self.assertEqual(rows, const("ENH_BASE_SET_COUNT", ENHANCED_COLOR))

    def test_forest_and_facility_sets_are_registered(self) -> None:
        src = enh_source()
        for name in ("ENH_BASE_FOREST_SPRING", "ENH_BASE_FOREST_FALL",
                      "ENH_BASE_FACILITY_RED"):
            with self.subTest(name):
                self.assertIn(name, src)

    def test_proc_forest_pal_sets_matches_its_count(self) -> None:
        src = enh_source()
        start = src.index("ProcForestPalSets:")
        end = src.index("ProcForestPalSets_End:")
        rows = src[start:end].count("\tdb ")
        self.assertEqual(rows, const("PROC_FOREST_PAL_COUNT"))

    def test_proc_facility_pal_sets_matches_its_count(self) -> None:
        src = enh_source()
        start = src.index("ProcFacilityPalSets:")
        end = src.index("ProcFacilityPalSets_End:")
        rows = src[start:end].count("\tdb ")
        self.assertEqual(rows, const("PROC_FACILITY_PAL_COUNT"))

    def test_facility_variant_0_is_the_plain_default_set(self) -> None:
        """The plan's 'default' Facility variant needs no new authored set."""
        src = enh_source()
        start = src.index("ProcFacilityPalSets:")
        end = src.index("ProcFacilityPalSets_End:")
        first_row = src[start:end].split("\n")[1]
        self.assertIn("ENH_BASE_DEFAULT", first_row)


class ResolverDispatchTest(unittest.TestCase):
    def setUp(self) -> None:
        self.body = routine("ResolveEnhancedBasePalSet::", end="ReadProcPaletteVariant:")

    def test_forest_and_facility_and_mansion_are_all_reachable(self) -> None:
        for label in (".procForest", ".procFacility", ".mansion"):
            with self.subTest(label):
                self.assertIn(label, self.body)

    def test_mansion_uses_four_explicit_compares(self) -> None:
        """Map IDs are not contiguous ($A5, then $D6-$D8) - no range check."""
        mansion_maps = ("POKEMON_MANSION_1F", "POKEMON_MANSION_2F",
                         "POKEMON_MANSION_3F", "POKEMON_MANSION_B1F")
        for name in mansion_maps:
            with self.subTest(name):
                self.assertIn("cp %s\n\tjr z, .mansion" % name, self.body)

    def test_mansion_selects_the_facility_red_set_directly_no_roll(self) -> None:
        mansion_block = self.body[self.body.index("\n.mansion\n"):]
        # Must set b and jump to .store WITHOUT going through
        # ReadProcPaletteVariant - Mansion is not a rolled stage.
        before_next_label = mansion_block[:mansion_block.index("\n\n", 1)]
        self.assertIn("ENH_BASE_FACILITY_RED", before_next_label)
        self.assertNotIn("ReadProcPaletteVariant", before_next_label)

    def test_forest_and_facility_read_their_own_sram_bytes(self) -> None:
        forest_block = self.body[self.body.index("\n.procForest\n"):
                                  self.body.index("\n.procFacility\n")]
        self.assertIn("sProcForestPalette", forest_block)
        self.assertIn("PROC_FOREST_PAL_COUNT", forest_block)
        facility_block = self.body[self.body.index("\n.procFacility\n"):]
        self.assertIn("sProcFacilityPalette", facility_block)
        self.assertIn("PROC_FACILITY_PAL_COUNT", facility_block)


class SgbForestSeasonMirrorTest(unittest.TestCase):
    """2B's follow-up: the user supplied real colours, so the SGB/DMG and
    CGB-non-enhanced paths (which share one PAL_* table pair) now show the
    season too, not just CGB Enhanced Colours.
    """

    def test_forest_pal_aliases_claim_the_two_spare_rows(self) -> None:
        src = PALETTE_CONSTANTS.read_text()
        self.assertIn("DEF PAL_FOREST_SPRING EQU PAL_25", src)
        self.assertIn("DEF PAL_FOREST_FALL   EQU PAL_27", src)

    def _sgb_row(self, path: Path, comment_fragment: str) -> list[tuple[int, int, int]]:
        for line in path.read_text().splitlines():
            if comment_fragment in line and ("RGB" in line):
                nums = [int(x) for x in re.findall(r"\d+", line.split(";")[0])]
                self.assertEqual(len(nums), 12, "expected 4 RGB triples: %s" % line)
                return [tuple(nums[i:i + 3]) for i in range(0, 12, 3)]
        self.fail("no row found in %s matching %r" % (path, comment_fragment))

    def test_sgb_palettes_row_matches_the_supplied_colours(self) -> None:
        self.assertEqual(self._sgb_row(SGB_PALETTES, "PAL_25"), SPRING_ROW)
        self.assertEqual(self._sgb_row(SGB_PALETTES, "PAL_27"), FALL_ROW)

    def _cgb_row(self, comment_fragment: str) -> list[tuple[int, int, int]]:
        src = CGB_PALETTES.read_text()
        start = src.index(comment_fragment)
        block = src[start:start + 400]
        rgbs = re.findall(r"RGB\s+(\d+),\s*(\d+),\s*(\d+)", block)[:4]
        return [tuple(int(x) for x in triple) for triple in rgbs]

    def test_cgb_palettes_row_is_paired_with_sgb_palettes(self) -> None:
        """The file's own header warns these two tables have no ASSERT tying
        them together and can silently desync - check both explicitly."""
        self.assertEqual(self._cgb_row("PAL_25"), SPRING_ROW)
        self.assertEqual(self._cgb_row("PAL_27"), FALL_ROW)

    def test_sgb_path_dispatches_forest_through_the_function_table(self) -> None:
        """2026-09-24: SetPal_Overworld's compare chain (whose .procForest stub
        had to stay short to keep .Lorelei in jr range) became the table-driven
        GetOverworldPalette. The forest is now one MapPaletteFunctions row."""
        src = SGB_PATH.read_text()
        table = src[src.index("\nMapPaletteFunctions:\n"):src.index("\nMapPalettes:\n")]
        self.assertRegex(table, r"db PROCEDURAL_FOREST\s*\n\s*dw ProcForestOverworldPalette")
        self.assertNotIn("sProcForestPalette", table)

    def test_procforestvariant_reads_the_same_byte_the_cgb_path_reads(self) -> None:
        src = SGB_PATH.read_text()
        start = src.index("\nProcForestOverworldPalette:\n")
        end = src.index("\nProcFacilityOverworldPalette:\n")
        body = src[start:end]
        self.assertIn("sProcForestPalette", body)
        self.assertIn("PROC_FOREST_PAL_COUNT", body)
        self.assertIn("PAL_FOREST_SPRING", body)
        self.assertIn("PAL_FOREST_FALL", body)
        self.assertIn("PAL_VIRIDIAN", body, "out-of-range must still fall back safely")


if __name__ == "__main__":
    unittest.main()
