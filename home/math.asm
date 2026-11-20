; Multiply and Divide live INLINE here in HOME rather than being farcalled out
; to a ROMX bank, same as Random (home/random.asm) and for the same reason: the
; trampoline cost more than it bought. Neither body ever bank-switches - they
; touch only registers and the math HRAM union - so they are safe in HOME.
; Moved 2026-09-24 using HOME bytes freed by the rst-vector far calls (see
; home/header.asm). Do not add anything here that changes banks.
;
; Both keep the EXACT register contract their old bank-switching wrappers had,
; including the undocumented parts, because callers were written against the
; real behaviour (see project memory on clobber-list mismatches):
; - Multiply: preserves bc/de/hl; returns a = hLoadedROMBank (callfar's
;   Bankswitch.Return left it there) and the routine's own exit flags.
; - Divide: preserves bc/de/hl; returns a = hLoadedROMBank and the CALLER's
;   entry flags (homecall's push af / pop af restored them).

; function to do multiplication
; all values are big endian
; INPUT
; FF96-FF98 =  multiplicand
; FF99 = multiplier
; OUTPUT
; FF95-FF98 = product
Multiply:: ; marcelnote - adapted from polishedcrystal
; Multiply hMultiplicand (3 bytes) by hMultiplier (1 byte). Result in hProduct (4 bytes).
	push hl
	push de
	push bc

; Rewritten 2026-11-19 (AI speed lever 3): the old loop accumulated through four
; HRAM read-modify-writes per set multiplier bit (~1,075 cycles per AI call). Now
; the low 16 bits of the multiplicand go through a register shift-add, c:h:l, its
; multiplier bits taken high to low and fully unrolled; a nonzero top byte (1% of
; AI calls) adds one 8x8 product into the top two bytes. Same contract, same exit
; flags (Z set, C clear), same results: test_math_routines checks all three against
; Python, and fails on a dropped carry.
	ldh a, [hMultiplicand + 1]
	ld d, a
	ldh a, [hMultiplicand + 2]
	ld e, a                         ; de = the multiplicand's low 16 bits
	ldh a, [hMultiplier]
	ld b, a                         ; b = the multiplier, kept for the top byte
	ld hl, 0
	ld c, l                         ; c:h:l = low 16 bits x multiplier
	REPT 8
	add hl, hl
	rl c                            ; product * 2
	add a                           ; next multiplier bit, high first, into carry
	jr nc, .low\@
	add hl, de                      ; + multiplicand
	jr nc, .low\@
	inc c
.low\@
	ENDR
	ldh a, [hMultiplicand]          ; read before hProduct + 1 (its alias) is written
	and a
	jr z, .store                    ; b = 0 below: the top byte adds nothing
; Top byte: (top x multiplier) << 16, a 16-bit product, into the top two bytes.
	push hl
	ld e, a
	ld d, 0                         ; de = the top byte
	ld a, b
	ld hl, 0
	REPT 8
	add hl, hl
	add a
	jr nc, .high\@
	add hl, de                      ; an 8x8 product never carries out of hl
.high\@
	ENDR
	ld a, l
	add c
	ld c, a                         ; product byte 1 += low byte of top x multiplier
	ld a, h
	adc 0
	ld b, a                         ; product byte 0 = its high byte + carry
	pop hl
	jr .write
.store
	ld b, a                         ; a = 0: product byte 0
.write
	ld a, b
	ldh [hProduct], a
	ld a, c
	ldh [hProduct + 1], a
	ld a, h
	ldh [hProduct + 2], a
	ld a, l
	ldh [hProduct + 3], a
	xor a                           ; Z set, C clear, as the old loop exited

.done
	pop bc
	pop de
	pop hl
	ldh a, [hLoadedROMBank] ; ldh leaves the flags alone
	ret

; function to do division
; all values are big endian
; INPUT
; FF95-FF98 = dividend
; FF99 = divisor
; b = number of bytes in the dividend (starting from FF95)
; OUTPUT
; FF95-FF98 = quotient
; FF99 = remainder
Divide:: ; adapted from polishedcrystal via yumepokered
; Divide hDividend, length b (max 4 bytes), by hDivisor (1 byte).
; Result in hQuotient (4 bytes), remainder in hRemainder. All values big endian.
;
; Shift-subtract long division, in place: each dividend byte is overwritten by
; its quotient byte, so no buffer is needed. Leading zero bytes are skipped, so
; a typical 2-significant-byte dividend costs 16 bit-iterations rather than 32.
;
; Yume's version takes a fixed 4-byte right-aligned dividend. Ours keeps the
; vanilla b-byte contract, where a b<4 dividend sits LEFT-aligned in hDividend
; with the unused trailing bytes holding garbage. The normalize step below
; shifts it right-aligned and zero-fills the front, which turns the b<4 case
; into Yume's 4-byte case with no call-site changes. The zero-skip then removes
; the cost of the padding again.
	ASSERT hQuotient == hDividend
	ASSERT hRemainder == hDividend + 4 ; .loopBytes stops when c reaches it

	push hl
	push de
	push bc
	push af               ; caller's flags come back out, as homecall did

	ldh a, [hDivisor]
	and a ; is divisor 0?
	jr z, .done ; polishedcrystal crashed here; returning leaves hQuotient untouched
	ld d, a              ; d = divisor

; right-align a b-byte dividend in ONE move per case. A loop that shifted all
; four bytes once per missing byte measured 18% slower than the old routine at
; b=1, since it paid for three full shifts before dividing a single byte.
	ld a, b
	cp 4
	jr nc, .aligned
	dec a
	jr z, .b1
	dec a
	jr z, .b2
; b=3
	ldh a, [hDividend + 2]
	ldh [hDividend + 3], a
	ldh a, [hDividend + 1]
	ldh [hDividend + 2], a
	ldh a, [hDividend]
	ldh [hDividend + 1], a
	xor a
	jr .zero1
.b2
	ldh a, [hDividend + 1]
	ldh [hDividend + 3], a
	ldh a, [hDividend]
	ldh [hDividend + 2], a
	xor a
	jr .zero2
.b1
	ldh a, [hDividend]
	ldh [hDividend + 3], a
	xor a
	ldh [hDividend + 2], a
.zero2
	ldh [hDividend + 1], a
.zero1
	ldh [hDividend], a
.aligned

	ld c, LOW(hDividend) ; address tracker to use ldh a, [c]
	ld e, 0              ; e = remainder

; first check if we can skip high bytes equal to 0
	ld b, 4              ; number of bytes to check
.skipZeros
	ldh a, [c]           ; a = [hDividend + nByte], next dividend byte
	and a                ; is this dividend 0?
	jr nz, .loopBytes    ; if not, start division
	inc c                ; otherwise move to next byte
	dec b
	jr nz, .skipZeros
; all dividends are 0 so set remainder to 0 and we're done
	ldh [c], a           ; [hRemainder] = 0
	jr .done

.loopBytes
	ldh a, [c]    ; a = [hDividend + nByte], next dividend byte
	ld h, a       ; h = dividend for this byte, will become quotient
	ld a, e       ; a = remainder within bits loop
; The 8 bits are unrolled (2026-11-19, AI speed lever 3): the old counted loop
; spent `dec b` + `jr nz` (16 of ~52 cycles) per bit on loop control. Same steps,
; same results; test_math_routines checks them against Python.
	REPT 8
	sla h         ; rotate dividend bit out and quotient bit left
	rla           ; bring in next bit of dividend into a
	jr c, .carry\@ ; if carry from rla, then $1a [9bits] >= d so subtract d and increase h
	cp d          ; a >= d?
	jr c, .skip\@ ; if not, move to next bit
.carry\@
	sub d         ; subtract divisor from remainder
	inc h         ; increase quotient
.skip\@
	ENDR
	ld e, a       ; update remainder
	ld a, h
	ldh [c], a    ; [hQuotient + nByte] = quotient
	inc c         ; move to next dividend byte
	ld a, c
	cp LOW(hRemainder) ; is c = LOW(hRemainder)?
	jr nz, .loopBytes  ; if not, more bytes to divide

	ld a, e
	ldh [c], a    ; [hRemainder] = e. NOTE: hRemainder ALIASES hDivisor, so the
	              ; divisor is destroyed - as it always has been.
.done
	pop af                  ; caller's flags
	ldh a, [hLoadedROMBank] ; a = current bank, as homecall left it; flags kept
	pop bc
	pop de
	pop hl
	ret
