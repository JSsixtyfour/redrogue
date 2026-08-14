Random::
; Return a random number in a.
; For battles, use BattleRandom.
	push hl
	push de
	push bc
	farcall Random_
	ldh a, [hRandomAdd]
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
