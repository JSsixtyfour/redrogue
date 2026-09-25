"""Balance Phase 3: how many encounter-rolling steps does a wild area take?

The model turns a wild area into min(budget, steps x rate / 256) encounters, and
`steps` was a placeholder. This measures it on layouts the real ROM generates:
boot, scramble the RNG, enter the area through the lobby, then decode the
loaded map's walkability from the ROM's own tables and BFS it.

Walkability is Gen 1's rule, read from memory rather than restated:
  - a cell is passable when its bottom-left tile is in the tileset's collision
    list (wTilesetCollisionPtr, ROM0),
  - a move between two cells is blocked when their tiles form a
    TilePairCollisionsLand pair for this tileset (cave/forest elevation),
  - sprites (boss, balls) and warp cells are walls, except the destination.
Encounter-rolling cells are TryDoWildEncounter's rule: every cell on an indoor
map, but on the FOREST tileset only cells whose bottom-right tile is wGrassTile.

Two routes per layout:
  beeline   entrance -> next to the boss (the shortest way through)
  full      entrance -> all balls (best order) -> next to the boss

The decode is not trusted on its own: --validate walks the beeline in the
emulator with encounters off and asserts the player ends where the BFS said,
which fails if any wall or pair rule above is wrong.

Runs in WSL (needs PyBoy):
    python3 tools/balance/measure_wild_paths.py --stage cave --layouts 50
    python3 tools/balance/measure_wild_paths.py --stage cave --render
    python3 tools/balance/measure_wild_paths.py --stage all --layouts 200 --validate 5 --json tmp/balance/wild_paths.json
"""

from __future__ import annotations

import argparse
import json
import random
import re
import statistics
import sys
import time
from collections import deque
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants, parse_rgbds_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"
RNG_STATE_BYTES = 10
FOLLOWER_SLOT = 15        # measured: the slot that trails the player on every stage
BORDER = 3                # wOverworldMap pads the map by 3 blocks on each side

STAGES = {
    "cave": ("PROCEDURAL_CAVE_1", "Procedural Cave"),
    "forest": ("PROCEDURAL_FOREST", "Procedural Forest"),
    "facility": ("PROCEDURAL_FACILITY", "Procedural Facility"),
    "cemetery": ("PROCEDURAL_CEMETERY_1", "Procedural Cemetery"),
}
CEMETERY_FLOORS = ("PROCEDURAL_CEMETERY_1", "PROCEDURAL_CEMETERY_2", "PROCEDURAL_CEMETERY_3",
                   "PROCEDURAL_CEMETERY_4")
SUMMED = ("beeline_steps", "beeline_rolls_min", "beeline_rolls_max", "full_steps", "full_rolls", "balls")
STEPS = {"up": (-1, 0), "down": (1, 0), "left": (0, -1), "right": (0, 1)}


# =============================================================================
# Decode
# =============================================================================

