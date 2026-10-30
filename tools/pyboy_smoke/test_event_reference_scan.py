"""Reference scans ignore checkout-local scratch, not ancestor folder names."""
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gen_event_constants as events


class EventReferenceScanTest(unittest.TestCase):
    def test_tmp_ancestor_does_not_hide_real_scripts_or_admit_scratch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "tmp" / "checkout"
            for relative, event in [("scripts/Main.asm", "EVENT_KEEP"),
                                    ("constants/event_constants.asm", "EVENT_GENERATED")]:
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("SetEvent " + event)
            for relative in ("tmp", "builds", ".git", ".claude", "tools/pyboy_smoke"):
                path = root / relative / "Copy.asm"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("SetEvent EVENT_NOISE")
            with patch.object(events, "ROOT", str(root)), patch.object(
                    events, "OUT", str(root / "constants/event_constants.asm")):
                refs = events.scrape_refs(["EVENT_KEEP", "EVENT_GENERATED", "EVENT_NOISE"])
            self.assertEqual(dict(refs), {"EVENT_KEEP": {"scripts/Main.asm"}})

    def test_walk_never_descends_into_excluded_trees(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "scripts/Main.asm").write_text("SetEvent EVENT_KEEP")
            for relative in ("tmp/deep", "builds/snap", ".git/objects", ".claude/worktrees/a",
                             "tools/pyboy_smoke/sub"):
                path = root / relative
                path.mkdir(parents=True)
                (path / "Copy.asm").write_text("SetEvent EVENT_NOISE")
            visited = []
            real_walk = os.walk

            def recording_walk(top):
                for dirpath, dirnames, files in real_walk(top):
                    visited.append(os.path.relpath(dirpath, top).replace("\\", "/"))
                    yield dirpath, dirnames, files

            with patch.object(events, "ROOT", str(root)), patch.object(
                    events, "OUT", str(root / "constants/event_constants.asm")), patch.object(
                    events.os, "walk", recording_walk):
                events.scrape_refs(["EVENT_KEEP", "EVENT_NOISE"])
            excluded = {"tmp", "builds", ".git", ".claude", "pyboy_smoke"}
            self.assertIn("scripts", visited)
            for rel in visited:
                self.assertFalse(excluded & set(rel.split("/")), rel)
