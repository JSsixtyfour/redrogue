"""Every rule must flag a known-bad snippet and stay quiet on its fixed twin.

A rule that cannot fail is worse than no rule (it reports "clean" forever), so
each case here builds a tiny source tree with a matching .map, runs the real
run_all.py against it, and checks the positive label IS reported and the
negative label is NOT.

    python3 tools/static_audit/test_rules.py
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent

MACROS = """
MACRO text
	db 0, \\#
ENDM
MACRO line
	db "<LINE>", \\#
ENDM
MACRO prompt
	db "<PROMPT>"
ENDM
MACRO done
	db "<DONE>"
ENDM
MACRO text_end
	db $50
ENDM
MACRO text_asm
	db 8
ENDM
MACRO text_far
	db $17
	dab \\1
ENDM
MACRO sound_get_item_1
	db $0b
ENDM
"""


def build_map(sections):
    """sections: [(name, region, bank)] -> .map text in rgblink's format."""
    by = {}
    for name, region, bank in sections:
        by.setdefault((region, bank), []).append(name)
    out = []
    for (region, bank), names in by.items():
        out.append(f"{region} bank #{bank}:")
        base = 0x0000 if region == "ROM0" else 0xA000 if region == "SRAM" else \
            0xC000 if region.startswith("WRAM") else 0x4000
        for i, n in enumerate(names):
            a = base + i * 0x100
            out.append(f'\tSECTION: ${a:04x}-${a + 0xff:04x} ($0100 bytes) ["{n}"]')
    return "\n".join(out) + "\n"


def run_case(main_asm, sections, rules):
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "includes.asm").write_text(MACROS, encoding="utf-8")
        (root / "main.asm").write_text(textwrap.dedent(main_asm), encoding="utf-8")
        (root / "pokeblue.sym").write_text("", encoding="utf-8")
        (root / "pokeblue.map").write_text(build_map(sections), encoding="utf-8")
        out = root / "out.json"
        env = dict(os.environ, STATIC_AUDIT_REPO=str(root))
        args = [sys.executable, str(HERE / "run_all.py"), "--rom", "pokeblue", "--info",
                "--json", str(out)]
        for r in rules:
            args += ["--rule", r]
        subprocess.run(args, env=env, capture_output=True, text=True)
        return json.loads(out.read_text(encoding="utf-8")) if out.exists() else []


