"""Serial focused smoke/integration pilot using the existing resource supervisor.

Run only in a dedicated native-Linux execution snapshot. The snapshot's ignored
artifacts path is linked into the monitored output; the shared checkout is refused.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import tarfile

from campaign_limits import supervise
from run_campaign import ROOT, atomic_json, build_identity, native_storage, source_identity


def execute(args, notify):
    initial = {'source': source_identity(), 'builds': build_identity(),
               'commands': args.commands, 'execution_root': str(ROOT),
               'environment': {name: os.environ[name] for name in ('REDROGUE_ENDLESS_SOURCE_JOURNEY',
                    'REDROGUE_ENDLESS_LOSS_SEARCH', 'REDROGUE_AUDIO_CALL_TRACE')
                               if name in os.environ}}
    # Preserve the unique test overlay; source/build capsules can be reused.
    overlay = args.output / 'test_tools.tar.gz'
    with tarfile.open(overlay, 'w:gz') as archive:
        for name in initial['source']['files']:
            if name.startswith('tools/') and (ROOT / name).is_file():
                archive.add(ROOT / name, arcname=name, recursive=False)
    from run_campaign import digest
    initial['test_tools_sha256'] = digest(overlay)
    atomic_json(args.output / 'manifest.json', initial)
    artifacts = ROOT / 'tools/pyboy_smoke/artifacts'
    # No pre-existing evidence is removed or replaced.
    if artifacts.is_symlink():
        old = artifacts.resolve()
        receipt = old.parent / 'supervision.json'
        audit = json.loads(receipt.read_text()) if receipt.is_file() else {}
        if (old.name != 'artifacts' or not (old.parent / 'manifest.json').is_file()
                or audit.get('cleanup_remaining_pids') != []):
            raise ValueError('existing artifact link has no completed supervision receipt')
        artifacts.rename(artifacts.with_name(f'artifacts_previous_{time.time_ns()}'))
    elif artifacts.exists():
        raise ValueError('snapshot artifacts already exist; use a fresh execution snapshot')
    target = args.output / 'artifacts'
    target.mkdir()
    artifacts.symlink_to(target, target_is_directory=True)
    results = []
    for index, command in enumerate(args.commands):
        if source_identity() != initial['source'] or build_identity() != initial['builds']:
            raise ValueError('snapshot identity changed before command')
        notify({'kind': 'phase', 'name': f'command_{index + 1}'})
        with (args.output / f'command_{index + 1}.log').open('w') as log:
            completed = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        results.append({'argv': command, 'exit': completed.returncode})
        atomic_json(args.output / 'results.json', {'commands': results})
        if source_identity() != initial['source'] or build_identity() != initial['builds']:
            raise ValueError('snapshot identity changed after command')
    return int(any(row['exit'] for row in results))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', action='append', default=[], help='smoke test-ID pattern')
    parser.add_argument('--integration', action='append', default=[],
                        help='integration module stem, optionally .Class.test_method')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--campaign-budget', type=float, default=900)
    parser.add_argument('--storage-budget-mib', type=float, default=128)
    parser.add_argument('--rss-budget-mib', type=float, default=1536)
    args = parser.parse_args()
    if os.name != 'posix' or not (ROOT / 'snapshot_identity.json').is_file():
        parser.error('requires a dedicated verified Linux snapshot')
    if not native_storage(ROOT) or not native_storage(args.output.resolve()):
        parser.error('snapshot and output must use native Linux storage')
    for value, ceiling in ((args.campaign_budget, 900), (args.storage_budget_mib, 128),
                           (args.rss_budget_mib, 1536)):
        if not 0 < value <= ceiling:
            parser.error('budgets must be positive and within 900s/128MiB/1536MiB')
    if not args.test and not args.integration:
        parser.error('select at least one smoke pattern or integration module')
    args.commands = []
    if args.test:
        args.commands.append([sys.executable, 'tools/pyboy_smoke/run_smoke.py', '--jobs', '1',
            '--test-timeout', '120', '--verbose', '--report', str(args.output.resolve() / 'smoke_results.json')] +
            [part for pattern in args.test for part in ('--test', pattern)])
    for selection in args.integration:
        if not re.fullmatch(r'integration_[a-z0-9_]+(?:\.[a-zA-Z0-9_]+){0,2}', selection):
            parser.error('invalid integration module stem')
        module, _, test = selection.partition('.')
        if module == 'integration_endless_recovery' and not os.environ.get('REDROGUE_ENDLESS_SOURCE_JOURNEY'):
            parser.error('recovery selection requires REDROGUE_ENDLESS_SOURCE_JOURNEY')
        if (test.endswith('test_later_circuit_blackout_then_next_ordinary_stage')
                and os.environ.get('REDROGUE_ENDLESS_LOSS_SEARCH') != '1'):
            parser.error('natural-loss discovery selection requires REDROGUE_ENDLESS_LOSS_SEARCH=1')
        path = ROOT / 'tools/pyboy_smoke' / f'{module}.py'
        if not path.is_file():
            parser.error(f'module missing: {module}')
        args.commands.append([sys.executable, str(path)] + ([test] if test else []))
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    audit = supervise(execute, args)
    atomic_json(args.output / 'supervision.json', audit)
    print(json.dumps(audit, indent=2))
    return audit['exit']


if __name__ == '__main__':
    raise SystemExit(main())
