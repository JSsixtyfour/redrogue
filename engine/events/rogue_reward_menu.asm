RogueRewardMenu::
    ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	ld hl, RogueRewardText
	call PrintText
; the following are the menu settings
	xor a
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld a, PAD_A | PAD_B | PAD_UP | PAD_DOWN
	ld [wMenuWatchedKeys], a
	ld a, $03
	ld [wMaxMenuItem], a
	ld a, $04
	ld [wTopMenuItemY], a
	ld a, $01
	ld [wTopMenuItemX], a
	hlcoord 0, 2
	ld b, 8
	ld c, 16
	call TextBoxBorder
	call GetRogueRewardMenuId
	call UpdateSprites
	ld hl, RogueRewardTextChoice
	call PrintText
	; if trade is active, show hover box immediately (cursor starts at slot 0)
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_TRADE_ACTIVE, a
	jr z, .menuLoop
	jr .showTradeHover
.menuLoop
	call HandleMenuInput
	bit B_PAD_A, a
	jr nz, .aPressed
	bit B_PAD_B, a
	jr nz, .noChoice
	; cursor moved — update hover box if trade is active
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_TRADE_ACTIVE, a
	jr z, .menuLoop
	ldh a, [hCurrentMenuItem]
	and a
	jr nz, .eraseTradeHover
.showTradeHover
    hlcoord 0, 0
	lb bc, 18, 3
	predef SaveScreenTileAreaToBuffer3
	hlcoord 0, 0
	ld b, 1
	ld c, 16
	call TextBoxBorder
	hlcoord 1, 1
	ld de, TradeHoverLabel
	call PlaceString
	ld a, [wroguenpctradegive]
	ld [wNamedObjectIndex], a
	call GetMonName
	hlcoord 7, 1
	ld de, wNameBuffer
	call PlaceString
	jr .menuLoop
.eraseTradeHover
	hlcoord 0, 0
	lb bc, 18, 3
	predef LoadScreenTileAreaFromBuffer3
	jr .menuLoop
.aPressed
	ldh a, [hCurrentMenuItem]
	cp 3
	jr z, .noChoice
	call HandleRewardChoice
.noChoice
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	ret

RogueRewardText:
    text_far _RogueRewardText
	text_end
    
RogueRewardTextChoice:
	text_far _WhichPrizeText
	text_end

GetRogueRewardMenuId:
; determine which one among the three prize texts has been selected using the text ID (stored in [hTextID])
; prize texts' IDs are TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_1-TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_3
; load the three prizes at wPrize1-wPrice3
; load the three prices at wPrize1Price-wPrize3Price
; display the three prizes' names, distinguishing between Pokemon names and item names (specifically TMs)
	ldh a, [hTextID]
	sub TEXT_REWARDROOM_REWARD_VENDOR_1
	ld [wWhichPrizeWindow], a ; prize texts' relative ID (i.e. 0-2)
	add a
	add a
	ld d, 0
	ld e, a
	ld hl, PrizeDifferentMenuPtrs
	add hl, de
	ld a, [hli]
	ld d, [hl]
	ld e, a
	inc hl
	;push hl
	;ld hl, wRoguePokemon1
	;call CopyString
	;pop hl
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld de, wPrize1Price
	ld bc, 6
	call CopyData

.putMonName
	ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
	call GetMonName
	hlcoord 2, 4
	call PlaceString
	; if slot 1 is a trade offer, show "TRADE" label (name shown in hover box)
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_TRADE_ACTIVE, a
	jr z, .slot1NoTrade
	hlcoord 12, 4
	ld de, TradeSlotLabel
	call PlaceString
.slot1NoTrade
	ld a, [wRoguePokemon2]
	ld [wNamedObjectIndex], a
	call GetMonName
	hlcoord 2, 6
	call PlaceString
	ld a, [wRoguePokemon3]
	ld [wNamedObjectIndex], a
	call GetMonName
	hlcoord 2, 8
	call PlaceString
.putNoThanksText
	hlcoord 2, 10
	ld de, NoThanksText
	call PlaceString
    ret

HandleRewardChoice:
    ldh a, [hCurrentMenuItem]
    ld b, a
    push bc
	ld [wWhichPrize], a
	ld d, 0
	ld e, a
	ld hl, wRoguePokemon1
	add hl, de
	ld a, [hl]
	ld [wNamedObjectIndex], a
