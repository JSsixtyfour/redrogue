; custom_functions/credit_popup.asm
;
; Draws a brief "N credits earned, new total M" box if there are unreported
; credits, then zeroes the tally. No separate "popup pending" flag is needed:
; a nonzero wCreditsEarnedThisRun IS the pending condition, since this routine
; is the only thing that ever clears it.
;
; Deliberately does NOT reset run state (slot pulls, KO Defiance charges) -
; that belongs to RogueOnBlackout below. Tying the reset to the popup would
; skip it whenever the player blacks out having earned zero credits, which is
; exactly the bad early run where it matters most.

RogueCreditPopupCheck::
	ld a, [wCreditsEarnedThisRun]
	and a
	ret z

	hlcoord 1, 1
	lb bc, 18, 4
	predef SaveScreenTileAreaToBuffer3
	hlcoord 1, 1
	ld b, 2
	ld c, 16
	call TextBoxBorder
	hlcoord 2, 2
	ld de, .EarnedText
	call PlaceString
	hlcoord 9, 2
	ld de, wCreditsEarnedThisRun
	lb bc, LEFT_ALIGN | 1, 2
	call PrintNumber
	hlcoord 11, 2
	ld de, .CreditsText
	call PlaceString
	hlcoord 2, 3
	ld de, .TotalText
	call PlaceString
	hlcoord 9, 3
	ld de, wPlayerCoins
	ld c, 2 | LEADING_ZEROES | LEFT_ALIGN
	call PrintBCDNumber
	call UpdateSprites
	ld c, 90
	call DelayFrames

	hlcoord 1, 1
	lb bc, 18, 4
	predef LoadScreenTileAreaFromBuffer3

	xor a
	ld [wCreditsEarnedThisRun], a
	ret

.EarnedText:
	db "EARNED @"
.CreditsText:
	db "CREDITS@"
.TotalText:
	db "TOTAL: @"

; ============================================================
; RogueOnBlackout — farcalled from ResetStatusAndHalveMoneyOnBlackout.
; A blackout is the run boundary for credit purposes, so this refills the
; Credit Exchange slot pulls and re-derives KO Defiance charges from its
; SRAM upgrade tier (sKeyItemTiers is the source of truth; wKODefianceUsages
; is a derived cache).
;
; wRogueFlagsBitfield2 bits 0-1 count pulls USED, not pulls remaining, so the
; all-zero state a new game leaves behind already means "3 available" and
; the refill is just a clear. Storing "remaining" would have given a fresh
; save zero pulls until its first blackout.
; ============================================================
RogueOnBlackout::
	ld hl, wRogueFlagsBitfield2
	res 0, [hl]
	res 1, [hl]

	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, [sKeyItemTiers]
	and %00110000                 ; KO_DEFIANCE is key item index 2 -> bits 4-5
	swap a                        ; %00110000 -> %00000011, i.e. tier 0-3
	push af
	xor a
	ld [rRAMG], a                 ; leave SRAM disabled, never on a farcall boundary
	pop af
	inc a                         ; charges = 1 + tier
	ld [wKODefianceUsages], a
	ret
