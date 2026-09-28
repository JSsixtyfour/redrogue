from __future__ import annotations

from pathlib import Path
import argparse
import fnmatch
import os
import sys
import time
import unittest


SLOWEST_SHOWN = 10


class HardwareModeResult(unittest.TextTestResult):
    """Classify test modules before setUp constructs their PyBoy harness."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.durations_s: list[tuple[float, str]] = []

    def startTest(self, test):
        module_name = test.id().split(".", 1)[0]
        os.environ["REDROGUE_PYBOY_EXPECTED_MODE"] = (
            "CGB" if module_name.startswith("test_cgb_") else "DMG"
        )
        self._started_at = time.perf_counter()
        super().startTest(test)

    def stopTest(self, test):
        super().stopTest(test)
        self.durations_s.append((time.perf_counter() - self._started_at, test.id()))


def print_slowest(result: HardwareModeResult) -> None:
    """Surface smoke-time creep before the whole suite starts to look hung."""
    if not result.durations_s:
        return
    total = sum(seconds for seconds, _ in result.durations_s)
    print(f"\nSlowest {min(SLOWEST_SHOWN, len(result.durations_s))} tests "
          f"(suite total {total:.1f}s):")
    for seconds, test_id in sorted(result.durations_s, reverse=True)[:SLOWEST_SHOWN]:
        print(f"  {seconds:7.2f}s  {test_id}")


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
    print_slowest(result)
    return 0 if result.wasSuccessful() else 1


def iter_tests(suite):
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            yield from iter_tests(test)
        else:
            yield test


if __name__ == "__main__":
    raise SystemExit(main())
