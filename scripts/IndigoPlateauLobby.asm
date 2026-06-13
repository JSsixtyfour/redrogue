IndigoPlateauLobby_Script:
	; force facing up on entry only, regardless of which warp brought the player here
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	jr z, .skipFaceUp
	ld a, SPRITE_FACING_UP
	ld [wSpritePlayerStateData1FacingDirection], a
.skipFaceUp
	call EnableAutoTextBoxDrawing
    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal

    SetEvent EVENT_ENTER_ROOM
	; Pick the next random stage on map entry and patch the exit warp.
	; Uses SelectAndPatchLobbyExit (no BIT_WARP_FROM_CUR_SCRIPT — that flag
	; would cause an immediate warp before the player could do anything).
	farcall SelectAndPatchLobbyExit
	ld c, TRADE_FOR_RANDOM
	ld b, FLAG_RESET
    ld hl, wCompletedInGameTradeFlags
	predef FlagActionPredef
    ResetEvent EVENT_BOUGHT_POKEMON
    call PCTraderSuperNerdSetup
    call PCPokemonSalesmanSetup
    call PCClerksSetup
    
    .normal
    ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_2, [hl]
	res BIT_CUR_MAP_LOADED_2, [hl]
	ret z
	;ResetEvent EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH
	; Reset Elite Four events if the player started challenging them before
	;ld hl, wElite4Flags
	;bit BIT_STARTED_ELITE_4, [hl]
	;res BIT_STARTED_ELITE_4, [hl]
	;ret z
	;ResetEventRange INDIGO_PLATEAU_EVENTS_START, EVENT_LANCES_ROOM_LOCK_DOOR
	ret

IndigoPlateauLobby_TextPointers:
	def_text_pointers
	dw_const IndigoPlateauLobbyNurseText,            TEXT_PC_NURSE
    dw_const PCClerkText1,                           TEXT_PC_CLERK1
    dw_const PCClerkText2,                           TEXT_PC_CLERK2
    dw_const PCDaycareGentlemanText,                 TEXT_PC_DAYCARE_GENTLEMAN
    dw_const PCDaycareLadyText,                 TEXT_PC_DAYCARE_LADY
    dw_const MoveRelearnerText1,                     TEXT_PC_MOVE_RELEARNER
    dw_const IndigoPlateauLobbyGymGuideText,         TEXT_PC_PSYCHIC
	dw_const PCWitchText,                            TEXT_PC_WITCH
	dw_const PCPokemonSalesmanText,                  TEXT_PC_POKEMON_SALESMAN
    dw_const PCTraderSuperNerdText,                  TEXT_PC_TRADER_SUPER_NERD
    dw_const PCMoveTutorText,                        TEXT_PC_MOVE_TUTOR
	dw_const LobbyDoor1SignText,                     TEXT_PC_DOOR1_SIGN
	dw_const LobbyDoor2SignText,                     TEXT_PC_DOOR2_SIGN

LobbyDoor1SignText:
	text_asm
	ld a, [wRogueDoor1]
	ld hl, .itemPtrs
	ld d, 0
	ld e, a
	add hl, de
	add hl, de          ; hl += 2 * class (each entry is a dw)
	ld a, [hli]
	ld h, [hl]
	ld l, a
	call PrintText
	jp TextScriptEnd
.itemPtrs
	dw .healingText
	dw .statText
	dw .tmText
	dw .moneyText
.healingText
	text "DOOR 1:"
	line "HEALING ITEMS@"
	text_end
.statText
	text "DOOR 1:"
	line "STAT BOOSTS@"
	text_end
.tmText
	text "DOOR 1:"
	line "TM ITEMS@"
	text_end
.moneyText
	text "DOOR 1:"
	line "MONEY@"
	text_end

LobbyDoor2SignText:
	text_asm
	ld a, [wRogueDoor2]
	ld hl, .itemPtrs
	ld d, 0
	ld e, a
	add hl, de
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	call PrintText
	jp TextScriptEnd
