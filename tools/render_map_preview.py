"""Render a block map from actual Red Rogue assets, with optional event overlays.

This is an offline source-data render, not an emulator screenshot. No game files
are modified. WSL/Pillow is the normal project environment.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[1]
TREE_TILES=(4,5,6,7,35,21,22,23,36,37,38,39,53,54)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',type=Path,default=ROOT if (ROOT/'gfx/blocksets').is_dir() else Path.cwd(),
                   help='Red Rogue repository root; useful for the bundled skill copy')
    p.add_argument('--blocks',type=Path,required=True)
    p.add_argument('--width',type=int,required=True,help='32px blocks, not event tiles')
    p.add_argument('--height',type=int,required=True)
    p.add_argument('--tileset',required=True,help='asset stem, e.g. forest or cavern')
    p.add_argument('--scale',type=int,default=2)
    p.add_argument('--season',type=int,choices=(0,1,2,3),help='forest art only; does not simulate CGB palettes')
    p.add_argument('--collision',action='store_true')
    p.add_argument('--events',type=Path,help='JSON array: x, y, label, optional facing; event coordinates')
    p.add_argument('--out',type=Path,required=True)
    args=p.parse_args()
    root=args.root.resolve()
    if min(args.width,args.height,args.scale)<1:p.error('width, height and scale must be positive')
    raw=args.blocks.read_bytes()
    if len(raw)!=args.width*args.height:p.error(f'{len(raw)} bytes do not match {args.width}x{args.height}')
    gfx_path=root/f'gfx/tilesets/{args.tileset}.2bpp'
    block_path=root/f'gfx/blocksets/{args.tileset}.bst'
    gfx=bytearray(gfx_path.read_bytes());blocks=block_path.read_bytes()
    if len(gfx)%16 or len(blocks)%16:p.error('graphics and blockset must contain complete 16-byte records')
    if args.season is not None:
        if args.tileset!='forest':p.error('--season applies only to forest')
        if args.season in (0,3):
            name='cherry' if args.season==0 else 'winter'
            seasonal=(root/f'gfx/tilesets/forest_{name}.2bpp').read_bytes()
            for i,t in enumerate(TREE_TILES):gfx[t*16:t*16+16]=seasonal[i*16:i*16+16]
    events=json.loads(args.events.read_text()) if args.events else []
    for event in events:
        if not (0<=event['x']<2*args.width and 0<=event['y']<2*args.height):
            p.error(f'event outside map: {event}')
    native=Image.new('RGB',(args.width*32,args.height*32))
    for i,block in enumerate(raw):
        if block*16+16>len(blocks):p.error(f'unknown block {block:#x} at index {i}')
        for q,t in enumerate(blocks[block*16:block*16+16]):
            if t*16+16>len(gfx):p.error(f'block {block:#x} references missing tile {t:#x}')
            for y in range(8):
                lo,hi=gfx[t*16+y*2:t*16+y*2+2]
                for x in range(8):
                    shade=(255,168,88,0)[((lo>>(7-x))&1)|(((hi>>(7-x))&1)<<1)]
                    native.putpixel((i%args.width*32+q%4*8+x,i//args.width*32+q//4*8+y),(shade,)*3)
    args.out.parent.mkdir(parents=True,exist_ok=True)
    native.save(args.out.with_name(args.out.stem+'_native.png'))
    margin,top,cell=36,55,16*args.scale
    art=native.resize((native.width*args.scale,native.height*args.scale),Image.Resampling.NEAREST)
    sheet=Image.new('RGB',(art.width+margin+12,art.height+top+32),'#17202b')
    sheet.paste(art,(margin,top))
    draw=ImageDraw.Draw(sheet)
    font_path=Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
    font=ImageFont.truetype(str(font_path),12) if font_path.exists() else ImageFont.load_default()
    draw.text((10,8),f'{args.blocks.name}: {args.width}x{args.height} blocks; event grid below',font=font,fill='white')
    walk=None
    if args.collision:
        source=(root/'data/tilesets/collision_tile_ids.asm').read_text()
        match=re.search(r'^'+re.escape(args.tileset)+r'_Coll::\s*\n\s*coll_tiles\s+([^\n;]+)',source,re.I|re.M)
        if not match:p.error(f'no collision list for {args.tileset}')
        walk={int(v.strip().replace('$',''),16) for v in match.group(1).split(',')}
    collision=[]
    layer=Image.new('RGBA',sheet.size);d=ImageDraw.Draw(layer)
    for y in range(args.height*2):
        for x in range(args.width*2):
            b=raw[(y//2)*args.width+x//2]
            tile=blocks[b*16+(4,6,12,14)[(y%2)*2+x%2]]
            collision.append(tile)
            box=(margin+x*cell,top+y*cell,margin+(x+1)*cell-1,top+(y+1)*cell-1)
            if walk is not None and tile not in walk:d.rectangle(box,fill=(255,30,30,55))
            d.rectangle(box,outline=(90,120,155,100))
    sheet=Image.alpha_composite(sheet.convert('RGBA'),layer).convert('RGB');draw=ImageDraw.Draw(sheet)
    for x in range(args.width*2):draw.text((margin+x*cell+3,top-20),str(x),font=font,fill='white')
    for y in range(args.height*2):draw.text((6,top+y*cell+3),str(y),font=font,fill='white')
    for event in events:
        cx,cy=margin+event['x']*cell+cell//2,top+event['y']*cell+cell//2
        radius=max(8,cell//2-2)
        color=event.get('color','#45ff65')
        draw.ellipse((cx-radius,cy-radius,cx+radius,cy+radius),fill='#17202b',outline=color,width=2)
        draw.text((cx,cy),event.get('label','M'),font=font,fill=color,anchor='mm')
        if event.get('facing')=='south':
            draw.line((cx,cy+radius-3,cx,cy+radius+5),fill=color,width=2)
            draw.line((cx-3,cy+radius+2,cx,cy+radius+5,cx+3,cy+radius+2),fill=color,width=2)
    draw.text((10,top+art.height+8),'Source render, DMG grays. Red tint = solid; no runtime acceptance implied.',font=font,fill='white')
    sheet.save(args.out)
    manifest={'blocks':str(args.blocks),'width':args.width,'height':args.height,'tileset':args.tileset,
              'scale':args.scale,'season':args.season,'events':events,'collision_tiles':collision,
              'source_sha256':{str(path):hashlib.sha256(path.read_bytes()).hexdigest()
                               for path in (args.blocks,gfx_path,block_path)},
              'kind':'offline source render; not emulator screenshot or reachability proof'}
    args.out.with_suffix('.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(args.out)


if __name__=='__main__':main()
