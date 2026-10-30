"""Directed quota, identity oracle and fail-closed evidence tests (synthetic data)."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import directed_scenario as directed
import run_campaign as campaign

LAYOUT={'stride':44,'width':11,'moves':8,'pp':29,'form':7}


def trade_data():
    before={'count':3,'species':[0x54,10,20,255],
            'mons':[[species]+[0]*43 for species in (0x54,10,20)],
            'ot':[[index]*11 for index in range(3)],'names':[[index+4]*11 for index in range(3)]}
    traded=copy.deepcopy(before)
    for field in ('mons','ot','names'):traded[field]=traded[field][1:]+copy.deepcopy(traded[field][:1])
    traded['species']=[10,20,0x4d,255];traded['mons'][-1][0]=0x4d;traded['mons'][-1][7]=0x20
    return {'before':before,'traded':traded,'restored':copy.deepcopy(traded),'given_slot':0}


class DirectedCampaignTest(unittest.TestCase):
    def test_directed_quotas_require_the_directed_auditor(self):
        case={'id':'wrong_lane','args':['--seeds','1'],'required_exposure':{'directed_chains':1}}
        with self.assertRaises(ValueError):campaign.validate_config({'cases':[case]})
    def test_symlink_directory_cannot_hide_evidence_outside_attempt(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);attempt=root/'attempt';artifacts=attempt/'artifacts';artifacts.mkdir(parents=True)
            outside=root/'outside';outside.mkdir();(outside/'chain.json').write_text('{}')
            (artifacts/'trade').symlink_to(outside,target_is_directory=True)
            with self.assertRaises(ValueError):campaign.evidence_inventory(attempt,{'runs':[]})

    def test_worker_assertion_failure_retains_context_and_zero_exposure(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(directed.autoplay,'ARTIFACTS',Path(tmp)),patch(
                'test_trade_identity_chain.run_chain',side_effect=AssertionError('controlled fixture failure')):
            self.assertEqual(directed.main(['--case','trade']),1)
            summary=json.loads((Path(tmp)/'autoplay_summary_directed.json').read_text())
            self.assertEqual(campaign.classify(1,summary,'completed'),'harness_error')
            self.assertEqual(campaign.achieved_exposure(summary)['directed_chains'],0)
            status=json.loads((Path(tmp)/'trade/case_status.json').read_text())
            self.assertIn('controlled fixture failure',status['detail'])

    def test_missing_global_ledger_stays_unverified_or_rejects_requirement(self):
        from detector_health import assess
        with tempfile.TemporaryDirectory() as tmp:
            report=Path(tmp)/'report.json';report.write_text('{}')
            summary={'runs':[{'seed':1,'report':str(report)}]}
            self.assertEqual(assess({'scenario':'directed'},summary)[0]['status'],'unverified')
            with self.assertRaises(ValueError):assess({'scenario':'directed','required_detector_schema':1},summary)

    def test_trade_positive_and_identity_fault_have_exact_provenance(self):
        with patch.object(directed,'layout',return_value=LAYOUT):
            data=trade_data();self.assertEqual(directed.semantic_findings('trade',data),[])
            data['restored']['species'][-2]^=1;data['restored']['mons'][-1][0]^=1
            findings=directed.semantic_findings('trade',data,origin='controlled_detector_input')
            self.assertEqual([(f['field'],f['evidence_origin']) for f in findings],[('restored','controlled_detector_input')])

    def test_survivor_corruption_is_not_hidden_by_received_identity(self):
        with patch.object(directed,'layout',return_value=LAYOUT):
            data=trade_data();data['traded']['ot'][0][0]^=1
            self.assertIn('trade_survivors_ot',[f['field'] for f in directed.semantic_findings('trade',data)])

    def test_null_or_inconsistent_party_cannot_agree_to_clean(self):
        with patch.object(directed,'layout',return_value=LAYOUT):
            for field,value in (('count',True),('mons',None),('species',[0x54,10,20,0])):
                data=trade_data();data['before'][field]=value
                with self.assertRaises(ValueError):directed.semantic_findings('trade',data)

    def test_directed_family_quotas_do_not_inflate_purchases_or_runs(self):
        rows=[{'family':'directed','chain_family':family,'execution':'completed'} for family in
              ('credit','trade','teaching_empty','teaching_full','teaching_full')]
        counts=campaign.achieved_exposure({'runs':[{'cases':rows}]})
        self.assertEqual((counts['directed_chains'],counts['directed_teaching_full_chains']),(5,2))
        self.assertEqual((counts['purchase_cases'],counts['credit_cases'],counts['completed_runs']),(0,0,0))
        rows[0]['chain_family']='unknown'
        with self.assertRaises(ValueError):campaign.achieved_exposure({'runs':[{'cases':rows}]})

    def test_summary_inflation_and_extra_findings_are_rejected(self):
        row={'seed':1,'report':'unused','outcome':'completed','cases':[],'contract_findings':[]}
        case={'scenario':'directed','args':['--case','trade']}
        with patch.object(directed,'read_report',return_value=row):
            for key,value in (('seed',2),('cases',[{'execution':'completed'}]),('contract_findings',[{'field':'fake'}])):
                changed={**row,key:value}
                with self.assertRaises(ValueError):campaign.normalize_summary(case,{'runs':[changed]})

    def test_control_configuration_requires_exact_isolated_trade_control(self):
        case={'id':'control','scenario':'directed','args':['--case','trade'],'expected_verdict':'contract_violation'}
        with self.assertRaises(ValueError):campaign.validate_config({'cases':[case]})
        case['args'].append('--control-identity')
        with self.assertRaises(ValueError):campaign.validate_config({'cases':[case]})
        case['expected_findings']=[{'check':'directed_chain','version':1,'field':'restored','evidence_origin':'controlled_detector_input'}]
        self.assertEqual(campaign.validate_config({'cases':[case]}),[case])
        case['args']=['--case','all','--control-identity']
        with self.assertRaises(ValueError):campaign.validate_config({'cases':[case]})

    def test_inventory_omission_missing_and_altered_records_cannot_pass(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(directed,'layout',return_value=LAYOUT):
            directory=Path(tmp);args=directed.build_parser().parse_args(['--case','trade'])
            data={**trade_data(),'hardware_mode':'DMG','rom_sha256':'ROM','sym_sha256':'ROM',
                  'post_trade_fixture_writes':[],'movement':{'from':[1,1],'to':[1,2]}}
            (directory/'chain.json').write_text(json.dumps(data))
            (directory/'saved.sav').write_bytes(bytes(32768))
            for name in directed.REQUIRED['trade']:(directory/name).write_bytes(b'synthetic unit-test state')
            def digest(path):
                return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_relative_to(directory) else 'ROM'
            evidence=[{'path':p.name,'sha256':digest(p)} for p in sorted(directory.iterdir())]
            status={'identity':directed.identity('trade',args),'execution':'completed','evidence':evidence}
            status_path=directory/'case_status.json';status_path.write_text(json.dumps(status))
            with patch.object(directed,'digest',digest):
                self.assertEqual(directed.audit_chain(directory,'trade',args)['execution'],'completed')
                omitted=copy.deepcopy(status);omitted['evidence']=[r for r in evidence if r['path']!='saved.sav']
                status_path.write_text(json.dumps(omitted))
                with self.assertRaises(ValueError):directed.audit_chain(directory,'trade',args)
                status_path.write_text(json.dumps(status));(directory/'chain.json').write_text('{}')
                with self.assertRaises(ValueError):directed.audit_chain(directory,'trade',args)
                (directory/'traded.state').unlink()
                with self.assertRaises((ValueError,OSError)):directed.audit_chain(directory,'trade',args)

    def test_failed_fixture_has_no_completed_exposure(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp);args=directed.build_parser().parse_args(['--case','trade'])
            (directory/'case_status.json').write_text(json.dumps({'identity':directed.identity('trade',args),
                'execution':'error','detail':'fixture assertion failed; triage needed'}))
            row=directed.audit_chain(directory,'trade',args)
            self.assertEqual(campaign.achieved_exposure({'runs':[{'cases':[row]}]})['directed_chains'],0)
            status=json.loads((directory/'case_status.json').read_text())
            status['identity']['provenance']['natural_gameplay']=0
            (directory/'case_status.json').write_text(json.dumps(status))
            with self.assertRaises(ValueError):directed.audit_chain(directory,'trade',args)


if __name__=='__main__':unittest.main()