.itemPtrs
	dw .healingText
	dw .statText
	dw .tmText
	dw .moneyText
.healingText
	text "DOOR 2:"
	line "HEALING ITEMS@"
	text_end
.statText
	text "DOOR 2:"
	line "STAT BOOSTS@"
	text_end
.tmText
	text "DOOR 2:"
	line "TM ITEMS@"
	text_end
.moneyText
	text "DOOR 2:"
	line "MONEY@"
	text_end

IndigoPlateauLobbyNurseText:
	script_pokecenter_nurse

IndigoPlateauLobbyGymGuideText:
	text_far _IndigoPlateauLobbyGymGuideText
	text_end

YesNoScript:
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ret

PCWitchText:
	text_asm
	call SaveScreenTilesToBuffer2
	ld hl, .WitchIntroText
	call YesNoScript
	jr nz, .refuse
	ld hl, .Challenge
	call YesNoScript
	jr nz, .refuse
	ld hl, .Accept
	call PrintText
    call GBFadeOutToBlack
    ld a, TOGGLE_PC_WITCH
    ld [wToggleableObjectIndex], a
    predef HideObject
    call UpdateSprites
    call Delay3
    call GBFadeInFromBlack
	jp TextScriptEnd
.refuse
	ld hl, .Refusal
    call PrintText
	jp TextScriptEnd

.WitchIntroText:
	text_far _WitchIntroText
	text_end

.Challenge:
	text_far _WitchChallengeText
	text_end

.Accept:
	text_far _WitchAcceptanceText
	text_end

.Refusal:
	text_far _WitchRefusalText
	text_end

IndigoPlateauLobbyLinkReceptionistText:
	script_cable_club_receptionist

PCDaycareLadyText:
	text_asm
	call SaveScreenTilesToBuffer2
	ld a, [wDayCareInUse2]
	and a
	jp nz, .daycareInUse
	ld hl, IntroText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ld hl, ComeAgainText
	jp nz, .done
	ld a, [wPartyCount]
	dec a
	ld hl, OnlyHaveOneMonText
	jp z, .done
	ld hl, WhichMonText
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
	ld hl, AllRightThenText
	jp c, .done
	;callfar KnowsHMMove
	;ld hl, .CantAcceptMonWithHMText
	;jp c, .done
	xor a
	ld [wPartyAndBillsPCSavedMenuItem], a
	ldh a, [hWhichPokemon]
	ld hl, wPartyMonNicks
	call GetPartyMonName
	ld hl, WillLookAfterMonText
	call PrintText
	ld a, 1
	ld [wDayCareInUse2], a
	ld a, PARTY_TO_DAYCARE2
	ld [wMoveMonType], a
	call MoveMon
	xor a
	ld [wRemoveMonFromBox], a
	call RemovePokemon
	ld a, [wCurPartySpecies]
	call PlayCry
	ld hl, ComeSeeMeInAWhileText
	jp .done

.daycareInUse
	xor a
	ld hl, wDayCareMonName2
	call GetPartyMonName
	ld a, DAYCARE_DATA2
	ld [wMonDataLocation], a
	call LoadMonData
	callfar CalcLevelFromExperience
	ld a, d
	cp MAX_LEVEL
	jr c, .skipCalcExp

	ld d, MAX_LEVEL
	callfar CalcExperience
	ld hl, wDayCareMon2Exp
	ldh a, [hExperience]
	ld [hli], a
	ldh a, [hExperience + 1]
	ld [hli], a
	ldh a, [hExperience + 2]
	ld [hl], a
	ld d, MAX_LEVEL

.skipCalcExp
	xor a
	ld [wDayCareNumLevelsGrown2], a
	ld hl, wDayCareMon2BoxLevel
	ld a, [hl]
	ld [wDayCareStartLevel2], a
	cp d
	ld [hl], d
	ld hl, MonNeedsMoreTimeText
	jr z, .next
	ld a, [wDayCareStartLevel2]
	ld b, a
	ld a, d
	sub b
	ld [wDayCareNumLevelsGrown2], a
	ld hl, MonHasGrownText

