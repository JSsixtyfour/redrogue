"""Validate observed invocation requirements without inferring semantic coverage."""
import json
from functools import wraps
from pathlib import Path

CORE = ('check_world', 'check_party', 'check_items', 'check_key_items', 'check_map', '_on_battle_menu',
        'after_step', '_on_overworld_poll')
EXTRA = ('screen_pointers', 'screen_code_rules', 'cgb_palette', 'save_timer', 'branches', 'coverage', 'hook_callbacks', 'crash_vector')


def context_reporter(path, seed):
    """Persist last lifecycle phase even when no normal report can be written."""
    from run_campaign import atomic_json
    def record(phase, status='running', detail=None):
        atomic_json(path, {'schema_version': 1, 'seed': seed, 'phase': phase,
                          'status': status, 'detector_acceptance': 'unverified', 'detail': detail})
    return record


def failed_context(path, seed, detail, status='error'):
    try:
        phase = json.loads(path.read_text())['phase']
    except (OSError, ValueError, KeyError, TypeError):
        phase = 'worker_start'
    context_reporter(path, seed)(phase, status, detail)


def observed_check(method):
    """Count invocation returns and errors without suppressing exceptions."""
    @wraps(method)
    def observed(self, *args, **kwargs):
        row = self.detector_health.setdefault(method.__name__, {'attempted': 0, 'returned': 0, 'errors': 0})
        row['attempted'] += 1
        try:
            result = method(self, *args, **kwargs)
        except BaseException:
            row['errors'] += 1
            raise
        row['returned'] += 1
        return result
    return observed


def collect(report, configuration):
    """Inventory existing observations. Uninstrumented lanes stay unverified."""
    ledger = {}
    def entry(name, enabled, available, measured=0, errors=0, skipped=0, reason=None):
        for value in (measured, errors, skipped):
            if type(value) is not int or value < 0:
                raise ValueError('invalid ledger count')
        ledger[name] = {'enabled': enabled, 'available': available,
                        'status': 'error' if errors else 'disabled' if not enabled else
                                  'unavailable' if not available else 'observed' if measured else
                                  'skipped' if skipped else 'unreached',
                        'observations': measured, 'errors': errors, 'skipped': skipped, 'reason': reason}
    health = (report.get('checks') or {}).get('detector_health', {})
    for name in CORE:
        row = health.get(name)
        if row is not None:
            counts = [row.get(key) for key in ('attempted', 'returned', 'errors')]
            if any(type(value) is not int or value < 0 for value in counts) or counts[1] + counts[2] > counts[0]:
                raise ValueError('invalid source detector counters')
        entry(name, row.get('enabled') is True if row else True, row is not None, row.get('returned', 0) if row else 0,
              row.get('errors', 0) if row else 0)
    screen = report.get('screen_checks') or {}
    entry('screen_pointers', True, 'pointer_calls' in screen, sum(screen.get('pointer_calls', {}).values()))
    entry('screen_code_rules', True, screen.get('code_rules_available') is True,
          screen.get('code_rule_observations', 0), reason=report.get('coverage_inventory_error'))
    entry('cgb_palette', report.get('hardware_mode') == 'CGB', 'samples' in screen,
          screen.get('samples', 0), skipped=screen.get('skipped', 0))
    save = report.get('save_checks') or {}
    trips = save.get('round_trips', [])
    timers = [(trip.get('detectors') or {}).get('run_timer') for trip in trips]
    entry('save_timer', bool(configuration.get('save_checks')), 'round_trips' in save,
          sum(bool(row and row.get('enabled') is True and row.get('available') is True and row.get('status') == 'ok') for row in timers),
          sum(bool(row and (row.get('status') == 'error' or row.get('errors'))) for row in timers),
          sum(bool(trip.get('skipped')) for trip in trips))
    branch = report.get('branches') or {}
    records = branch.get('detector_records')
    branch_observations = branch_errors = 0
    if records is not None:
        if not isinstance(records, list) or len(records) != sum(row['branches'] for row in branch.get('totals', {}).values()):
            raise ValueError('missing branch detector records')
        if len({row['key'] for row in records}) != len(records):
            raise ValueError('duplicate branch detector records')
        for record in records:
            count = record['detector_health']['after_step']
            if any(type(count.get(key)) is not int or count[key] < 0 for key in ('attempted', 'returned', 'errors')):
                raise ValueError('invalid branch detector counters')
            if count['returned'] + count['errors'] > count['attempted']:
                raise ValueError('invalid branch detector totals')
            branch_observations += count['returned']
            branch_errors += len(record['hook_errors']) + sum(row['errors'] for row in record['detector_health'].values())
            branch_errors += int(record['outcome'] == 'error')
    entry('branches', bool(configuration.get('branches')), records is not None,
          branch_observations, branch_errors)
    coverage = report.get('coverage') or {}
    requested = coverage.get('requested')
    if requested is not None and (type(requested) is not int or requested < 0):
        raise ValueError('invalid requested coverage hooks')
    entry('coverage', bool(configuration.get('coverage')), requested is not None and requested > len(coverage.get('skipped', [])),
          len(set(coverage.get('hit', []))), skipped=len(coverage.get('skipped', [])))
    entry('hook_callbacks', True, 'hook_errors' in report, errors=len(report.get('hook_errors', [])))
    ledger['hook_callbacks']['status'] = 'error' if report.get('hook_errors') else 'available' if 'hook_errors' in report else 'unavailable'
    crash_hook = (report.get('checks') or {}).get('crash_vector_hook', {})
    armed = crash_hook.get('enabled') is True and crash_hook.get('available') is True and crash_hook.get('status') == 'armed'
    entry('crash_vector', True, armed, int(armed))
    for name, row in ledger.items():
        row['measurement'] = {'crash_vector': 'registered hook', 'coverage': 'unique labels hit',
                              'cgb_palette': 'safe palette samples', 'save_timer': 'timer observer records',
                              'branches': 'branch after_step returns', 'screen_pointers': 'checked pointer/glyph records',
                              'screen_code_rules': 'source rule calls', 'hook_callbacks': 'hook errors'}.get(name, 'invocation returns')
    return {'schema_version': 1, 'measurement': 'recorded observations, not semantic acceptance', 'detectors': ledger}


