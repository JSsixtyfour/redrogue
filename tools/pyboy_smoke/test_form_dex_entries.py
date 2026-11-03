"""Form Pokedex entries: format gate for Checkpoint E (no emulator needed).

data/pokemon/dex_form_entries.asm holds one entry per DEX_FORM_* identity, in id
order; descriptions live there or in any file it text_fars into. Rules (measured
2026-11-03 on the Pokedex page, which prints from column 1 next to a border at
column 19):
  - category: at most 10 characters
  - description lines: at most 18 tiles ('#' is the 4-tile "POKé"), at most 3
    lines per page, at most 2 pages (one `page`), ending in `dex`
  - height 0'00" .. 99'11", inches < 12; weight > 0 once an entry is real
  - no entry may reuse a base species' text (_<Species>DexEntry)
Placeholders (form_dex_pending) are allowed and reported; set
RR_FORM_DEX_COMPLETE=1 to require none (Checkpoint E's finish line).
"""
from pathlib import Path
import os
import re
import unittest

REPO = Path(__file__).resolve().parents[2]
ENTRIES = REPO / "data" / "pokemon" / "dex_form_entries.asm"
CATALOG = REPO / "data" / "pokemon" / "dex_forms.asm"
MAX_LINE, MAX_LINES_PER_PAGE, MAX_PAGES, MAX_CATEGORY = 18, 3, 2, 10


def rendered(text: str) -> int:
    return len(text.replace("#", "POKé"))


def text_blocks() -> dict[str, list[tuple[str, str]]]:
    """label -> [(command, string)] for every text block in the form text files."""
    blocks: dict[str, list[tuple[str, str]]] = {}
    files = [ENTRIES] + sorted((REPO / "data" / "pokemon").glob("dex_form_text*.asm"))
    for path in files:
        if not path.exists():
            continue
        label = None
        for line in path.read_text(encoding="utf-8").splitlines():
            m = re.match(r"^(_\w+)::?", line)
            if m:
                label = m.group(1)
                blocks[label] = []
                continue
            m = re.match(r'^\s*(text|next|line|cont|page|para)\s+"(.*)"', line)
            if m and label:
                blocks[label].append((m.group(1), m.group(2)))
            elif re.match(r"^\s*dex\b", line) and label:
                blocks[label].append(("dex", ""))
    return blocks


class FormDexEntriesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.source = ENTRIES.read_text(encoding="utf-8")
        self.ids = re.findall(r"^\s*dex_form\s+(DEX_FORM_\w+),", CATALOG.read_text(encoding="utf-8"), re.M)

    def entries(self) -> dict[str, str]:
        """entry label -> its body (up to the next label)."""
        out = {}
        for m in re.finditer(r"^(\w+FormDexEntry):[^\n]*\n(.*?)(?=^\w+:|\Z)", self.source, re.M | re.S):
            out[m.group(1)] = m.group(2)
        return out

    def test_pointer_table_has_one_entry_per_identity_in_order(self) -> None:
        table = self.source[self.source.index("FormDexEntryPointers:"):]
        pointers = re.findall(r"^\s*dw\s+(\w+)", table.split("assert_table_length")[0], re.M)
        self.assertEqual(len(pointers), len(self.ids))
        entries = self.entries()
        for pointer in pointers:
            self.assertIn(pointer, entries, pointer)

    def test_entry_fields_and_text_fit_the_page(self) -> None:
        blocks = text_blocks()
        pending = []
        for label, body in self.entries().items():
            if re.search(r"^\s*form_dex_pending\b", body, re.M):
                pending.append(label)
                continue
            with self.subTest(entry=label):
                category = re.search(r'^\s*db\s+"([^"]*)@"', body, re.M)
                self.assertIsNotNone(category, "category db \"...@\"")
                self.assertLessEqual(len(category.group(1)), MAX_CATEGORY, category.group(1))
                height = re.search(r"^\s*db\s+(\d+)\s*,\s*(\d+)", body, re.M)
                self.assertIsNotNone(height, "db feet, inches")
                self.assertLess(int(height.group(2)), 12, "inches")
                weight = re.search(r"^\s*dw\s+(\d+)", body, re.M)
                self.assertIsNotNone(weight, "dw weight (tenths of a pound)")
                self.assertGreater(int(weight.group(1)), 0)
                far = re.search(r"^\s*text_far\s+(\w+)", body, re.M)
                self.assertIsNotNone(far, "text_far")
                self.assertNotRegex(far.group(1), r"^_\w+(?<!Form)DexEntry$",
                                    "points at a base species' description")
                self.assertIn(far.group(1), blocks, "description label not found")
                commands = blocks[far.group(1)]
                self.assertEqual(commands[-1][0], "dex", "description must end with dex")
                pages, lines = 1, 0
                for command, string in commands[:-1]:
                    if command == "page":
                        pages, lines = pages + 1, 0
                    self.assertIn(command, ("text", "next", "page"), command)
                    lines += 1
                    self.assertLessEqual(rendered(string), MAX_LINE, string)
                    self.assertLessEqual(lines, MAX_LINES_PER_PAGE, f"page {pages}")
                self.assertLessEqual(pages, MAX_PAGES)
        print(f"\n{len(pending)} of {len(self.ids)} form Dex entries are still placeholders")
        if os.environ.get("RR_FORM_DEX_COMPLETE"):
            self.assertEqual(pending, [], "placeholders remain")


if __name__ == "__main__":
    unittest.main()
