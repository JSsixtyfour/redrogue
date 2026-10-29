"""Independent recorded dimensions; these do not replace acceptance rules."""


def dimensions(result, summary=None):
    if not result.get('evidence_valid', True):
        summary = None
    rows = summary.get('runs', []) if summary is not None else []
    contracts = sum(len(row.get('contract_findings', [])) for row in rows)
    suspicions = sum(len(row.get('anomalies', [])) + len(row.get('save_findings', [])) +
                     len((row.get('branches') or {}).get('findings', [])) +
                     int(row.get('outcome') in ('crashed', 'stalled')) for row in rows)
    semantic = ('unverified' if summary is None else 'contract_violation' if contracts else
                'suspected_issue' if suspicions else 'no_reported_findings')
    health = result.get('detector_health') or []
    detectors = ('unverified' if not result.get('evidence_valid', True) or not health else
                 'error' if any(row['status'] == 'error' for row in health) else
                 'incomplete' if any(row['status'] == 'incomplete' for row in health) else
                 'unverified' if any(row['status'] == 'unverified' for row in health) else 'requirements_met')
    requested = result['case'].get('required_exposure', {})
    missing = result.get('missing_exposure', {})
    exposure = ('not_requested' if not requested else 'unknown' if not result.get('evidence_valid', True) or
                any(row.get('status') == 'unknown' for row in missing.values()) or not result.get('achieved_exposure') else
                'unmet' if missing else 'requirements_met')
    return {'execution': {'status': result['execution']},
            'semantic': {'status': semantic, 'contract_findings': contracts if summary is not None else None,
                         'suspected_signals': suspicions if summary is not None else None},
            'detectors': {'status': detectors},
            'exposure': {'status': exposure, 'requested': requested,
                         'achieved': result.get('achieved_exposure', {}) if result.get('evidence_valid', True) else None,
                         'missing': missing}}


def markdown(results):
    lines = ['# Bounded autoplay campaign', '',
             '| Case | Execution | Semantic observations | Detector health | Exposure | Verdict | Expected | Seconds |',
             '|---|---|---|---|---|---|---|---|']
    for row in results:
        data = row['dimensions']
        lines.append('| ' + ' | '.join([row['case']['id'], data['execution']['status'],
                     data['semantic']['status'], data['detectors']['status'], data['exposure']['status'], row['verdict'],
                     row['case'].get('expected_verdict', 'no_issue_detected'), str(row.get('seconds', 'unknown'))]) + ' |')
    lines += ['', 'No reported findings is an observation, not full semantic acceptance. Detector requirements and exposure apply only to the declared case allocation.', '']
    return '\n'.join(lines)
