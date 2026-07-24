rogue_gift_randomized_batch::
   ld c, NUM_GIFTS
   call Rangerandom
   ld [wRoguePokemon1], a

   .rollpokemon2
   ld c, NUM_GIFTS
   call Rangerandom
   ld d, a
   ld a, [wRoguePokemon1]
   cp d
   jr z, .rollpokemon2
   ld hl, wRoguePokemon2
   ld [hl], d

   .rollpokemon3
   ld c, NUM_GIFTS
   call Rangerandom
   ld d, a
   ld a, [wRoguePokemon1]
   cp d
   jr z, .rollpokemon3
   ld a, [wRoguePokemon2]
   cp d
   jr z, .rollpokemon3
   ld hl, wRoguePokemon3
   ld [hl], d
   
   .doneBatch
RET

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
    ld a, [wRoguePokemon1]
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
    ld a, [wRoguePokemon2]
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
    ld a, [wRoguePokemon3]  
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