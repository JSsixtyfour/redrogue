ResetStatusAndHalveMoneyOnBlackout::
; Reset player status on blackout.
	xor a
	ld [wBattleResult], a
	ld [wWalkBikeSurfState], a
	ldh [hIsInBattle], a
	ld [wMapPalOffset], a
	ld [wNPCMovementScriptFunctionNum], a
	ldh [hJoyHeld], a
	ld [wNPCMovementScriptPointerTableNum], a
	ld [wMiscFlags], a

	ldh [hMoney], a
	ldh [hMoney + 1], a
	ldh [hMoney + 2], a
	call HasEnoughMoney
	jr c, .lostmoney ; never happens

	; Halve the player's money.
	ld a, [wPlayerMoney]
	ldh [hMoney], a
	ld a, [wPlayerMoney + 1]
	ldh [hMoney + 1], a
	ld a, [wPlayerMoney + 2]
	ldh [hMoney + 2], a
	xor a
	ldh [hDivideBCDDivisor], a
	ldh [hDivideBCDDivisor + 1], a
	ld a, 2
	ldh [hDivideBCDDivisor + 2], a
	predef DivideBCDPredef3
	ldh a, [hDivideBCDQuotient]
	ld [wPlayerMoney], a
	ldh a, [hDivideBCDQuotient + 1]
	ld [wPlayerMoney + 1], a
	ldh a, [hDivideBCDQuotient + 2]
	ld [wPlayerMoney + 2], a

.lostmoney
	ld hl, wStatusFlags6
	set BIT_FLY_OR_DUNGEON_WARP, [hl]
	res BIT_FLY_WARP, [hl]
	set BIT_ESCAPE_WARP, [hl]
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	; a blackout is the run boundary for credits: refill the Credit Exchange
	; slot pulls and re-derive KO Defiance charges from their SRAM tier
	farcall RogueOnBlackout
	predef_jump HealParty
