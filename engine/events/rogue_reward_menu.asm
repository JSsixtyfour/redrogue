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
	push hl
	ld hl, wRoguePokemon1
	;call CopyString
	pop hl
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
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
    ld [wToggleableObjectIndex], a
    predef HideObject
    ret
.givePrize
	ld hl, SoYouWantRewardText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem] ; yes/no answer (Y=0, N=1)
	and a
    pop bc
	jp nz, .printOhFineThen
.giveMon
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

GetRewardMonLevel:
	; level = 5 + (wBattleCount / 10) * 5, capped at 50
	ld a, [wBattleCount]
	ld b, 0             ; b = round counter
.countRounds
	cp 10
	jr c, .roundsDone
	sub 10
	inc b
	jr .countRounds
.roundsDone
	; b = round (0-8+)
	ld a, b
	add a               ; a = round*2
	add a               ; a = round*4
	add b               ; a = round*5
	add 5               ; a = 5 + round*5
	cp 51
	jr c, .levelOk
	ld a, 50
.levelOk
	ld [wCurEnemyLevel], a
	ret

RogueRefresh::
	farcall MarkCurrentStageVisited  ; record this stage as visited for no-duplicate selection
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef ShowObject
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef ShowObject
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef ShowObject
    ld a, TOGGLE_STAGE_RANDOM_ITEM
	ld [wToggleableObjectIndex], a
	predef ShowObject
    ret