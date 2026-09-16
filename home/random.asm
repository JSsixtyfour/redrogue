Random::
; Return a random number in a.
; For battles, use BattleRandom.
;
; The generator body is INLINE here, in HOME, rather than farcalled out to a
; ROMX bank. Measured 2026-09-15 with PyBoy's cycle counter: the body itself is
; 192 cycles, but the farcall trampoline wrapped around it cost 308 more, so
; 62% of every `call Random` was Bankswitch saving and restoring a bank this
; routine never needed changed. Inlining deletes that round trip, and also the
; `ldh a, [hRandomAdd]` reload the old wrapper needed only because Bankswitch
; clobbers a. Rangerandom draws through here in a rejection loop and 115 sites
; call it, so this is the hottest path in the whole RNG.
;
; This body is allowed to live in HOME only because it never bank-switches: it
; touches wRandomTable (WRAM) and hRandomAdd/hRandomSub (HRAM) and nothing
; else. Do not add anything here that changes banks.
	push hl
	push de
	push bc

; Patrik Rak's 8-bit Complementary-Multiply-With-Carry PRNG, public domain.
; Created 2012, revised 2014/2015, with optimisation contributions from Einar
; Saukas and Alan Albrecht.
;   https://gist.github.com/raxoft/2275716fea577b48f7f0
;   http://www.worldofspectrum.org/forums/showthread.php?t=39632
; Ported from Rak's Z80 source instruction for instruction; only the `jr nc,$+3`
; idioms became named labels. Replaced the Rak xor-shift import of 2026-08-13,
; which this fork carried until 2026-09-15.
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
; are never touched. The three `jr nc` branches cost the same either way (taken
; is 12 cycles and skips the dec b; not taken is 8 plus the dec b's 4), so the
; routine is exactly constant-time at 192 cycles regardless of its data.
;
; THERE IS NO ABSORBING STATE, which is why this replaced the xor-shift and why
; that version's explicit zero guard is gone. Init zeroes all of WRAM, so the
; generator starts from i=0, cy=0, q[]=0; that gives t = 0 and x = ~0 = $ff, so
; it writes $ff into q[i] and walks itself out.
;
; Cold-start transient, measured against a model of this exact code: from the
; all-zero state the first ~60-100 outputs are still visibly structured (runs of
; $ff and $00 as the carry works its way through the lag table) before the byte
; stream saturates. VBlank calls Random once a frame from Init onward, so that
; transient is spent inside the first ~2 seconds of the boot logo, thousands of
; frames before the title screen and before anything rolls a gameplay value.
; Nothing needs to be done about it, but do not seed this generator and then
; immediately consume a handful of outputs. Seed with a well-mixed table (see
; .seedRNG in engine/debug/debug_fight2.asm and seed_rng in the PyBoy harness).
;
; Labelled so BGB and the PyBoy harness keep a breakpoint target on the
; generator itself. It is NOT callable: it falls through into the pops below.
.body
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

	; Publish the output pair. hRandomAdd is what this routine returns.
	; hRandomSub holds the previous output, so the sites that read it directly
	; without a preceding `call Random` still get an independent random byte:
	; it was x[n-2] under the xor-shift, and roughly -hRandomAdd under stock
	; pokered.
	ld e, a
	ldh a, [hRandomAdd]
	ldh [hRandomSub], a
	ld a, e
	ldh [hRandomAdd], a

	; a already holds the new value, and none of the pops touch it.
	pop bc
	pop de
	pop hl
	ret

; Return a random number in [0, c-1] in a. c is the range.
;
; Rejection-samples against the smallest (2^k)-1 mask >= c-1, so every outcome is
; exactly equally likely. The previous multiply-shift form, floor(rand * c / 256),
; handed some outcomes one more of the 256 source values than others: at c=40 the
; buckets were 6 or 7 wide (~17% relative bias), at c=24 they were 10 or 11 (~10%,
; the Elite 4 order shuffle). Powers of two were always fair and still are.
;
; Expected draws is under 2 (acceptance is c/2^k >= 1/2), and dropping Multiply
; roughly pays for the extra draws. It also no longer touches
; hMultiplicand/hMultiplier/hProduct, which removes the old re-entrancy hazard
; with any other Multiply user, and de now survives the call (it did not before).
Rangerandom::
	push bc
	ld a, c
	and a
	jr z, .done          ; c = 0 -> 0, matching the old behaviour
	ld b, a
	dec b                ; b = c-1 = largest valid result
	ld a, 1
.mask
	cp b
	jr nc, .gotmask      ; mask >= c-1, so it covers every valid result
	add a, a
	inc a                ; 1, 3, 7, 15, 31, ...
	jr .mask
.gotmask
	ld b, a              ; b = mask
.draw
	call Random          ; preserves bc
	and b
	cp c
	jr nc, .draw         ; landed above the range - draw again
.done
	pop bc
	ret

