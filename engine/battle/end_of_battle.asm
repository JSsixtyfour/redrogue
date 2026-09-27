EndOfBattle:
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	jr nz, .notLinkBattle
; link battle
	ld a, [wEnemyMonPartyPos]
	ld hl, wEnemyMon1Status
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld a, [wEnemyMonStatus]
	ld [hl], a
	call ClearScreen
	callfar DisplayLinkBattleVersusTextBox
	ld a, [wBattleResult]
	cp $1
	ld de, YouWinText
	jr c, .placeWinOrLoseString
	ld de, YouLoseText
	jr z, .placeWinOrLoseString
	ld de, DrawText
.placeWinOrLoseString
	hlcoord 6, 8
	call PlaceString
	ld c, 200
	call DelayFrames
	jr .evolution
.notLinkBattle
	ld a, [wBattleResult]
	and a
	jr nz, .resetVariables
	ld hl, wTotalPayDayMoney
	ld a, [hli]
	or [hl]
	inc hl
	or [hl]
	jr z, .evolution ; if pay day money is 0, jump
	ld de, wPlayerMoney + 2
	ld c, $3
	predef AddBCDPredef
	ld hl, PickUpPayDayMoneyText
	call PrintText
.evolution
	farcall IronmanClearFaintedEvolveFlags ; Ironman only: fainted mons don't evolve
	xor a
	ld [wForceEvolution], a
	predef EvolutionAfterBattle
.resetVariables
	ld a, [wBattleResult]
	and a
	jr nz, .noPPTonic ; don't restore HP/PP from a battle the player lost (or drew)
	; Ironman: release every mon still at 0 HP. Skipped on a loss, like the
	; recovery below: a loss is a blackout (the run reset wipes the party) or
	; the losable Oak's Lab rival fight, which must keep its only mon.
	farcall IronmanReleaseFaintedMons
	ld a, LEFTOVERS
	ld [wCurItem], a
	farcall IsKeyItemActive     ; NZ = active (in bag)
	jr z, .checkPPTonic
	farcall LeftoversRecovery
	ld a, PP_TONIC
	ld [wCurItem], a
	farcall IsKeyItemActive
	jr z, .hpOnlyMsg
	farcall PPTonicRecovery
	ld hl, PartyHPAndPPRecoveredText
	call PrintText
	jr .noPPTonic
.hpOnlyMsg
	ld hl, PartyHPRecoveredText
	call PrintText
	jr .noPPTonic
.checkPPTonic
	ld a, PP_TONIC
	ld [wCurItem], a
	farcall IsKeyItemActive
	jr z, .noPPTonic
	farcall PPTonicRecovery
	ld hl, PartyPPRecoveredText
	call PrintText
.noPPTonic
	xor a
	ld [wLowHealthAlarm], a ;disable low health alarm
	ld [wChannelSoundIDs + CHAN5], a
	ldh [hIsInBattle], a
	ld [wBattleType], a
	ld [wMoveMissed], a
	ld [wCurOpponent], a
	ld [wForcePlayerToChooseMon], a
	ld [wNumRunAttempts], a
	ld [wEscapedFromBattle], a
	ld hl, wPartyAndBillsPCSavedMenuItem
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	ld [wListScrollOffset], a
	ld hl, wBattleStatusData
	ld b, wBattleStatusDataEnd - wBattleStatusData
.loop
	ld [hli], a
	dec b
	jr nz, .loop
	ld hl, wStatusFlags2
	set BIT_WILD_ENCOUNTER_COOLDOWN, [hl]
	call WaitForSoundToFinish
	call GBPalWhiteOut
	ld a, $ff
	ld [wDestinationWarpID], a
	ret

YouWinText:
	db "YOU WIN@"

YouLoseText:
	db "YOU LOSE@"

DrawText:
	db "  DRAW@"

PickUpPayDayMoneyText:
	text_far _PickUpPayDayMoneyText
	text_end

PartyHPRecoveredText:
	text_far _PartyHPRecoveredText
	text_end

PartyPPRecoveredText:
	text_far _PartyPPRecoveredText
	text_end

PartyHPAndPPRecoveredText:
	text_far _PartyHPAndPPRecoveredText
	text_end
