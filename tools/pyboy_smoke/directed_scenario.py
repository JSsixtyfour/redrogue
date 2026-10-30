"""Thin campaign adapter and independent evidence audit for configured chains."""
import argparse
import copy
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import traceback
import unittest

import autoplay
from harness import SymbolTable
from source_constants import parse_rgbds_constants

CASES = {'credit': 'credit', 'trade': 'trade', 'teaching_empty': 'teaching_empty',
         'teaching_decline': 'teaching_full', 'teaching_cancel_forget': 'teaching_full'}
PROVENANCE = {name: {'natural_gameplay': False, 'save': 'writer_invoked',
    'interaction': 'text_handler_fixture_with_real_menus' if name.startswith('teaching') else 'configured_offer_with_real_input'} for name in CASES}
REQUIRED = {'credit': ('purchase/initial.state','purchase/result.json','purchase/contract.json',
                       'upgrade/initial.state','upgrade/result.json','upgrade/contract.json'),
            'trade': ('before.state','traded.state','continued.state'),
            'teaching_empty': ('continued.state',),
            'teaching_decline': ('initial.state','continued.state'),
            'teaching_cancel_forget': ('initial.state','continued.state')}


def build_parser():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seeds',choices=('1',),default='1',help='fixed catalog identity, not varied natural RNG')
    parser.add_argument('--case',choices=(*CASES,'all'),default='all')
    parser.add_argument('--cgb',action='store_true')
    parser.add_argument('--control-identity',action='store_true')
    parser.set_defaults(jobs=1,timeout=120)
    return parser


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


@lru_cache(maxsize=1)
def layout():
    symbols=SymbolTable(autoplay.ROOT/'pokeblue_debug.sym')
    address=lambda label:symbols.get(label)[1]
    base=address('wPartyMon1Species')
    return {'stride':address('wPartyMon2Species')-base,
            'width':address('wPartyMon2OT')-address('wPartyMon1OT'),
            'moves':address('wPartyMon1Moves')-base,'pp':address('wPartyMon1PP')-base,
            'form':address('wPartyMon1CatchRate')-base}


def byte_list(value,size=None):
    if (not isinstance(value,list) or not value or (size is not None and len(value)!=size)
            or any(type(byte) is not int or not 0<=byte<=255 for byte in value)):
        raise ValueError('invalid directed byte observation')


def valid_party(value):
    if not isinstance(value,dict) or set(value)!= {'count','species','mons','ot','names'}:
        raise ValueError('invalid directed party schema')
    count=value['count'];shape=layout()
    if type(count) is not int or not 1<=count<=6:raise ValueError('invalid party count')
    byte_list(value['species'],count+1)
    if value['species'][-1]!=255:raise ValueError('party sentinel missing')
    for field,size in (('mons',shape['stride']),('ot',shape['width']),('names',shape['width'])):
        if not isinstance(value[field],list) or len(value[field])!=count:raise ValueError('party rows missing')
        for row in value[field]:byte_list(row,size)
    if value['species'][:-1]!=[row[0] for row in value['mons']]:raise ValueError('party species disagree')


