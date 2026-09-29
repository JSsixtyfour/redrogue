GetMachinePrice::
; Input:  [wCurItem] = Item ID of an HM or TM
; Output: Stores the machine's price at hItemPrice (3-byte BCD)
; Each machine carries a price tier (a nybble in TechnicalMachinePrices, HMs
; first); the tier's price is a BCD-thousands byte in TMPriceTierTable. HMs
; used to be a fixed Y3000 here; they are priced by tier like the TMs now.
	ld a, [wCurItem]
	sub HM01
	ld d, a
	ld hl, TechnicalMachinePrices
	srl a
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl] ; the byte whose high or low nybble is this machine's tier
	srl d
	jr c, .lowNybbleIsTier ; odd index: low nybble
	swap a
.lowNybbleIsTier
	and $0f
	ld c, a ; b is still 0
	ld hl, TMPriceTierTable
	add hl, bc
	ld a, [hl] ; BCD thousands, $TU = Y TU,000
	ld b, a
	swap a
	and $0f
	ldh [hItemPrice], a ; ten-thousands digit
	ld a, b
	swap a
	and $f0
	ldh [hItemPrice + 1], a ; thousands digit, hundreds 0
	xor a
	ldh [hItemPrice + 2], a
	ret

INCLUDE "data/items/tm_prices.asm"
