"""Checkpoint 2 probe: rarity-colored reward Poke Balls on CGB, both colour modes.

Enter a real stage, record the cache the natural roll built, then force one
offer per tier, rebuild, move the stage's four balls (slot 6 random item, slots
7-9 rewards) onto the row under the player, and read back OAM attributes and
OBJ palette RAM. Saves a screenshot per mode.
"""
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_rgbds_constants, parse_map_constants  # noqa: E402

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
ARTIFACTS = REPO / "tools" / "pyboy_smoke" / "artifacts"
MONS = parse_rgbds_constants(REPO / "constants" / "pokemon_constants.asm")
MAPS = parse_map_constants(REPO / "constants" / "map_constants.asm")
STAGE = MAPS["DIGLETTS_CAVE"]
FORCED = [("BULBASAUR", 1), ("GASTLY", 2), ("TAUROS", 3)]


def obj_palettes(h):
    pals = []
    for pal in range(8):
        row = []
        for c in range(4):
            idx = pal * 8 + c * 2
            h.pyboy.memory[0xFF6A] = idx
            lo = h.pyboy.memory[0xFF6B]
            h.pyboy.memory[0xFF6A] = idx + 1
            hi = h.pyboy.memory[0xFF6B]
            w = lo | (hi << 8)
            row.append((w & 31, (w >> 5) & 31, (w >> 10) & 31))
        pals.append(row)
    return pals


def run(enhanced):
    tag = "enh" if enhanced else "plain"
    h = RedRogueHarness(REPO, ARTIFACTS, cgb_mode=True)
    failures = []
    try:
        h.boot_to_lobby()
        opt = h.read8("wOptions2")
        opt = (opt | 0x40) if enhanced else (opt & ~0x40)
        h.write8("wOptions2", opt)
        h.enter_stage_door1(STAGE, description="Digletts Cave")
        cache = h.read_bytes("wBallRarityPal", 16)
        offers = h.read_bytes("wRoguePokemon1", 3)
        print(f"[{tag}] natural offers={offers} cache={cache}")
        if any(cache[i] for i in list(range(0, 7)) + list(range(10, 16))):
            failures.append(f"{tag}: non-reward slot coloured after entry: {cache}")

        # Force one offer per tier, no trade, and rebuild.
        for i, (name, _) in enumerate(FORCED):
            h.write8("wRoguePokemon1", MONS[name], offset=i)
            h.write8("wRoguePokemonForm1", 0, offset=i)
        h.write8("wRogueFlagsBitfield", h.read8("wRogueFlagsBitfield") & ~0x04)
        h.park_before_hijack()
        h.call_routine("RefreshBallRarityCache")
        cache = h.read_bytes("wBallRarityPal", 16)
        want = [0] * 16
        for i, (_, cls) in enumerate(FORCED):
            want[7 + i] = cls
        print(f"[{tag}] forced cache={cache}")
        if cache != want:
            failures.append(f"{tag}: forced cache {cache} != {want}")

        # Unhide balls 1-3 and the random item, then park all four by the player.
        flags = h.address("wToggleableObjectFlags")
        for t in ("TOGGLE_ROGUE_REWARD_POKEBALL_1", "TOGGLE_ROGUE_REWARD_POKEBALL_2",
                  "TOGGLE_ROGUE_REWARD_POKEBALL_3", "TOGGLE_STAGE_RANDOM_ITEM"):
            idx = parse_rgbds_constants(REPO / "constants" / "toggle_constants.asm")[t]
            h.pyboy.memory[flags + idx // 8] &= ~(1 << (idx % 8)) & 0xFF
        y = h.read8("wYCoord")
        x = h.read8("wXCoord")
        d2 = h.address("wSpriteStateData2")
        for n, slot in enumerate((6, 7, 8, 9)):
            h.pyboy.memory[d2 + slot * 16 + 4] = y + 5
            h.pyboy.memory[d2 + slot * 16 + 5] = x + 1 + 2 * n
        h.tick(30, render=True)

        d1 = h.address("wSpriteStateData1")
        oam = [h.pyboy.memory[0xFE00 + i] for i in range(160)]
        for slot in (6, 7, 8, 9):
            ypx = h.pyboy.memory[d1 + slot * 16 + 4]
            xpx = h.pyboy.memory[d1 + slot * 16 + 6]
            pic = h.pyboy.memory[d1 + slot * 16]
            img = h.pyboy.memory[d1 + slot * 16 + 2]
            attrs = []
            for e in range(40):
                oy, ox, tile, attr = oam[e * 4:e * 4 + 4]
                if oy - 16 - ypx in (0, 8) and ox - 8 - xpx in (0, 8):
                    attrs.append(attr)
            exp = want[slot]
            print(f"[{tag}] slot {slot} pic=${pic:02x} img=${img:02x} px=({ypx},{xpx}) "
                  f"oam attrs={[hex(a) for a in attrs]} expect pal {exp}")
            if len(attrs) != 4 or any((a & 7) != exp for a in attrs):
                failures.append(f"{tag}: slot {slot} attrs {attrs} expected pal {exp} x4")

        pals = obj_palettes(h)
        for p in range(4):
            print(f"[{tag}] OBJ{p} {pals[p]}")
        # The ball's top is pixel shade 2, which rOBP0 = 3,1,0,0 sends to
        # hardware colour 2 (= base colour 1). It must be the tier's hue.
        g, u, m = pals[1][2], pals[2][2], pals[3][2]
        if not (g[2] > g[0] and g[2] > g[1]):
            failures.append(f"{tag}: OBJ1 top {g} not blue")
        if max(u) > 4:
            failures.append(f"{tag}: OBJ2 top {u} not near-black")
        if not (m[0] > m[1] and m[2] > m[1]):
            failures.append(f"{tag}: OBJ3 top {m} not purple")
        h.pyboy.screen.image.save(str(OUT / f"ball_rarity_{tag}.png"))
    finally:
        h.close()
    return failures


all_failures = []
for enhanced in (True, False):
    all_failures += run(enhanced)
print("FAILURES:" if all_failures else "ALL CHECKS PASSED")
for f in all_failures:
    print("  " + f)
