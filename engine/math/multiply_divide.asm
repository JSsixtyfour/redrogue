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
; Result in hQuotient, remainder in hRemainder. All values big endian.
;
; Shift-subtract long division: 8 iterations per dividend byte, so cost is
; bounded and O(b). The repeated-subtraction routine this replaces cost
; ~9,760 cycles because its inner loop scaled with the QUOTIENT.
	ldh a, [hDivisor]
	and a ; is divisor 0?
	ret z ; polishedcrystal crashed here; returning leaves hQuotient untouched

	ld d, a              ; d = divisor
	ld c, LOW(hDividend) ; to use ldh a, [c]
	ld e, 0              ; e = running remainder
.loopBytes
	push bc              ; save b = byte counter, c = LOW(hDividend) + nByte
	ld b, 8              ; b = bit counter
	ldh a, [c]           ; next dividend byte
	ld h, a              ; h = dividend byte being shifted out
	ld l, 0              ; l = quotient byte being shifted in
.loopBits
	sla h
	rl e                 ; bring next bit of h into the remainder
	ld a, e
	jr c, .carry         ; carry out of rl e means the 9-bit value >= d
	cp d
	jr c, .skip
.carry
	sub d
	ld e, a              ; update remainder
	inc l                ; set this quotient bit
.skip
	dec b
	jr z, .doneByte
	sla l
	jr .loopBits
.doneByte
	ld a, c
	add hDivideBuffer - hDividend
	ld c, a              ; c = LOW(hDivideBuffer) + nByte
	ld a, l
	ldh [c], a           ; stash this byte's quotient
	pop bc               ; restore byte counter and dividend cursor
	inc c
	dec b
	jr nz, .loopBytes

	xor a
	ldh [hDividend], a
	ldh [hDividend + 1], a
	ldh [hDividend + 2], a
	ldh [hDividend + 3], a
	ld a, e
	ldh [hRemainder], a  ; NOTE: hRemainder ALIASES hDivisor (both union offset
	                     ; 4), so the divisor is destroyed. The routine being
	                     ; replaced destroyed it too - this is not a regression.
	ld a, c              ; c = LOW(hDividend) + initial b
	sub LOW(hQuotient)   ; hQuotient aliases hDividend, so this recovers b
	ld b, a
	add LOW(hDivideBuffer) - 1
	ld c, a              ; c = LOW(hDivideBuffer) + last byte written
	ldh a, [c]
	ldh [hQuotient + 3], a
	dec b
.exit1 ; named for hookability (project convention): b=1 exit, quotient set
	ret z
	dec c
	ldh a, [c]
	ldh [hQuotient + 2], a
	dec b
.exit2 ; b=2 exit
	ret z
	dec c
	ldh a, [c]
	ldh [hQuotient + 1], a
	dec b
.exit3 ; b=3 exit
	ret z
	dec c
	ldh a, [c]
	ldh [hQuotient], a
.exit4 ; b=4 exit
	ret
