; calculates the level a mon should be based on its current exp
CalcLevelFromExperience::
	ld a, [wLoadedMonSpecies]
	ld [wCurSpecies], a
	call GetMonHeader
	ld d, $1 ; init level to 1
.loop
	inc d ; increment level
	call CalcExperience
	push hl
	ld hl, wLoadedMonExp + 2 ; current exp
; compare exp needed for level d with current exp
	ldh a, [hExperience + 2]
	ld c, a
	ld a, [hld]
	sub c
	ldh a, [hExperience + 1]
	ld c, a
	ld a, [hld]
	sbc c
	ldh a, [hExperience]
	ld c, a
	ld a, [hl]
	sbc c
	pop hl
	jr nc, .loop ; if exp needed for level d is not greater than exp, try the next level
	dec d ; since the exp was too high on the last loop iteration, go back to the previous value and return
	ret

; calculates the amount of experience needed for level d
CalcExperience::
; Underflow protection. Three of the six growth rates carry a constant term big
; enough that the polynomial evaluates NEGATIVE at level 1 (Slightly Fast -19,
; Slightly Slow -49, Medium Slow -53), and the accumulator below is unsigned, so
; it wraps to roughly 16.7 million instead of clamping at zero. That is reachable:
; add_mon.asm calls this directly with d = the mon's level to seed a newly
; created mon's exp, so a level-1 mon of one of those rates is stored with a
; garbage exp that reads back as level 100.
;
; Level 1 is the ONLY input that can underflow, verified by evaluating all six
; growth rates over levels 1-255; the maximum is 1,250,000, which also leaves no
; overflow case. Guarding just that one level, instead of reordering the term
; summation the way the upstream fix does, keeps every level >= 2 computing
; bit-for-bit as before. That matters here: the reordered version was measured
; to shift this fork's deterministic party-generation RNG stream (the pyboy
; smoke suite's FIGHT 2 fixture caught it), for no gain at any level the game
; actually generates.
	ld a, d
	dec a
	jr nz, .calculate
; every growth rate is worth 0 or 1 exp at level 1, so d (== 1) is both the
; clamp and the correct value for the rates that do not underflow
	xor a
	ldh [hExperience], a
	ldh [hExperience + 1], a
	ld a, d
	ldh [hExperience + 2], a
	ret
.calculate
	ld a, [wMonHGrowthRate]
	add a
	add a
	ld c, a
	ld b, 0
	ld hl, GrowthRateTable
	add hl, bc
	call CalcDSquared
	ld a, d
	ldh [hMultiplier], a
	call Multiply
	ld a, [hl]
	and $f0
	swap a
	ldh [hMultiplier], a
	call Multiply
	ld a, [hli]
	and $f
	ldh [hDivisor], a
	ld b, $4
	call Divide
	ldh a, [hQuotient + 1]
	push af
	ldh a, [hQuotient + 2]
	push af
	ldh a, [hQuotient + 3]
	push af
	call CalcDSquared
	ld a, [hl]
	and $7f
	ldh [hMultiplier], a
	call Multiply
	ldh a, [hProduct + 1]
	push af
	ldh a, [hProduct + 2]
	push af
	ldh a, [hProduct + 3]
	push af
	ld a, [hli]
	push af
	xor a
	ldh [hMultiplicand], a
	ldh [hMultiplicand + 1], a
	ld a, d
	ldh [hMultiplicand + 2], a
	ld a, [hli]
	ldh [hMultiplier], a
	call Multiply
	ld b, [hl]
	ldh a, [hProduct + 3]
	sub b
	ldh [hProduct + 3], a
	ld b, $0
	ldh a, [hProduct + 2]
	sbc b
	ldh [hProduct + 2], a
	ldh a, [hProduct + 1]
	sbc b
	ldh [hProduct + 1], a
; The difference of the linear term and the constant term consists of 3 bytes
; starting at hProduct + 1. Below, hExperience (an alias of that address) will
; be used instead for the further work of adding or subtracting the squared
; term and adding the cubed term.
	pop af
	and $80
	jr nz, .subtractSquaredTerm ; check sign
	pop bc
	ldh a, [hExperience + 2]
	add b
	ldh [hExperience + 2], a
	pop bc
	ldh a, [hExperience + 1]
	adc b
	ldh [hExperience + 1], a
	pop bc
	ldh a, [hExperience]
	adc b
	ldh [hExperience], a
	jr .addCubedTerm
.subtractSquaredTerm
	pop bc
	ldh a, [hExperience + 2]
	sub b
	ldh [hExperience + 2], a
	pop bc
	ldh a, [hExperience + 1]
	sbc b
	ldh [hExperience + 1], a
	pop bc
	ldh a, [hExperience]
	sbc b
	ldh [hExperience], a
.addCubedTerm
	pop bc
	ldh a, [hExperience + 2]
	add b
	ldh [hExperience + 2], a
	pop bc
	ldh a, [hExperience + 1]
	adc b
	ldh [hExperience + 1], a
	pop bc
	ldh a, [hExperience]
	adc b
	ldh [hExperience], a
	ret

; calculates d*d
CalcDSquared:
	xor a
	ldh [hMultiplicand], a
	ldh [hMultiplicand + 1], a
	ld a, d
	ldh [hMultiplicand + 2], a
	ldh [hMultiplier], a
	jp Multiply

INCLUDE "data/growth_rates.asm"
