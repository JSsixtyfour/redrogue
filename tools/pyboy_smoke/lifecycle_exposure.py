"""Audit run-indexed exposure without treating early blackouts as progression.

Read retained autoplay reports; this tool never launches an emulator. A missing
observation is incomplete coverage, not a confirmed gameplay defect.
"""
import argparse
import json
from pathlib import Path


def evaluate(data, required_runs=3, min_stages=1, min_battles=1):
    gaps = []
    records = data.get('runs', [])
    visits = [event for event in data.get('events', []) if event.get('kind') == 'playable_visit']
    exposure = []
    for index in range(1, required_runs + 1):
        record = records[index - 1] if index <= len(records) else {}
        observed = [event for event in visits if event.get('run_index') == index
                    and isinstance(event.get('state'), dict)
                    and event['state'].get('wEndlessDepth') == [0]
                    and event['state'].get('hIsInBattle') == [0]
                    and event['state'].get('wBattleCount')]
        row = {'run_index': index, 'outcome': record.get('outcome'),
               'stages': record.get('stages_cleared', 0),
               'battles_won': record.get('battles_won', 0),
               'playable_maps': sorted({event['map'] for event in observed}),
               'state_observations': len(observed)}
        if record.get('run_index') != index:
            gaps.append(f'run {index}: missing indexed end record')
        if record.get('outcome') not in ('champion', 'blackout'):
            gaps.append(f'run {index}: ordinary end outcome missing')
        if row['stages'] < min_stages or row['battles_won'] < min_battles:
            gaps.append(f'run {index}: meaningful progression quota unmet')
        if not observed:
            gaps.append(f'run {index}: no input-ready state observation')
        exposure.append(row)
    if data.get('outcome') != 'completed':
        gaps.append('requested sequence did not complete')
    if not data.get('build_identity', {}).get('gbc') or not data.get('build_identity', {}).get('sym'):
        gaps.append('build identity missing')
    if data.get('anomalies') or data.get('hook_errors'):
        gaps.append('findings or hook errors require review')
    from detector_health import CORE
    detectors = data.get('detector_ledger', {}).get('detectors', {})
    for name in CORE + ('screen_pointers', 'screen_code_rules', 'crash_vector'):
        row = detectors.get(name, {})
        if (row.get('enabled') is not True or row.get('available') is not True
                or row.get('status') != 'observed' or row.get('errors') != 0):
            gaps.append(f'detector {name}: required observations unavailable')
    return {'schema_version': 1, 'verdict': 'incomplete' if gaps else 'exposure_met',
            'exposure': exposure, 'gaps': gaps,
            'scope': 'run progression and input-ready observations only; service, reset/preserve, '
                     'audio, save/cold-load and Endless contracts require separate evidence'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('--runs', type=int, default=3)
    parser.add_argument('--min-stages', type=int, default=1)
    parser.add_argument('--min-battles', type=int, default=1)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if min(args.runs, args.min_stages, args.min_battles) < 1:
        parser.error('all quotas must be positive')
    result = evaluate(json.loads(args.report.read_text()), args.runs, args.min_stages, args.min_battles)
    result['report'] = str(args.report.resolve())
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(result['verdict'])
    return int(bool(result['gaps']))


if __name__ == '__main__':
    raise SystemExit(main())
