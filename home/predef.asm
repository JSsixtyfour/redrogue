PredefContinue::
; Second half of Predef, whose entry is the rst $28 vector (home/header.asm).
; To preserve other registers, have the
; destination call GetPredefRegisters.
	ld [rROMB], a

	call GetPredefPointer

	ld a, [wPredefBank]
	ldh [hLoadedROMBank], a
	ld [rROMB], a

	ld de, .done
	push de
	jp hl
.done

	pop af
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	ret

GetPredefRegisters:: ; marcelnote - optimized
; Restore the contents of register pairs
; when GetPredefPointer was called.
; Returns a = l (the old version returned a = c); flags untouched either way.
; Audited 2026-09-24: no caller reads a before writing it, and a predef
; target's a never reaches its caller because Predef's .done pops af.
	ASSERT wPredefHL + 2 == wPredefDE && wPredefDE + 2 == wPredefBC
	ld hl, wPredefBC + 1
	ld a, [hld] ; wPredefBC + 1
	ld c, a
	ld a, [hld] ; wPredefBC
	ld b, a
	ld a, [hld] ; wPredefDE + 1
	ld e, a
	ld a, [hld] ; wPredefDE
	ld d, a
	ld a, [hld] ; wPredefHL + 1
	ld h, [hl]  ; wPredefHL
	ld l, a
	ret
