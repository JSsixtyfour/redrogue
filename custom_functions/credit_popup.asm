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
; RogueResetRunState - the single end-of-run wipe.
;
; Called from RogueOnBlackout (below) and, by farcall, from
; HallOfFameResetEventsAndSaveScript (scripts/HallOfFame.asm). Those are the
; only two places a run ends, and this is the only thing that ends one.
;
; The event half is one ResetEventRange over ZONE 1 of
; constants/event_constants.asm - every stage/gym/Elite 4 trainer bit, every
; auto-walk "no turning back" flag, the reward/offer flags, the procedural
; stage flags and EVENT_VICTORY_ROAD_CLEARED. That file byte-aligns both ends
; of the range (asserted there), so the macro emits plain `ld [hli], a` stores
; and cannot clip a neighbouring zone.
;
; ZONE 0 is deliberately NOT touched: the ELEMENT PRISM one-time-ever grant
; messages live there, and never being cleared IS their mechanism. ZONE 2 is
; the unreachable-map graveyard and has nothing to reset.
;
; Badges and the visited-stage bitfield go with them. Before this existed
; neither was ever cleared, so a blackout kept your gym progress and its
; already-beaten trainer bits while the run notionally restarted.
; ============================================================
RogueResetRunState::
	ResetEventRange RUN_EVENTS_START, RUN_EVENTS_END
	xor a
	ld [wObtainedBadges], a        ; gym progress restarts with the run
	ld hl, wVisitedStagesBitfield  ; ds 4: stage N visited this run
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	; Witch run state. wEarnedStatBoosts and wWitchPrizesEarned are packed
	; multi-bit byte fields, not event flags, so they are cleared by hand here
	; rather than folded into the range above.
	ld [wEarnedStatBoosts], a
	ld [wWitchPrizesEarned], a
	ld [wWitchPrizesEarned + 1], a
	ld hl, wRogueFlagsBitfield
	res BIT_WITCH_ACCEPTED, [hl]   ; an accepted challenge does not survive
	ret

; ============================================================
; RogueOnBlackout — farcalled from ResetStatusAndHalveMoneyOnBlackout.
; A blackout is the run boundary for credit purposes, so this refills the
; Credit Exchange slot pulls, re-derives KO Defiance charges from its SRAM
; upgrade tier (sKeyItemTiers is the source of truth; wKODefianceUsages is a
; derived cache), and refills the three dice items' charges the same way
; (see KEY_ITEM_EFFECTS_PLAN_PC.md).
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

	; A blackout ends the run. Everything run-scoped is cleared in one place.
	call RogueResetRunState

	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a       ; select bank 1 explicitly; ambient bank is unreliable
	ld a, [sKeyItemTiers]
	and %00110000                 ; KO_DEFIANCE is key item index 2 -> bits 4-5
	swap a                        ; %00110000 -> %00000011, i.e. tier 0-3
	inc a                         ; charges = 1 + tier
	ld [wKODefianceUsages], a

	; Dice charges: DOOR_DICE/MON_DICE/ITEM_DICE each refill to 1+tier,
	; packed 2 bits each into wDiceCharges (bits 0-1/2-3/4-5). Charges store
	; REMAINING, unlike the slot-pull bits above which store USED - a fresh/
	; new-game byte reading 0 correctly means "own no dice yet". Read tiers
	; directly from sKeyItemTiers while SRAM is already enabled, same as
	; KO_DEFIANCE above, rather than three farcalls to GetKeyItemPower.
	ld a, [sKeyItemTiers + 2]
	and %11000000                 ; DOOR_DICE is key item index 11 -> bits 6-7
	swap a
	srl a
	srl a                         ; a = tier (0-3)
	inc a                         ; a = charges (1-3), into bits 0-1
	ld b, a

	ld a, [sKeyItemTiers + 3]
	ld c, a                       ; keep byte 3 around for ITEM_DICE below
	and %00000011                 ; MON_DICE is key item index 12 -> bits 0-1
	inc a                         ; charges (1-3)
	sla a
	sla a                         ; shift into bits 2-3
	or b
	ld b, a

	ld a, c
	and %00001100                 ; ITEM_DICE is key item index 13 -> bits 2-3
	srl a
	srl a                         ; a = tier (0-3)
	inc a                         ; a = charges (1-3)
	swap a                        ; shift into bits 4-5
	or b
	ld [wDiceCharges], a

	xor a
	ld [rRAMG], a                 ; leave SRAM disabled, never on a farcall boundary
	ret
