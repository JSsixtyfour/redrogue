from __future__ import annotations

from pathlib import Path
import argparse
import fnmatch
import os
import sys
import unittest


class HardwareModeResult(unittest.TextTestResult):
    """Classify test modules before setUp constructs their PyBoy harness."""

    def startTest(self, test):
        module_name = test.id().split(".", 1)[0]
        os.environ["REDROGUE_PYBOY_EXPECTED_MODE"] = (
            "CGB" if module_name.startswith("test_cgb_") else "DMG"
        )
        super().startTest(test)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Red Rogue PyBoy smoke tests")
    parser.add_argument(
        "--test", action="append", default=[], metavar="PATTERN",
        help="run test IDs matching a shell-style pattern; may be repeated",
    )
    parser.add_argument("--list", action="store_true", help="list selected test IDs")
    args = parser.parse_args()
    suite_dir = Path(__file__).resolve().parent
    sys.path.insert(0, str(suite_dir))
    suite = unittest.defaultTestLoader.discover(
        str(suite_dir), pattern="test_*.py", top_level_dir=str(suite_dir)
    )
    tests = list(iter_tests(suite))
    if args.test:
        tests = [
            test for test in tests
            if any(fnmatch.fnmatchcase(test.id(), pattern) for pattern in args.test)
        ]
        if not tests:
            parser.error(f"no tests matched: {', '.join(args.test)}")
    if args.list:
        for test in tests:
            print(test.id())
        return 0
    suite = unittest.TestSuite(tests)
    result = unittest.TextTestRunner(
        verbosity=2, resultclass=HardwareModeResult
    ).run(suite)
    return 0 if result.wasSuccessful() else 1


def iter_tests(suite):
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            yield from iter_tests(test)
        else:
            yield test


if __name__ == "__main__":
    raise SystemExit(main())