class Layout:
    def __init__(self, h: RedRogueHarness, rom: bytes, tilesets: dict[str, int], indoor: bool,
                 ball_pic: int, boss_in_slot1: bool = True):
        mem = h.pyboy.memory
        word = lambda label: h.read8(label) | (h.read8(label, 1) << 8)
        self.bw, self.bh = h.read8("wCurMapWidth"), h.read8("wCurMapHeight")
        self.w, self.h = 2 * self.bw, 2 * self.bh
        self.tileset = h.read8("wCurMapTileset")
        self.grass = h.read8("wGrassTile")

        coll_ptr = word("wTilesetCollisionPtr")
        self.passable: set[int] = set()
        while mem[coll_ptr] != 0xFF:
            self.passable.add(mem[coll_ptr])
            coll_ptr += 1

        pair_ptr = h.address("TilePairCollisionsLand")
        self.pairs: set[frozenset[int]] = set()
        while mem[pair_ptr] != 0xFF:
            if mem[pair_ptr] == self.tileset:
                self.pairs.add(frozenset((mem[pair_ptr + 1], mem[pair_ptr + 2])))
            pair_ptr += 3

        bank, blocks_ptr = h.read8("wTilesetBank"), word("wTilesetBlocksPtr")
        if blocks_ptr >= 0x8000:
            self.block_bytes = lambda i: mem[blocks_ptr + i]
        else:
            off = blocks_ptr if blocks_ptr < 0x4000 else bank * 0x4000 + (blocks_ptr - 0x4000)
            self.block_bytes = lambda i: rom[off + i]

        base, stride = h.address("wOverworldMap"), self.bw + 2 * BORDER
        self.blocks = [[mem[base + (by + BORDER) * stride + bx + BORDER] for bx in range(self.bw)]
                       for by in range(self.bh)]

        self.start = (h.read8("wYCoord"), h.read8("wXCoord"))
        # Slot 1 is the boss everywhere. Balls are every slot showing the poke
        # ball picture: 2-5 on every stage, plus the facility's four fake item
        # balls in 6-9, which the player cannot tell from real ones. Every
        # other map object (the cave/forest stage-event pair in 6-7) is a wall
        # too. Slot 15 is the follower, which trails the player and blocks
        # nothing.
        pics = h.address("wSpritePlayerStateData1PictureID")
        objects = {}
        for slot, pos in enumerate(h.sprite_positions(FOLLOWER_SLOT - 1), start=1):
            pic = mem[pics + slot * 16]
            if pic and self.inside(tuple(pos)):
                objects[slot] = (tuple(pos), pic)
        # Slot 1 is the boss on cave/forest/facility even when its picture is
        # the poke ball (measured: 2/200 caves). The cemetery's boss is a
        # coordinate trigger, and its slot 1 is an ordinary ball.
        self.boss = objects[1][0] if boss_in_slot1 and 1 in objects else None
        self.slot1 = objects.get(1)
        self.balls = [pos for slot, (pos, pic) in objects.items()
                      if pic == ball_pic and (slot > 1 or not boss_in_slot1)]
        self.warp_rows = h.warp_entries()
        self.warps = {(e[0], e[1]) for e in self.warp_rows}
        self.walls = {pos for pos, _ in objects.values()} | (self.warps - {self.start})
        self.goal_warp = None     # set by aim_at_warp: route ONTO this cell instead of to the boss
        self.encounter_everywhere = indoor and self.tileset != tilesets["FOREST"]

    def inside(self, p) -> bool:
        return 0 <= p[0] < self.h and 0 <= p[1] < self.w

    def tile(self, cell, r: int, c: int) -> int:
        cy, cx = cell
        block = self.blocks[cy // 2][cx // 2]
        return self.block_bytes(block * 16 + (2 * (cy % 2) + r) * 4 + 2 * (cx % 2) + c)

    def standing(self, cell) -> int:
        return self.tile(cell, 1, 0)       # bottom-left: collision + pair checks

    def rolls(self, cell) -> bool:
        return self.encounter_everywhere or self.tile(cell, 1, 1) == self.grass

    def can_step(self, a, b) -> bool:
        if not self.inside(b) or b in self.walls or self.standing(b) not in self.passable:
            return False
        return frozenset((self.standing(a), self.standing(b))) not in self.pairs

    def neighbours(self, a):
        for dy, dx in STEPS.values():
            b = (a[0] + dy, a[1] + dx)
            if self.can_step(a, b):
                yield b

    def bfs(self, sources) -> dict:
        """cell -> (steps, min rolling steps, max rolling steps, parent)."""
        out = {s: (0, 0, 0, None) for s in sources}
        queue = deque(sources)
        while queue:
            a = queue.popleft()
            d, lo, hi, _ = out[a]
            for b in self.neighbours(a):
                r = int(self.rolls(b))
                if b not in out:
                    out[b] = (d + 1, lo + r, hi + r, a)
                    queue.append(b)
                elif out[b][0] == d + 1:   # another shortest path: widen the roll range
                    ob = out[b]
                    out[b] = (ob[0], min(ob[1], lo + r), max(ob[2], hi + r), ob[3])
        return out

    def adjacent(self, p) -> list:
        return [(p[0] + dy, p[1] + dx) for dy, dx in STEPS.values()
                if self.inside((p[0] + dy, p[1] + dx))
                and (p[0] + dy, p[1] + dx) not in self.walls
                and self.standing((p[0] + dy, p[1] + dx)) in self.passable]

    def aim_at(self, cells) -> None:
        """Route ONTO any of these cells (stairs, a coordinate trigger)."""
        self.goal_warp = set(cells)
        self.walls -= self.goal_warp

    def goal_hit(self, reach: dict):
        if self.goal_warp is not None:
            hits = [(reach[c], c) for c in self.goal_warp if c in reach]
            return min(hits, key=lambda x: (x[0][0], x[0][1])) if hits else None
        return self.best(reach, self.boss)

    def best(self, reach: dict, target):
        hits = [(reach[c], c) for c in self.adjacent(target) if c in reach]
        return min(hits, key=lambda x: (x[0][0], x[0][1])) if hits else None

    def measure(self) -> dict:
        if self.goal_warp is None and self.boss is None:
            return {"reachable": False, "balls": len(self.balls),
                    "note": f"no boss sprite; slot 1 = {self.slot1}"}
        from_start = self.bfs([self.start])
        boss = self.goal_hit(from_start)
        row = {"reachable": boss is not None, "balls": len(self.balls)}
        if boss is None:
            row["note"] = "goal unreachable from the entrance"
        if boss is None:
            return row
        (steps, lo, hi, _), end = boss
        row.update(beeline_steps=steps, beeline_rolls_min=lo, beeline_rolls_max=hi,
                   path=self.path(from_start, end))

        # Full clear: the best ball order (Held-Karp). A node is a (ball, cell
        # beside it) pair, and each leg is a BFS from that exact cell, so the
        # route cannot hop around a ball between two of its sides for free.
        nodes = [(i, c) for i, s in enumerate(self.balls) for c in self.adjacent(s)]
        n = len(self.balls)
        if not n:
            row.update(full_steps=steps, full_rolls=lo)
            return row
        reach = [self.bfs([c]) for _, c in nodes]
        cell_cost = lambda r, c: (r[c][0], r[c][1]) if c in r else None
        add = lambda a, b: (a[0] + b[0], a[1] + b[1])
        dp: dict = {}
        for k, (i, c) in enumerate(nodes):
            v = cell_cost(from_start, c)
            if v is not None and v < dp.get((1 << i, k), (10 ** 9, 0)):
                dp[(1 << i, k)] = v
        for mask in range(1, 1 << n):
            for k, (i, _) in enumerate(nodes):
                here = dp.get((mask, k))
                if here is None:
                    continue
                for k2, (j, c2) in enumerate(nodes):
                    if mask & (1 << j):
                        continue
                    leg = cell_cost(reach[k], c2)
                    if leg is None:
                        continue
                    key, val = (mask | (1 << j), k2), add(here, leg)
                    if val < dp.get(key, (10 ** 9, 0)):
                        dp[key] = val
        done = (1 << n) - 1
        finals = []
        for k in range(len(nodes)):
            if (done, k) in dp:
                hit = self.goal_hit(reach[k])
                if hit is not None:
                    finals.append(add(dp[(done, k)], (hit[0][0], hit[0][1])))
        if finals:
            full = min(finals)
            row.update(full_steps=full[0], full_rolls=full[1])
        return row

    @staticmethod
    def path(reach: dict, end) -> list:
        out = []
        while end is not None:
            out.append(end)
            end = reach[end][3]
        return out[::-1]

    def render(self, path=()) -> str:
        on_path = set(path)
        lines = []
        for y in range(self.h):
            row = ""
            for x in range(self.w):
                c = (y, x)
                row += ("@" if c == self.start else "B" if c == self.boss else "o" if c in self.balls
                        else "W" if c in self.warps else "*" if c in on_path
                        else ("," if self.rolls(c) else ".") if self.standing(c) in self.passable else "#")
            lines.append(row)
        return "\n".join(lines)


# =============================================================================
# Driving the ROM
# =============================================================================

def enter(stage: str, seed: int, maps: dict[str, int]) -> RedRogueHarness:
    map_name, description = STAGES[stage]
    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    h.boot_to_lobby()
    rng = random.Random(seed)
    base = h.address("wRandomTable")
    for offset in range(RNG_STATE_BYTES):     # never all-zero: zero is absorbing for the CMWC
        h.pyboy.memory[base + offset] = rng.randrange(1, 256)
    h.preload_and_enter_wild_area(maps[map_name], description)
    return h


def _press(h: RedRogueHarness, direction: str, a) -> tuple[int, int]:
    """One step attempt from cell a; returns where the player ends up."""
    here = a
    for _ in range(3):                     # a press can be eaten, or only turn the player
        h.pyboy.button_press(direction)
        h.tick(3)
        h.pyboy.button_release(direction)
        # wYCoord/wXCoord change at the START of a step; wait for it to end so
        # the next press is one step, not a held key.
        for _ in range(60):
            h.tick(1)
            if h.read8("wWalkCounter") == 0 and (h.read8("wYCoord"), h.read8("wXCoord")) != a:
                break
        h.tick(2)
        here = (h.read8("wYCoord"), h.read8("wXCoord"))
        if here != a:
            break
    return here


def validate_walk(h: RedRogueHarness, lay: Layout, path: list, bumps: int = 6) -> tuple[bool, str, int]:
    """Walk the BFS path with encounters off; the player must end on its last
    cell. Along the way, press into up to `bumps` cells the decoder calls
    blocked by a tile (not a sprite or warp) and require the player not to
    move: a false wall would otherwise only make paths look longer."""
    h.write8("wGrassRate", 0)
    here = (h.read8("wYCoord"), h.read8("wXCoord"))
    bumped = 0
    for a, b in zip(path, path[1:]):
        if here != a:
            return False, f"at {here}, expected {a}", bumped
        if bumped < bumps:
            for direction, (dy, dx) in STEPS.items():
                wall = (a[0] + dy, a[1] + dx)
                if (lay.inside(wall) and wall not in lay.walls and not lay.can_step(a, wall)):
                    if _press(h, direction, a) != a:
                        return False, f"walked into decoded wall {wall} from {a}", bumped
                    bumped += 1
                    break
        direction = next(k for k, (dy, dx) in STEPS.items() if (a[0] + dy, a[1] + dx) == b)
        here = _press(h, direction, a)
        if here != b:
            return False, f"stuck at {here} trying {a}->{b} ({direction})", bumped
    return True, "ok", bumped


def take_warp(h: RedRogueHarness, path: list) -> bool:
    """Walk a path whose last cell is a warp; True once the map has changed."""
    before = h.read8("hCurMap")
    here = path[0]
    for a, b in zip(path, path[1:]):
        if here != a:
            return False
        direction = next(k for k, (dy, dx) in STEPS.items() if (a[0] + dy, a[1] + dx) == b)
        here = _press(h, direction, a)
        if h.read8("hCurMap") != before:
            break
    for _ in range(600):
        if h.read8("hCurMap") != before:
            h.tick(240)              # the next floor generates on load
            return True
        h.tick(1)
    return False


def cemetery_boss_cells() -> list:
    """ProceduralCemetery4BossCoords: the boss is a coordinate trigger, not a
    sprite. dbmapcoord is x, y; cells here are (y, x)."""
    text = (REPO_ROOT / "scripts" / "ProceduralCemetery4.asm").read_text(encoding="utf-8")
    body = text.split("ProceduralCemetery4BossCoords:", 1)[1].split("db -1", 1)[0]
    cells = [(int(y), int(x)) for x, y in re.findall(r"dbmapcoord\s+(\d+)\s*,\s*(\d+)", body)]
    if not cells:
        raise ValueError("ProceduralCemetery4BossCoords not found")
    return cells


def measure_cemetery(h: RedRogueHarness, rom: bytes, tilesets, ball_pic, maps, render: bool) -> dict:
    """Floor by floor: route onto the forward stairs, take them, repeat until
    the floor with the boss. The walk is the validation, since a floor that
    cannot actually be left cannot be measured."""
    floor_ids = {maps[n] for n in CEMETERY_FLOORS}
    boss_floor, boss_cells = maps[CEMETERY_FLOORS[-1]], cemetery_boss_cells()
    total = {"reachable": True, "floors": 0, **{k: 0 for k in SUMMED}}
    h.write8("wGrassRate", 0)
    for _ in range(len(CEMETERY_FLOORS) + 2):
        cur = h.read8("hCurMap")
        lay = Layout(h, rom, tilesets, True, ball_pic, boss_in_slot1=False)
        if cur == boss_floor:
            lay.aim_at(boss_cells)
        else:
            forward = [(e[0], e[1]) for e in lay.warp_rows if e[3] in floor_ids and e[3] > cur]
            if not forward:
                return {**total, "reachable": False, "note": f"no forward stairs on map {cur:#x}"}
            lay.aim_at(forward[:1])
        row = lay.measure()
        if render:
            print(lay.render(row.get("path", ())))
            print({k: v for k, v in row.items() if k != "path"})
        if not row["reachable"]:
            return {**total, "reachable": False, "note": f"map {cur:#x} goal unreachable"}
        total["floors"] += 1
        for k in SUMMED:
            total[k] += row.get(k, 0)
        if cur == boss_floor:
            total["walk_ok"], total["walk_note"] = True, "every floor's stairs taken"
            return total
        # The floor's stairs sit adjacent to where the next floor puts the
        # player, so the path to them is also this floor's validation walk.
        if not take_warp(h, row["path"]):
            return {**total, "reachable": False, "walk_ok": False,
                    "walk_note": f"stairs on map {cur:#x} did not warp"}
        h.write8("wGrassRate", 0)
    return {**total, "reachable": False, "note": "no boss floor reached"}


def run_stage(stage: str, layouts: int, validate: int, render: bool, seed0: int) -> list[dict]:
    maps = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
    tilesets = parse_rgbds_constants(REPO_ROOT / "constants" / "tileset_constants.asm")
    first_indoor = parse_rgbds_constants(REPO_ROOT / "constants" / "map_constants.asm").get("FIRST_INDOOR_MAP")
    rom = (REPO_ROOT / "pokeblue_debug.gbc").read_bytes()
    ball_pic = parse_rgbds_constants(REPO_ROOT / "constants" / "sprite_constants.asm")["SPRITE_POKE_BALL"]
    rows = []
    for i in range(layouts):
        h = enter(stage, seed0 + i, maps)
        try:
            if stage == "cemetery":
                rows.append({"stage": stage, "seed": seed0 + i,
                             **measure_cemetery(h, rom, tilesets, ball_pic, maps, render)})
                continue
            map_id = h.read8("hCurMap")
            indoor = first_indoor is None or map_id >= first_indoor
            lay = Layout(h, rom, tilesets, indoor, ball_pic)
            row = {"stage": stage, "seed": seed0 + i, **lay.measure()}
            if render:
                print(lay.render(row.get("path", ())))
                print(json.dumps({k: v for k, v in row.items() if k != "path"}))
            if i < validate and row["reachable"]:
                row["walk_ok"], row["walk_note"], row["walls_bumped"] = validate_walk(h, lay, row["path"])
            row.pop("path", None)
            rows.append(row)
        finally:
            try:
                h.close()
            except Exception:
                pass
    return rows


def summarize(rows: list[dict]) -> dict:
    ok = [r for r in rows if r["reachable"]]
    out = {"layouts": len(rows), "unreachable": len(rows) - len(ok)}
    for key in ("beeline_steps", "beeline_rolls_min", "beeline_rolls_max", "full_steps", "full_rolls"):
        vals = sorted(r[key] for r in ok if key in r)
        if vals:
            out[key] = {"mean": round(statistics.mean(vals), 1), "p10": vals[len(vals) // 10],
                        "median": vals[len(vals) // 2], "p90": vals[len(vals) * 9 // 10]}
    walks = [r for r in rows if "walk_ok" in r]
    out["walks"] = f"{sum(r['walk_ok'] for r in walks)}/{len(walks)}"
    out["walls_bumped"] = sum(r.get("walls_bumped", 0) for r in walks)
    notes = [(r["seed"], r["note"]) for r in rows if r.get("note")]
    if notes:
        out["notes"] = notes[:10]
    bad = [r for r in walks if not r["walk_ok"]]
    if bad:
        out["walk_failures"] = [(r["seed"], r["walk_note"]) for r in bad]
    return out


MODEL_INPUT = Path(__file__).resolve().parent / "data" / "wild_paths.json"


def model_input(report: dict) -> dict:
    """The compact form model.py samples from: encounter-rolling steps per
    layout. The forest's beeline takes the middle of its shortest paths' grass
    range, since a player neither seeks nor dodges grass on the way through."""
    out = {}
    for stage, body in report.items():
        ok = [r for r in body["rows"] if r["reachable"] and "full_rolls" in r]
        out[stage] = {
            "layouts": len(body["rows"]),
            "unreachable": len(body["rows"]) - len(ok),
            "beeline": [(r["beeline_rolls_min"] + r["beeline_rolls_max"]) // 2 for r in ok],
            "full": [r["full_rolls"] for r in ok],
            "measured": time.strftime("%Y-%m-%d"),
        }
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stage", choices=[*STAGES, "all"], default="all")
    ap.add_argument("--layouts", type=int, default=50)
    ap.add_argument("--validate", type=int, default=3, help="walk the beeline on the first N layouts")
    ap.add_argument("--render", action="store_true", help="print each layout's grid (use with --layouts 1)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--json", type=Path, help="write the summary + per-layout rows here")
    ap.add_argument("--model-out", type=Path, default=MODEL_INPUT,
                    help="where model.py reads its input (written only for --stage all)")
    ap.add_argument("--from-json", type=Path, help="skip measuring; rebuild --model-out from a --json file")
    args = ap.parse_args(argv)

    if args.from_json:
        args.model_out.parent.mkdir(parents=True, exist_ok=True)
        args.model_out.write_text(json.dumps(model_input(json.loads(args.from_json.read_text())), indent=1))
        print(f"wrote {args.model_out}")
        return 0

    report = {}
    failed = False
    for stage in (STAGES if args.stage == "all" else [args.stage]):
        t0 = time.time()
        rows = run_stage(stage, args.layouts, args.validate, args.render, args.seed)
        summary = summarize(rows)
        report[stage] = {"summary": summary, "rows": rows}
        print(f"{stage}: {json.dumps(summary)}  ({time.time() - t0:.0f}s)")
        failed |= bool(summary.get("walk_failures")) or summary["unreachable"] > 0
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=1))
        print(f"wrote {args.json}")
    if args.stage == "all":
        args.model_out.parent.mkdir(parents=True, exist_ok=True)
        args.model_out.write_text(json.dumps(model_input(report), indent=1))
        print(f"wrote {args.model_out}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