.getMonName
	call GetMonName
    ; trade offer always occupies slot 1 (index 0); BIT_ROGUE_TRADE_ACTIVE gates it
    ldh a, [hCurrentMenuItem]
    and a
    jr nz, .givePrize
    ld a, [wRogueFlagsBitfield]
    bit BIT_ROGUE_TRADE_ACTIVE, a
    jr z, .givePrize
    ; trade slot selected — run full in-game trade dialogue with animation
    pop bc                          ; balance push bc from top of HandleRewardChoice
    ld hl, wStatusFlags5
    res BIT_NO_TEXT_DELAY, [hl]     ; restore normal text speed for animation
    ld a, TRADE_FOR_RANDOM
    ld [wWhichTrade], a
    ldh a, [hTileAnimations]
    push af
    xor a
    ldh [hTileAnimations], a
    predef RogueDoInGameTradeDialogue
    pop af
    ldh [hTileAnimations], a
    ; TRADE_FOR_RANDOM flag is set by InGameTrade_DoTrade on success
    ld c, TRADE_FOR_RANDOM
    ld b, FLAG_TEST
    ld hl, wCompletedInGameTradeFlags
    predef FlagActionPredef
    ld a, c
    and a
    ret z                           ; declined or wrong mon selected
    SetEvent EVENT_GOT_ROGUE_POKEMON
    ret                             ; trade NPC stays visible, unlike the pokeballs
.givePrize
	ld hl, SoYouWantRewardText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem] ; yes/no answer (Y=0, N=1)
	and a
    pop bc
	jp nz, .printOhFineThen
.giveMon
    ; Challenge 7 (PARTY_LIMIT): limit = min(2 + wBattleCount/10, 5).
    ; Increases by 1 each round (every 10 battles), starting at 2. Cap 5.
    ld a, [wRogueFlagsBitfield]
    bit BIT_WITCH_ACCEPTED, a
    jr z, .noPartyLimit
    ld a, [wWitchChallenge]
    cp CHALLENGE_PARTY_LIMIT
    jr nz, .noPartyLimit
    ld a, [wBattleCount]
    ld c, 0
.limitDivLoop
    cp 10
    jr c, .limitDivDone
    sub 10
    inc c
    jr .limitDivLoop
.limitDivDone
    ld a, c
    add 2               ; limit = 2 + rounds_completed
    cp 6
    jr c, .limitCapped
    ld a, 5
.limitCapped
    ld c, a             ; c = party limit
    ld a, [wPartyCount]
    cp c
    jr c, .noPartyLimit ; wPartyCount < limit: allow
    ld hl, WitchPartyLimitText
    call PrintText
    ret
.noPartyLimit
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
    add a, b
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, [wNamedObjectIndex]
	ld [wCurPartySpecies], a
	push af
	call GetRewardMonLevel
	ld c, a
	pop af
	ld b, a
	call GivePokemon
    SetEvent EVENT_GOT_ROGUE_POKEMON

; If either the party or box was full, wait after displaying message.
	push af
	ld a, [wAddedToParty]
	and a
	call z, WaitForTextScrollButtonPress
	pop af

; If the mon couldn't be given to the player (because both the party and box
; were full), return without subtracting coins.
	ret nc
.normal
	; _GivePokemon's add-to-party success path sets hNoWaitAfterText=1 for its
	; own purposes and never clears it - without this, Goodluck below would
	; flash by without waiting for a button press.
	xor a
	ldh [hNoWaitAfterText], a
	ld hl, Goodluck
	jp PrintText
.bagFull
	ld hl, RewardRoomBagIsFullText
	jp PrintText
.printOhFineThen
	ld hl, OhFineThenRewardText
	jp PrintText

;UnknownPrizeData:
; XXX what's this?
	db $00,$01,$00,$01,$00,$01,$00,$00,$01

WitchPartyLimitText:
	text_far _WitchPartyLimitText
	text_end

SoYouWantRewardText:
	text_far _SoYouWantPrizeText
	text_end

RogueTradeOfferText:
	text_far _RogueTradeOfferText
	text_end

TradeSlotLabel:
	db "TRADE@"

TradeHoverLabel:
	db "GIVE:@"

RewardRoomBagIsFullText:
	text_far _OopsYouDontHaveEnoughRoomText
	;text_waitbutton
	text_end

OhFineThenRewardText:
	text_far _OhFineThenText
	;text_waitbutton
	text_end
    
Goodluck:
	text_far _Goodluck
	;text_waitbutton
	text_end

