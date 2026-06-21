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

; get a random number in [0, c-1]
; c is the range
Rangerandom::
push bc
call Random                 ; get a random number to determine pokemon
ldh [hMultiplicand+2], a    ; place number in for multiplication
xor a
ldh [hMultiplicand], a      ; put zero in highest byte
ldh [hMultiplicand+1], a    ; put second byte for multiplication
ld a, c                     ; multiply by amount of this class
ldh [hMultiplier], a        ; place amount of class in multiplier
call Multiply               ; multiply random number by amount in class
ldh a, [hProduct+2]         ; high byte = floor(random*N/256), always in [0,N-1]
pop bc
ret