def validate_requirements(requirements):
    if not isinstance(requirements, dict):
        raise ValueError('required_detectors must be an object')
    for name, minimum in requirements.items():
        if name not in CORE + EXTRA or type(minimum) is not int or minimum < 1:
            raise ValueError(f'invalid detector requirement: {name}')


def validate_schema(schema):
    if schema is not None and (type(schema) is not int or schema != 1):
        raise ValueError('required_detector_schema must be 1')


def assess(case, summary):
    """Read authoritative report evidence for every seed, including on resume."""
    required = case.get('required_detectors', {})
    validate_requirements(required)
    validate_schema(case.get('required_detector_schema'))
    rows = []
    physical = []
    for run in summary['runs']:
        if 'detector_reports' in run:
            records = run['detector_reports']
            if not isinstance(records, list) or not records:
                raise ValueError('nested detector reports missing')
            identities = [(row['seed'], row['fill'], row['repetition']) for row in records]
            if len(set(identities)) != len(identities) or any(row['seed'] != run['seed'] for row in records):
                raise ValueError('invalid nested detector identities')
            physical.extend(records)
        else:
            physical.append(run)
    for run in physical:
        report = json.loads(Path(run['report']).read_text()) if run.get('report') else {}
        ledger = (report.get('checks') or {}).get('detector_health', {})
        global_ledger = report.get('detector_ledger')
        if case.get('required_detector_schema') and global_ledger is None:
            raise ValueError('required detector ledger missing')
        if global_ledger is not None:
            if global_ledger.get('schema_version') != 1:
                raise ValueError('unsupported detector ledger schema')
            recomputed = collect(report, report.get('detector_configuration', {}))
            if 'args' in case and case.get('scenario', 'autoplay') == 'autoplay':
                import run_autoplay
                options = run_autoplay.build_parser().parse_args(case['args'])
                expected = {'save_checks': options.save_checks, 'coverage': options.coverage, 'branches': bool(options.branches)}
                if report.get('detector_configuration') != expected:
                    raise ValueError('detector configuration differs from campaign case')
            elif case.get('scenario') == 'sram' and report.get('detector_configuration') != {
                    'save_checks': False, 'coverage': False, 'branches': False}:
                raise ValueError('nested SRAM detector configuration differs from scenario')
            if global_ledger != recomputed:
                raise ValueError('detector ledger differs from recorded observations')
            ledger = {name: {'enabled': row['enabled'], 'status': row['status'],
                            'attempted': row['observations'] + row['errors'],
                            'returned': row['observations'], 'errors': row['errors']}
                      for name, row in recomputed['detectors'].items()}
        if not isinstance(ledger, dict):
            raise ValueError('detector health must be an object')
        missing = {}
        errors = []
        for name, row in ledger.items():
            if not isinstance(row, dict):
                raise ValueError('malformed detector row')
            counts = [row.get(key) for key in ('attempted', 'returned', 'errors')]
            if any(type(value) is not int or value < 0 for value in counts) or counts[1] + counts[2] > counts[0]:
                raise ValueError('invalid detector counters')
            if row.get('status') == 'error' or counts[2]:
                errors.append(name)
        for name, minimum in required.items():
            row = ledger.get(name, {})
            if row.get('enabled') is not True or row.get('status') != 'observed' or row.get('returned', 0) < minimum:
                missing[name] = {'required_observations': minimum, 'observed_observations': row.get('returned'),
                                 'status': row.get('status', 'unavailable')}
        rows.append({'seed': run['seed'], **{key: run[key] for key in ('fill', 'repetition', 'role') if key in run},
                     'status': 'error' if errors else 'incomplete' if missing else
                     'requirements_met' if required else 'unverified', 'errors': errors, 'missing': missing})
    return rows