def semantic_findings(name,data,*,origin='actual_ROM_fixture'):
    findings=[]
    def compare(field,expected,observed):
        if expected!=observed:findings.append({'check':'directed_chain','version':1,'field':field,
            'expected':expected,'observed':observed,'signature':f'directed_chain/v1/{field}',
            'classification':'contract_violation','severity':'correctness','evidence_origin':origin})
    if name=='credit':
        from test_key_item_equipment import bits
        states=[data[key] for key in ('purchase','restored','upgrade_refused')]
        for state in states:
            if set(state)!= {'money','items','party','coins','flags','tiers'}:raise ValueError('invalid credit chain schema')
            for field,size in (('coins',2),('flags',4),('tiers',4),('party',None),('items',None)):byte_list(state[field],size)
            if type(state['money']) is not int or not 0<=state['money']<=999999:raise ValueError('invalid money')
        compare('credit_owned',bits(('SHINY_CHARM',),('SHINY_CHARM',)),states[0]['flags'])
        compare('credit_balance',[0,0],states[0]['coins']);compare('credit_tiers',[0]*4,states[0]['tiers'])
        compare('restored',states[0],states[1]);compare('upgrade_refused',states[0],states[2])
        return findings
    shape=layout();species=parse_rgbds_constants(autoplay.ROOT/'constants/pokemon_constants.asm')
    fields=('before','traded','restored') if name=='trade' else (
        ('before','taught','refused','restored') if name=='teaching_empty' else ('before','cancelled','replaced','restored'))
    for field in fields:valid_party(data[field])
    before=data['before']
    if name=='trade':
        slot=data['given_slot'];traded=data['traded']
        if type(slot) is not int or not 0<=slot<before['count']:raise ValueError('invalid removed slot')
        compare('given_species',species['PIKACHU'],before['species'][slot])
        expected_species=before['species'][:slot]+before['species'][slot+1:-1]+[species['MEOWTH'],255]
        compare('trade_species',expected_species,traded['species'])
        for field in ('mons','ot','names'):
            compare('trade_survivors_'+field,before[field][:slot]+before[field][slot+1:],traded[field][:-1])
        compare('received_identity',[species['MEOWTH'],0x20],
                [traded['mons'][-1][0],traded['mons'][-1][shape['form']]&0x60])
        compare('restored',traded,data['restored']);return findings
    from test_bridge_teach_known_move import MOVES
    if before['count']<2:raise ValueError('non-lead teaching target missing')
    expected=copy.deepcopy(before);target=expected['mons'][1];move_offset=shape['moves'];pp_offset=shape['pp']
    if name=='teaching_empty':
        if type(data['target_slot']) is not int or data['target_slot']!=1 or before['mons'][1][move_offset+1:move_offset+4]!=[0]*3 or before['mons'][1][pp_offset+1:pp_offset+4]!=[0]*3:
            raise ValueError('empty-slot fixture mismatch')
        move=next(MOVES[key] for key in ('TACKLE','SURF') if MOVES[key]!=target[move_offset])
        compare('taught_move',move,data['move']);target[move_offset+1]=move
        target[pp_offset+1]=35 if move==MOVES['TACKLE'] else 15
        compare('taught',expected,data['taught']);compare('refused',data['taught'],data['refused'])
        compare('restored',data['taught'],data['restored'])
    else:
        initial=[MOVES[key] for key in ('TACKLE','GROWL','TAIL_WHIP','QUICK_ATTACK')]
        if target[move_offset:move_offset+4]!=initial or target[pp_offset:pp_offset+4]!=[0xc1,0x82,0x43,4]:raise ValueError('full-menu fixture mismatch')
        kind='decline' if name=='teaching_decline' else 'cancel_forget'
        if not isinstance(data['attempts'],list) or any(type(row.get(key)) is not int for row in data['attempts'] for key in ('offer','forget','abandon')):
            raise ValueError('invalid learning prompt counters')
        if data['attempts']!=[{'kind':kind,'offer':1,'forget':int(kind!='decline'),'abandon':1},
                              {'kind':'replace','offer':1,'forget':1,'abandon':0}]:raise ValueError('learning prompt sequence mismatch')
        if data['menu_stats']['full_forget_replace']['moves']<2:raise ValueError('replacement navigation missing')
        target[move_offset+2]=MOVES['SURF'];target[pp_offset+2]=15
        compare('cancelled',before,data['cancelled']);compare('replaced',expected,data['replaced'])
        compare('restored',data['replaced'],data['restored'])
    return findings


def identity(name,args):
    return {'case':name,'family':CASES[name],'hardware_mode':'CGB' if args.cgb else 'DMG',
            'provenance':PROVENANCE[name]}