.next
	call PrintText
	ld a, [wPartyCount]
	cp PARTY_LENGTH
	ld hl, NoRoomForMonText
	jp z, .leaveMonInDayCare
	ld de, wDayCareTotalCost
	xor a
	ld [de], a
	inc de
	ld [de], a
	ld hl, wDayCarePerLevelCost2
	ld a, $1
	ld [hli], a
	ld [hl], $0
	ld a, [wDayCareNumLevelsGrown2]
	inc a
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
	ld hl, OweMoneyText
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ld hl, AllRightThenText
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
	ld hl, NotEnoughMoneyText
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
	ld hl, HeresYourMonText
	call PrintText
	ld a, DAYCARE_TO_PARTY2
	ld [wMoveMonType], a
	call MoveMon
	ld a, [wDayCareMon2Species]
	ld [wCurPartySpecies], a
	ld a, [wPartyCount]
	dec a
	push af
	ld bc, PARTYMON_STRUCT_LENGTH
	push bc
	ld hl, wPartyMon1Moves
	call AddNTimes
	ld d, h
	ld e, l
	ld a, 1
	ld [wLearningMovesFromDayCare], a
	predef WriteMonMoves
	pop bc
	pop af

; set mon's HP to max
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

	ld a, [wCurPartySpecies]
	call PlayCry
	ld hl, GotMonBackText
	jr .done

.leaveMonInDayCare
	ld a, [wDayCareStartLevel]
	ld [wDayCareMonBoxLevel], a

.done
	call PrintText
	jp TextScriptEnd


; just needs ram update for woman
; data constants
; experience calc
; second wram location
; update daycare_exp.asm
PCDaycareGentlemanText:
	text_asm
	call SaveScreenTilesToBuffer2
	ld a, [wDayCareInUse]
	and a
	jp nz, .daycareInUse
	ld hl, IntroText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ld hl, ComeAgainText
	jp nz, .done
	ld a, [wPartyCount]
	dec a
	ld hl, OnlyHaveOneMonText
	jp z, .done
	ld hl, WhichMonText
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
	ld hl, AllRightThenText
	jp c, .done
	;callfar KnowsHMMove
	;ld hl, .CantAcceptMonWithHMText
	;jp c, .done
	xor a
	ld [wPartyAndBillsPCSavedMenuItem], a
	ldh a, [hWhichPokemon]
	ld hl, wPartyMonNicks
	call GetPartyMonName
	ld hl, WillLookAfterMonText
	call PrintText
	ld a, 1
	ld [wDayCareInUse], a
	ld a, PARTY_TO_DAYCARE
	ld [wMoveMonType], a
	call MoveMon
	xor a
	ld [wRemoveMonFromBox], a
	call RemovePokemon
	ld a, [wCurPartySpecies]
	call PlayCry
	ld hl, ComeSeeMeInAWhileText
	jp .done

.daycareInUse
	xor a
	ld hl, wDayCareMonName
	call GetPartyMonName
	ld a, DAYCARE_DATA
	ld [wMonDataLocation], a
	call LoadMonData
	callfar CalcLevelFromExperience
	ld a, d
	cp MAX_LEVEL
	jr c, .skipCalcExp

	ld d, MAX_LEVEL
	callfar CalcExperience
	ld hl, wDayCareMonExp
	ldh a, [hExperience]
	ld [hli], a
	ldh a, [hExperience + 1]
	ld [hli], a
	ldh a, [hExperience + 2]
	ld [hl], a
	ld d, MAX_LEVEL

