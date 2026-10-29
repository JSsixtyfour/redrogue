"""Invocation health must preserve return values and propagate failures."""
import unittest
import json
from pathlib import Path
import tempfile
from detector_health import assess, validate_requirements, collect
from unittest.mock import patch
import run_campaign as campaign
import queue
import run_autoplay
from autoplay_checks import observed_check


class Probe:
    def __init__(self):
        self.detector_health = {}

    @observed_check
    def check(self, fail=False):
        if fail:
            raise ValueError("injected detector error")
        return 7


class DetectorHealthTest(unittest.TestCase):
    def test_early_worker_failure_keeps_phase_without_normal_report(self):
        import autoplay
        def broken(seed, **options):
            options['phase_callback']('detector_initialization')
            raise RuntimeError('controlled initialization fault')
        with tempfile.TemporaryDirectory() as temporary, \
                patch.object(autoplay, 'ARTIFACTS', Path(temporary)), \
                patch.object(autoplay, 'play', side_effect=broken):
            results = queue.Queue()
            run_autoplay._worker(7, {}, results)
            row = results.get()[1]
            self.assertEqual(row['outcome'], 'error')
            self.assertIsNone(row['report'])
            context = json.loads(next(Path(temporary).glob('*.detectors.json')).read_text())
            self.assertEqual((context['phase'], context['status'], context['detector_acceptance']),
                             ('detector_initialization', 'error', 'unverified'))

    def test_nested_requirements_apply_to_every_repeat_without_exposure_multiplication(self):
        from test_sram_matched import fixture, CASE
        import sram_fuzz
        with tempfile.TemporaryDirectory() as temporary:
            raw = fixture(Path(temporary))
            raw['initialization_comparisons'] = [sram_fuzz.evaluate_matched_pair(raw['expected_comparisons'][0], raw['records'])]
            raw['comparison_errors'] = []
            normalized = campaign.normalize_summary(CASE, raw)
            self.assertEqual(normalized['runs'][0]['sram_fills'], 1)
            for record in raw['records']:
                path = Path(record['directory']) / 'report.json'
                data = json.loads(path.read_text())
                data['checks'] = {'detector_health': {'check_world':
                    {'enabled': True, 'status': 'observed', 'attempted': 1, 'returned': 1, 'errors': 0}}}
                path.write_text(json.dumps(data))
            case = {**CASE, 'required_detectors': {'check_world': 1}}
            self.assertEqual(len(assess(case, normalized)), 6)
            self.assertTrue(all(row['status'] == 'requirements_met' for row in assess(case, normalized)))
            path.write_text('{}')
            health = assess(case, normalized)
            self.assertEqual(sum(row['status'] == 'incomplete' for row in health), 1)
            self.assertIn('repetition', health[-1])

    def test_nested_report_cannot_escape_attempt(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'artifacts').mkdir()
            report = root / 'outside.json'
            report.write_text('{}')
            with self.assertRaisesRegex(ValueError, 'outside attempt'):
                campaign.evidence_inventory(root, {'runs': [{'seed': 1, 'detector_reports': [{'report': str(report)}]}]})

    def test_matched_repetitions_cannot_share_a_directory(self):
        from test_sram_matched import fixture, CASE
        with tempfile.TemporaryDirectory() as temporary:
            raw = fixture(Path(temporary))
            raw['initialization_comparisons'] = []
            raw['expected_fills'][1]['directory'] = raw['expected_fills'][0]['directory']
            with self.assertRaisesRegex(ValueError, 'share an evidence directory'):
                campaign.normalize_summary(CASE, raw)

    def test_global_ledger_keeps_disabled_skipped_and_unavailable_distinct(self):
        data = {'hardware_mode': 'DMG', 'screen_checks': {'samples': 0, 'skipped': 2,
                'pointer_calls': {'glyph': 3}, 'code_rules_available': False}, 'hook_errors': []}
        ledger = collect(data, {'branches': True, 'coverage': False})['detectors']
        self.assertEqual(ledger['cgb_palette']['status'], 'disabled')
        self.assertEqual(ledger['screen_code_rules']['status'], 'unavailable')
        self.assertEqual(ledger['screen_pointers']['observations'], 3)
        self.assertEqual(ledger['branches']['status'], 'unavailable')
        self.assertEqual(ledger['coverage']['status'], 'disabled')
        data['hardware_mode'] = 'CGB'
        self.assertEqual(collect(data, {})['detectors']['cgb_palette']['status'], 'skipped')

    def test_global_ledger_recomputation_rejects_stale_clean_and_counter_spoofing(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'report.json'
            data = {'hardware_mode': 'CGB', 'screen_checks': {'samples': 1, 'skipped': 0},
                    'hook_errors': [], 'detector_configuration': {}}
            data['detector_ledger'] = collect(data, {})
            path.write_text(json.dumps(data))
            case = {'required_detectors': {'cgb_palette': 1}}
            summary = {'runs': [{'seed': 1, 'report': str(path)}]}
            self.assertEqual(assess(case, summary)[0]['status'], 'requirements_met')
            data['screen_checks']['samples'] = 0
            path.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, 'differs'):
                assess(case, summary)
            data['screen_checks']['samples'] = True
            with self.assertRaises(ValueError):
                collect(data, {})

    def test_global_hook_error_blocks_health_without_requirements(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'report.json'
            data = {'hook_errors': ['injected observer failure'], 'detector_configuration': {}}
            data['detector_ledger'] = collect(data, {})
            path.write_text(json.dumps(data))
            self.assertEqual(assess({}, {'runs': [{'seed': 1, 'report': str(path)}]})[0]['status'], 'error')

    def test_required_schema_cannot_fall_back_to_legacy_health(self):
        with self.assertRaisesRegex(ValueError, 'ledger missing'):
            assess({'required_detector_schema': 1}, {'runs': [{'seed': 1}]})

    def test_branch_records_and_coverage_have_independent_health(self):
        count = {'attempted': 1, 'returned': 1, 'errors': 0}
        data = {'branches': {'totals': {'lobby': {'branches': 1}}, 'detector_records': [
            {'key': 'one', 'outcome': 'ok', 'detector_health': {'after_step': count}, 'hook_errors': []}]},
            'coverage': {'requested': 3, 'hit': ['a', 'a'], 'skipped': ['b']}}
        ledger = collect(data, {'branches': True, 'coverage': True})['detectors']
        self.assertEqual(ledger['branches']['observations'], 1)
        self.assertEqual(ledger['coverage']['observations'], 1)
        data['branches']['detector_records'][0]['outcome'] = 'error'
        self.assertEqual(collect(data, {'branches': True})['detectors']['branches']['status'], 'error')
        data['branches']['detector_records'] = []
        with self.assertRaisesRegex(ValueError, 'missing branch'):
            collect(data, {'branches': True})

    def test_controller_blocks_missing_required_detector_and_expected_control(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runner = root / 'worker.py'
            runner.write_text("import json,os\nfrom pathlib import Path\n"
                              "p=Path(os.environ['REDROGUE_AUTOPLAY_ARTIFACTS'])\n"
                              "(p/'autoplay_summary.json').write_text(json.dumps({'runs':[{'seed':1,'outcome':'completed'}]}))\n")
            case = {'id': 'required', 'args': ['--seeds', '1'], 'required_detectors': {'check_world': 1}}
            with patch.object(campaign, 'RUNNER', runner):
                result = campaign.execute_case(case, root / 'case', 10)
            self.assertEqual(result['verdict'], 'incomplete')
            self.assertEqual(result['detector_health'][0]['missing']['check_world']['status'], 'unavailable')
            self.assertIn('detector requirements', campaign.validate_retained_evidence(result))

    def test_requirements_reject_unknown_zero_boolean_and_non_object(self):
        for required in ([], {'unknown': 1}, {'check_world': 0}, {'check_world': True}):
            with self.subTest(required=required), self.assertRaises(ValueError):
                validate_requirements(required)

    def test_each_seed_requires_authoritative_observations(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'report.json'
            case = {'required_detectors': {'check_world': 2}}
            summary = {'runs': [{'seed': 1, 'report': str(path)}, {'seed': 2}]}
            row = {'enabled': True, 'status': 'observed', 'attempted': 2, 'returned': 2, 'errors': 0}
            path.write_text(json.dumps({'checks': {'detector_health': {'check_world': row}}}))
            self.assertEqual([value['status'] for value in assess(case, summary)], ['requirements_met', 'incomplete'])
            for update in ({'enabled': False}, {'status': 'unreached'}, {'returned': 1}, {'errors': 1, 'returned': 1, 'status': 'error'}):
                path.write_text(json.dumps({'checks': {'detector_health': {'check_world': {**row, **update}}}}))
                self.assertNotEqual(assess(case, summary)[0]['status'], 'requirements_met')
            path.write_text(json.dumps({'checks': {'detector_health': {'check_world': {**row, 'returned': True}}}}))
            with self.assertRaises(ValueError):
                assess(case, summary)

    def test_unreached_is_not_observed(self):
        self.assertEqual(Probe().detector_health, {})

    def test_returns_and_errors_are_independent(self):
        probe = Probe()
        self.assertEqual(probe.check(), 7)
        with self.assertRaisesRegex(ValueError, "injected"):
            probe.check(True)
        self.assertEqual(probe.detector_health['check'], {"attempted": 2, "returned": 1, "errors": 1})
