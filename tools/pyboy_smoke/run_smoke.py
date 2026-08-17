from __future__ import annotations

from pathlib import Path
import sys
import unittest


def main() -> int:
    suite_dir = Path(__file__).resolve().parent
    sys.path.insert(0, str(suite_dir))
    suite = unittest.defaultTestLoader.discover(
        str(suite_dir), pattern="test_*.py", top_level_dir=str(suite_dir)
    )
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
