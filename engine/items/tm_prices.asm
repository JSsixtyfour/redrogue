GetMachinePrice::
; Input:  [wCurItem] = Item ID of a TM
; Output: Stores the TM price at hItemPrice
	ld a, [wCurItem]
	sub TM01 ; underflows if item is an HM (HMs sit below TM01)
	jr nc, .isTM
	; HM: fixed price ₽3000
	ld a, $30
	ldh [hItemPrice + 1], a
	xor a
	ldh [hItemPrice], a
	ldh [hItemPrice + 2], a
	ret
.isTM
	ld d, a
	ld hl, TechnicalMachinePrices
	srl a
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl] ; a contains byte whose high or low nybble is the TM price (in thousands)
	srl d
	jr nc, .highNybbleIsPrice ; is TM id odd?
	swap a
.highNybbleIsPrice
	and $f0
	ldh [hItemPrice + 1], a
	xor a
	ldh [hItemPrice], a
	ldh [hItemPrice + 2], a
	ret

INCLUDE "data/items/tm_prices.asm"
