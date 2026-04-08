RogueRewardMenu::
    ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	ld hl, RogueRewardText
	call PrintText
; the following are the menu settings
	xor a
	ld [wCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld a, PAD_A | PAD_B
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
	call HandleMenuInput ; menu choice handler
	bit B_PAD_B, a
	jr nz, .noChoice
	ld a, [wCurrentMenuItem]
	cp 3 ; "NO,THANKS" choice
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
	call CopyString
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
    ld a, [wCurrentMenuItem]
	ld [wWhichPrize], a
	ld d, 0
	ld e, a
	ld hl, wRoguePokemon1
	add hl, de
	ld a, [hl]
	ld [wNamedObjectIndex], a
.getMonName
	call GetMonName
.givePrize
	ld hl, SoYouWantRewardText
	call PrintText
	call YesNoChoice
	ld a, [wCurrentMenuItem] ; yes/no answer (Y=0, N=1)
	and a
	jr nz, .printOhFineThen
.giveMon
    ld a, [wCurrentMenuItem]
    ld b, TOGGLE_ROGUE_REWARD_POKEBALL_1
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

RewardRoomBagIsFullText:
	text_far _OopsYouDontHaveEnoughRoomText
	text_waitbutton
	text_end

OhFineThenRewardText:
	text_far _OhFineThenText
	text_waitbutton
	text_end
    
Goodluck:
	text_far _Goodluck
	text_waitbutton
	text_end

GetRewardMonLevel:
;	ld a, [wCurPartySpecies]
;	ld b, a
;	ld hl, PrizeMonLevelDictionary
;.loop
;	ld a, [hli]
;	cp b
;	jr z, .matchFound
;	inc hl
;	jr .loop
;.matchFound
	ld a, 5
	ld [wCurEnemyLevel], a
	ret