.skipCalcExp
	xor a
	ld [wDayCareNumLevelsGrown], a
	ld hl, wDayCareMonBoxLevel
	ld a, [hl]
	ld [wDayCareStartLevel], a
	cp d
	ld [hl], d
	ld hl, MonNeedsMoreTimeText
	jr z, .next
	ld a, [wDayCareStartLevel]
	ld b, a
	ld a, d
	sub b
	ld [wDayCareNumLevelsGrown], a
	ld hl, MonHasGrownText

.next
	call PrintText
	ld a, [wPartyCount]
	cp PARTY_LENGTH
	ld hl, NoRoomForMonText
	jp z, .leaveMonInDayCare
	ld de, wDayCareTotalCost
	xor a
	ld [de], a
	inc de
	ld [de], a
	ld hl, wDayCarePerLevelCost
	ld a, $1
	ld [hli], a
	ld [hl], $0
	ld a, [wDayCareNumLevelsGrown]
	inc a
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
	ld hl, OweMoneyText
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ld hl, AllRightThenText
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
	ld hl, NotEnoughMoneyText
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
	ld hl, HeresYourMonText
	call PrintText
	ld a, DAYCARE_TO_PARTY
	ld [wMoveMonType], a
	call MoveMon
	ld a, [wDayCareMonSpecies]
	ld [wCurPartySpecies], a
	ld a, [wPartyCount]
	dec a
	push af
	ld bc, PARTYMON_STRUCT_LENGTH
	push bc
	ld hl, wPartyMon1Moves
	call AddNTimes
	ld d, h
	ld e, l
	ld a, 1
	ld [wLearningMovesFromDayCare], a
	predef WriteMonMoves
	pop bc
	pop af

; set mon's HP to max
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

	ld a, [wCurPartySpecies]
	call PlayCry
	ld hl, GotMonBackText
	jr .done

.leaveMonInDayCare
	ld a, [wDayCareStartLevel]
	ld [wDayCareMonBoxLevel], a

.done
	call PrintText
	jp TextScriptEnd

IntroText:
	text_far _DaycareGentlemanIntroText
	text_end

WhichMonText:
	text_far _DaycareGentlemanWhichMonText
	text_end

WillLookAfterMonText:
	text_far _DaycareGentlemanWillLookAfterMonText
	text_end

ComeSeeMeInAWhileText:
	text_far _DaycareGentlemanComeSeeMeInAWhileText
	text_end

MonHasGrownText:
	text_far _DaycareGentlemanMonHasGrownText
	text_end

OweMoneyText:
	text_far _DaycareGentlemanOweMoneyText
	text_end

GotMonBackText:
	text_far _DaycareGentlemanGotMonBackText
	text_end

MonNeedsMoreTimeText:
	text_far _DaycareGentlemanMonNeedsMoreTimeText
	text_end

AllRightThenText:
	text_far _DaycareGentlemanAllRightThenText
ComeAgainText:
	text_far _DaycareGentlemanComeAgainText
	text_end

NoRoomForMonText:
	text_far _DaycareGentlemanNoRoomForMonText
	text_end

OnlyHaveOneMonText:
	text_far _DaycareGentlemanOnlyHaveOneMonText
	text_end

CantAcceptMonWithHMText:
	text_far _DaycareGentlemanCantAcceptMonWithHMText
	text_end

HeresYourMonText:
	text_far _DaycareGentlemanHeresYourMonText
	text_end

NotEnoughMoneyText:
	text_far _DaycareGentlemanNotEnoughMoneyText
	text_end

