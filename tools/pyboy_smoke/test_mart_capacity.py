"""Real menu transactions conserve resources at count-pocket capacity."""
from pathlib import Path
import tempfile
import unittest

import purchase_scenario


class MartCapacityTest(unittest.TestCase):
    def check_transaction(self, scenario, before_count, after_count, after_money):
        with tempfile.TemporaryDirectory() as temporary:
            record = purchase_scenario.run_one(7, scenario, Path(temporary) / scenario)
            self.assertEqual(record['execution'], 'completed', record.get('detail'))
            slot = record['potion_slot']
            self.assertEqual(record['before']['items'][slot], before_count)
            self.assertEqual(record['actual_after']['items'][slot], after_count)
            self.assertEqual(record['actual_after']['money'], after_money)
            self.assertEqual(record['actual_after']['party'], record['before']['party'])
            self.assertEqual(record['findings'], [])

    def test_full_pocket_refuses_payment(self):
        self.check_transaction('capacity_full', 99, 99, 1000)

    def test_oversized_request_refuses_the_whole_transaction(self):
        self.check_transaction('capacity_partial', 98, 98, 1000)

    def test_exact_remaining_capacity_succeeds(self):
        self.check_transaction('capacity_exact', 96, 99, 400)