GetRewardMonLevel::
	; Reward Room and Oak's Lab (starter selection) always use a flat level 5
	; regardless of progress. Everywhere else, the level is tailored to
	; whichever tier is relevant (1 higher than the highest standard,
	; non-final-bonus trainer level in that tier), read directly from
	; trainer_difficulty_settings/_gym so it can never drift out of sync with
	; the actual trainer data.
	;
	; Two different callers, two different tiers:
	; - A stage's own reward pokeballs are rolled at stage entry, while still
	;   on a route - the gym of the SAME round is always what's coming up
	;   next, so this case always uses the gym tier, no remainder check.
	; - The salesman/trader (lobby only) needs to know which door is
	;   literally next, which does depend on wBattleCount's position within
	;   the round (remainder 0-4 = route next, 5-9 = gym next).
	ldh a, [hCurMap]
	cp REWARD_ROOM
	jr z, .flatFive
	cp OAKS_LAB
	jr z, .flatFive
	cp INDIGO_PLATEAU_LOBBY
	jr z, .lobbyCaller

	ld a, [wBattleCount]
	cp 90
	jr c, .noClampRoundStage
	ld a, 89
.noClampRoundStage
	ld b, 0                 ; b = round index (0-8)
.getRoundIndexStage
	cp 10
	jr c, .gotTable
	sub 10
	inc b
	jr .getRoundIndexStage

.lobbyCaller
	ld a, [wBattleCount]
	cp 90
	jr c, .noClampRound
	ld a, 89                ; clamp to round 9's settings, same as GetRandRoster
.noClampRound
	ld b, 0                 ; b = round index (0-8)
.getRoundIndex
	cp 10
	jr c, .gotRoundIndex
	sub 10
	inc b
	jr .getRoundIndex
.gotRoundIndex
	; a = remainder within the round (0-9): 0-4 means a gym was just cleared
	; (or no battles yet) and a route is next; 5-9 means a route was just
	; cleared and the gym is next.
	cp 5
	jr nc, .gotTable
	ld hl, trainer_difficulty_settings
	jr .pickedTable
.gotTable
	ld hl, trainer_difficulty_settings_gym
.pickedTable
	ld a, b                 ; each settings block is 11 bytes
	ld d, a
	add a, a                ; *2
	add a, a                ; *4
	add a, a                ; *8
	add a, d                ; *9
	add a, d                ; *10
	add a, d                ; *11
	ld c, a
	ld b, 0
	add hl, bc               ; hl -> this round's 11-byte block (still bank 07 address)
	ld de, wRewardLevelDataBuffer ; trainer_difficulty_settings/_gym live in bank 07,
	ld a, BANK(trainer_difficulty_settings) ; this function doesn't - read across
	ld bc, 2                ; banks instead of a plain (same-bank-only) [hl] read
	call FarCopyData
	ld a, [wRewardLevelDataBuffer]   ; byte 0: level range
	ld b, a
	ld a, [wRewardLevelDataBuffer + 1] ; byte 1: minimum level
	add b                    ; minimum + range = (max standard level) + 1
	cp 51
	jr c, .levelOk
	ld a, 50
.levelOk
	ld [wCurEnemyLevel], a
	ret
.flatFive
	ld a, 5
	ld [wCurEnemyLevel], a
	ret

RogueRefresh::
	farcall MarkCurrentStageVisited  ; record this stage as visited for no-duplicate selection
	; witch's "no reward pokemon" challenge: hide all 3 pokeballs and the
	; trade NPC instead of the usual show/hide-by-trade-flag logic below
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .normalPokeballLogic
	ld a, [wWitchChallenge]
	cp CHALLENGE_NO_REWARD_POKEMON
	jr nz, .normalPokeballLogic
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_ROGUE_TRADE_NPC
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef HideObject
	jr .randomItemCheck
.normalPokeballLogic
	; show/hide pokeball 1 and trade NPC based on trade active flag
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_TRADE_ACTIVE, a
	jr nz, .tradeActive
	; no trade: show pokeball 1, hide trade NPC
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_ROGUE_TRADE_NPC
	ld [wToggleableObjectIndex], a
	predef HideObject
	jr .showRest
.tradeActive
	; trade: hide pokeball 1, show trade NPC
	ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_ROGUE_TRADE_NPC
	ld [wToggleableObjectIndex], a
	predef ShowObject
.showRest
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef ShowObject
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef ShowObject
.randomItemCheck
	; witch's "no random item" challenge: hide the random item instead of
	; the usual unconditional show
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .showRandomItem
	ld a, [wWitchChallenge]
	cp CHALLENGE_NO_RANDOM_ITEM
	jr nz, .showRandomItem
	ld a, TOGGLE_STAGE_RANDOM_ITEM
	ld [wToggleableObjectIndex], a
	predef HideObject
	ret
