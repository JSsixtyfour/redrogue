; engine/events/lobby_daycare.asm
;
; The two Indigo Plateau lobby daycare NPCs (the lady holds slot 2, the
; gentleman slot 1). Moved out of scripts/IndigoPlateauLobby.asm on 2026-09-25:
; that file's floating "Maps 2" section sat in bank $06 with 13 bytes free, and
; the lobby fixes needed room there. Bank $06 keeps only a text_asm stub per NPC
; that farcalls in here and then `jp TextScriptEnd`s.
;
; Everything these routines call is HOME or reached by farcall/callfar/predef,
; and their text_far stubs live below in this same section, so PrintText finds
; them in the bank that is loaded while this code runs.
;
; Growth is reported when you talk to them but only written to the stored mon
; when it actually leaves (.enoughMoney). Writing it up front and undoing just
; the level on the stay-behind paths left the new exp behind, and withdrawal
; recomputes level from exp, so the mon later came back grown for free.
;
; Two lobby-fix changes against the code that was moved (identical in both):
;   - Growth gate: a mon picked up before ANY battle since drop-off does not
;     grow. Every stage kind advances wBattleCount (routes, gyms, and wild areas
;     via procedural_stage_hooks.asm's .addExitBattles), so "no battles" means
;     "has not been through another map". The level used to jump straight to the
;     lobby tier the moment it was deposited, for $0.
;   - Pickup costs DAYCARE_PRICE_PER_LEVEL per level actually gained.
; scripts/Daycare.asm uses the same growth gate and fee.

LobbyDaycareLady::
	call SaveScreenTilesToBuffer2
	ld a, [wDayCareInUse2]
	and a
	jp nz, .daycareInUse
	ld hl, LobbyDaycareIntroText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ld hl, LobbyDaycareComeAgainText
	jp nz, .done
	ld a, [wPartyCount]
	dec a
	ld hl, LobbyDaycareOnlyHaveOneMonText
	jp z, .done
	ld hl, LobbyDaycareWhichMonText
	call PrintText
	xor a
	ldh [hUpdateSpritesEnabled], a
	ld [wPartyMenuTypeOrMessageID], a
	ld [wMenuItemToSwap], a
	call DisplayPartyMenu
	push af
	call GBPalWhiteOutWithDelay3
	call RestoreScreenTilesAndReloadTilePatterns
	call LoadGBPal
	pop af
	ld hl, LobbyDaycareAllRightThenText
	jp c, .done
	xor a
	ld [wPartyAndBillsPCSavedMenuItem], a
	ldh a, [hWhichPokemon]
	ld hl, wPartyMonNicks
	call GetPartyMonName
	ld hl, LobbyDaycareWillLookAfterMonText
	call PrintText
	ld a, 1
	ld [wDayCareInUse2], a
	ld a, [wBattleCount]
	ld [wDayCareDepositBattleCount2], a
	ld a, PARTY_TO_DAYCARE2
	ld [wMoveMonType], a
	call MoveMon
	xor a
	ld [wRemoveMonFromBox], a
	call RemovePokemon
	ld a, [wCurPartySpecies]
	call PlayCry
	ld hl, LobbyDaycareComeSeeMeInAWhileText
	jp .done

.daycareInUse
	xor a
	ld hl, wDayCareMonName2
	call GetPartyMonName
	ld a, DAYCARE_DATA2
	ld [wMonDataLocation], a
	call LoadMonData            ; populates wCurPartySpecies, needed for CalcExperience below
	; GetRewardMonLevel's "return in a" does NOT survive a farcall: Bankswitch's
	; return path ends `pop bc / ld a, b`, which leaves a holding the CALLER's
	; bank number. This read used to be `ld d, a` and so grew every deposited mon
	; to level 6 (this script's bank) instead of the tier level. Read the value
	; the routine actually publishes instead.
	farcall GetRewardMonLevel   ; sets wCurEnemyLevel = current tier level
	ld a, [wCurEnemyLevel]
	ld d, a
	; Growth gate (see the file header). Z from this cp has to reach the jr
	; below, AFTER wDayCareStartLevel2 is written: the retrieval commit and
	; DaycareRetrieveUpgrade both read that byte as the deposit level. The three
	; ld's in between leave the flags alone.
	ld a, [wDayCareDepositBattleCount2]
	ld e, a
	ld a, [wBattleCount]
	cp e                        ; Z = no battles since drop-off
	ld hl, wDayCareMon2BoxLevel
	ld a, [hl]
	ld [wDayCareStartLevel2], a
	jr z, .noGrowth
	cp MAX_LEVEL
	jr nc, .noGrowth
	cp d
	jr c, .reportGrowth
	ld d, a
	inc d                      ; progress guarantees one level even above the reward tier
.reportGrowth
	; Only REPORT the growth here. The stored mon is not touched until it really
	; leaves (.enoughMoney): every path that keeps it here (full party, declined,
	; can't pay) used to restore the old level but keep the new exp, and the
	; withdrawal recomputes level from exp, so it came back grown for free later.
	ld b, a
	ld a, d
	sub b
	ld [wDayCareNumLevelsGrown2], a ; also the deferred-growth amount .enoughMoney commits
	ld [wDayCareNumLevelsGrown], a  ; MonHasGrownText is shared with the Gentleman and hardcodes this variable
	ld hl, LobbyDaycareMonHasGrownText
	jr .next
.noGrowth
	xor a
	ld [wDayCareNumLevelsGrown2], a ; nothing for .enoughMoney to commit
	ld hl, LobbyDaycareMonNeedsMoreTimeText

.next
	call PrintText
	ld a, [wPartyCount]
	cp PARTY_LENGTH
	ld hl, LobbyDaycareNoRoomForMonText
	jp z, .leaveMonInDayCare
	ld a, [wDayCareNumLevelsGrown2]
	ld e, a
	call DaycareQuotePickup
	ld hl, LobbyDaycareOweMoneyText
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ld hl, LobbyDaycareAllRightThenText
	ldh a, [hCurrentMenuItem]
	and a
	jp nz, .leaveMonInDayCare
	ld hl, wDayCareTotalCost
	ld de, hMoney
	ld bc, 3
	call CopyData
	call HasEnoughMoney
	jr nc, .enoughMoney
	ld hl, LobbyDaycareNotEnoughMoneyText
	jp .leaveMonInDayCare

.enoughMoney
	; Commit the growth reported above, now that the mon is really leaving. Has
	; to run before MoveMon, which recomputes level from exp.
	ld a, [wDayCareNumLevelsGrown2]
	and a
	jr z, .growthCommitted
	ld b, a
	ld a, [wDayCareStartLevel2]
	add b
	ld [wDayCareMon2BoxLevel], a
	push af
	ld a, DAYCARE_DATA2
	ld [wMonDataLocation], a
	call LoadMonData            ; reload the header: CalcExperience reads its growth rate
	pop af
	ld d, a
	callfar CalcExperience
	ld hl, wDayCareMon2Exp
	ldh a, [hExperience]
	ld [hli], a
	ldh a, [hExperience + 1]
	ld [hli], a
	ldh a, [hExperience + 2]
	ld [hl], a
.growthCommitted
	xor a
	ld [wDayCareInUse2], a
	ld [wDayCareNumLevelsGrown2], a
	ld hl, wDayCareTotalCost + 2
	ld de, wPlayerMoney + 2
	ld c, $3
	predef SubBCDPredef
	ld a, SFX_PURCHASE
	call PlaySoundWaitForCurrent
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ld hl, LobbyDaycareHeresYourMonText
	call PrintText
	ld a, DAYCARE_TO_PARTY2
	ld [wMoveMonType], a
	call MoveMon
	ld a, [wDayCareMon2Species]
	ld [wCurPartySpecies], a
; Shin Red import Phase 10. The cry moves ahead of everything else so it is the
; mon you handed over that greets you, not whatever it turns into; the upgrade
; pass has to run before the HP-to-max write below, because evolving changes
; MaxHP. The old `predef WriteMonMoves` (which silently shifted the oldest move
; out with no prompt) is gone, and with it the wLearningMovesFromDayCare flag
; this was the only place still setting - it was never cleared here either.
	ld a, [wCurPartySpecies]
	call PlayCry
	ld a, [wDayCareStartLevel2]
	ld [wDayCareStartLevel], a ; the helper reads slot 1's copy for both slots
	farcall DaycareRetrieveUpgrade

; set mon's HP to max
	ld a, [wPartyCount]
	dec a
	ld bc, PARTYMON_STRUCT_LENGTH
	ld hl, wPartyMon1HP
	call AddNTimes
	ld d, h
	ld e, l
	ld bc, MON_MAXHP - MON_HP
	add hl, bc
	ld a, [hli]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a

	ld hl, LobbyDaycareLadyGotMonBackText
	jr .done

.leaveMonInDayCare               ; the stored mon was never modified, nothing to undo
.done
	jp PrintText


LobbyDaycareGentleman::
	call SaveScreenTilesToBuffer2
	ld a, [wDayCareInUse]
	and a
	jp nz, .daycareInUse
	ld hl, LobbyDaycareIntroText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ld hl, LobbyDaycareComeAgainText
	jp nz, .done
	ld a, [wPartyCount]
	dec a
	ld hl, LobbyDaycareOnlyHaveOneMonText
	jp z, .done
	ld hl, LobbyDaycareWhichMonText
	call PrintText
	xor a
	ldh [hUpdateSpritesEnabled], a
	ld [wPartyMenuTypeOrMessageID], a
	ld [wMenuItemToSwap], a
	call DisplayPartyMenu
	push af
	call GBPalWhiteOutWithDelay3
	call RestoreScreenTilesAndReloadTilePatterns
	call LoadGBPal
	pop af
	ld hl, LobbyDaycareAllRightThenText
	jp c, .done
	xor a
	ld [wPartyAndBillsPCSavedMenuItem], a
	ldh a, [hWhichPokemon]
	ld hl, wPartyMonNicks
	call GetPartyMonName
	ld hl, LobbyDaycareWillLookAfterMonText
	call PrintText
	ld a, 1
	ld [wDayCareInUse], a
	ld a, [wBattleCount]
	ld [wDayCareDepositBattleCount], a
	ld a, PARTY_TO_DAYCARE
	ld [wMoveMonType], a
	call MoveMon
	xor a
	ld [wRemoveMonFromBox], a
	call RemovePokemon
	ld a, [wCurPartySpecies]
	call PlayCry
	ld hl, LobbyDaycareComeSeeMeInAWhileText
	jp .done

.daycareInUse
	xor a
	ld hl, wDayCareMonName
	call GetPartyMonName
	ld a, DAYCARE_DATA
	ld [wMonDataLocation], a
	call LoadMonData            ; populates wCurPartySpecies, needed for CalcExperience below
	; See LobbyDaycareLady for why this reads wCurEnemyLevel, not a.
	farcall GetRewardMonLevel   ; sets wCurEnemyLevel = current tier level
	ld a, [wCurEnemyLevel]
	ld d, a
	; Growth gate - see LobbyDaycareLady for why Z must outlive the start-level write.
	ld a, [wDayCareDepositBattleCount]
	ld e, a
	ld a, [wBattleCount]
	cp e                        ; Z = no battles since drop-off
	ld hl, wDayCareMonBoxLevel
	ld a, [hl]
	ld [wDayCareStartLevel], a
	jr z, .noGrowth
	cp MAX_LEVEL
	jr nc, .noGrowth
	cp d
	jr c, .reportGrowth
	ld d, a
	inc d                      ; progress guarantees one level even above the reward tier
.reportGrowth
	; Report only; .enoughMoney commits it (see LobbyDaycareLady).
	ld b, a
	ld a, d
	sub b
	ld [wDayCareNumLevelsGrown], a ; also the deferred-growth amount .enoughMoney commits
	ld hl, LobbyDaycareMonHasGrownText
	jr .next
.noGrowth
	xor a
	ld [wDayCareNumLevelsGrown], a ; nothing for .enoughMoney to commit
	ld hl, LobbyDaycareMonNeedsMoreTimeText

.next
	call PrintText
	ld a, [wPartyCount]
	cp PARTY_LENGTH
	ld hl, LobbyDaycareNoRoomForMonText
	jp z, .leaveMonInDayCare
	ld a, [wDayCareNumLevelsGrown]
	ld e, a
	call DaycareQuotePickup
	ld hl, LobbyDaycareOweMoneyText
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ld hl, LobbyDaycareAllRightThenText
	ldh a, [hCurrentMenuItem]
	and a
	jp nz, .leaveMonInDayCare
	ld hl, wDayCareTotalCost
	ld de, hMoney
	ld bc, 3
	call CopyData
	call HasEnoughMoney
	jr nc, .enoughMoney
	ld hl, LobbyDaycareNotEnoughMoneyText
	jp .leaveMonInDayCare

.enoughMoney
	; Commit the reported growth; see LobbyDaycareLady for the ordering.
	ld a, [wDayCareNumLevelsGrown]
	and a
	jr z, .growthCommitted
	ld b, a
	ld a, [wDayCareStartLevel]
	add b
	ld [wDayCareMonBoxLevel], a
	push af
	ld a, DAYCARE_DATA
	ld [wMonDataLocation], a
	call LoadMonData            ; reload the header: CalcExperience reads its growth rate
	pop af
	ld d, a
	callfar CalcExperience
	ld hl, wDayCareMonExp
	ldh a, [hExperience]
	ld [hli], a
	ldh a, [hExperience + 1]
	ld [hli], a
	ldh a, [hExperience + 2]
	ld [hl], a
.growthCommitted
	xor a
	ld [wDayCareInUse], a
	ld [wDayCareNumLevelsGrown], a
	ld hl, wDayCareTotalCost + 2
	ld de, wPlayerMoney + 2
	ld c, $3
	predef SubBCDPredef
	ld a, SFX_PURCHASE
	call PlaySoundWaitForCurrent
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ld hl, LobbyDaycareHeresYourMonText
	call PrintText
	ld a, DAYCARE_TO_PARTY
	ld [wMoveMonType], a
	call MoveMon
	ld a, [wDayCareMonSpecies]
	ld [wCurPartySpecies], a
; See LobbyDaycareLady for the Shin Red Phase 10 note on this ordering.
	ld a, [wCurPartySpecies]
	call PlayCry
	farcall DaycareRetrieveUpgrade

; set mon's HP to max
	ld a, [wPartyCount]
	dec a
	ld bc, PARTYMON_STRUCT_LENGTH
	ld hl, wPartyMon1HP
	call AddNTimes
	ld d, h
	ld e, l
	ld bc, MON_MAXHP - MON_HP
	add hl, bc
	ld a, [hli]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a

	ld hl, LobbyDaycareGotMonBackText
	jr .done

.leaveMonInDayCare               ; the stored mon was never modified, nothing to undo
.done
	jp PrintText

; e = quoted levels. Keep the three-byte price in existing menu scratch
; across the text and confirmation prompt. Both daycare slots alias this area.
DaycareQuotePickup::
	ASSERT wDayCareTotalCost == wDayCareTotalCost2
	ASSERT wDayCareTotalCost + 2 == wDayCarePerLevelCost
	call DaycareQuoteGrowth
	ld hl, hMoney
	ld de, wDayCareTotalCost
	ld bc, 3
	jp CopyData

; e = levels gained. Returns the three-byte BCD fee in hMoney.
DaycareQuoteGrowth::
	xor a
	ldh [hMoney], a
	ldh [hMoney + 1], a
	ldh [hMoney + 2], a
	ld a, e
	and a
	ret z
	push de
	ld hl, .unitPrice
	ld de, hItemPrice
	ld bc, 3
	call CopyData
	pop bc
	ld b, c
.priceLoop
	push bc
	ld hl, hItemPrice + 2
	ld de, hMoney + 2
	ld c, 3
	predef AddBCDPredef
	pop bc
	dec b
	jr nz, .priceLoop
	ret

.unitPrice
	bcd3 DAYCARE_PRICE_PER_LEVEL

LobbyDaycareIntroText:
	text_far _DaycareGentlemanIntroText
	text_end

LobbyDaycareWhichMonText:
	text_far _DaycareGentlemanWhichMonText
	text_end

LobbyDaycareWillLookAfterMonText:
	text_far _DaycareGentlemanWillLookAfterMonText
	text_end

LobbyDaycareComeSeeMeInAWhileText:
	text_far _DaycareGentlemanComeSeeMeInAWhileText
	text_end

LobbyDaycareMonHasGrownText:
	text_far _DaycareGentlemanMonHasGrownText
	text_end

LobbyDaycareOweMoneyText:
	text_far _DaycareGentlemanOweMoneyText
	text_end

LobbyDaycareGotMonBackText:
	text_far _DaycareGentlemanGotMonBackText
	text_end

LobbyDaycareLadyGotMonBackText:
	text_far _DaycareLadyGotMonBackText
	text_end

LobbyDaycareMonNeedsMoreTimeText:
	text_far _DaycareGentlemanMonNeedsMoreTimeText
	text_end

LobbyDaycareAllRightThenText:
	text_far _DaycareGentlemanAllRightThenText
LobbyDaycareComeAgainText:
	text_far _DaycareGentlemanComeAgainText
	text_end

LobbyDaycareNoRoomForMonText:
	text_far _DaycareGentlemanNoRoomForMonText
	text_end

LobbyDaycareOnlyHaveOneMonText:
	text_far _DaycareGentlemanOnlyHaveOneMonText
	text_end

LobbyDaycareHeresYourMonText:
	text_far _DaycareGentlemanHeresYourMonText
	text_end

LobbyDaycareNotEnoughMoneyText:
	text_far _DaycareGentlemanNotEnoughMoneyText
	text_end
