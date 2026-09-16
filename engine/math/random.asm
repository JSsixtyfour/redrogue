SECTION "Random", ROMX

; Patrik Rak's 8-bit Complementary-Multiply-With-Carry PRNG, public domain.
; Created 2012, revised 2014/2015, with optimisation contributions from Einar
; Saukas and Alan Albrecht.
;   https://gist.github.com/raxoft/2275716fea577b48f7f0
;   http://www.worldofspectrum.org/forums/showthread.php?t=39632
; Ported from Rak's Z80 source instruction for instruction; only the `jr nc,$+3`
; idioms became named labels, and the two-byte output tail at the end is ours.
; Replaced the Rak xor-shift import of 2026-08-13, which this fork carried until
; 2026-09-15.
;
; Base b = 256, lag r = 8, multiplier a = 253. Period 253*2^59 ~= 2^67.
;   i    = (i & 7) + 1
;   t    = 253*q[i] + cy
;   cy   = t >> 8          ; stays < 253: t <= 253*255 + 252 = 64767, >>8 = 252
;   x    = ~(t & 255)      ; "complementary": x = (b-1) - (t & 255)
;   q[i] = x, and x is the output
;
; 253*y is computed as 256*y - 3*y: load b:a = y:cy, then subtract y three times
; with a manual borrow into b. No multiply routine, and hMultiplicand/hProduct
; are never touched.
;
; THERE IS NO ABSORBING STATE, which is the whole reason this replaced the
; xor-shift and why that version's explicit zero guard is gone. Init zeroes all
; of WRAM, so the generator starts from i=0, cy=0, q[]=0; that gives t = 0 and
; x = ~0 = $ff, so it writes $ff into q[i] and walks itself out.
;
; Cold-start transient, measured against a model of this exact code: from the
; all-zero state the first ~60-100 outputs are still visibly structured (runs of
; $ff and $00 as the carry works its way through the lag table) before the byte
; stream saturates. VBlank calls Random once a frame from Init onward, so that
; transient is spent inside the first ~2 seconds of the boot logo, thousands of
; frames before the title screen and before anything rolls a gameplay value.
; Nothing needs to be done about it - but do not seed this generator and then
; immediately consume a handful of outputs. Seed with a well-mixed table (see
; .seedRNG in engine/debug/debug_fight2.asm and seed_rng in the PyBoy harness).
;
; State lives in WRAM (wRandomTable, ram/wram.asm) because it is 10 bytes and
; HRAM has only 6 free. The routine reaches it through hl/de, which costs the
; same from either region, so nothing is lost by the move; the published output
; pair hRandomAdd/hRandomSub stays in HRAM, where ~15 sites read it with `ldh`.
Random_::
	ld hl, wRandomTable

	ld a, [hl]                ; i = (i & 7) + 1
	and 7
	inc a
	ld [hl], a

	inc l                     ; hl = &cy

	ld d, h                   ; de = &q[i]
	add a, l
	ld e, a

	ld a, [de]                ; y = q[i]
	ld b, a
	ld c, a
	ld a, [hl]                ; ba = 256*y + cy

	sub c                     ; ba = 255*y + cy
	jr nc, .noBorrow1
	dec b
.noBorrow1
	sub c                     ; ba = 254*y + cy
	jr nc, .noBorrow2
	dec b
.noBorrow2
	sub c                     ; ba = 253*y + cy
	jr nc, .noBorrow3
	dec b
.noBorrow3

	ld [hl], b                ; cy = ba >> 8
	cpl                       ; x = (b-1) - (ba & 255) = ~(ba & 255)
	ld [de], a                ; q[i] = x

	; Publish the output pair. hRandomAdd is what Random:: returns. hRandomSub
	; holds the previous output, so the sites that read it directly without a
	; preceding `call Random` still get an independent random byte - it was
	; x[n-2] under the xor-shift, and roughly -hRandomAdd under stock pokered.
	ld e, a
	ldh a, [hRandomAdd]
	ldh [hRandomSub], a
	ld a, e
	ldh [hRandomAdd], a
	ret

; Fold hardware entropy into the generator state. Called once from MainMenu,
; i.e. after the player's first real input has perturbed timing. This covers the
; emulator/flashcart case where RAM is cleared at boot, which is what
; shinpokered's RNG_Correction addresses - done here without its 4-byte $DEF0
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