.showRandomItem
    ld a, TOGGLE_STAGE_RANDOM_ITEM
	ld [wToggleableObjectIndex], a
	predef ShowObject
	; Challenge 9 (ALL_POISONED): poison every party member at stage entry.
	; Fainted mons are included visually but PSN does no additional battle damage to them.
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z
	ld a, [wWitchChallenge]
	cp CHALLENGE_ALL_POISONED
	ret nz
	ld a, [wPartyCount]
	and a
	ret z
	ld b, a          ; b = party count
	ld hl, wPartyMon1Status
	ld de, PARTYMON_STRUCT_LENGTH
.poisonLoop
	set PSN, [hl]            ; set PSN bit on status byte (PSN = bit 3 = $08)
	add hl, de               ; advance to next mon's status byte
	dec b
	jr nz, .poisonLoop
    

BridgeGiftMenu::
    ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	ld hl, BridgeGiftText
	call PrintText
; the following are the menu settings
	xor a
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld a, PAD_A | PAD_B | PAD_UP | PAD_DOWN
	ld [wMenuWatchedKeys], a
	ld a, $03
	ld [wMaxMenuItem], a
	ld a, $04
	ld [wTopMenuItemY], a
	ld a, $01
	ld [wTopMenuItemX], a
	hlcoord 0, 2
	ld b, 8
	ld c, 18
	call TextBoxBorder
	call GetBridgeGiftMenuId
	call UpdateSprites
	xor a
    ld d, a
	ld a, [wRoguePokemon1]
    sla a       ; double for offset
    ld e, a     ; place in DE
    ld hl, CopyCatGiftDescriptionTable
    add hl, de
    ld a, [hli]           ; 
    ld h, [hl]
    ld l, a               ; pointer to specific text address 
    call PrintText

.menuLoop
	call HandleMenuInput
	bit B_PAD_A, a
	jr nz, .aPressed
	bit B_PAD_B, a
	jr nz, .noChoice
    xor a
    ld d, a
	ldh a, [hCurrentMenuItem]
    cp a, 3
    jp z, .empty
	ld hl, wRoguePokemon1
    ld e, a
    add hl, de
    ld a, [hl]          ; you have the ID of what you're hovering over
    sla a               ; double for offset
    ld e, a             ; place in de
    ld hl, CopyCatGiftDescriptionTable
    add hl, de             ; you now have the text instructions address
    ld a, [hli]           ; 
    ld h, [hl]
    ld l, a               ; pointer to specific text address
    
    call PrintText
    jr .menuLoop
    
.empty
    ld hl, Empty
    call PrintText
    jr .menuLoop
.aPressed
	ldh a, [hCurrentMenuItem]
	cp 3
	jr z, .noChoice
	call HandleGiftChoice
.noChoice
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	ret
    
BridgeGiftText:
    text_far _BridgeGiftText
	text_end
    
BridgeGiftTextChoice:
	text_far _WhichPrizeText
	text_end
    
GetBridgeGiftMenuId:
; determine which one among the three prize texts has been selected using the text ID (stored in [hTextID])
; prize texts' IDs are TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_1-TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_3
; load the three prizes at wPrize1-wPrice3
; load the three prices at wPrize1Price-wPrize3Price
; display the three prizes' names, distinguishing between Pokemon names and item names (specifically TMs)
	ldh a, [hTextID]
	sub TEXT_REWARDROOM_REWARD_VENDOR_1
	ld [wWhichPrizeWindow], a ; prize texts' relative ID (i.e. 0-2)
	add a
	add a
	ld d, 0
	ld e, a
	ld hl, PrizeDifferentMenuPtrs
	add hl, de
	ld a, [hli]
	ld d, [hl]
	ld e, a
	inc hl
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld de, wPrize1Price
	ld bc, 6
	call CopyData

.slot1
    ld c, NUM_GIFTS
    call Rangerandom
    ld [wRoguePokemon1], a
    sla a
    ld e, a
    xor a
    ld d, a
    ld hl, .GiftTextTable
    add hl, de
    ld a, [hli]
    ld d, [hl]
    ld e, a
	hlcoord 2, 4
	call PlaceString
.slot1NoTrade
	ld c, NUM_GIFTS
    call Rangerandom   
    ld [wRoguePokemon2], a      ; load gift number
    sla a                       ; double for offset
    ld e, a
    xor a
    ld d, a
    ld hl, .GiftTextTable
    add hl, de
    ld a, [hli]
    ld d, [hl]
    ld e, a
	hlcoord 2, 6
	call PlaceString
	ld c, NUM_GIFTS
    call Rangerandom 
    ld [wRoguePokemon3], a   
    sla a
    ld e, a
    xor a
    ld d, a
    ld hl, .GiftTextTable
    add hl, de
    ld a, [hli]
    ld d, [hl]
    ld e, a
	hlcoord 2, 8
	call PlaceString
