"""Exact cave block art with event coordinates and reachable placement choices.

Writes review artifacts only. Does not change maps or encounter positions.
Run from WSL: python3 tools/pyboy_smoke/render_subroom_placement.py
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
from render_cave_region import load_tiles, load_blocks
from test_cave_subroom import ROOMS, room_tiles, room_reach, WALKABLE, ELEVATION_PAIRS

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'builds/procedural_updates/checkpoint3/placement'
FONT = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 13)
SMALL = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 10)
COLORS = {'L1':'#ffdc39', 'L2':'#ffdc39', 'R':'#ff8b34', 'I':'#ffffff',
          'W':'#20d9ed', 'S':'#ef92eb', 'A':'#45ff65', 'B':'#45ff65',
          'r':'#ff8b34', 'i':'#ffffff'}


def neighbours(p):
    return [(p[0]+dx, p[1]+dy) for dx, dy in ((1,0),(-1,0),(0,1),(0,-1))]


def choices(room):
    occupied = {room[k] for k in ('resident','ball','water','land')} | set(room['ladders'])
    tiles = room_tiles(room)
    base = room_reach(room, room['ladders'][0], occupied - set(room['ladders']))
    valid = []
    for p in sorted(base):
        if p in occupied or any(abs(p[0]-q[0])+abs(p[1]-q[1]) < 3 for q in occupied):
            continue
        if not all(q in tiles and tiles[q] in WALKABLE and
                   (tiles[p],tiles[q]) not in ELEVATION_PAIRS for q in neighbours(p)):
            continue
        blocked = occupied - set(room['ladders']) | {p}
        reach = room_reach(room, room['ladders'][0], blocked)
        if not all(q in reach for q in room['ladders']):
            continue
        if not all(any(q in reach for q in neighbours(room[k])) for k in ('resident','ball')):
            continue
        talks = [q for q in neighbours(p) if q in reach]
        if talks:
            valid.append((p, talks, len(reach)))
    # Prefer open central positions; spread the alternative away from A.
    centre = (room['w'],room['h'])
    valid.sort(key=lambda v: (abs(v[0][0]-centre[0])+abs(v[0][1]-centre[1]),v[0]))
    assert valid, room['name']
    a = valid[0]
    rest = sorted(valid[1:], key=lambda v: (-min(6,abs(v[0][0]-a[0][0])+abs(v[0][1]-a[0][1])),
                                         abs(v[0][0]-centre[0])+abs(v[0][1]-centre[1]),v[0]))
    assert rest
    return dict(zip(('A','B'),(a,rest[0])))


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    blocks, tiles = load_blocks(), load_tiles()
    report = []
    for room in ROOMS:
        native = Image.new('RGB',(room['w']*32,room['h']*32))
        for by in range(room['h']):
            for bx in range(room['w']):
                block = blocks[room['blocks'][by*room['w']+bx]]
                for ty in range(4):
                    for tx in range(4):
                        tile = tiles[block[ty*4+tx]]
                        for py in range(8):
                            for px in range(8):
                                v = (255,168,88,0)[tile[py][px]]
                                native.putpixel((bx*32+tx*8+px,by*32+ty*8+py),(v,v,v))
        native.save(OUT/f'{room["name"]}_native.png')
        picks = choices(room)
        w,h = room['w']*2,room['h']*2
        cell,margin,top = 32,36,64
        art = native.resize((w*cell,h*cell),Image.Resampling.NEAREST)
        sheet = Image.new('RGB',(w*cell+margin+12,h*cell+top+140),'#17202b')
        sheet.paste(art,(margin,top))
        overlay = Image.new('RGBA',sheet.size)
        d = ImageDraw.Draw(overlay)
        tt = room_tiles(room)
        for (x,y),tile in tt.items():
            box=(margin+x*cell,top+y*cell,margin+(x+1)*cell-1,top+(y+1)*cell-1)
            if tile not in WALKABLE:
                d.rectangle(box,fill=(255,40,40,42))
            d.rectangle(box,outline=(90,120,155,100))
            for dx,dy in ((1,0),(0,1)):
                q=(x+dx,y+dy)
                if q in tt and (tile,tt[q]) in ELEVATION_PAIRS:
                    if dx:
                        d.line((box[2],box[1],box[2],box[3]),fill='#bb42ff',width=4)
                    else:
                        d.line((box[0],box[3],box[2],box[3]),fill='#bb42ff',width=4)
        sheet=Image.alpha_composite(sheet.convert('RGBA'),overlay).convert('RGB')
        d=ImageDraw.Draw(sheet)
        d.text((12,8),f'{room["name"]}: existing geometry, event tile coordinates',font=FONT,fill='white')
        d.text((12,29),'Red tint: blocked   Purple: forbidden elevation step   Green: proposed A/B',font=FONT,fill='white')
        for x in range(w):
            d.text((margin+x*cell+8,top-20),str(x),font=SMALL,fill='white')
        for y in range(h):
            d.text((7,top+y*cell+9),str(y),font=SMALL,fill='white')
        marks={'L1':room['ladders'][0],'L2':room['ladders'][1],
               **{label:room[key] for label,key in [('R','resident'),('I','ball'),('W','water'),('S','land')]},
               **{label:value[0] for label,value in picks.items()}}
        reach = room_reach(room,room['ladders'][0],{room['resident'],room['ball']})
        interaction_tiles = {key: next(q for q in neighbours(room[key]) if q in reach)
                             for key in ('resident','ball')}
        marks.update({'r':interaction_tiles['resident'],'i':interaction_tiles['ball']})
        for label,(x,y) in marks.items():
            cx,cy=margin+x*cell+16,top+y*cell+16
            d.ellipse((cx-13,cy-13,cx+13,cy+13),fill='#17202b',outline=COLORS[label],width=2)
            d.text((cx-8,cy-8),label,font=FONT,fill=COLORS[label])
        yy=top+h*cell+10
        d.text((12,yy),'L1/L2: returns   R: resident   I: item   W: water scenery   S: land scenery',font=FONT,fill='white')
        for i,(label,(p,talks,_)) in enumerate(picks.items()):
            d.text((12,yy+23+i*22),f'{label}: {p}; safe adjacent talk tiles: {talks}',font=FONT,fill=COLORS[label])
        d.text((12,yy+73),f'r: resident talk tile {interaction_tiles["resident"]}; i: item approach {interaction_tiles["ball"]}',font=FONT,fill='white')
        d.text((12,yy+104),'Exact source art, 2x pixels. Markers are review overlays, not sprites.',font=SMALL,fill='white')
        sheet.save(OUT/f'{room["name"]}_review.png')
        report.append({'name':room['name'],'choices':{k:{'position':v[0],'talk_tiles':v[1],'reachable_tiles':v[2]} for k,v in picks.items()},
                       'existing':marks,'interaction_tiles':interaction_tiles})
    (OUT/'positions.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__ == '__main__':
    main()
