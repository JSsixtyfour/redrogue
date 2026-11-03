import io, sys
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root / "tools" / "pyboy_smoke"))
from harness import RedRogueHarness
h = RedRogueHarness(root, root / "tools" / "pyboy_smoke" / "artifacts")
h.boot_to_lobby(); h.park_before_hijack()
rom = (root / "pokeblue_debug.gbc").read_bytes()
addr = h.address("wCurEnemyLevel")
pat = bytes([0xEA, addr & 0xFF, addr >> 8])
sites = []
i = rom.find(pat)
while i >= 0:
    bank, off = divmod(i, 0x4000)
    sites.append((bank, off + (0x4000 if bank else 0)))
    i = rom.find(pat, i + 1)
print(len(sites), "store sites")
fired = []
for b, a in sites:
    try:
        h.pyboy.hook_register(b, a, lambda ctx: fired.append(ctx), (b, a))
    except Exception as e:
        pass
snap = io.BytesIO(); h.save_state(snap)
h.load_state(snap); h.write8('wBattleCount', 8)
fired.clear()
h.call_routine('PCGetBossLevel')
print("after call_routine level", h.read8('wCurEnemyLevel'))
for b, a in fired:
    print("store fired at", hex(b), hex(a), h.symbols.nearest(b, a))
h.close()
