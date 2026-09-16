SECTION "Random", ROMX

; The CMWC generator itself lives in HOME, inlined into Random:: in
; home/random.asm. It was farcalled out here until 2026-09-15, when measurement
; showed the farcall trampoline cost 308 cycles against the body's 192, i.e.
; 62% of every call went on a bank switch the generator never needed. Only the
; once-per-boot seed stir stays in ROMX, where its size costs nothing.

; Fold hardware entropy into the generator state. Called once from MainMenu,
; i.e. after the player's first real input has perturbed timing. This covers the
; emulator/flashcart case where RAM is cleared at boot, which is what
; shinpokered's RNG_Correction addresses, done here without its 4-byte $DEF0
; WRAM mirror.
;
; Only q[] is perturbed. wRandomCarry carries the generator's cy < 253
; invariant and must never receive an arbitrary byte; wRandomIndex must stay in
; 1..8. Any byte value is legal in q[], so the XOR is safe there. The eight
; diffusion calls circulate the perturbation through every lag, since a change
; to one q entry only reaches the others via cy on subsequent steps.
RandomSeedStir::
	ldh a, [rDIV]
	ld b, a
	ldh a, [hFrameCounter]
	xor b
	ld hl, wRandomQ           ; q[1]
	xor [hl]
	ld [hl], a
	ld b, 8
.diffuse
	call Random               ; HOME, safe to call from ROMX; preserves bc
	dec b
	jr nz, .diffuse
	ret
