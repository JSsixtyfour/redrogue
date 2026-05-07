IndigoPlateauLobby_Script:
	call EnableAutoTextBoxDrawing
	
    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal
    
    SetEvent EVENT_ENTER_ROOM
	ld c, TRADE_FOR_RANDOM
	ld b, FLAG_RESET
    ld hl, wCompletedInGameTradeFlags
	predef FlagActionPredef
    call PCTraderSuperNerdSetup
    ;call PCPokemonSalesmanSetup
    ;call PCClerksSetup
    
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
    dw_const PCDaycareGentlemanText,                 TEXT_PC_DAYCARE_LADY
    dw_const MoveRelearnerText1,                     TEXT_PC_MOVE_RELEARNER
    dw_const IndigoPlateauLobbyGymGuideText,         TEXT_PC_PSYCHIC
	dw_const PCWitchText,                            TEXT_PC_WITCH
	dw_const PCPokemonSalesmanText,                  TEXT_PC_POKEMON_SALESMAN
    dw_const PCTraderSuperNerdText,                  TEXT_PC_TRADER_SUPER_NERD
    dw_const PCMoveTutorText,                        TEXT_PC_MOVE_TUTOR

IndigoPlateauLobbyNurseText:
	script_pokecenter_nurse

IndigoPlateauLobbyGymGuideText:
	text_far _IndigoPlateauLobbyGymGuideText
	text_end

YesNoScript:
	call PrintText
	call YesNoChoice
	ld a, [wCurrentMenuItem]
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

PCDaycareGentlemanText:
	text_asm
	call SaveScreenTilesToBuffer2
	ld a, [wDayCareInUse]
	and a
	jp nz, .daycareInUse
	ld hl, .IntroText
	call PrintText
	call YesNoChoice
	ld a, [wCurrentMenuItem]
	and a
	ld hl, .ComeAgainText
	jp nz, .done
	ld a, [wPartyCount]
	dec a
	ld hl, .OnlyHaveOneMonText
	jp z, .done
	ld hl, .WhichMonText
	call PrintText
	xor a
	ld [wUpdateSpritesEnabled], a
	ld [wPartyMenuTypeOrMessageID], a
	ld [wMenuItemToSwap], a
	call DisplayPartyMenu
	push af
	call GBPalWhiteOutWithDelay3
	call RestoreScreenTilesAndReloadTilePatterns
	call LoadGBPal
	pop af
	ld hl, .AllRightThenText
	jp c, .done
	callfar KnowsHMMove
	ld hl, .CantAcceptMonWithHMText
	jp c, .done
	xor a
	ld [wPartyAndBillsPCSavedMenuItem], a
	ld a, [wWhichPokemon]
	ld hl, wPartyMonNicks
	call GetPartyMonName
	ld hl, .WillLookAfterMonText
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
	ld hl, .ComeSeeMeInAWhileText
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
	ld hl, .MonNeedsMoreTimeText
	jr z, .next
	ld a, [wDayCareStartLevel]
	ld b, a
	ld a, d
	sub b
	ld [wDayCareNumLevelsGrown], a
	ld hl, .MonHasGrownText

.next
	call PrintText
	ld a, [wPartyCount]
	cp PARTY_LENGTH
	ld hl, .NoRoomForMonText
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
	ld hl, .OweMoneyText
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ld hl, .AllRightThenText
	ld a, [wCurrentMenuItem]
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
	ld hl, .NotEnoughMoneyText
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
	ld hl, .HeresYourMonText
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
	ld hl, .GotMonBackText
	jr .done

.leaveMonInDayCare
	ld a, [wDayCareStartLevel]
	ld [wDayCareMonBoxLevel], a

.done
	call PrintText
	jp TextScriptEnd

.IntroText:
	text_far _DaycareGentlemanIntroText
	text_end

.WhichMonText:
	text_far _DaycareGentlemanWhichMonText
	text_end

.WillLookAfterMonText:
	text_far _DaycareGentlemanWillLookAfterMonText
	text_end

.ComeSeeMeInAWhileText:
	text_far _DaycareGentlemanComeSeeMeInAWhileText
	text_end

.MonHasGrownText:
	text_far _DaycareGentlemanMonHasGrownText
	text_end

.OweMoneyText:
	text_far _DaycareGentlemanOweMoneyText
	text_end

.GotMonBackText:
	text_far _DaycareGentlemanGotMonBackText
	text_end

.MonNeedsMoreTimeText:
	text_far _DaycareGentlemanMonNeedsMoreTimeText
	text_end

.AllRightThenText:
	text_far _DaycareGentlemanAllRightThenText
.ComeAgainText:
	text_far _DaycareGentlemanComeAgainText
	text_end

.NoRoomForMonText:
	text_far _DaycareGentlemanNoRoomForMonText
	text_end

.OnlyHaveOneMonText:
	text_far _DaycareGentlemanOnlyHaveOneMonText
	text_end

.CantAcceptMonWithHMText:
	text_far _DaycareGentlemanCantAcceptMonWithHMText
	text_end

.HeresYourMonText:
	text_far _DaycareGentlemanHeresYourMonText
	text_end

.NotEnoughMoneyText:
	text_far _DaycareGentlemanNotEnoughMoneyText
	text_end

PCPokemonSalesmanText:
	text_asm
	CheckEvent EVENT_BOUGHT_POKEMON, 1
	jp c, .alreadyBoughtPokemon
	ld hl, .IGotADealText
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ld a, [wCurrentMenuItem]
	and a
	jp nz, .choseNo
	ldh [hMoney], a
	ldh [hMoney + 2], a
	ld a, $5
	ldh [hMoney + 1], a
	call HasEnoughMoney
	jr nc, .enoughMoney
	ld hl, .NoMoneyText
	jr .printText
.enoughMoney
	lb bc, MAGIKARP, 5
	call GivePokemon
	jr nc, .done
	xor a
	ld [wPriceTemp], a
	ld [wPriceTemp + 2], a
	ld a, $5
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

.IGotADealText
	text_far _MtMoonPokecenterMagikarpSalesmanIGotADealText
	text_end

.NoText
	text_far _MtMoonPokecenterMagikarpSalesmanNoText
	text_end

.NoMoneyText
	text_far _MtMoonPokecenterMagikarpSalesmanNoMoneyText
	text_end

.NoRefundsText
	text_far _MtMoonPokecenterMagikarpSalesmanNoRefundsText
	text_end

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
	ld a, [wCurrentMenuItem]
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
	ld [wUpdateSpritesEnabled], a
	ld [wMenuItemToSwap], a
	call DisplayPartyMenu
	push af
	call GBPalWhiteOutWithDelay3
	call RestoreScreenTilesAndReloadTilePatterns
	call LoadGBPal
	pop af
	jp c, .exit
	ld a, [wWhichPokemon]
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
	ld [wCurrentMenuItem], a
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
	ld [wWhichPokemon], a
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
    ;push de
    ; c will be a flag to pick a pokemon of equivalent rarity
    ;.looptradeget
    call Random_Pokemon_Selection
    ld a, d
    ;pop de
    ;push de
    ;cp d
    ;jr z, .looptradeget
    ;pop de
    ld [wroguenpctradeget], a ; load in pokemon that they will give player
    call GetMonName         ; get name of pokemon to receive
    ld [wroguenpctrade], a   ; load name into location
    ; could make a list of random names to choose from
    
    pop hl
    ret 
    
    