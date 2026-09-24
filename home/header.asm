; rst vectors
;
; $00 and $38 stay crash traps (a jump to NULL or into $FF padding lands on
; one). $08 and $18 hold the inline far call/jump used by `rfarcall`/`rfarjp`
; (macros/farcall.asm): 4 bytes per site instead of 8, with the routine itself
; living in padding that used to be dead, so it costs HOME nothing. Both end in
; the real Bankswitch, so the target sees exactly what `farcall` gives it
; (a = b = bank, hl = target, de and flags passed through) and returns hl/de/
; flags the same way.

SECTION "rst0", ROM0[$0000]
	rst $38

	ds $08 - @, 0 ; unused

SECTION "rst8", ROM0[$0008]
FarCallInline::
; rst FarCallInline / dba Target: call Target in its bank, return past the dba.
	pop hl        ; hl -> inline dba (bank, low, high)
	ld a, [hli]
	ld b, a
	ld a, [hli]
	ld c, a
	ld a, [hli]
	push hl       ; resume after the 3 data bytes
	ld h, a
	ld l, c
	jp Bankswitch
	ASSERT @ <= $18, "FarCallInline overran into the $18 vector"

	ds $18 - @, 0 ; unused

SECTION "rst18", ROM0[$0018]
FarJumpInline::
; rst FarJumpInline / dba Target: tail-jump to Target in its bank. The inline
; return address is dropped, so Target returns straight to our caller's
; caller - exactly `farjp`, with no extra stack depth.
	pop hl        ; hl -> inline dba (bank, low, high)
	ld a, [hli]
	ld b, a
	ld a, [hli]
	ld c, a
	ld a, [hl]
	ld h, a
	ld l, c
	jp Bankswitch
	ASSERT @ <= $28, "FarJumpInline overran into the $28 vector"
	ASSERT FarCallInline == RST_FARCALL && FarJumpInline == RST_FARJUMP

	ds $28 - @, 0 ; unused

SECTION "rst28", ROM0[$0028]
Predef::
; Call predefined function a (`predef` = ld a, id / rst Predef: 3 B, not 5).
; rst pushes the same return address `call` does, so targets see no change.
; The first 13 bytes of the dispatcher live here in dead vector padding; the
; rest, and .done, are PredefContinue (home/predef.asm).
	ld [wPredefID], a ; Save the predef id for GetPredefPointer.
	; A hack for LoadDestinationWarpPosition.
	; See LoadTilesetHeader (predef $19).
	ldh a, [hLoadedROMBank]
	ld [wPredefParentBank], a
	push af
	ld a, BANK(GetPredefPointer)
	ldh [hLoadedROMBank], a
	jp PredefContinue
	ASSERT @ <= $38, "Predef entry overran into the $38 crash trap"
	ASSERT Predef == RST_PREDEF

SECTION "rst38", ROM0[$0038]
	rst $38

	ds $40 - @, 0 ; unused


; Game Boy hardware interrupts

SECTION "vblank", ROM0[$0040]
	jp VBlank

	ds $48 - @, 0 ; unused

SECTION "lcd", ROM0[$0048]
	rst $38

	ds $50 - @, 0 ; unused

SECTION "timer", ROM0[$0050]
	jp Timer

	ds $58 - @, 0 ; unused

SECTION "serial", ROM0[$0058]
	jp Serial

	ds $60 - @, 0 ; unused

SECTION "joypad", ROM0[$0060]
	reti


SECTION "Header", ROM0[$0100]

Start::
; Nintendo requires all Game Boy ROMs to begin with a nop ($00) and a jp ($C3)
; to the starting address.
	nop
	jp _Start

; The Game Boy cartridge header data is patched over by rgbfix.
; This makes sure it doesn't get used for anything else.

	ds $0150 - @

ENDSECTION
