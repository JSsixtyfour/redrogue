_Multiply:: ; marcelnote - adapted from polishedcrystal
; Multiply hMultiplicand (3 bytes) by hMultiplier (1 byte). Result in hProduct (4 bytes).
; All values are big endian.

	ldh a, [hMultiplicand]
	ld e, a
	ldh a, [hMultiplicand + 1]
	ld h, a
	ldh a, [hMultiplicand + 2]
	ld l, a

	xor a
	ld d, a
	ldh [hProduct], a
	ldh [hProduct + 1], a
	ldh [hProduct + 2], a
	ldh [hProduct + 3], a

	ldh a, [hMultiplier]

.loop ; performs dehl * a
	and a                 ; a = 0?
	ret z                 ; if yes, we're done

	; here a ≠ 0, carry not set
	rra                   ; divide a by 2, is the last bit 1?
	jr nc, .next          ; if not, just multiply dehl by 2

	; else, add dehl to result before multiplying it by 2
	ld b, a               ; store multiplier in b

	ld c, LOW(hProduct + 3)
	ldh a, [c]
	add l
	ldh [c], a

	dec c ; c = LOW(hProduct + 2)
	ldh a, [c]
	adc h
	ldh [c], a

	dec c ; c = LOW(hProduct + 1)
	ldh a, [c]
	adc e
	ldh [c], a

	dec c ; c = LOW(hProduct)
	ldh a, [c]
	adc d
	ldh [c], a

	ld a, b               ; retrieve multiplier

.next
	add hl, hl            ; multiply hl by 2
	rl e                  ; multiply e by 2 (plus carry)
	rl d                  ; multiply d by 2 (plus carry)
	jr .loop



_Divide:: ; adapted from polishedcrystal via yumepokered
; Divide hDividend, length b (max 4 bytes), by hDivisor (1 byte).
; Result in hQuotient (4 bytes), remainder in hRemainder. All values big endian.
;
; Shift-subtract long division, in place: each dividend byte is overwritten by
; its quotient byte, so no buffer is needed. Leading zero bytes are skipped, so
; a typical 2-significant-byte dividend costs 16 bit-iterations rather than 32.
;
; Yume's version takes a fixed 4-byte right-aligned dividend. Ours keeps the
; vanilla b-byte contract, where a b<4 dividend sits LEFT-aligned in hDividend
; with the unused trailing bytes holding garbage. The normalize loop below
; shifts it right-aligned and zero-fills the front, which turns the b<4 case
; into Yume's 4-byte case with no call-site changes. The zero-skip then removes
; the cost of the padding again.
	ASSERT hQuotient == hDividend
	ASSERT hRemainder == hDividend + 4 ; .loopBytes stops when c reaches it

	ldh a, [hDivisor]
	and a ; is divisor 0?
	ret z ; polishedcrystal crashed here; returning leaves hQuotient untouched
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
	ret

.loopBytes
	ldh a, [c]    ; a = [hDividend + nByte], next dividend byte
	ld h, a       ; h = dividend for this byte, will become quotient
	ld a, e       ; a = remainder within bits loop
	ld b, 8       ; b = bit counter
.loopBits
	sla h         ; rotate dividend bit out and quotient bit left
	rla           ; bring in next bit of dividend into a
	jr c, .carry  ; if carry from rla, then $1a [9bits] >= d so subtract d and increase h
	cp d          ; a >= d?
	jr c, .skip   ; if not, move to next bit
.carry
	sub d         ; subtract divisor from remainder
	inc h         ; increase quotient
.skip
	dec b         ; one less bit to do
	jr nz, .loopBits
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
	ret
