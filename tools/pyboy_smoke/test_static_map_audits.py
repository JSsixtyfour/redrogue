"""Static map audits, run as part of `make smoke`. No emulator.

Both scripts guard defects that never crash and never warn, so they were only found in play:
- audit_map_text_id_slots.py --scope all: a script-fired text id <= wNumSprites is rerouted
  by DisplayTextID to another object's text (SS Anne B1F, Route 24, Viridian Forest).
- audit_map_object_const_order.py: a map's object consts out of order with its objects, so a
  toggle row keyed on one hides the wrong slot (SS Anne B1F's captain).
Each script's docstring has the details and its negative control.
"""

import subprocess
import sys
import unittest
from pathlib import Path

SUITE_DIR = Path(__file__).resolve().parent


def run_audit(*args):
    return subprocess.run(
        [sys.executable, str(SUITE_DIR / args[0]), *args[1:]],
        capture_output=True, text=True, timeout=120,
    )


class StaticMapAuditTest(unittest.TestCase):
    def assertAuditPasses(self, *args):
        result = run_audit(*args)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_no_script_fired_text_id_is_rerouted(self):
        self.assertAuditPasses("audit_map_text_id_slots.py", "--scope", "all")

    def test_object_consts_match_object_slots(self):
        self.assertAuditPasses("audit_map_object_const_order.py")


if __name__ == "__main__":
    unittest.main()