.putNoThanksText
	hlcoord 2, 10
	ld de, NoThanksText
	call PlaceString
    ret

def NUM_GIFTS EQU 7

.GiftTextTable:
	dw .Gift1
	dw .Gift2
	dw .Gift3
	dw .Gift4
	dw .Gift5
    dw .Gift6
    dw .Gift7
    
.Gift1:
	db "SUPER DITTO@"

.Gift2:
	db "MIMIC TM@"

.Gift3:
	db "PSYCHIC TM@"

.Gift4:
	db "MIRROR MOVE TUTOR@"

.Gift5:
	db "TRANSFORM TUTOR@"
    
.Gift6:
	db "NUGGET@"

.Gift7:
	db "SUBSTITUTE TM@"
    
; hl needs to be the given Bridge NPCs Gift Routines
HandleGiftChoice:
    ldh a, [hCurrentMenuItem]
    ld hl, wRoguePokemon1
    add a, l
    ld l, a
    ld a, [hl]
    ld b, a
    push bc
	ld [wWhichPrize], a
	ld d, 0
    sla a
	ld e, a
    ld hl, CopyCatGiftTable
	add hl, de
    ld a, [hli]
    ld h, [hl]
    ld l, a
    jp hl
	xor a
	ldh [hNoWaitAfterText], a
	ld hl, Goodluck
	jp PrintText
.bagFull
	ld hl, RewardRoomBagIsFullText
	jp PrintText
.printOhFineThen
	ld hl, OhFineThenRewardText
	jp PrintText
    
CopyCatGiftTable:
	dw CopyCatGift1
	dw CopyCatGift2
	dw CopyCatGift3
	dw CopyCatGift4
	dw CopyCatGift5
    dw CopyCatGift6
    dw CopyCatGift7
    
CopyCatGift1::
    text_asm
    ;push af
	call GetRewardMonLevel
    pop bc
	ld c, a
	;pop af
    ld b, DITTO
	call GivePokemon
	;jr nc, .party_full
;.party_full
	ret
   
CopyCatGift2::
    text_asm
    xor a ; prevent text_asm consumption, gotta be something better than this
    ld c, 1
	ld b, MIMIC
	call GiveItem
    pop bc
	ret

CopyCatGift3::
    text_asm
    xor a ; prevent text_asm consumption, gotta be something better than this
	ld b, PSYCHIC_M
    ld c, 1
	call GiveItem
    pop bc
	ret

CopyCatGift4::    
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
.chooseMove
	; Save the selected move id.
	ld a, MIRROR_MOVE
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
	jr z, .exit
    
    .exit
	ld hl, BridgeByeText
	call PrintText
	ret
    
    CopyCatGift5::    
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
.chooseMove
	; Save the selected move id.
	ld a, TRANSFORM
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
	jr z, .exit
    
    .exit
	ld hl, BridgeByeText
	call PrintText
	ret
    
CopyCatGift6::
    text_asm
    xor a ; prevent text_asm consumption, gotta be something better than this
	ld b, NUGGET
	ld c, 1
	call GiveItem
    pop bc
	ret
    
CopyCatGift7::
    text_asm
    xor a ; prevent text_asm consumption, gotta be something better than this
	ld b, SUBSTITUTE
	ld c, 1
	call GiveItem
    pop bc
    ret
    
    
BridgeByeText:
	text_far _PCMoveTutorByeText
	text_end
    
CopyCatGiftDescriptionTable:
	dw CopyCatGift1Desc
	dw CopyCatGift2Desc
	dw CopyCatGift3Desc
	dw CopyCatGift4Desc
	dw CopyCatGift5Desc
    dw CopyCatGift6Desc
    dw CopyCatGift7Desc
    
CopyCatGift1Desc:
	text_far _CopyCatGift1Desc
	text_end

CopyCatGift2Desc:
	text_far _CopyCatGift2Desc
	text_end
    
CopyCatGift3Desc:
	text_far _CopyCatGift3Desc
	text_end
    
CopyCatGift4Desc:
	text_far _CopyCatGift4Desc
	text_end
    
CopyCatGift5Desc:
	text_far _CopyCatGift5Desc
	text_end

CopyCatGift6Desc:
	text_far _CopyCatGift6Desc
	text_end
    
CopyCatGift7Desc:
	text_far _CopyCatGift7Desc
	text_end
    
Empty:
	text_far _Empty
	text_end