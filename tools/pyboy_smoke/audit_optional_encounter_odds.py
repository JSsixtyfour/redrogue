"""Seeded production generation: real theme/odds, reachable outcomes and losses."""
import argparse
import io
import json
import math
from collections import Counter
from pathlib import Path
from harness import RedRogueHarness
from source_constants import parse_map_constants,parse_rgbds_constants
from test_forest_grotto import ROOT,ARTIFACTS,cells_for_grid
from audit_forest_clearings import flood
from test_cave_subroom import TAIL,SITES


def interval(k,n):
    if not n:return None
    z=1.95996398454;p=k/n;den=1+z*z/n
    mid=(p+z*z/(2*n))/den;half=z*math.sqrt(p*(1-p)/n+z*z/(4*n*n))/den
    return [mid-half,mid+half]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--per-kind',type=int,default=1000)
    p.add_argument('--kind',choices=('forest','cave','both'),default='both')
    p.add_argument('--cgb',action='store_true')
    p.add_argument('--out',type=Path,required=True)
    args=p.parse_args();records=[];context={}
    h=RedRogueHarness(ROOT,ARTIFACTS,cgb_mode=args.cgb)
    try:
        maps=parse_map_constants(ROOT/'constants/map_constants.asm')
        flags=parse_rgbds_constants(ROOT/'constants/ram_constants.asm')
        h.boot_to_lobby(battle_count=11,encounter_kind=4);h.write8('wStageEvent',0)
        # boot_to_lobby stops at door selection, before that visit's preload
        # and NPC setup finish. Complete it before taking fresh-stage trials.
        h.tick(240)
        h.write8('wStatusFlags6',h.read8('wStatusFlags6')&~(1<<flags['BIT_DEBUG2_MODE']))
        base=io.BytesIO();h.save_state(base)
        def roll(_):
            context['rolls']+=1
            context['trace'].append({'frame':h.pyboy.frame_count,'map':h.read8('hCurMap')})
        h.register_hook('OptionalForestOutcome',roll);h.register_hook('OptionalCaveOutcome',roll)
        for kind in (('forest','cave') if args.kind=='both' else (args.kind,)):
            parent=maps['PROCEDURAL_FOREST' if kind=='forest' else 'PROCEDURAL_CAVE_1']
            for seed in range(1,args.per_kind+1):
                h.load_state(base);context['rolls']=0;context['trace']=[]
                h.seed_rng((seed&255,(seed>>8)&255,83 if kind=='forest' else 173,41))
                h.preload_and_enter_wild_area(parent,kind)
                identity=h.read_bytes('wOptionalEncounterSpecies',7)
                species,package,level,state,destination,script,pending=identity
                theme=h.read_sram_bytes('sProcForestPalette' if kind=='forest' else 'sProcCavePalette',1,bank=0)[0]
                expected_rolls=1 if kind=='forest' or theme==1 else 0
                if context['rolls']!=expected_rolls:
                    args.out.parent.mkdir(parents=True,exist_ok=True)
                    with args.out.with_suffix('.failure.pyboy').open('wb') as f:h.save_state(f)
                    args.out.with_suffix('.failure.json').write_text(json.dumps({'kind':kind,'seed':seed,'context':context,'theme':theme,'diagnostic':h.diagnostic_state()},indent=2))
                    raise AssertionError((kind,seed,'roll count',context))
                if not species:assert identity==[0]*7,(kind,seed,'uncleared identity',identity)
                else:
                    assert level>0 and (state,script,pending)==(0,0,0),(kind,seed,identity)
                    assert destination==maps['PROCEDURAL_FOREST_GROTTO' if kind=='forest' else 'PROCEDURAL_CAVE_SUBROOM']
                accessible=False;ladder_a=ladder_b=None
                if kind=='forest':
                    assert theme in range(4)
                    if species:assert package in ((2,3) if theme==3 else (1,))
                    top=h.warp_entries()[31];accessible=top[0]!=255
                    assert accessible==bool(species),(seed,'missing/empty grove',identity,top)
                    if accessible:
                        edge=h.read_sram_bytes('sProcForestExitEdge',1,bank=0)[0]
                        side=top[2]//2;assert side!=edge
                        packed=h.read_sram_bytes('sProcForestStagingBuffer',400,bank=0)
                        cells=cells_for_grid(packed,20,20)
                        for slot in range(1,8):
                            if not h.read8('wSprite01StateData1',offset=16*(slot-1)):continue
                            sy,sx=h.read_bytes('wSprite01StateData2MapY',2,16*(slot-1));sx-=4;sy-=4
                            cells.pop((sx,sy),None)
                            if slot==1:
                                dx,dy=(1,0) if edge==0 else (0,1);cells.pop((sx+dx,sy+dy),None)
                        reachable=flood(cells,(18,35))
                        bottom=h.warp_entries()[3]
                        assert all((w[1],w[0]) in reachable for w in (top,bottom)),(seed,'grove blocked')
                    assert h.read_sram_bytes('sProcForestItemGot',1,bank=0)[0]&31!=1
                else:
                    assert theme in (0,1)
                    if species:assert theme==1 and package in (2,3),(seed,'warm rare',identity)
                    raw=h.read_sram_bytes('sProcCaveStagingBuffer',TAIL+2,bank=0)
                    ladder_a,ladder_b=raw[TAIL:]
                    accessible=ladder_a<len(SITES)
                    armed=[i for i,w in enumerate(h.warp_entries()[2:32],2) if w[0]!=255]
                    assert len(armed)==(2 if accessible else 0),(seed,'ladder arming',armed,ladder_a,ladder_b)
                    if accessible:assert ladder_b<len(SITES) or ladder_b==254
                records.append(dict(kind=kind,seed=seed,theme=theme,species=species,package=package,
                                    level=level,accessible=accessible,a=ladder_a,b=ladder_b))
                # Leave a readable progress breadcrumb even for a long corpus.
                if seed%250==0:print(kind,seed,'generated',flush=True)
        assert not h.hook_errors,h.hook_errors
        summaries={}
        for kind in ('forest','cave'):
            subset=[r for r in records if r['kind']==kind]
            if not subset:continue
            summary={'n':len(subset),'themes':dict(Counter(r['theme'] for r in subset)),
                     'selected':dict(Counter(r['species'] for r in subset)),
                     'available':dict(Counter(r['species'] for r in subset if r['accessible'] and r['species'])),
                     'lost_selected':[r['seed'] for r in subset if r['species'] and not r['accessible']],
                     'no_subroom':sum(not r['accessible'] for r in subset),
                     'conditioned':{str(t):dict(Counter(r['species'] for r in subset if r['theme']==t)) for t in sorted({r['theme'] for r in subset})}}
            summary['selected_95ci']={str(s):interval(k,len(subset)) for s,k in Counter(r['species'] for r in subset).items()}
            summaries[kind]=summary
        report={'rom':h.rom_sha256,'sym':h.sym_sha256,'hardware':h.hardware_mode,
                'fixture':'Debug2 flag cleared; real production Random/Rangerandom/themes/outcomes, no outcome hooks',
                'summary':summaries,'records':records}
        args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(summaries,indent=2),flush=True)
    finally:h.close()


if __name__=='__main__':main()
