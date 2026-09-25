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
; Two lobby-fix changes against the code that was moved (identical in both):
;   - Growth gate: a mon picked up before ANY battle since drop-off does not
;     grow. Every stage kind advances wBattleCount (routes, gyms, and wild areas
;     via procedural_stage_hooks.asm's .addExitBattles), so "no battles" means
;     "has not been through another map". The level used to jump straight to the
;     lobby tier the moment it was deposited, for $0.
;   - Price rounds UP to the next round: $500 per started block of 10 battles,
;     $0 only when no battles have passed. With the old floor, one route (5
;     battles) grew the mon and still cost nothing.
; scripts/Daycare.asm carries the same two changes for the vanilla daycare map.

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
	; below, AFTER wDayCareStartLevel2 is written: .leaveMonInDayCare copies that
	; byte back into the box level, so skipping the write would stamp a stale
	; level onto the mon. The three ld's in between leave the flags alone.
	ld a, [wDayCareDepositBattleCount2]
	ld e, a
	ld a, [wBattleCount]
	cp e                        ; Z = no battles since drop-off
	ld hl, wDayCareMon2BoxLevel
	ld a, [hl]
	ld [wDayCareStartLevel2], a
	jr z, .noGrowth
	cp d
	jr nc, .noGrowth            ; current level (a) >= target (d): never lower a deposited mon's level
	callfar CalcExperience
	ld hl, wDayCareMon2Exp
	ldh a, [hExperience]
	ld [hli], a
	ldh a, [hExperience + 1]
	ld [hli], a
	ldh a, [hExperience + 2]
	ld [hl], a
	ld hl, wDayCareMon2BoxLevel
	ld [hl], d
	ld a, [wDayCareStartLevel2]  ; display-only: how many levels it gained, no longer used for pricing
	ld b, a
	ld a, d
	sub b
	ld [wDayCareNumLevelsGrown2], a
	ld [wDayCareNumLevelsGrown], a  ; MonHasGrownText is shared with the Gentleman and hardcodes this variable
	ld hl, LobbyDaycareMonHasGrownText
	jr .next
.noGrowth
	ld hl, LobbyDaycareMonNeedsMoreTimeText

.next
	call PrintText
	ld a, [wPartyCount]
	cp PARTY_LENGTH
	ld hl, LobbyDaycareNoRoomForMonText
	jp z, .leaveMonInDayCare
	; price = $500 per round (10 battles) started since deposit, rounded up
	ld a, [wBattleCount]
	ld b, a
	ld a, [wDayCareDepositBattleCount2]
	ld c, a
	ld a, b
	sub c                       ; a = battles fought since deposit
	ld b, 0                     ; b = rounds to charge
	jr z, .stagesElapsedDone    ; no battles: free (and the gate above kept it from growing)
	dec a                       ; round up: 1-10 battles -> 1, 11-20 -> 2, ...
	inc b
.countStagesElapsed
	cp 10
	jr c, .stagesElapsedDone
	sub 10
	inc b
	jr .countStagesElapsed
.stagesElapsedDone
	ld de, wDayCareTotalCost2
	xor a
	ld [de], a
	inc de
	ld [de], a
	ld hl, wDayCarePerLevelCost2
	ld a, DAYCARE_PRICE_PER_ROUND_BCD
	ld [hli], a
	ld [hl], $0
	ld a, b                     ; a = rounds to charge (price multiplier; 0 = free)
	and a
	jr z, .noCost
	ld b, a
	ld c, 2
.calcPriceLoop
	push hl
	push de
	push bc
	predef AddBCDPredef
	pop bc
	pop de
	pop hl
	dec b
	jr nz, .calcPriceLoop
.noCost
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
	ld hl, wDayCareTotalCost2
	ldh [hMoney], a
	ld a, [hli]
	ldh [hMoney + 1], a
	ld a, [hl]
	ldh [hMoney + 2], a
	call HasEnoughMoney
	jr nc, .enoughMoney
	ld hl, LobbyDaycareNotEnoughMoneyText
	jp .leaveMonInDayCare

.enoughMoney
	xor a
	ld [wDayCareInUse2], a
	ld hl, wDayCareNumLevelsGrown2
	ld [hli], a
	inc hl
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

	ld hl, LobbyDaycareGotMonBackText
	jr .done

.leaveMonInDayCare
	ld a, [wDayCareStartLevel2]
	ld [wDayCareMon2BoxLevel], a

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
	cp d
	jr nc, .noGrowth            ; current level (a) >= target (d): never lower a deposited mon's level
	callfar CalcExperience
	ld hl, wDayCareMonExp
	ldh a, [hExperience]
	ld [hli], a
	ldh a, [hExperience + 1]
	ld [hli], a
	ldh a, [hExperience + 2]
	ld [hl], a
	ld hl, wDayCareMonBoxLevel
	ld [hl], d
	ld a, [wDayCareStartLevel]  ; display-only: how many levels it gained, no longer used for pricing
	ld b, a
	ld a, d
	sub b
	ld [wDayCareNumLevelsGrown], a
	ld hl, LobbyDaycareMonHasGrownText
	jr .next
.noGrowth
	ld hl, LobbyDaycareMonNeedsMoreTimeText

.next
	call PrintText
	ld a, [wPartyCount]
	cp PARTY_LENGTH
	ld hl, LobbyDaycareNoRoomForMonText
	jp z, .leaveMonInDayCare
	; price = $500 per round (10 battles) started since deposit, rounded up
	ld a, [wBattleCount]
	ld b, a
	ld a, [wDayCareDepositBattleCount]
	ld c, a
	ld a, b
	sub c                       ; a = battles fought since deposit
	ld b, 0                     ; b = rounds to charge
	jr z, .stagesElapsedDone    ; no battles: free (and the gate above kept it from growing)
	dec a                       ; round up: 1-10 battles -> 1, 11-20 -> 2, ...
	inc b
.countStagesElapsed
	cp 10
	jr c, .stagesElapsedDone
	sub 10
	inc b
	jr .countStagesElapsed
.stagesElapsedDone
	ld de, wDayCareTotalCost
	xor a
	ld [de], a
	inc de
	ld [de], a
	ld hl, wDayCarePerLevelCost
	ld a, DAYCARE_PRICE_PER_ROUND_BCD
	ld [hli], a
	ld [hl], $0
	ld a, b                     ; a = rounds to charge (price multiplier; 0 = free)
	and a
	jr z, .noCost
	ld b, a
	ld c, 2
.calcPriceLoop
	push hl
	push de
	push bc
	predef AddBCDPredef
	pop bc
	pop de
	pop hl
	dec b
	jr nz, .calcPriceLoop
.noCost
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
	ldh [hMoney], a
	ld a, [hli]
	ldh [hMoney + 1], a
	ld a, [hl]
	ldh [hMoney + 2], a
	call HasEnoughMoney
	jr nc, .enoughMoney
	ld hl, LobbyDaycareNotEnoughMoneyText
	jp .leaveMonInDayCare

.enoughMoney
	xor a
	ld [wDayCareInUse], a
	ld hl, wDayCareNumLevelsGrown
	ld [hli], a
	inc hl
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

.leaveMonInDayCare
	ld a, [wDayCareStartLevel]
	ld [wDayCareMonBoxLevel], a

.done
	jp PrintText

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