PCPokemonSalesmanText:
	text_asm
	CheckEvent EVENT_BOUGHT_POKEMON
	jp c, .alreadyBoughtPokemon
    
    ld a, [wroguenpcsell]   ; load pokemon for sale
    ld [wNamedObjectIndex], a   ; place pokemon id in spot for GetMonName
    call GetMonName         ; get name of pokemon to receive
    
    ld a, [wroguenpcclass]
    ld hl, .IGotADealTextPokeball
    ld c, 1
    cp c
    jr z, .print
    inc c       ; greatball class
    ld hl, .IGotADealTextGreatball
    ld b, $30
    cp c
    jr z, .print
	ld hl, .IGotADealTextUltraball
    .print
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jp nz, .choseNo
	ldh [hMoney], a
	ldh [hMoney + 2], a
    
    ld a, [wroguenpcclass]
    ld b, $10
    ld c, 1
    cp c
    jr z, .pokemon_cost
    inc c       ; greatball class

    ld b, $30
    cp c
    jr z, .pokemon_cost
    
    ; ultraball class
    ld b, $50
    
    .pokemon_cost
    ld a, b
	ldh [hMoney + 1], a
	call HasEnoughMoney
	jr nc, .enoughMoney
	ld hl, .NoMoneyText
	jr .printText
.enoughMoney
    ld a, [wroguenpcsell]   ; load pokemon for sale
    ld b, a                 ; move pokemon ID to b
	ld c, 5                 ; temporary set level, will need some sort of system
	call GivePokemon
	jr nc, .done
	xor a
	ld [wPriceTemp], a
	ld [wPriceTemp + 2], a
    
    ld a, [wroguenpcclass]
    ld b, $10
    ld c, 1
    cp c
    jr z, .pokemon_cost_2
    inc c       ; greatball class

    ld b, $30
    cp c
    jr z, .pokemon_cost_2
    
    ; ultraball class
    ld b, $50
    
    
	.pokemon_cost_2
    ld a, b
	ld [wPriceTemp + 1], a
	ld hl, wPriceTemp + 2
	ld de, wPlayerMoney + 2
	ld c, $3
	predef SubBCDPredef
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	SetEvent EVENT_BOUGHT_POKEMON
	jr .done
.choseNo
	ld hl, .NoText
	jr .printText
.alreadyBoughtPokemon
	ld hl, .NoRefundsText
.printText
	call PrintText
.done
	jp TextScriptEnd

.IGotADealTextPokeball
	text_far _PCPokemonSalesmanIGotADealPokeballText
	text_end

.IGotADealTextGreatball
	text_far _PCPokemonSalesmanIGotADealGreatballText
	text_end
    
.IGotADealTextUltraball
	text_far _PCPokemonSalesmanIGotADealUltraballText
	text_end

.NoText
	text_far _PCPokemonSalesmanNoText
	text_end

.NoMoneyText
	text_far _PCPokemonSalesmanNoMoneyText
	text_end

.NoRefundsText
	text_far _PCPokemonSalesmanNoRefundsText
	text_end

; need a way to prevent trading for same pokemon or evolution
PCTraderSuperNerdText:
	text_asm
	ld a, TRADE_FOR_RANDOM
	ld [wWhichTrade], a
    predef RogueDoInGameTradeDialogue
	jp TextScriptEnd
    
PCMoveTutorText::
	text_asm
; Display the list of moves to the player.
	ld hl, PCMoveTutorGreetingText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jp nz, .exit
	xor a
	;charge 3000 money
	ld [hMoney], a	
	ld [hMoney + 2], a	
	ld a, $12
	ld [hMoney + 1], a  
	call HasEnoughMoney
	jr nc, .enoughMoney
	; not enough money
	ld hl, PCMoveTutorNotEnoughMoneyText
	call PrintText
	jp TextScriptEnd
.enoughMoney
	ld hl, PCMoveTutorSaidYesText
	call PrintText
	; Select pokemon from party.
	call SaveScreenTilesToBuffer2
	xor a
	ld [wListScrollOffset], a
	ld [wPartyMenuTypeOrMessageID], a
	ldh [hUpdateSpritesEnabled], a
	ld [wMenuItemToSwap], a
	call DisplayPartyMenu
	push af
	call GBPalWhiteOutWithDelay3
	call RestoreScreenTilesAndReloadTilePatterns
	call LoadGBPal
	pop af
	jp c, .exit
	ldh a, [hWhichPokemon]
	ld b, a
	push bc
	ld hl, PrepareMoveTutorList
	ld b, Bank(PrepareMoveTutorList)
	call Bankswitch
	ld a, [wMoveBuffer]
	and a
	jr nz, .chooseMove
	pop bc
	ld hl, PCMoveTutorNoMovesText
	call PrintText
	jp TextScriptEnd
