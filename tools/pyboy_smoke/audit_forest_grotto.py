"""Bounded N/W/E geometry fixtures. Assignment is forced ONLY by test hooks.

No Pokemon is created here and this is not a production chance/placement proof.
"""
import argparse
from collections import Counter
import io
import json
from pathlib import Path
from harness import RedRogueHarness
from source_constants import parse_map_constants
from audit_forest_clearings import flood, exit_event_tiles, fc
from test_forest_grotto import cells_for_grid, assignment_fixture

ROOT=Path(__file__).resolve().parents[2]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--seeds',type=int,default=4,help='per allowed wall pair and force value, 30 normal/fallback groups')
    p.add_argument('--include-rooms',action='store_true',help='include dormant force5, which has a preserved pre-grotto connectivity failure')
    p.add_argument('--require-placement',action='store_true',help='fail if an assigned encounter has no opening')
    p.add_argument('--out',type=Path,default=ROOT/'builds/procedural_updates/three_edges/corpus.json')
    args=p.parse_args()
    h=RedRogueHarness(ROOT,ROOT/'tools/pyboy_smoke/artifacts')
    records=[];context={}
    try:
        h.boot_to_lobby(battle_count=11,encounter_kind=4);h.write8('wStageEvent',0)
        start=io.BytesIO();h.save_state(start)
        assignment_fixture(h)
        h.register_hook('PFRollBoss',lambda _:h.pyboy.memory.__setitem__(h.address('sProcForestExitEdge'),context['main']))
        h.register_hook('FGChooseWall.return',lambda _:setattr(h.pyboy.register_file,'A',context['preferred']))
        h.register_hook('PFinalizeForest',lambda _:h.write_sram_bytes('sProcForestAlgoForce',[context['algorithm']],bank=0))
        def before_carve(_):
            context['before']=[h.read8('wOverworldMap',offset=81+y*26+x) for y in range(20) for x in range(20)]
        h.register_hook('FGPrototypeCarve',before_carve)
        forest=parse_map_constants(ROOT/'constants/map_constants.asm')['PROCEDURAL_FOREST']
        for main in range(3):
            for preferred in range(3):
                if preferred==main:continue
                for algorithm in ((1,2,3,4,5,6) if args.include_rooms else (1,2,3,4,6)):
                    context.update(main=main,preferred=preferred,algorithm=algorithm)
                    for seed in range(1,args.seeds+1):
                        h.load_state(start);h.seed_rng((seed,seed^0xa5,algorithm,main+1))
                        h.preload_and_enter_wild_area(forest,'forest')
                        packed=h.read_sram_bytes('sProcForestStagingBuffer',400,bank=0)
                        live=[h.read8('wOverworldMap',offset=81+y*26+x) for y in range(20) for x in range(20)]
                        assert packed==live,(context,seed,'bake mismatch')
                        before=context.pop('before')
                        assert h.read_sram_bytes('sProcForestExitEdge',1,bank=0)==[main]
                        assert h.read_sram_bytes('sProcForestRiverSide',1,bank=0)==[255]
                        assert h.read_sram_bytes('sProcForestItemGot',1,bank=0)[0]&31!=1
                        index=h.read_sram_bytes('sProcForestExitI',1,bank=0)[0]
                        raw_cells=cells_for_grid(packed,20,20)
                        if not exit_event_tiles(main,index)&flood(raw_cells,(18,35)):
                            args.out.parent.mkdir(parents=True,exist_ok=True)
                            with args.out.with_suffix('.main_failure.pyboy').open('wb') as f:h.save_state(f)
                            cell=((2*index+1,1) if main==0 else (1 if main==1 else 17,2*index+1))
                            args.out.with_suffix('.main_failure.json').write_text(json.dumps({'context':dict(context),'seed':seed,'index':index,'inner_cell':cell,'inner_block':packed[cell[1]*20+cell[0]],'packed':packed,'tilemap':h.read_bytes('wTileMap',360),'rom':h.rom_sha256,'sym':h.sym_sha256},indent=2))
                            raise AssertionError((dict(context),seed,'main exit disconnected',index,cell,packed[cell[1]*20+cell[0]]))
                        top=h.warp_entries()[31];side=None
                        if top[0]!=255:
                            side=top[2]//2
                            assert side in (0,1,2) and side!=main
                            x,y=top[1],top[0]
                            site=(x if side==0 else y)//2
                            expected=({site:88} if side==0 else
                                      {20*site:86} if side==1 else
                                      {20*site+18:27,20*site+19:87})
                            changed={i:v for i,v in enumerate(packed) if v!=before[i]}
                            assert changed==expected,(dict(context),seed,'unexpected terrain overwrite',changed,expected)
                            assert (y==0 if side==0 else x==(0 if side==1 else 39))
                            bottom=[y+(side!=0),x+(side==0),2*side+1,top[3]]
                            assert h.warp_entries()[3]==bottom
                            cells=dict(raw_cells)
                            for slot in range(1,8):
                                if not h.read8('wSprite01StateData1',offset=16*(slot-1)):continue
                                sx=h.read8('wSprite01StateData2MapX',offset=16*(slot-1))-4
                                sy=h.read8('wSprite01StateData2MapY',offset=16*(slot-1))-4
                                cells.pop((sx,sy),None)
                                if slot==1:
                                    # The live forest script guards exactly one flank.
                                    dx,dy=(1,0) if main==0 else (0,1)
                                    cells.pop((sx+dx,sy+dy),None)
                            reach=flood(cells,(18,35))
                            for goal in ((x,y),(bottom[1],bottom[0])):
                                if goal not in reach:
                                    args.out.parent.mkdir(parents=True,exist_ok=True)
                                    with args.out.with_suffix('.failure.pyboy').open('wb') as f:h.save_state(f)
                                    args.out.with_suffix('.failure.json').write_text(json.dumps({'context':context,'seed':seed,'goal':goal,'packed':packed,'tilemap':h.read_bytes('wTileMap',360),'rom':h.rom_sha256,'sym':h.sym_sha256},indent=2))
                                    raise AssertionError((dict(context),seed,'grotto not reachable',goal))
                        if args.require_placement:
                            assert side is not None,(dict(context),seed,'assigned grotto missing')
                        records.append(dict(context,seed=seed,actual=side))
        assert not h.hook_errors,h.hook_errors
        summary={f'{a}->{b}':dict(Counter(str(r['actual']) for r in records if r['main']==a and r['preferred']==b))
                 for a in range(3) for b in range(3) if a!=b}
        report={'rom':h.rom_sha256,'sym':h.sym_sha256,'summary':summary,'records':records,
                'fixture':'assigned predicate forced by test hook; no actual Pokemon, production gate remains closed',
                'scope':'normal modes1..4 and retired6 fallback; dormant rooms5 is a separately preserved pre-carve failure' if not args.include_rooms else 'all force values including dormant rooms5'}
        args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(summary,indent=2))
        print(len(records),'layouts pass; explicit no-site:',sum(r['actual'] is None for r in records))
    finally:h.close()


if __name__=='__main__':main()
