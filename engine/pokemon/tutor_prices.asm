; Input: e = move ID. Output: hItemPrice = three-byte BCD fee,
; de = hItemPrice. Other registers are clobbered (including by farcall).
GetTutorMovePrice::
	ld d, 0
	ld hl, MoveRankByID
	add hl, de
	ld de, hItemPrice
	ld bc, 1
	ld a, BANK(MoveRankByID)
	call FarCopyData
	ldh a, [hItemPrice]
	cp MOVE_RANK_OFFLIST
	jr c, .ranked
	xor a ; OFFLIST is a randomizer exclusion, not a tutor restriction.
.ranked
	ld e, a
	ld d, 0
	ld hl, TutorMovePrices
	add hl, de
	add hl, de
	add hl, de
	ld de, hItemPrice
	ld bc, 3
	call CopyData
	ld de, hItemPrice
	ret

TutorMovePrices::
	table_width 3, TutorMovePrices
	bcd3 MOVE_TUTOR_PRICE_F
	bcd3 MOVE_TUTOR_PRICE_D
	bcd3 MOVE_TUTOR_PRICE_C
	bcd3 MOVE_TUTOR_PRICE_B
	bcd3 MOVE_TUTOR_PRICE_A
	bcd3 MOVE_TUTOR_PRICE_S
	assert_table_length MOVE_RANK_OFFLIST