def audit_chain(directory,name,args):
    status=json.loads((directory/'case_status.json').read_text())
    if status['identity']!=identity(name,args):raise ValueError('directed identity/provenance mismatch')
    if status['identity']['provenance']['natural_gameplay'] is not False:raise ValueError('invalid fixture provenance type')
    if status['execution']=='error':
        if not isinstance(status.get('detail'),str) or not status['detail']:raise ValueError('missing failure context')
        return {'family':'directed','chain_family':CASES[name],'scenario':name,'execution':'error',
                'findings':[],'detail':status['detail']}
    if status['execution']!='completed':raise ValueError('directed chain incomplete')
    rows=status['evidence']
    if not isinstance(rows,list) or not rows:raise ValueError('directed evidence missing')
    seen=set()
    for row in rows:
        relative=Path(row['path'])
        if relative.is_absolute() or '..' in relative.parts or str(relative) in seen:raise ValueError('invalid evidence path')
        seen.add(str(relative));path=directory/relative
        if not path.resolve().is_relative_to(directory.resolve()) or path.is_symlink() or digest(path)!=row['sha256']:raise ValueError('directed evidence changed')
    if not set(('chain.json','saved.sav',*REQUIRED[name]))<=seen:raise ValueError('required directed evidence omitted')
    if (directory/'saved.sav').stat().st_size!=32768:raise ValueError('invalid saved SRAM size')
    data=json.loads((directory/'chain.json').read_text())
    if data['hardware_mode']!=identity(name,args)['hardware_mode'] or (data['rom_sha256'],data['sym_sha256'])!=(
            digest(autoplay.ROOT/'pokeblue_debug.gbc'),digest(autoplay.ROOT/'pokeblue_debug.sym')):raise ValueError('directed build/mode mismatch')
    writes='post_load_fixture_writes' if name=='credit' else 'post_trade_fixture_writes' if name=='trade' else 'post_initial_party_fixture_writes'
    if data[writes]!=[]:raise ValueError('post-boundary fixture writes')
    findings=semantic_findings(name,data)
    if name!='credit':
        movement=data['movement']
        byte_list(movement['from'],2);byte_list(movement['to'],2)
        if movement['from']==movement['to']:
            findings.append({'check':'directed_chain','version':1,'field':'movement','expected':'position changed',
                'observed':movement,'signature':'directed_chain/v1/movement','classification':'contract_violation',
                'severity':'correctness','evidence_origin':'actual_ROM_fixture'})
    if name=='credit':
        from credit_scenario import audit_driver
        for phase,case,funds,state_key in (('purchase','exact',None,'purchase'),('upgrade','upgrade_insufficient',0,'upgrade_refused')):
            observation,result,real=audit_driver(directory/phase,case,args.cgb,funds_override=funds)
            after=observation['after'];projected={key:after[key] for key in ('items','party','coins','flags','tiers')}
            projected['money']=int(''.join(f'{byte:02x}' for byte in after['money']))
            if projected!=data[state_key] or result['position'] in ([2,3],[4,3]):raise ValueError('credit chain/phase disagreement')
            findings+=real
    if args.control_identity:
        controlled=copy.deepcopy(data);controlled['restored']['species'][-2]^=1;controlled['restored']['mons'][-1][0]^=1
        findings+=semantic_findings(name,controlled,origin='controlled_detector_input')
    return {'family':'directed','chain_family':CASES[name],'scenario':name,'execution':'completed','findings':findings}


def read_report(path,args):
    report=json.loads(path.read_text());names=list(CASES) if args.case=='all' else [args.case]
    if (type(report.get('seed')) is not int or type(report.get('cgb')) is not bool or type(report.get('control')) is not bool
            or report!={'seed':1,'cases':names,'cgb':args.cgb,'control':args.control_identity}):raise ValueError('directed report allocation mismatch')
    cases=[audit_chain(path.parent/name,name,args) for name in names]
    return {'seed':1,'outcome':'completed' if all(row['execution']=='completed' for row in cases) else 'error',
            'report':str(path),'cases':cases,'contract_findings':[f for row in cases for f in row['findings']]}


def main(argv=None):
    args=build_parser().parse_args(argv)
    if args.control_identity and args.case!='trade':raise ValueError('identity control requires trade fixture')
    from run_campaign import atomic_json
    from test_credit_service_chain import run_chain as credit
    from test_trade_identity_chain import run_chain as trade
    from test_teaching_identity_chain import run_chain as empty
    from test_teaching_full_menu import run_chain as full
    output=autoplay.ARTIFACTS.resolve();output.mkdir(parents=True,exist_ok=True)
    names=list(CASES) if args.case=='all' else [args.case]
    for name in names:
        directory=output/name;directory.mkdir();test=unittest.TestCase();detail=None
        atomic_json(directory/'case_status.json',{'identity':identity(name,args),'execution':'running'})
        try:
            if name=='credit':credit(test,cgb=args.cgb,output=directory)
            elif name=='trade':trade(test,cgb=args.cgb,output=directory)
            elif name=='teaching_empty':empty(test,cgb=args.cgb,output=directory)
            else:full(test,cgb=args.cgb,cancellation='decline' if name=='teaching_decline' else 'cancel_forget',output=directory)
        except Exception:detail=traceback.format_exc()
        finally:
            if not test.doCleanups():detail=(detail or '')+'\nfixture cleanup failed'
        evidence=[{'path':str(path.relative_to(directory)),'sha256':digest(path)} for path in sorted(directory.rglob('*'))
                  if path.is_file() and path.suffix in ('.json','.state','.sav') and path.name!='case_status.json']
        atomic_json(directory/'case_status.json',{'identity':identity(name,args),'execution':'error' if detail else 'completed',
                                                  'detail':detail,'evidence':evidence})
    path=output/'directed_report.json';atomic_json(path,{'seed':1,'cases':names,'cgb':args.cgb,'control':args.control_identity})
    row=read_report(path,args);atomic_json(output/'autoplay_summary_directed.json',{'schema_version':1,'runs':[row]})
    return int(row['outcome']!='completed' or bool(row['contract_findings']))


if __name__=='__main__':raise SystemExit(main())
