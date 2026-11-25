"""A bank switch must write hLoadedROMBank before rROMB.

VBlank restores the ROM bank from hLoadedROMBank. An interrupt between the two writes in the
other order maps the old bank back, and the caller runs whatever sits at the target's address
there. CheckForHiddenEventOrBookshelfOrCardKeyDoor (every overworld A press) had the wrong order
at all three of its switches and froze Bill's PC fuzz seed 999 on 2026-11-24: CheckForHiddenEvent
ran with bank $07 mapped, so the CPU executed graphics.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

from harness import RedRogueHarness

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
SOURCES = ("home", "engine", "custom_functions", "audio", "scripts", "data")
ROUTINE = "CheckForHiddenEventOrBookshelfOrCardKeyDoor"


def reversed_switches(text: str) -> list[int]:
    """Line numbers of `ld [rROMB], a` followed by the hLoadedROMBank store it should come after."""
    code = [(n, line.split(";")[0].strip()) for n, line in enumerate(text.splitlines(), 1)]
    code = [(n, line) for n, line in code if line]
    return [n for (n, line), (_, after) in zip(code, code[1:])
            if re.fullmatch(r"ld \[rROMB\],\s*a", line) and re.fullmatch(r"ldh? \[hLoadedROMBank\],\s*a", after)]


class BankSwitchOrderTest(unittest.TestCase):
    def test_every_switch_stores_the_bank_number_first(self) -> None:
        self.assertEqual(reversed_switches("\tld [rROMB], a ; x\n\n\tldh [hLoadedROMBank], a\n"), [1])
        self.assertEqual(reversed_switches("\tldh [hLoadedROMBank], a\n\tld [rROMB], a\n"), [])
        found = [f"{path.relative_to(ROOT).as_posix()}:{n}" for top in SOURCES
                 for path in sorted((ROOT / top).rglob("*.asm"))
                 for n in reversed_switches(path.read_text(encoding="utf-8", errors="replace"))]
        self.assertEqual(found, [], "VBlank between these two writes maps the old bank back")

    def test_a_vblank_inside_the_hidden_event_switches_is_harmless(self) -> None:
        """Press A in the lobby with a VBlank forced between the two writes of each switch it runs."""
        h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        h.tick(180)
        bank, start, end = h.symbols.routine_range(ROUTINE)
        body = h.rom_path.read_bytes()[start:end]
        hloaded = h.address("hLoadedROMBank") & 0xFF
        pair = {b"\xea\x00\x20\xe0" + bytes([hloaded]), b"\xe0" + bytes([hloaded]) + b"\xea\x00\x20"}
        sites = [start + i for i in range(len(body) - 4) if body[i:i + 5] in pair]
        self.assertEqual(len(sites), 3)
        memory, ran = h.pyboy.memory, []
        forced = {"on": False, "pending": None}

        def force(site):
            def fire(_context) -> None:
                # PyBoy takes the interrupt before the hooked instruction, then comes back to it.
                if not forced["on"] or forced["pending"] == site:
                    forced["pending"] = None
                    return
                forced["pending"] = site
                memory[0xFF0F] = memory[0xFF0F] | 1
            return fire

        def after(site):
            def check(_context) -> None:
                wanted = h.read8("hLoadedROMBank")
                mapped = [memory[a] for a in range(0x4000, 0x4100)]
                ran.append((site, mapped == [memory[wanted, a] for a in range(0x4000, 0x4100)]))
            return check

        vblanks = []
        h.register_hook("VBlank", lambda _c: vblanks.append(1) if forced["on"] else None)
        for site in sites:
            second = site + (3 if body[site - start] == 0xEA else 2)
            h._register_at((bank, second), force(site))
            h._register_at((bank, site + 5), after(site))
        forced["on"] = True
        for _ in range(4):
            h.pyboy.button_press("a")
            h.tick(4)
            h.pyboy.button_release("a")
            h.tick(8)
        self.assertGreater(len(vblanks), 48, "no extra VBlank was forced")  # 48 frames ticked
        self.assertEqual([site for site, ok in ran if not ok], [], "the wrong ROM bank was mapped")
        self.assertTrue({sites[0], sites[2]} <= {site for site, _ in ran}, ran)


if __name__ == "__main__":
    unittest.main()