class Rules(unittest.TestCase):
    def check(self, rule, main_asm, sections, bad, good):
        found = run_case(main_asm, sections, [rule])
        labels = {f["label"] for f in found if f["rule"] == rule}
        self.assertIn(bad, labels, f"{rule} missed its positive case; got {found}")
        self.assertNotIn(good, labels, f"{rule} fired on its negative case; got {found}")

    def test_b1_plain_cross_bank_call(self):
        self.check("B1", """
            SECTION "A", ROMX
            Bad::
            	call Far
            	ret
            Good::
            	call Near
            	ret
            Near::
            	ret
            SECTION "B", ROMX
            Far::
            	ret
            """, [("A", "ROMX", 2), ("B", "ROMX", 3)], "Bad", "Good")

    def test_b1f_same_bank_by_luck(self):
        self.check("B1f", """
            SECTION "A", ROMX
            Bad::
            	call InB
            	ret
            Good::
            	call InA
            	ret
            InA::
            	ret
            SECTION "B", ROMX
            InB::
            	ret
            """, [("A", "ROMX", 2), ("B", "ROMX", 2)], "Bad", "Good")

    def test_b2_cross_bank_pointer(self):
        self.check("B2", """
            SECTION "A", ROMX
            Bad::
            	ld hl, TableB
            	ld a, [hl]
            	ret
            Good::
            	ld hl, TableB
            	ld de, $c000
            	ld bc, 4
            	ld a, BANK(TableB)
            	call FarCopyData
            	ret
            SECTION "B", ROMX
            TableB::
            	db 1, 2, 3, 4
            SECTION "H", ROM0
            FarCopyData::
            	ret
            """, [("A", "ROMX", 2), ("B", "ROMX", 3), ("H", "ROM0", 0)], "Bad", "Good")

    def test_b3_home_to_romx(self):
        self.check("B3", """
            SECTION "H", ROM0
            Bad::
            	call InX
            	ret
            Good::
            	ld a, BANK(InX)
            	call SetCurBank
            	call InX
            	ret
            SetCurBank::
            	ret
            SECTION "X", ROMX
            InX::
            	ret
            """, [("H", "ROM0", 0), ("X", "ROMX", 5)], "Bad", "Good")

    def test_b4_farcall_callee_reads_destroyed_register(self):
        self.check("B4", """
            SECTION "A", ROMX
            Bad::
            	ld c, 3
            	farcall ReadsC
            	ret
            Good::
            	ld e, 3
            	farcall ReadsE
            	ret
            SECTION "B", ROMX
            ReadsC::
            	ld a, c
            	ld [$c000], a
            	ret
            ReadsE::
            	ld a, e
            	ld [$c000], a
            	ret
            """, [("A", "ROMX", 2), ("B", "ROMX", 3)], "Bad", "Good")

    def test_b5_reads_garbage_after_farcall(self):
        self.check("B5", """
            SECTION "A", ROMX
            Bad::
            	farcall Callee
            	ld [$c000], a
            	ret
            Good::
            	farcall Callee
            	ld a, [$c001]
            	ld [$c000], a
            	ret
            SECTION "B", ROMX
            Callee::
            	ld a, 1
            	ret
            """, [("A", "ROMX", 2), ("B", "ROMX", 3)], "Bad", "Good")

    def test_b5_hl_after_farcall_to_hl_preserving_callee(self):
        # the ParalyzeEffect_ shape: callee push/pops hl, so hl comes back as
        # the far-call target address
        self.check("B5", """
            SECTION "A", ROMX
            Bad::
            	ld hl, $c000
            	farcall KeepsHL
            	set 6, [hl]
            	ret
            Good::
            	ld hl, $c000
            	push hl
            	farcall KeepsHL
            	pop hl
            	set 6, [hl]
            	ret
            SECTION "B", ROMX
            KeepsHL::
            	push hl
            	ld hl, $c010
            	bit 0, [hl]
            	pop hl
            	ret
            """, [("A", "ROMX", 2), ("B", "ROMX", 3)], "Bad", "Good")

    def test_b6_bank_switch_from_romx(self):
        self.check("B6", """
            SECTION "A", ROMX
            Bad::
            	ld a, 3
            	ld [rROMB], a
            	ret
            SECTION "H", ROM0
            Good::
            	ld a, 3
            	ld [rROMB], a
            	ret
            """, [("A", "ROMX", 2), ("H", "ROM0", 0)], "Bad", "Good")

    def test_b7_documented_preserve_violated(self):
        self.check("B7", """
            SECTION "A", ROMX
            ; Preserves de.
            Bad::
            	ld d, 0
            	ret
            ; Preserves de.
            Good::
            	push de
            	ld d, 0
            	pop de
            	ret
            """, [("A", "ROMX", 2)], "Bad", "Good")

    def test_b8_pop_af_discards_test(self):
        self.check("B8", """
            SECTION "A", ROMX
            Bad::
            	push af
            	cp 3
            	pop af
            	jr z, .x
            .x
            	ret
            Good::
            	push af
            	cp 3
            	jr z, .y
            	pop af
            	ret
            .y
            	pop af
            	ret
            """, [("A", "ROMX", 2)], "Bad", "Good")

    def test_a1_ret_with_value_pushed(self):
        self.check("A1", """
            SECTION "A", ROMX
            Caller::
            	call Bad
            	call Good
            	ret
            Bad::
            	push bc
            	ld a, 1
            	ret
            Good::
            	push bc
            	pop bc
            	ret
            """, [("A", "ROMX", 2)], "Bad", "Good")

    def test_a2_sram_touched_while_closed(self):
        self.check("A2", """
            SECTION "A", ROMX
            Caller::
            	call Bad
            	call Good
            	ret
            Bad::
            	ld a, $0a
            	ld [rRAMG], a
            	xor a
            	ld [rRAMG], a
            	ld a, [sThing]
            	ret
            Good::
            	ld a, $0a
            	ld [rRAMG], a
            	ld a, [sThing]
            	xor a
            	ld [rRAMG], a
            	ret
            SECTION "S", SRAM
            sThing:: ds 1
            """, [("A", "ROMX", 2), ("S", "SRAM", 0)], "Bad", "Good")

    def test_a2_sram_wrong_bank(self):
        self.check("A2", """
            SECTION "A", ROMX
            Caller::
            	call Bad
            	call Good
            	ret
            Bad::
            	ld a, $0a
            	ld [rRAMG], a
            	ld a, 1
            	ld [rRAMB], a
            	ld a, [sBank0Thing]
            	xor a
            	ld [rRAMG], a
            	ret
            Good::
            	ld a, $0a
            	ld [rRAMG], a
            	ld a, BANK(sBank0Thing)
            	ld [rRAMB], a
            	ld a, [sBank0Thing]
            	xor a
            	ld [rRAMG], a
            	ret
            SECTION "S", SRAM
            sBank0Thing:: ds 1
            """, [("A", "ROMX", 2), ("S", "SRAM", 0)], "Bad", "Good")

    def test_c1_falls_into_data(self):
        self.check("C1", """
            SECTION "A", ROMX
            Bad::
            	ld a, 1
            .str
            	db "TEST@"
            Good::
            	ld a, 1
            	ret
            .str2
            	db "TEST@"
            """, [("A", "ROMX", 2)], "Bad", "Good")

    def test_c2_jump_table_without_length_assert(self):
        self.check("C2", """
            SECTION "A", ROMX
            BadTable::
            	dw R1
            	dw R2
            	dw R3
            GoodTable::
            	table_width 2, GoodTable
            	dw R1
            	dw R2
            	dw R3
            	assert_table_length 3
            R1::
            	ret
            R2::
            	ret
            R3::
            	ret
            """, [("A", "ROMX", 2)], "BadTable", "GoodTable")

    def test_c3_at_before_prompt(self):
        self.check("C3", """
            SECTION "A", ROMX
            BadText::
            	text "hi@"
            	prompt
            GoodText::
            	text "hi"
            	prompt
            """, [("A", "ROMX", 2)], "BadText", "GoodText")

    def test_c3_text_asm_clobbers_cursor(self):
        self.check("C3", """
            SECTION "A", ROMX
            BadText::
            	text_asm
            	ld c, 5
            	ld hl, NextText
            	ret
            GoodText::
            	text_asm
            	push bc
            	ld c, 5
            	pop bc
            	ld hl, NextText
            	ret
            NextText::
            	text "x"
            	text_end
            """, [("A", "ROMX", 2)], "BadText", "GoodText")

    def test_c3_split_far_text_needs_terminator(self):
        self.check("C3", """
            SECTION "A", ROMX
            BadText::
            	text_far _BadHalf
            	sound_get_item_1
            	text_far _Second
            	text_end
            GoodText::
            	text_far _GoodHalf
            	sound_get_item_1
            	text_far _Second
            	text_end
            _BadHalf::
            	text "one"
            	text_end
            _GoodHalf::
            	text "one@"
            	text_end
            _Second::
            	text "two"
            	text_end
            """, [("A", "ROMX", 2)], "BadText", "GoodText")

    def test_d1_unreachable_code(self):
        self.check("D1", """
            SECTION "A", ROMX
            Entry::
            	call Used
            	ret
            DeadCode::
            	ld a, 1
            	ret
            Used::
            	ret
            """, [("A", "ROMX", 2)], "DeadCode", "Used")

    def test_b9_wbuffer0_cached_across_farcopydata(self):
        self.check("B9", """
            SECTION "H", ROM0
            FarCopyData::
            	ld [wBuffer], a
            	ret
            LoadsFarData::
            	call FarCopyData
            	ret
            Harmless::
            	ret
            SECTION "A", ROMX
            Bad::
            	ld [wBuffer], a
            .loop
            	ld a, [wBuffer]
            	call Helper
            	jr .loop
            Helper::
            	jp LoadsFarData
            Good::
            	ld [wBuffer], a
            	call Harmless
            	ld a, [wBuffer]
            	ret
            SECTION "W", WRAM0
            wBuffer:: ds 30
            """, [("H", "ROM0", 0), ("A", "ROMX", 2), ("W", "WRAM0", 0)], "Bad", "Good")

    def test_d2_false_same_bank_claim(self):
        self.check("D2", """
            SECTION "A", ROMX
            Bad::
            	call Far ; same bank, plain call is fine
            	ret
            Good::
            	call Near ; same bank, plain call is fine
            	ret
            Near::
            	ret
            SECTION "B", ROMX
            Far::
            	ret
            """, [("A", "ROMX", 2), ("B", "ROMX", 3)], "Bad", "Good")


if __name__ == "__main__":
    unittest.main(verbosity=2)
