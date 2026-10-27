"""Compare actual OAM output from two ROM/sym sets over identical sprite fixtures.

Explicit isolated call fixtures, not a player choreography test. Each ROM gets
its own boot and state. Includes all 14 tile bases / 16 facing indices, hidden
sprites, empty slots, grass/rarity attributes, fixed poses and clearing modes.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path

from harness import RedRogueHarness


def run(root, cgb):
    h = RedRogueHarness(root, root, cgb_mode=cgb)
    outputs = []
    done = {}
    try:
        h.boot_to_lobby()
        h.tick(120)
        state = io.BytesIO()
        h.save_state(state)

        def returned(_):
            done.update(oam=h.read_bytes("wShadowOAM", 160),
                        state1=h.read_bytes("wSpriteStateData1", 256),
                        offset=h.read8("hOAMBufferOffset"),
                        sp=h.pyboy.register_file.SP)
            h.pyboy.register_file.PC = h.address("DelayFrame.halt")

        h.register_hook("Bankswitch.Return", returned)
        # All valid image indices, plus offscreen, disabled/hidden update modes.
        cases = [(base * 16 + facing, 1, priority, ledge)
                 for base in range(14) for facing in range(16)
                 for priority, ledge in [(0,0),(0x80,0xff)]]
        cases += [(0xff,1,0,0), (0,0,0,0), (0,2,0,0), (0,0xff,0,0)]
        for image, enabled, priority, ledge in cases:
            state.seek(0)
            h.load_state(state)
            h.pyboy.memory[0xffff] = 0  # no asynchronous OAM construction
            h.write8("hUpdateSpritesEnabled", enabled)
            h.write8("wMovementFlags", ledge)
            for i in range(160):
                h.pyboy.memory[h.address("wShadowOAM") + i] = 0x55
            for slot in range(16):
                data = h.address("wSpriteStateData1") + slot * 16
                h.pyboy.memory[data:data+16] = [0] * 16
                if slot >= 8:
                    continue
                h.pyboy.memory[data] = 1 if slot != 6 else 0
                h.pyboy.memory[data+2] = image if slot != 7 else 0xff
                h.pyboy.memory[data+4] = (slot * 24 - 4) & 255
                h.pyboy.memory[data+6] = (slot * 20 - 8) & 255
                h.write8("wSpriteStateData2", priority, slot * 16 + 7)
                h.write8("wBallRarityPal", slot % 4 if cgb else 0, slot)
            # Real RET to a mapped HOME hook: capture before unrelated code.
            sp = 0xdff0
            target = h.address("Bankswitch.Return")
            h.pyboy.memory[sp:sp+2] = [target & 255, target >> 8]
            bank, addr = h.symbols.get("PrepareOAMData")
            h.pyboy.memory[0x2000] = bank
            h.write8("hLoadedROMBank", bank)
            h.pyboy.register_file.SP = sp
            h.pyboy.register_file.PC = addr
            done.clear()
            h.wait_until(lambda: bool(done), "isolated OAM return", 4)
            assert done["sp"] == sp + 2, done
            outputs.append(dict(done))
        assert not h.hook_errors, h.hook_errors
    finally:
        h.close()
    return outputs


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("before", type=Path)
    p.add_argument("after", type=Path)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    results = []
    for cgb in (False, True):
        before, after = run(args.before.resolve(), cgb), run(args.after.resolve(), cgb)
        for i, (a,b) in enumerate(zip(before, after)):
            assert a == b, f"OAM difference: cgb={cgb}, fixture={i}"
        assert len(before) == len(after)
        result = {"mode": "CGB" if cgb else "DMG", "identical_fixtures": len(before),
                  "sha256": hashlib.sha256(json.dumps(before, sort_keys=True).encode()).hexdigest()}
        results.append(result)
        print(result, flush=True)
    args.output.write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
