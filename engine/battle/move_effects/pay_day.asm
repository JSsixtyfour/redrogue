PayDayEffect_:
	xor a
	ld hl, wPayDayMoney
	ld [hli], a
	ldh a, [hWhoseTurn]
	and a
	ld a, [wBattleMonLevel]
	jr z, .payDayEffect
	ld a, [wEnemyMonLevel]
.payDayEffect
; level * 2, carried into a second byte: past level 127 it no longer fits one
; (ENDLESS_MODE_CHECKPOINT_G.md). At most 2 * MAX_LEVEL, so the hundreds digit
; below stays a single BCD digit.
	ASSERT 2 * MAX_LEVEL < 1000
	add a
	ldh [hDividend + 3], a
	ld a, 0                 ; keeps the carry
	rla
	ldh [hDividend + 2], a
	xor a
	ldh [hDividend], a
	ldh [hDividend + 1], a
; convert to BCD
	ld a, 100
	ldh [hDivisor], a
	ld b, $4
	call Divide
	ldh a, [hQuotient + 3]
	ld [hli], a ; wPayDayMoney + 1
	ldh a, [hRemainder]
	ldh [hDividend + 3], a
	ld a, 10
	ldh [hDivisor], a
	ld b, $4
	call Divide
	ldh a, [hQuotient + 3]
	swap a
	ld b, a
	ldh a, [hRemainder]
	add b
	ld [hl], a ; wPayDayMoney + 2
	ld de, wTotalPayDayMoney + 2
	ld c, $3
	predef AddBCDPredef
	ld hl, CoinsScatteredText
	jp PrintText

CoinsScatteredText:
	text_far _CoinsScatteredText
	text_end