.chooseMove
	ld hl, PCMoveTutorWhichMoveText
	call PrintText
	xor a
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld a, MOVESLISTMENU
	ld [wListMenuID], a
	ld de, wMoveBuffer
	ld hl, wListPointer
	ld [hl], e
	inc hl
	ld [hl], d
	xor a
	ld [wPrintItemPrices], a ; don't print prices
	call DisplayListMenuID
	pop bc
	jr c, .exit  ; exit if player chose cancel
	push bc
	; Save the selected move id.
	ld a, [wCurPartySpecies]
	ld [wMoveNum], a
	ld [wNamedObjectIndex],a
	call GetMoveName
	call CopyToStringBuffer ; copy name to wcf4b
	pop bc
	ld a, b
	ldh [hWhichPokemon], a
	ld a, [wLetterPrintingDelayFlags]
	push af
	xor a
	ld [wLetterPrintingDelayFlags], a
	predef LearnMove
	pop af
	ld [wLetterPrintingDelayFlags], a
	ld a, b
	and a
	jr z, .exit
	; Charge 3000 money
	xor a
	ld [wPriceTemp], a
	ld [wPriceTemp + 2], a	
	ld a, $12               ; there is predef list of the sales price of items that can be used to easily subtract, this is for Full Restore, which is 3000
	ld [wPriceTemp + 1], a	
	ld hl, wPriceTemp + 2
	ld de, wPlayerMoney + 2
	ld c, $3
	predef SubBCDPredef
	ld hl, PCMoveTutorByeText
	call PrintText
	jp TextScriptEnd
.exit
	ld hl, PCMoveTutorByeText
	call PrintText
	jp TextScriptEnd


PCMoveTutorGreetingText:
	text_far _PCMoveTutorGreetingText
	text_end

PCMoveTutorSaidYesText:
	text_far _PCMoveTutorSaidYesText
	text_end

PCMoveTutorNotEnoughMoneyText:
	text_far _PCMoveTutorNotEnoughMoneyText
	text_end

PCMoveTutorWhichMoveText:
	text_far _PCMoveTutorWhichMoveText
	text_end

PCMoveTutorByeText:
	text_far _PCMoveTutorByeText
	text_end

PCMoveTutorNoMovesText:
	text_far _PCMoveTutorNoMovesText
	text_end
    
DEF pokeball_pokemon_line_number EQU 28
DEF pokeball_pokemon_number EQU 28 + 26 + 6
DEF greatball_pokemon_line_number EQU pokeball_pokemon_line_number + 28
DEF greatball_pokemon_number EQU pokeball_pokemon_number + 28 + 25 + 8
DEF ultraball_pokemon_line_number EQU greatball_pokemon_line_number+ 16
DEF ultraball_pokemon_number EQU greatball_pokemon_number + 16 + 3 + 2
DEF masterball_pokemon_line_number EQU ultraball_pokemon_line_number + 5
DEF masterball_pokemon_number EQU ultraball_pokemon_number + 5 + 2
    
