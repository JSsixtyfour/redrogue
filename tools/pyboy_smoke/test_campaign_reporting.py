"""Mixed outcomes remain visible without promoting missing evidence to clean."""
import unittest
from campaign_reporting import dimensions, markdown


class ReportingTest(unittest.TestCase):
    def result(self):
        return {'case': {'id': 'mixed', 'required_exposure': {'stages': 2}},
                'execution': 'completed', 'verdict': 'contract_violation', 'evidence_valid': True,
                'achieved_exposure': {'stages': 1}, 'missing_exposure': {'stages': {'required': 2, 'achieved': 1}},
                'detector_health': [{'status': 'error'}]}

    def test_contract_failure_does_not_hide_detector_error_or_unmet_quota(self):
        result = self.result()
        result['dimensions'] = dimensions(result, {'runs': [{'contract_findings': [{'field': 'money'}]}]})
        self.assertEqual([result['dimensions'][name]['status'] for name in ('execution','semantic','detectors','exposure')],
                         ['completed','contract_violation','error','unmet'])
        table = markdown([result])
        self.assertIn('| completed | contract_violation | error | unmet |', table)

    def test_invalidated_evidence_never_reuses_clean_observations(self):
        result = self.result()
        result['evidence_valid'] = False
        result['detector_health'] = [{'status': 'requirements_met'}]
        data = dimensions(result, {'runs': []})
        self.assertEqual(data['semantic']['status'], 'unverified')
        self.assertIsNone(data['semantic']['contract_findings'])
        self.assertEqual(data['detectors']['status'], 'unverified')
        self.assertEqual(data['exposure']['status'], 'unknown')

    def test_interrupted_execution_preserves_observed_findings(self):
        result = self.result()
        result['execution'] = 'budget_exhausted'
        data = dimensions(result, {'runs': [{'anomalies': ['observed before interruption']}]})
        self.assertEqual(data['execution']['status'], 'budget_exhausted')
        self.assertEqual(data['semantic']['status'], 'suspected_issue')

    def test_missing_report_is_unknown_not_measured_zero(self):
        data = dimensions(self.result())
        self.assertEqual(data['semantic']['status'], 'unverified')
        self.assertIsNone(data['semantic']['suspected_signals'])

    def test_no_findings_is_not_package_acceptance(self):
        result = self.result()
        result['case']['required_exposure'] = {}
        result['detector_health'] = [{'status': 'unverified'}]
        data = dimensions(result, {'runs': [{'outcome': 'completed'}]})
        self.assertEqual(data['semantic']['status'], 'no_reported_findings')
        self.assertEqual(data['detectors']['status'], 'unverified')
        self.assertEqual(data['exposure']['status'], 'not_requested')
