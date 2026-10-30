"""Campaign adapter for existing configured Credit Store real-input fixtures."""
import argparse
import copy
import hashlib
import json
from pathlib import Path

import autoplay
from test_credit_store import CreditStoreLiveTest, credit_contract, credit_fixture

CASES = ('exact', 'decline', 'insufficient', 'full_active', 'upgrade_exact',
         'upgrade_final', 'upgrade_decline', 'upgrade_insufficient', 'upgrade_pc', 'upgrade_max')


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seeds', choices=('7',), default='7', help='fixed existing fixture identity')
    parser.add_argument('--case', choices=(*CASES, 'all'), default='all')
    parser.add_argument('--cgb', action='store_true')
    parser.add_argument('--control-credit-balance', action='store_true')
    parser.set_defaults(jobs=1, timeout=120)
    return parser


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit_case(directory, name, cgb, control):
    record = json.loads((directory / 'case.json').read_text())
    result = json.loads((directory / 'result.json').read_text())
    observation = json.loads((directory / 'contract.json').read_text())
    if (record['case'], record['cgb'], record['control']) != (name, cgb, control):
        raise ValueError('credit case identity mismatch')
    if (result['case'], result['cgb']) != (name, cgb):
        raise ValueError('credit driver identity mismatch')
    if (result['rom_sha256'], result['sym_sha256']) != (
            digest(autoplay.ROOT / 'pokeblue_debug.gbc'), digest(autoplay.ROOT / 'pokeblue_debug.sym')):
        raise ValueError('credit build identity mismatch')
    if digest(directory / 'initial.state') != result['initial_state_sha256']:
        raise ValueError('credit state hash mismatch')
    if not result['inputs'] or result['final_frame'] <= result['started_frame']:
        raise ValueError('credit inputs or completion missing')
    fixture = credit_fixture(name)
    expected_before = {'coins': [0, int(f"{fixture['funds']:02d}", 16)],
                       'flags': fixture['flags'], 'tiers': fixture['tiers']}
    if any(observation['before'][key] != value for key, value in expected_before.items()):
        raise ValueError('credit fixture precondition mismatch')
    if observation['expected'] != fixture['expected']:
        raise ValueError('credit expected contract mismatch')
    after = observation['after']
    for field, key in (('coins', 'coins'), ('flags', 'flags'), ('tiers', 'tiers'),
                       ('paid_calls', 'paid'), ('grant_calls', 'grant'), ('tier_calls', 'changed_tier')):
        if after[field] != result[key]:
            raise ValueError('credit observation/driver disagreement')
    money = int(''.join(f'{value:02x}' for value in after['money']))
    if (money != result['after']['money'] or after['party'] != result['after']['party']
            or after['items'] != result['after']['items']):
        raise ValueError('credit observation/driver disagreement')
    real = credit_contract(observation['before'], after, **fixture['expected'])
    if real != observation['findings']:
        raise ValueError('credit observed findings mismatch')
    findings = list(real)
    if control:
        changed = copy.deepcopy(after)
        changed['coins'][1] ^= 1
        findings += credit_contract(observation['before'], changed, **fixture['expected'],
                                    evidence_origin='controlled_detector_input')
    if record['findings'] != findings:
        raise ValueError('credit recorded findings mismatch')
    return {'family': 'credit', 'scenario': name, 'execution': 'completed', 'findings': findings}


def read_report(path, args):
    report = json.loads(path.read_text())
    names = list(CASES) if args.case == 'all' else [args.case]
    if report != {'seed': 7, 'cases': names, 'cgb': args.cgb, 'control': args.control_credit_balance}:
        raise ValueError('credit report allocation mismatch')
    cases = [audit_case(path.parent / f'credit_seed7_{name}', name, args.cgb,
                        args.control_credit_balance) for name in names]
    return {'seed': 7, 'outcome': 'completed', 'report': str(path), 'cases': cases,
            'contract_findings': [finding for case in cases for finding in case['findings']]}


def main(argv=None):
    args = build_parser().parse_args(argv)
    if args.control_credit_balance and args.case != 'exact':
        raise ValueError('credit balance control requires the exact purchase fixture')
    from run_campaign import atomic_json
    output = autoplay.ARTIFACTS.resolve()
    output.mkdir(parents=True, exist_ok=True)
    names = list(CASES) if args.case == 'all' else [args.case]
    for name in names:
        directory = output / f'credit_seed7_{name}'
        test = CreditStoreLiveTest()
        try:
            test.live(name, cgb=args.cgb, output=directory, assert_contract=False)
        finally:
            test.doCleanups()
        observation = json.loads((directory / 'contract.json').read_text())
        findings = list(observation['findings'])
        if args.control_credit_balance:
            changed = copy.deepcopy(observation['after'])
            changed['coins'][1] ^= 1
            findings += credit_contract(observation['before'], changed, **observation['expected'],
                                        evidence_origin='controlled_detector_input')
        atomic_json(directory / 'case.json', {'case': name, 'cgb': args.cgb,
                    'control': args.control_credit_balance, 'findings': findings})
    path = output / 'credit_report.json'
    atomic_json(path, {'seed': 7, 'cases': names, 'cgb': args.cgb, 'control': args.control_credit_balance})
    row = read_report(path, args)
    atomic_json(output / 'autoplay_summary_credit.json', {'schema_version': 1, 'runs': [row]})
    return int(bool(row['contract_findings']))


if __name__ == '__main__':
    raise SystemExit(main())