PCTraderSuperNerdSetup:
    ld b, 0
    ld c, 0
    ld hl, wPartySpecies
    push hl
    
    .loop
    pop hl
    ld a, [hli]
    push hl
	cp $ff
	jr z, .box
    
    inc c
    ld hl, wAllSpecies - 1
    add hl, bc
    ld [hl], a ; load mon into allspecies
    jr .loop
    
    .box ;
    pop hl
    ld hl, wBoxSpecies
    push hl
    
    .loop2
    pop hl
    ld a, [hli]
    push hl
	cp $ff
	jr z, .randomselect
    
    inc c
    ld hl, wAllSpecies - 1
    add hl, bc
    ld [hl], a ; load mon into allspecies
    jr .loop2
    
    
	.randomselect
    call Rangerandom
    ld c, a     ; place random number in c
    ld hl, wAllSpecies
    add hl, bc
    ld a, [hl]    ; get the pokemon the trader wants
    ld [wroguenpctradegive], a
    
    ; begin finding pokemon that you get
    ld d, a ; place giving pokemon in d
    ld hl, pokemon_classes ; list of all pokemon
    ld e, 0
    
    .loopclass
    inc e    ; keep adding to get how far down the list we
    ld a, [hli] ; load pokemon
    cp d     ; see if we found the pokemon the trader wants from player
    jr nz, .loopclass   ; loop back until we find the pokemon
    
    ld a, pokeball_pokemon_number
    ld c, 1 ; auto pokeball class
    cp e ; see if pokeball class
    jr nc, .get_pokemon
    
    ld a, greatball_pokemon_number
    inc c
    cp e ; see if pokeball class
    jr nc, .get_pokemon
    
    inc c
    ld a, ultraball_pokemon_number
    cp e ; see if pokeball class
    jr nc, .get_pokemon
    inc c
    ; if we're here, it's masterball class
    ; will need to make some exception for mew and mewtwo UPDATE
    .get_pokemon
    call Random_Pokemon_Selection
    ld a, d
    ld [wroguenpctradeget], a ; load in pokemon that they will give player
    ld [wNamedObjectIndex], a   ; place pokemon id in spot for GetMonName
    call GetMonName         ; get name of pokemon to receive
    ld hl, wNameBuffer      ; name address
    ld de, wroguenpctradename   ; load name into this location
    ld bc, NAME_LENGTH      ; name length
    call CopyData           ; copy name to location
    ; could make a list of random names to choose from
    pop hl
    ret 
    
    DEF salesman_pokeball_odds EQU $99
    DEF salesman_greatball_odds EQU $99 + $5E
    DEF salesman_ultraball_odds EQU $8 + $5E + $99

PCPokemonSalesmanSetup:
    call Random
    ld b, a     ; move random number to b
    ld c, 1     ; auto pokeball class
    ld hl, wroguenpcclass
    
    .determineClassSlot
    ld a, salesman_pokeball_odds
    ld [hl], c
    cp b
    jr nc, .get_pokemon
    inc c       ; greatball class
    ld [hl], c
    ld a, salesman_greatball_odds
    cp b
    jr nc, .get_pokemon
    inc c       ; ultraball class
    ld [hl], c
    
    .get_pokemon
    call Random_Pokemon_Selection
    ld a, d
    ld [wroguenpcsell], a ; load in pokemon that they will give player
    
    
    ld [wNamedObjectIndex], a   ; place pokemon id in spot for GetMonName
    call GetMonName         ; get name of pokemon to receive
    ld hl, wNameBuffer      ; name address
    ld de, wroguenpctradename   ; load name into this location
    ld bc, NAME_LENGTH      ; name length
    call CopyData           ; copy name to location
    ; could make a list of random names to choose from
    
    ret 
    
    PCClerksSetup:
    ld  hl, PCClerkText1    ; begining of address used for generating marts
    ld  a, TX_SCRIPT_MART
    ld [hli], a
    ld [hl], $A       ; Amount of items
    
    ld hl, PCClerkText1Items    ; ram address to save ids to
    call Random_Healing_Mart_Selection
    
    ld hl, PCClerkText2    ; begining of address used for generating marts
    ld  a, TX_SCRIPT_MART
    ld [hli], a
    ld [hl], $A       ; Amount of items
    
    ld hl, PCClerkText2Items    ; ram address to save ids to
    call Random_StatTM_Mart_Selection
    ret