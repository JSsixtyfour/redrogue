"""Natural, one-partner and zero-site cave policy with distinct warp pairs."""
import argparse
import io
import json
from collections import deque
from pathlib import Path
from harness import RedRogueHarness
from source_constants import parse_map_constants
import test_cave_subroom as cave


def tiles(grid):
    bst=(cave.ROOT/'gfx/blocksets/cavern.bst').read_bytes()
    return {(2*x+q%2,2*y+q//2):bst[grid[y*20+x]*16+i]
            for y in range(20) for x in range(20) for q,i in enumerate((4,6,12,14))
            if bst[grid[y*20+x]*16+i] in cave.WALKABLE}


def reach(grid,blocked=()):
    cells=tiles(grid);start=(18,39);seen={start};todo=deque([start]);blocked=set(blocked)
    while todo:
        x,y=todo.popleft()
        for p in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
            if p in cells and p not in seen and p not in blocked and (cells[x,y],cells[p]) not in cave.ELEVATION_PAIRS:
                seen.add(p);todo.append(p)
    return seen


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--seeds',type=int,default=100)
    p.add_argument('--out',type=Path,required=True)
    args=p.parse_args();context={};records=[]
    h=RedRogueHarness(cave.ROOT,cave.ARTIFACTS)
    try:
        h.boot_to_lobby(battle_count=11,encounter_kind=4);h.write8('wStageEvent',0)
        base=io.BytesIO();h.save_state(base)
        h.register_hook('OptionalCaveAssignEncounter',lambda _:h.pyboy.memory.__setitem__(h.address('sProcCavePalette'),context['cold']))
        def exhaust(_):
            if context['mode']=='zero' or (context['mode']=='single' and h.pyboy.register_file.C!=255):
                h.pyboy.register_file.HL&=0xff00
        h.register_hook('CaveLadderWalk.end',exhaust)
        def before(_):
            context['grid']=[h.read8('wOverworldMap',offset=81+y*26+x) for y in range(20) for x in range(20)]
            context['actors']=[h.read_bytes('wSprite01StateData2MapY',2,16*i) for i in range(7)]
        h.register_hook('CaveSubroomPlaceLadders',before)
        parent=parse_map_constants(cave.ROOT/'constants/map_constants.asm')['PROCEDURAL_CAVE_1']
        for cold,mode in ((1,'natural'),(0,'natural'),(1,'single'),(0,'single'),(1,'zero'),(0,'zero')):
            context.update(cold=cold,mode=mode)
            for seed in range(1,args.seeds+1):
                h.load_state(base);h.seed_rng((seed&255,(seed>>8)+1,seed^0xa5&255,37))
                h.preload_and_enter_wild_area(parent,'cave')
                grid=[h.read8('wOverworldMap',offset=81+y*26+x) for y in range(20) for x in range(20)]
                raw=h.read_sram_bytes('sProcCaveStagingBuffer',cave.TAIL+4,bank=0)
                a,b=raw[cave.TAIL:cave.TAIL+2];assigned=bool(h.read8('wOptionalEncounterSpecies'))
                assert assigned==bool(cold),(seed,cold,assigned)
                assert context['grid'][19*20+9]==36,(seed,'entrance invariant')
                assert [h.read_bytes('wSprite01StateData2MapY',2,16*i) for i in range(7)]==context['actors'],(seed,'actor moved')
                fallback=b==254
                expected={};armed=set();blocked=set()
                if a<len(cave.SITES):
                    ax,ay=cave.SITES[a];expected[ay*20+ax]=40;armed.add(2+a);blocked.add((2*ax+1,2*ay+1))
                    assert b<len(cave.SITES) or fallback,(seed,'one site has no second connection',a,b)
                    if b<len(cave.SITES):
                        bx,by=cave.SITES[b];expected[by*20+bx]=40;armed.add(2+b);blocked.add((2*bx+1,2*by+1))
                    else:
                        expected[389]=40
                        if context['grid'][390] in (14,19):expected[390]=1
                        slot=3 if a==0 else 2;armed.add(slot);blocked.add((19,39))
                        assert h.warp_entries()[slot][:2]==[39,19]
                        old=reach(context['grid']);new=reach(grid,blocked)
                        assert old-blocked<=new,(seed,'ladder cuts cave',sorted(old-new-blocked))
                else:
                    assert not fallback and grid[389]==36,(seed,'zero sites added a basement',a,b)
                if mode=='single':assert fallback,(seed,'forced single missing entrance',a,b)
                if mode=='zero':assert a>=len(cave.SITES),(seed,'zero sites got an ordinary ladder')
                assert {i:v for i,v in enumerate(grid) if v!=context['grid'][i]}==expected,(seed,mode,'unexpected terrain edit')
                assert {i for i,w in enumerate(h.warp_entries()[2:32],2) if w[0]!=255}==armed,(seed,mode,'wrong armed slots')
                records.append(dict(seed=seed,cold=cold,mode=mode,a=a,b=b,fallback=fallback,assigned=assigned))
        assert not h.hook_errors,h.hook_errors
        report={'rom':h.rom_sha256,'sym':h.sym_sha256,'records':records,
                'layouts':len(records),'entrance_fallbacks':sum(r['fallback'] for r in records),
                'accepted_zero_site_cases':sum(r['a']>=len(cave.SITES) for r in records)}
        args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps({k:v for k,v in report.items() if k!='records'},indent=2))
    finally:h.close()


if __name__=='__main__':main()
