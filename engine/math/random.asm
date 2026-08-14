SECTION "Random", ROMX

; Patrik Rak's 8-bit Xor-Shift PRNG, released into the public domain.
; http://www.worldofspectrum.org/forums/showthread.php?t=23070
; Ported from shinpokered (github.com/jojobear13/shinpokered), rewritten here
; into ldh form - shinpokered reaches the state through hl, which gains nothing
; from HRAM; this version is ~1 byte smaller and ~8 cycles faster.
; 32-bit state, period 2^32-1. The all-zero state is ABSORBING, hence the guard
; below: Init zeroes all of HRAM, so we always start there.
Random_::
	ldh a, [hRandomSub]       ; x[n-2]
	ld b, a
	ldh a, [hRandomAdd]       ; x[n]
	ld c, a
	ldh a, [hRandomLast + 1]  ; x[n-3]
	ld d, a
	ldh a, [hRandomLast]      ; x[n-1]
	ld e, a

	; whole state is now in bcde - break out of the absorbing zero state
	; before it can produce an endless run of 0s
	ld a, b
	or c
	or d
	or e
	jr nz, .stateOK
	inc c
.stateOK
	; shift the pair down: x[n-1] := x[n], x[n-3] := x[n-2].
	; Must happen before the core clobbers b and c.
	ld a, c
	ldh [hRandomLast], a
	ld a, b
	ldh [hRandomLast + 1], a

	; x[n+1] = f(x[n], x[n-3])
	ld a, c
	add a, a
	add a, a
	add a, a
	xor c                     ; t1 = x[n] ^ (x[n] << 3)
	ld c, a
	ld a, d
	add a, a
	xor d                     ; t2 = x[n-3] ^ (x[n-3] << 1)
	ld b, a
	rra                       ; xor cleared carry, so this is t2 >> 1
	xor b
	xor c                     ; new x[n]
	ldh [hRandomAdd], a
	ld a, e
	ldh [hRandomSub], a       ; new x[n-2] := old x[n-1]
	ret

; Fold real entropy into the RNG state. Called once from MainMenu, i.e. after
; player input has perturbed timing. This covers the emulator/flashcart case
; where RAM is cleared at boot, which is what shinpokered's RNG_Correction
; addresses - done here without its 4-byte $DEF0 WRAM mirror, which I prefer
; to avoid because we're already wRam hungry enoguh. The nonzero guarantee comes from Random_'s
; own guard, so it is not duplicated here.
RandomSeedStir::
	ldh a, [rDIV]
	ld b, a
	ldh a, [hRandomAdd]
	xor b
	ldh [hRandomAdd], a
	ldh a, [hFrameCounter]
	ld b, a
	ldh a, [hRandomSub]
	xor b
	ldh [hRandomSub], a
	ld b, 4
.diffuse
	call Random               ; HOME, safe to call from ROMX
	dec b
	jr nz, .diffuse
	ret
