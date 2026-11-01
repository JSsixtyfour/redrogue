"""Retained skip evidence must include the ID and every reason."""
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from run_smoke import WorkerResult


class SmokeReportingTest(unittest.TestCase):
    def test_skip_record_keeps_id_and_reason(self):
        class Example(unittest.TestCase):
            def runTest(self):
                self.skipTest('dependency intentionally unavailable')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'records.jsonl'
            with patch.object(WorkerResult, 'results_path', path, create=True), \
                    patch.object(WorkerResult, 'test_timeout_s', 10, create=True), \
                    patch('run_smoke.faulthandler.dump_traceback_later'), \
                    patch('run_smoke.faulthandler.cancel_dump_traceback_later'):
                unittest.TextTestRunner(stream=io.StringIO(), resultclass=WorkerResult).run(Example())
            record = json.loads(path.read_text())
            self.assertEqual(record['status'], 'skip')
            self.assertEqual(record['id'], Example().id())
            self.assertEqual(record['skip_reasons'], ['dependency intentionally unavailable'])

    def test_class_fixture_skip_expands_to_requested_cases(self):
        class Example(unittest.TestCase):
            @classmethod
            def setUpClass(cls):
                raise unittest.SkipTest('fixture unavailable')
            def test_first(self):
                self.fail('must not run')
            def test_second(self):
                self.fail('must not run')
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(Example)
        ids = [test.id() for test in suite]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'records.jsonl'
            with patch.object(WorkerResult, 'results_path', path, create=True), \
                    patch.object(WorkerResult, 'requested_ids', ids):
                result = unittest.TextTestRunner(stream=io.StringIO(), resultclass=WorkerResult).run(suite)
            self.assertTrue(result.wasSuccessful())
            records = [json.loads(line) for line in path.read_text().splitlines()]
            self.assertEqual([row['id'] for row in records], ids)
            self.assertTrue(all(row['status'] == 'skip' and row['skip_reasons'] ==
                                ['fixture unavailable'] for row in records))

    def test_later_subtest_skip_cannot_hide_a_real_failure(self):
        class Example(unittest.TestCase):
            def runTest(self):
                with self.subTest('violation'):
                    self.fail('real contract violation')
                with self.subTest('excluded'):
                    self.skipTest('expected exclusion')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'records.jsonl'
            with patch.object(WorkerResult, 'results_path', path, create=True), \
                    patch.object(WorkerResult, 'test_timeout_s', 10, create=True), \
                    patch('run_smoke.faulthandler.dump_traceback_later'), \
                    patch('run_smoke.faulthandler.cancel_dump_traceback_later'):
                result = unittest.TextTestRunner(stream=io.StringIO(), resultclass=WorkerResult).run(Example())
            self.assertFalse(result.wasSuccessful())
            record = json.loads(path.read_text())
            self.assertEqual(record['status'], 'fail')
            self.assertEqual(record['skip_reasons'], ['expected exclusion'])
