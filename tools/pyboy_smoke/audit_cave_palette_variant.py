"""Phase 4b probe: does a cave palette variant actually reach the palette engine?

This answers the half of Phase 4 that does NOT need eyes on a screen.
sProcCavePalette is rolled in PCPreloadCave, and ResolveEnhancedBasePalSet is
supposed to turn it into wEnhBasePalSet once per palette command. If that
mapping holds for every variant INCLUDING an out-of-range one, the only thing
left to confirm on hardware is whether the colours look right, not whether the
plumbing runs.

Two things this probe deliberately does NOT do, because the first version did
both and proved nothing:

  * It does not run in DMG mode. With hGBC = 0 SetPal_Overworld never reaches
    LoadEnhancedOverworldPaletteCommand, so wEnhBasePalSet is never written and
    reads 0 as uninitialised WRAM. Variant 0 also expects 0, so the test passed
    while measuring nothing. It now boots CGB and fails loudly if hGBC is 0.
  * It does not wait for the roll to produce each variant. The harness boots
    from a fixed seed, so every boot rolls the SAME value - eight runs produced
    variant 0 eight times, which is the seed, not the weighting. It writes each
    variant into SRAM and drives the resolver directly instead.

Usage:  python3 -m tools.pyboy_smoke.audit_cave_palette_variant
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from tools.pyboy_smoke.harness import RedRogueHarness  # noqa: E402
from tools.pyboy_smoke.source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

# custom_functions/func_enhancedcolor.asm ProcCavePalSets, plus the range-check
# fallback. Hardcoded on purpose: reading the table out of the ROM would make
# the probe agree with it by construction and it could never fail.
#   sProcCavePalette -> expected wEnhBasePalSet
CASES = {
    0: 0,     # default cavern
    1: 1,     # cold  -> GBCEnhancedOverworldPalettes_ColdCavern
    2: 0,     # CUT. The darkened variant was removed 2026-09-16, so 2 is now
              # out of range and must fall back to default like any other bad
              # value. Kept as a case precisely because it USED to be valid:
              # a save written before the cut can still hold a 2.
    0xFF: 0,  # fresh/pre-field SRAM powers up $ff -> must fall back to default,
              # never index ProcCavePalSets with it
}


def main() -> int:
    ids = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS, cgb_mode=True)
    failures: list[str] = []
    try:
        harness.boot_to_lobby()
        harness.preload_and_enter_wild_area(ids["PROCEDURAL_CAVE_1"], "Procedural Cave")

        gbc = harness.read8("hGBC")
        options2 = harness.read8("wOptions2")
        print(f"hGBC={gbc} wOptions2=${options2:02x}")
        # SetPal_Overworld tests hGBC with a bare `and a`, so ANY non-zero value
        # takes the enhanced branch. This build reports 2, not vanilla's 1, which
        # is why the check is != 0 rather than == 1.
        if gbc == 0:
            print(
                "FAIL hGBC == 0: the enhanced colour path is not reachable in "
                "this mode, so nothing below would be measuring the resolver."
            )
            return 1

        # The ordering check, and the only part of this probe that exercises the
        # REAL entry path rather than a direct call: ResolveEnhancedBasePalSet is
        # called from LoadEnhancedOverworldPaletteCommand just before the rebuild,
        # so by the time the cave map is up, wEnhBasePalSet must already agree
        # with whatever PCPreloadCave rolled. If it does not, the resolver is
        # running too late (or not on this path) and a variant would show the
        # PREVIOUS map's colours until something else forced a rebuild.
        rolled = harness.read_sram_bytes("sProcCavePalette", 1, bank=0)[0]
        on_entry = harness.read8("wEnhBasePalSet")
        entry_expected = CASES.get(rolled, 0)
        entry_ok = on_entry == entry_expected
        print(
            f"on map entry: rolled variant={rolled}, wEnhBasePalSet={on_entry} "
            f"(expected {entry_expected}) {'ok' if entry_ok else 'MISMATCH'}"
        )
        if not entry_ok:
            failures.append(
                f"map entry: PCPreloadCave rolled {rolled} but wEnhBasePalSet is "
                f"{on_entry}; ResolveEnhancedBasePalSet is not running before the "
                f"rebuild on the map-load path"
            )

        for variant, expected in CASES.items():
            # Bank 0: sProcCavePalette is in the "Sprite Buffers" SRAM section.
            # pyboy.memory would read/write the wrong bank once the map is up.
            harness.write_sram_bytes("sProcCavePalette", [variant], bank=0)
            harness.write8("wEnhBasePalSet", 0xAA)  # poison, so a resolver that
            #                                         never runs cannot look
            #                                         like it returned 0
            harness.call_routine("ResolveEnhancedBasePalSet")
            got = harness.read8("wEnhBasePalSet")
            ok = got == expected
            print(
                f"sProcCavePalette=${variant:02x} -> wEnhBasePalSet={got} "
                f"(expected {expected}) {'ok' if ok else 'MISMATCH'}"
            )
            if not ok:
                if got == 0xAA:
                    failures.append(
                        f"variant ${variant:02x}: wEnhBasePalSet still holds the "
                        f"poison value, so ResolveEnhancedBasePalSet never wrote it"
                    )
                else:
                    failures.append(
                        f"variant ${variant:02x}: expected base set {expected}, "
                        f"got {got}"
                    )
    finally:
        harness.close()

    print()
    if failures:
        for line in failures:
            print(f"FAIL {line}")
        return 1
    print("PASS: every variant, and an out-of-range $ff, resolved as specified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
