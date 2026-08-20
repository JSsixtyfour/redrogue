_Start::
; Shin Red import Phase 3. This used to write wOnCGB directly - which silently
; did nothing, because Init zeroes ALL of WRAM0 (including wOnCGB) immediately
; after we jump to it. The boot-time A value is the only chance to detect CGB,
; so the answer is carried through the wipe in E instead: Init's clear loop uses
; only hl/bc/a, and DisableLCD on the way there uses only a/b, so de survives.
; Init writes wOnCGB from E once the wipe is done. See SoftReset, which reloads
; E the same way so a soft reset does not lose the flag.
	cp BOOTUP_A_CGB
	ld e, FALSE
	jr nz, .ok
	ld e, TRUE
.ok
	jp Init
