"""Exercise the real Makefile and scanner in a small isolated source tree.

Run after building tools/scan_includes: python3 tools/test_build_dependencies.py
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCES = (
    "audio", "home", "main", "maps", "ram", "text",
    "gfx/pics", "gfx/sprites", "gfx/tilesets",
)


class BuildDependenciesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write("Makefile", (ROOT / "Makefile").read_text())
        self.write("tools/Makefile", "all clean:\n\t@:\n")
        shutil.copy2(ROOT / "tools/scan_includes", self.root / "tools/scan_includes")
        for source in (*SOURCES, "includes", "rgbdscheck", "buildid"):
            self.write(source + ".asm", "; fixture\n")
        self.write("layout.link", "; fixture\n")
        self.write("main.asm", 'INCLUDE "nested.asm"\n')
        self.write("nested.asm", 'INCLUDE "leaf.asm"\nINCBIN "asset.bin"\n')
        self.write("leaf.asm", "; leaf\n")
        self.write("asset.bin", "asset")
        self.make("-n")  # GNU make generates included depfiles even with -n.
        for source in SOURCES:
            for suffix in ("red", "blue", "blue_debug", "red_vc", "blue_vc"):
                self.write(f"{source}_{suffix}.o", "object")
        self.write("rgbdscheck.o", "object")
        for rom in ("pokered", "pokeblue", "pokeblue_debug"):
            self.write(rom + ".gbc", "ROM")
        # A no-op must not invoke Git or date just to compute build identity.
        self.write("bin/git", '#!/bin/sh\necho git >> metadata_calls\necho fixture\n')
        self.write("bin/date", '#!/bin/sh\necho date >> metadata_calls\necho "2026-10-22 12 34 56"\n')
        for name in ("git", "date"):
            (self.root / "bin" / name).chmod(0o755)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def make(self, *args):
        env = dict(os.environ, PATH=str(self.root / "bin") + os.pathsep + os.environ["PATH"])
        return subprocess.run(
            ["make", "--no-print-directory", *args], cwd=self.root, env=env,
            check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=20,
        ).stdout

    def cache_times(self):
        return {p.relative_to(self.root): p.stat().st_mtime_ns
                for p in (self.root / ".deps").rglob("*.d")}

    def test_noop_preserves_cache_and_skips_metadata(self):
        before = self.cache_times()
        self.assertIn("Nothing to be done", self.make("-n"))
        self.assertEqual(before, self.cache_times())
        self.assertFalse((self.root / "metadata_calls").exists())

    def test_nested_addition_discovers_new_dependency(self):
        self.write("new_leaf.asm", "; new leaf\n")
        self.write("leaf.asm", 'INCLUDE "new_leaf.asm"\n')
        output = self.make("-n")
        self.assertIn("-o main_red.o main.asm", output)
        self.assertIn("-o main_blue_debug.o main.asm", output)
        self.assertNotIn("-o main_blue.o main.asm", output)
        self.assertIn("new_leaf.asm", (self.root / ".deps/main.d").read_text())

    def test_removed_include_does_not_leave_stale_prerequisite(self):
        self.write("nested.asm", 'INCBIN "asset.bin"\n')
        (self.root / "leaf.asm").unlink()
        self.make("-n")
        self.assertNotIn("leaf.asm", (self.root / ".deps/main.d").read_text())

    def test_preinclude_change_rebuilds_every_default_object(self):
        self.write("includes.asm", 'INCLUDE "constants.asm"\n')
        self.write("constants.asm", "; constants\n")
        output = self.make("-n")
        for source in SOURCES:
            self.assertIn(f"-o {source}_red.o {source}.asm", output)
            self.assertIn(f"-o {source}_blue_debug.o {source}.asm", output)

    def test_forced_nested_change_rebuilds_without_restart_loop(self):
        output = self.make("-n", "-W", "nested.asm")
        self.assertIn("-o main_red.o main.asm", output)

    def test_cached_dependencies_match_legacy_scanner(self):
        legacy = subprocess.check_output(
            [str(self.root / "tools/scan_includes"), "main.asm"],
            cwd=self.root, text=True,
        ).split()
        cached = self.make("dump", "--eval=dump:;@echo $(main.asm_deps)").split()
        self.assertEqual(legacy, cached)

    def test_incbin_change_rebuilds_objects_without_rescanning(self):
        before = self.cache_times()
        self.write("asset.bin", "changed asset")
        output = self.make("-n")
        self.assertIn("-o main_red.o main.asm", output)
        self.assertIn("-o main_blue_debug.o main.asm", output)
        self.assertEqual(before, self.cache_times())

    def test_new_graphics_dependency_runs_conversion(self):
        self.write("nested.asm", 'INCBIN "fixture.2bpp"\n')
        self.write("fixture.png", "image fixture")
        output = self.make("-n")
        self.assertIn("-o fixture.2bpp fixture.png", output)
        self.assertIn("-o main_red.o main.asm", output)

    def test_all_variants_share_one_metadata_snapshot(self):
        output = self.make("-n", "all_roms", "-W", "buildid.asm")
        self.assertIn("-o pokeblue_buildid.o", output)
        self.assertEqual((self.root / "metadata_calls").read_text().splitlines(),
                         ["date", "git", "git"])
        self.assertEqual(output.count("BUILD_DATE_TEXT=2026-10-22 12:34"), 3)
        self.assertEqual(output.count("BUILD_ID_TEXT=fixture"), 3)

    def test_tidy_removes_cached_dependencies(self):
        self.make("tidy")
        self.assertEqual(self.cache_times(), {})

    def test_release_skip_forwards_flag_with_other_release_arguments(self):
        output = self.make("-n", "release-skip", "RELEASE_ARGS=--dry-run")
        self.assertIn("python3 tools/release.py --dry-run --skip-prompts", output)

    def test_ordinary_release_still_prompts(self):
        output = self.make("-n", "release")
        self.assertIn("python3 tools/release.py", output)
        self.assertNotIn("--skip-prompts", output)

    def test_release_audit_does_not_build_or_scan_regular_blue(self):
        (self.root / "pokeblue.gbc").unlink()
        output = self.make("-n", "audit", "AUDIT_ROMS=pokered pokeblue_debug")
        self.assertIn("run_all.py --rom pokered --rom pokeblue_debug", output)
        self.assertNotIn("-o pokeblue.gbc", output)
        self.assertNotIn("--rom pokeblue ", output)
        self.assertIn("run_smoke.py --source-only", output)

    def test_full_audit_still_builds_and_scans_regular_blue(self):
        (self.root / "pokeblue.gbc").unlink()
        output = self.make("-n", "audit")
        self.assertIn("-o pokeblue.gbc", output)
        self.assertIn("run_all.py --rom pokered --rom pokeblue --rom pokeblue_debug", output)


if __name__ == "__main__":
    unittest.main()
