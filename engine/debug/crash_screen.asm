; Debug build only: what a stray jump shows instead of a frozen screen.
;
; The debug ROM pads every unused byte with $FF (`rst $38`), and `rst $00` is
; `rst $38` too, so a jump into padding or to NULL arrives at $0038. In the debug
; build that vector switches to this bank and jumps here (home/header.asm); in
; Red/Blue it is still the old hang. Nothing returns from here.
;
; The screen shows where the CPU was (`PC bank:address`, BGB's form), the stack
; (the return address plus the six words above it, i.e. the call chain), the
; registers and the map, so a tester's screenshot is a measurement. Developers
; turn the numbers into labels with tools/crash_lookup.py and that build's .sym.
;
; Contract with the vector: interrupts are off, this bank is in rROMB, A is
; lost, F/BC/DE/HL/SP are as they were, and hLoadedROMBank still names the bank
; mapped at the crash. Pinned beside "Build ID" (layout.link), whose strings it
; reads by plain label. The section stays (empty) in release because
; layout.link names it.

SECTION "Crash Screen", ROMX

IF DEF(_DEBUG)

DEF CRASH_STACK_WORDS EQU 7 ; the return address, then six callers

; Saved state lives in wShadowOAM: sprites are never drawn again, and OAM DMA
; only runs from VBlank, which never runs again. Our own stack grows down from
; wShadowOAMEnd, below the four pushed register pairs, so it cannot reach this.
	rsreset
DEF CRASH_STACK     rb CRASH_STACK_WORDS * 2
DEF CRASH_SP        rw 1
DEF CRASH_ROM_BANK  rb 1
DEF CRASH_WRAM_BANK rb 1
DEF CRASH_MAP       rb 1
DEF CRASH_X         rb 1
DEF CRASH_Y         rb 1
DEF CRASH_SAVED     rb 0
	ASSERT CRASH_SAVED <= wShadowOAMEnd - wShadowOAM - 8 - 32, "crash state would meet its own stack"

DEF wCrash EQUS "wShadowOAM"
; push order hl, de, bc, af: F is lowest
DEF wCrashF EQUS "(wShadowOAMEnd - 8)"
DEF wCrashC EQUS "(wShadowOAMEnd - 6)"
DEF wCrashB EQUS "(wShadowOAMEnd - 5)"
DEF wCrashE EQUS "(wShadowOAMEnd - 4)"
DEF wCrashD EQUS "(wShadowOAMEnd - 3)"
DEF wCrashL EQUS "(wShadowOAMEnd - 2)"
DEF wCrashH EQUS "(wShadowOAMEnd - 1)"

CrashScreen::
	ld [hSPTemp], sp
	ld sp, wShadowOAMEnd
	push hl
	push de
	push bc
	push af
	xor a ; RAMG_SRAM_DISABLE: whatever went wrong can't keep writing the save
	ld [rRAMG], a

; The stack first, with the WRAM bank the crash had: $DFxx is banked on CGB.
	ldh a, [hSPTemp]
	ld l, a
	ld [wCrash + CRASH_SP], a
	ldh a, [hSPTemp + 1]
	ld h, a
	ld [wCrash + CRASH_SP + 1], a
	ld de, wCrash + CRASH_STACK
	ld c, CRASH_STACK_WORDS * 2
.copyStack
	ld a, [hli]
	ld [de], a
	inc de
	dec c
	jr nz, .copyStack

	ldh a, [hLoadedROMBank]
	ld [wCrash + CRASH_ROM_BANK], a
	ldh a, [hGBC]
	and a
	ld a, 1 ; DMG has no WRAM banks; rSVBK reads $FF there
	jr z, .gotWRAMBank
	ldh a, [rSVBK]
	and %111
.gotWRAMBank
	ld [wCrash + CRASH_WRAM_BANK], a
	ld a, 1 ; wXCoord/wYCoord are in $D000-$DFFF
	ldh [rSVBK], a
	ldh a, [hCurMap]
	ld [wCrash + CRASH_MAP], a
	ld a, [wXCoord]
	ld [wCrash + CRASH_X], a
	ld a, [wYCoord]
	ld [wCrash + CRASH_Y], a

; LCD off, in VBlank (turning it off mid-frame can damage a DMG screen).
	ldh a, [rLCDC]
	bit B_LCDC_ENABLE, a
	jr z, .lcdOff
.waitVBlank
	ldh a, [rLY]
	cp LY_VBLANK
	jr c, .waitVBlank
	xor a
	ldh [rLCDC], a
.lcdOff

; Every write below is safe on DMG too, so there is no CGB branch: rVBK and
; the BG palette registers do nothing there, and the attribute clear just
; writes zeroes into the tilemap that the space fill then overwrites.
	ld a, 1
	ldh [rVBK], a
	ld hl, vBGMap0
	ld bc, TILEMAP_AREA
	xor a
	call CrashFill ; attributes: palette 0, VRAM bank 0, no flips
	xor a
	ldh [rVBK], a
	ldh [rSCX], a
	ldh [rSCY], a
	ld a, %11100100
	ldh [rBGP], a
	ld a, BGPI_AUTOINC ; palette 0, colour 0
	ldh [rBGPI], a
	ld hl, CrashPalette
	ld c, CrashPaletteEnd - CrashPalette
.palette
	ld a, [hli]
	ldh [rBGPD], a
	dec c
	jr nz, .palette

	ld a, BANK(@) ; FarCopyDataDouble switches back to hLoadedROMBank when done
	ldh [hLoadedROMBank], a
	ld hl, FontGraphics
	ld de, vFont
	ld bc, FontGraphicsEnd - FontGraphics
	ld a, BANK(FontGraphics)
	call FarCopyDataDouble
	ld hl, vChars2 + ' ' * TILE_SIZE ; the space tile, normally the text box's
	ld bc, TILE_SIZE
	xor a
	call CrashFill
	ld hl, vBGMap0
	ld bc, TILEMAP_AREA
	ld a, ' '
	call CrashFill

	ld hl, CrashTexts
.texts
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a
	or e
	jr z, .values
	call CrashPlaceString
	jr .texts

.values
	ld hl, vBGMap0 + 2 * TILEMAP_WIDTH + 0
	ld de, BuildDateText
	call CrashPlaceString.from_de
	ld hl, vBGMap0 + 3 * TILEMAP_WIDTH + 3
	ld de, BuildIdText
	call CrashPlaceString.from_de

; PC: the byte the CPU executed was the one before the return address.
	ld a, [wCrash + CRASH_STACK]
	sub 1
	ld e, a
	ld a, [wCrash + CRASH_STACK + 1]
	sbc 0
	ld d, a
	ld hl, vBGMap0 + 5 * TILEMAP_WIDTH + 4
	cp HIGH($4000)
	jr c, .homeBank
	cp HIGH($8000)
	jr nc, .ramPC
	ld a, [wCrash + CRASH_ROM_BANK]
	jr .printPCBank
.homeBank
	xor a
.printPCBank
	call CrashPrintHex
	jr .printPC
.ramPC
	ld a, '-'
	ld [hli], a
	ld [hli], a
.printPC
	inc hl ; past the ':'
	call CrashPrintWord

	ld hl, vBGMap0 + 6 * TILEMAP_WIDTH + 4
	ld a, [wCrash + CRASH_SP + 1]
	ld d, a
	ld a, [wCrash + CRASH_SP]
	ld e, a
	call CrashPrintWord
	ld hl, vBGMap0 + 6 * TILEMAP_WIDTH + 16
	ld a, [wCrash + CRASH_WRAM_BANK]
	call CrashPrintHex

	ld de, wCrash + CRASH_STACK + 2
	ld hl, vBGMap0 + 8 * TILEMAP_WIDTH + 6
	call CrashPrintStackPair
	ld hl, vBGMap0 + 9 * TILEMAP_WIDTH + 6
	call CrashPrintStackPair
	ld hl, vBGMap0 + 10 * TILEMAP_WIDTH + 6
	call CrashPrintStackPair

	ld hl, vBGMap0 + 12 * TILEMAP_WIDTH + 3
	ld a, [wCrashB]
	call CrashPrintHex
	ld a, [wCrashC]
	call CrashPrintHex
	ld hl, vBGMap0 + 12 * TILEMAP_WIDTH + 12
	ld a, [wCrashD]
	call CrashPrintHex
	ld a, [wCrashE]
	call CrashPrintHex
	ld hl, vBGMap0 + 13 * TILEMAP_WIDTH + 3
	ld a, [wCrashH]
	call CrashPrintHex
	ld a, [wCrashL]
	call CrashPrintHex
	ld hl, vBGMap0 + 13 * TILEMAP_WIDTH + 12
	ld a, [wCrashF]
	call CrashPrintHex

	ld hl, vBGMap0 + 14 * TILEMAP_WIDTH + 4
	ld a, [wCrash + CRASH_MAP]
	call CrashPrintHex
	ld hl, vBGMap0 + 14 * TILEMAP_WIDTH + 10
	ld a, [wCrash + CRASH_X]
	call CrashPrintHex
	ld hl, vBGMap0 + 14 * TILEMAP_WIDTH + 16
	ld a, [wCrash + CRASH_Y]
	call CrashPrintHex

	ld a, LCDC_ON | LCDC_BLOCK21 | LCDC_BG_9800 | LCDC_OBJ_OFF | LCDC_WIN_OFF | LCDC_BG_ON
	ldh [rLCDC], a
.forever
	jr .forever

; Fill bc bytes at hl with a (LCD off, so VRAM is always writable).
CrashFill:
	ld d, a
.loop
	ld a, d
	ld [hli], a
	dec bc
	ld a, b
	or c
	jr nz, .loop
	ret

; Copy the "@"-terminated string at hl to VRAM de; return hl past it.
CrashPlaceString:
.loop
	ld a, [hli]
	cp '@'
	ret z
	ld [de], a
	inc de
	jr .loop

; Same, string at de to VRAM hl (for strings read by label).
.from_de
	ld a, [de]
	cp '@'
	ret z
	ld [hli], a
	inc de
	jr .from_de

; Two stack words from de (little-endian) at hl, "XXXX XXXX"; de advances.
CrashPrintStackPair:
	call .one
	inc hl
.one
	ld a, [de]
	inc de
	ld c, a
	ld a, [de]
	inc de
	push de
	ld d, a
	ld e, c
	call CrashPrintWord
	pop de
	ret

; de as four hex digits at hl.
CrashPrintWord:
	ld a, d
	call CrashPrintHex
	ld a, e
	; fallthrough

; a as two hex digits at hl.
CrashPrintHex:
	push af
	swap a
	call .digit
	pop af
.digit
	and $f
	cp 10
	jr c, .decimal
	add 'A' - 10
	ld [hli], a
	ret
.decimal
	add '0'
	ld [hli], a
	ret

CrashPalette:
	; white, light grey, dark grey, black: the font draws in colour 3
	dw $7fff, $56b5, $294a, $0000
CrashPaletteEnd:

MACRO crash_text ; col, row, text
	dw vBGMap0 + (\2) * TILEMAP_WIDTH + (\1)
	db \3, "@"
ENDM

CrashTexts:
	crash_text 0, 0, "RED ROGUE CRASHED"
	crash_text 0, 3, "ID"
	crash_text 0, 5, "PC    :"
	crash_text 0, 6, "SP"
	crash_text 11, 6, "WRAM"
	crash_text 0, 8, "STACK"
	crash_text 0, 12, "BC"
	crash_text 9, 12, "DE"
	crash_text 0, 13, "HL"
	crash_text 9, 13, "F"
	crash_text 0, 14, "MAP"
	crash_text 8, 14, "X"
	crash_text 14, 14, "Y"
	crash_text 0, 16, "SCREENSHOT THIS AND"
	crash_text 0, 17, "SEND IT TO THE DEVS"
	dw 0

ENDC
