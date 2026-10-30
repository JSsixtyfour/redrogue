"""Credit campaign evidence, quota separation and exact-control rejection."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import credit_scenario as credit
import run_campaign as campaign
from test_credit_store import credit_fixture


class CreditCampaignTest(unittest.TestCase):
    def fixture(self, directory):
        args = credit.build_parser().parse_args(['--case', 'exact'])
        fixture = credit_fixture('exact')
        before = {'coins': [0, 0x11], 'money': [0, 0, 0], 'flags': fixture['flags'],
                  'tiers': fixture['tiers'], 'party': [1, 2], 'items': [3, 4]}
        after = {**before, 'coins': [0, 0], 'flags': fixture['expected']['flags'],
                 'tiers': fixture['expected']['tiers'], 'paid_calls': 1, 'grant_calls': 1, 'tier_calls': 0}
        observation = {'before': before, 'after': after, 'expected': fixture['expected'], 'findings': []}
        result = {'case': 'exact', 'cgb': False, 'rom_sha256': 'pokeblue_debug.gbc',
                  'sym_sha256': 'pokeblue_debug.sym', 'initial_state_sha256': 'initial.state',
                  'inputs': [[1, 'a', 2]], 'started_frame': 1, 'final_frame': 20,
                  'coins': after['coins'], 'flags': after['flags'], 'tiers': after['tiers'],
                  'after': {'money': 0, 'party': after['party'], 'items': after['items']},
                  'paid': 1, 'grant': 1, 'changed_tier': 0}
        folder = directory / 'credit_seed7_exact'
        folder.mkdir()
        for name, data in (('contract.json', observation), ('result.json', result),
                           ('case.json', {'case': 'exact', 'cgb': False, 'control': False, 'findings': []})):
            (folder / name).write_text(json.dumps(data))
        report = directory / 'credit_report.json'
        report.write_text(json.dumps({'seed': 7, 'cases': ['exact'], 'cgb': False, 'control': False}))
        return args, folder, report

    def test_quota_is_credit_not_ordinary_purchase(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(credit, 'digest', lambda path: path.name):
            args, _, report = self.fixture(Path(tmp))
            row = credit.read_report(report, args)
            counts = campaign.achieved_exposure({'runs': [row]})
            self.assertEqual((counts['credit_cases'], counts['purchase_cases']), (1, 0))

    def test_summary_cannot_inflate_or_hide_findings(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(credit, 'digest', lambda path: path.name):
            args, _, report = self.fixture(Path(tmp))
            row = credit.read_report(report, args)
            case = {'scenario': 'credit', 'args': ['--case', 'exact']}
            for mutation in ('extra_case', 'extra_finding', 'wrong_seed'):
                changed = copy.deepcopy(row)
                if mutation == 'extra_case': changed['cases'].append(changed['cases'][0])
                elif mutation == 'extra_finding': changed['contract_findings'] = [{'field': 'coins'}]
                else: changed['seed'] = 8
                with self.assertRaises(ValueError):
                    campaign.normalize_summary(case, {'runs': [changed]})

    def test_changed_expected_contract_cannot_silence_fault(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(credit, 'digest', lambda path: path.name):
            args, folder, report = self.fixture(Path(tmp))
            path = folder / 'contract.json'
            data = json.loads(path.read_text())
            data['expected']['bought'] = False
            path.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, 'expected contract'):
                credit.read_report(report, args)

    def test_unreported_real_fault_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(credit, 'digest', lambda path: path.name):
            args, folder, report = self.fixture(Path(tmp))
            path = folder / 'contract.json'; data = json.loads(path.read_text())
            data['after']['party'] = [9, 9]
            path.write_text(json.dumps(data))
            with self.assertRaises(ValueError):
                credit.read_report(report, args)

    def test_recorded_real_fault_remains_actual_rom_contract_violation(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(credit, 'digest', lambda path: path.name):
            args, folder, report = self.fixture(Path(tmp))
            observation = json.loads((folder / 'contract.json').read_text())
            observation['after']['party'] = [9, 9]
            observation['findings'] = credit.credit_contract(observation['before'], observation['after'],
                                                            **observation['expected'])
            result = json.loads((folder / 'result.json').read_text())
            result['after']['party'] = [9, 9]
            record = json.loads((folder / 'case.json').read_text())
            record['findings'] = observation['findings']
            for name, value in (('contract.json', observation), ('result.json', result), ('case.json', record)):
                (folder / name).write_text(json.dumps(value))
            row = credit.read_report(report, args)
            self.assertEqual(row['contract_findings'][0]['evidence_origin'], 'actual_ROM_fixture')
            self.assertEqual(campaign.classify(1, {'runs': [row]}, 'completed'), 'contract_violation')

    def test_missing_observation_is_not_a_completed_case(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(credit, 'digest', lambda path: path.name):
            args, folder, report = self.fixture(Path(tmp))
            (folder / 'contract.json').unlink()
            with self.assertRaises(OSError):
                credit.read_report(report, args)

    def test_expected_violation_requires_control_and_exact_signature(self):
        case = {'id': 'credit_control', 'scenario': 'credit', 'args': ['--case', 'exact'],
                'expected_verdict': 'contract_violation', 'required_exposure': {'credit_cases': 1}}
        with self.assertRaises(ValueError): campaign.validate_config({'cases': [case]})
        case['args'].append('--control-credit-balance')
        with self.assertRaises(ValueError): campaign.validate_config({'cases': [case]})
        case['expected_findings'] = [{'check': 'credit_transaction', 'version': 1, 'field': 'coins',
                                      'evidence_origin': 'controlled_detector_input'}]
        self.assertEqual(campaign.validate_config({'cases': [case]}), [case])
        case['args'] = ['--case', 'decline', '--control-credit-balance']
        with self.assertRaises(ValueError): campaign.validate_config({'cases': [case]})


if __name__ == '__main__':
    unittest.main()
