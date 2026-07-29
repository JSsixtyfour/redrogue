
;; randomize the gifts the giver gives, place ID in e
rogue_gift_randomized_batch::
   xor a
   ld d, a
   ld a, [wCurrentGiftGiver]
   ld e, a
   ld hl, GIFT_TOTALS
   add hl, de
   ld c, [hl]
   call Rangerandom
   ld [wGift1], a

   .rollpokemon2
   call Rangerandom
   ld d, a
   ld a, [wGift1]
   cp d
   jr z, .rollpokemon2
   ld hl, wGift2
   ld [hl], d

   .rollpokemon3
   call Rangerandom
   ld d, a
   ld a, [wGift1]
   cp d
   jr z, .rollpokemon3
   ld a, [wGift2]
   cp d
   jr z, .rollpokemon3
   ld hl, wGift3
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
    ld hl, GiftDescriptionTablePointers
    ld a, [wCurrentGiftGiver]
    sla a
    ld e, a
    add hl, de
    ld a, [hli]           ; 
    ld h, [hl]
    ld l, a               ; pointer to Gift Givers Table
	ld a, [wGift1]
    sla a       ; double for offset
    ld e, a     ; place in DE
    add hl, de              ; address of gift in gift givers table
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
    

    
	ld hl, wGift1
    ld e, a
    add hl, de
    ld a, [hl]          ; you have the ID of what you're hovering over
    sla a               ; double for offset
    ld e, a             ; place in de
    push de
    
    ld hl, GiftDescriptionTablePointers
    ld a, [wCurrentGiftGiver]
    sla a
    ld e, a
    add hl, de
    ld a, [hli]           ; 
    ld h, [hl]
    ld l, a               ; pointer to Gift Givers Table
    
    pop de                ; bring back de whichwill give us the  offset to the description
    
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
    xor a
    ld d, a
    ld hl, GiftTextTablePointers
    ld a, [wCurrentGiftGiver]
    sla a
    ld e, a
    add hl, de
    ld a, [hli]           ; 
    ld h, [hl]
    ld l, a               ; pointer to Gift Givers Table
    push hl
    ld a, [wGift1]
    sla a
    ld e, a
    xor a
    ld d, a
    add hl, de
    ld a, [hli]
    ld d, [hl]
    ld e, a
	hlcoord 2, 4
	call PlaceString
    ld a, [wGift2]
    sla a                       ; double for offset
    ld e, a
    xor a
    ld d, a
    pop hl
    push hl
    add hl, de
    ld a, [hli]
    ld d, [hl]
    ld e, a
	hlcoord 2, 6
	call PlaceString
    ld a, [wGift3]  
    sla a
    ld e, a
    xor a
    ld d, a
    pop hl
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

HandleGiftChoice:
    SetEvent EVENT_BRIDGE_RECEIVE_GIFT
    ldh a, [hCurrentMenuItem]
    ld hl, wGift1
    add a, l
    ld l, a
    ld a, [hl]
    ld b, a
    push bc
	ld [wWhichPrize], a
	ld d, 0
    sla a
	ld e, a
    push de
    xor a
    ld d, a
    ld hl, GiftTablePointers
    ld a, [wCurrentGiftGiver]
    sla a
    ld e, a
    add hl, de
    ld a, [hli]           ; 
    ld h, [hl]
    ld l, a               ; pointer to Gift Givers Table
    pop de
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
    
BridgeByeText:
	text_far _BridgeByeText
	text_end

ReceivedItem::
    call GetItemName         ; get name of item to receive
    ld hl, ReceivedItemText
    call PrintText
    ret
    
ReceivedItemText:
	text_far _ReceivedItemText
	text_end
    
Empty:
	text_far _Empty
	text_end
    
const_def
    const_export COPYCAT_GIFT       ; $00
    const_export BILL_GIFT          ; $01
    const_export MRFUJI_GIFT        ; $02
DEF NUM_GIFT_GIVERS EQU const_value - 1

GIFT_TOTALS::
db $07     ; Copy Cat
db $07     ; Bill
db $07     ; Mr. Fuji

GiftDescriptionTablePointers:
dw CopyCatGiftDescriptionTable
dw BillGiftDescriptionTable
dw MrFujiGiftDescriptionTable


CopyCatGiftDescriptionTable:
	dw CopyCatGift1_Desc
	dw CopyCatGift2_Desc
	dw CopyCatGift3_Desc
	dw CopyCatGift4_Desc
	dw CopyCatGift5_Desc
    dw CopyCatGift6_Desc
    dw CopyCatGift7_Desc
    
CopyCatGift1_Desc:
	text_far _CopyCatGift1Desc
	text_end

CopyCatGift2_Desc:
	text_far _CopyCatGift2Desc
	text_end
    
CopyCatGift3_Desc:
	text_far _CopyCatGift3Desc
	text_end
    
CopyCatGift4_Desc:
	text_far _CopyCatGift4Desc
	text_end
    
CopyCatGift5_Desc:
	text_far _CopyCatGift5Desc
	text_end

CopyCatGift6_Desc:
	text_far _CopyCatGift6Desc
	text_end
    
CopyCatGift7_Desc:
	text_far _CopyCatGift7Desc
	text_end

BillGiftDescriptionTable:
	dw BillGift1_Desc
	dw BillGift2_Desc
	dw BillGift3_Desc
	dw BillGift4_Desc
	dw BillGift5_Desc
    dw BillGift6_Desc
    dw BillGift7_Desc
    
BillGift1_Desc:
	text_far _BillGift1Desc
	text_end

BillGift2_Desc:
	text_far _BillGift2Desc
	text_end
    
BillGift3_Desc:
	text_far _BillGift3Desc
	text_end
    
BillGift4_Desc:
	text_far _BillGift4Desc
	text_end
    
BillGift5_Desc:
	text_far _BillGift5Desc
	text_end

BillGift6_Desc:
	text_far _BillGift6Desc
	text_end
    
BillGift7_Desc:
	text_far _BillGift7Desc
	text_end
    
MrFujiGiftDescriptionTable:
	dw MrFujiGift1_Desc
	dw MrFujiGift2_Desc
	dw MrFujiGift3_Desc
	dw MrFujiGift4_Desc
	dw MrFujiGift5_Desc
    dw MrFujiGift6_Desc
    dw MrFujiGift7_Desc
    
MrFujiGift1_Desc:
	text_far _MrFujiGift1Desc
	text_end

MrFujiGift2_Desc:
	text_far _MrFujiGift2Desc
	text_end
    
MrFujiGift3_Desc:
	text_far _MrFujiGift3Desc
	text_end
    
MrFujiGift4_Desc:
	text_far _MrFujiGift4Desc
	text_end
    
MrFujiGift5_Desc:
	text_far _MrFujiGift5Desc
	text_end

MrFujiGift6_Desc:
	text_far _MrFujiGift6Desc
	text_end
    
MrFujiGift7_Desc:
	text_far _MrFujiGift7Desc
	text_end
    
GiftTextTablePointers:
dw CopyCat_GiftTextTable
dw Bill_GiftTextTable
dw MrFuji_GiftTextTable

CopyCat_GiftTextTable:
	dw CopyCatGift1_Text
	dw CopyCatGift2_Text
	dw CopyCatGift3_Text
	dw CopyCatGift4_Text
	dw CopyCatGift5_Text
    dw CopyCatGift6_Text
    dw CopyCatGift7_Text
    
CopyCatGift1_Text:
	db "SUPER DITTO@"

CopyCatGift2_Text:
	db "MIMIC TM@"

CopyCatGift3_Text:
	db "PSYCHIC TM@"

CopyCatGift4_Text:
	db "MIRROR MOVE TUTOR@"

CopyCatGift5_Text:
	db "TRANSFORM TUTOR@"
    
CopyCatGift6_Text:
	db "NUGGET@"

CopyCatGift7_Text:
	db "SUBSTITUTE TM@"
    
Bill_GiftTextTable:
	dw BillGift1_Text
	dw BillGift2_Text
	dw BillGift3_Text
	dw BillGift4_Text
	dw BillGift5_Text
    dw BillGift6_Text
    dw BillGift7_Text
    
BillGift1_Text:
	db "MAD SCIENCE@"

BillGift2_Text:
	db "EEVEE@"

BillGift3_Text:
	db "JOLTEON@"

BillGift4_Text:
	db "FLAREON@"

BillGift5_Text:
	db "VAPOREON@"
    
BillGift6_Text:
	db "DUPLICATE TRICK@"

BillGift7_Text:
	db "THUNDERBOLT TM@"
    
    ; other gifts: ice beam, flamethrower, evolutionary stones, mist stone
    
MrFuji_GiftTextTable:
	dw MrFujiGift1_Text
	dw MrFujiGift2_Text
	dw MrFujiGift3_Text
	dw MrFujiGift4_Text
	dw MrFujiGift5_Text
    dw MrFujiGift6_Text
    dw MrFujiGift7_Text
    
MrFujiGift1_Text:
	db "POKé FLUTE@"

MrFujiGift2_Text:
	db "#MON RESCUE@"

MrFujiGift3_Text:
	db "THICK CLUB@"

MrFujiGift4_Text:
	db "GENE SPLICING@"

MrFujiGift5_Text:
	db "NIGHTSHADE TUTOR@"
    
MrFujiGift6_Text:
	db "CONFUSE RAY TUTOR@"

MrFujiGift7_Text:
	db "LICK TUTOR@"
    
    ; other gifts: mist stone, shrink or giant pokemon, group ghost move tutor, other rescue pokemon
    
GiftTablePointers:
dw CopyCatGiftTable
dw BillGiftTable
dw MrFujiGiftTable

CopyCatGiftTable:
	dw CopyCatGift1
	dw CopyCatGift2
	dw CopyCatGift3
	dw CopyCatGift4
	dw CopyCatGift5
    dw CopyCatGift6
    dw CopyCatGift7
    
CopyCatGift1::
    ;text_asm
	call GetRewardMonLevel
	ld c, a
    ld b, DITTO
	call GivePokemon
    ld hl, BridgeByeText
	call PrintText
    pop bc
	ret
   
CopyCatGift2::
    ;text_asm
    ;call placeholder ; prevent text_asm consumption, gotta be something better than this
    ld c, 1
	ld b, MIMIC
	call GiveItem
    call ReceivedItem
    pop bc
    ld hl, BridgeByeText
	call PrintText
	ret

CopyCatGift3::
    ;text_asm
    ;call placeholder ; prevent text_asm consumption, gotta be something better than this
	ld b, PSYCHIC_M
    ld c, 1
	call GiveItem
    call ReceivedItem
    pop bc
    ld hl, BridgeByeText
	call PrintText
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
    ;text_asm
    ;call placeholder ; prevent text_asm consumption, gotta be something better than this
	ld b, NUGGET
	ld c, 1
	call GiveItem
    call ReceivedItem
    pop bc
    ld hl, BridgeByeText
	call PrintText
	ret
    
CopyCatGift7::
    ;text_asm
    ;call placeholder ; prevent text_asm consumption, gotta be something better than this
	ld b, SUBSTITUTE
	ld c, 1
	call GiveItem
    call ReceivedItem
    pop bc
    ld hl, BridgeByeText
	call PrintText
    ret
    
BillGiftTable:
	dw BillGift1
	dw BillGift2
	dw BillGift3
	dw BillGift4
	dw BillGift5
    dw BillGift6
    dw BillGift7
    
BillGift1::     ; MAD SCIENCE PLACEHOLDER
	call GetRewardMonLevel
    pop bc
	ld c, a
    ld b, DITTO
	call GivePokemon
    ld hl, BridgeByeText
	call PrintText
	ret
   
BillGift2::     ; EEVEE
	call GetRewardMonLevel
	ld c, a
    ld b, EEVEE
	call GivePokemon
    ld hl, BridgeByeText
	call PrintText
    pop bc
	ret

BillGift3::     ; JOLTEON
	call GetRewardMonLevel
	ld c, a
    ld b, JOLTEON
	call GivePokemon
    ld hl, BridgeByeText
	call PrintText
    pop bc
	ret

BillGift4::    ; FLAREON
    call GetRewardMonLevel
	ld c, a
    ld b, FLAREON
	call GivePokemon
    ld hl, BridgeByeText
	call PrintText
    pop bc
	ret
    
BillGift5::    ; VAPOREON
    call GetRewardMonLevel
	ld c, a
    ld b, VAPOREON
	call GivePokemon
    ld hl, BridgeByeText
	call PrintText
    pop bc
	ret
    
BillGift6::     ; DUPLICATION TRICK PLACEHOLDER
    ;text_asm
    ;call placeholder ; prevent text_asm consumption, gotta be something better than this
	ld b, NUGGET
	ld c, 1
	call GiveItem
    call ReceivedItem
    pop bc
    ld hl, BridgeByeText
	call PrintText
	ret
    
BillGift7::     ; THUNDERBOLT TM
	ld b, THUNDERBOLT
	ld c, 1
	call GiveItem
    call ReceivedItem
    pop bc
    ld hl, BridgeByeText
	call PrintText
    ret
    
MrFujiGiftTable:
	dw MrFujiGift1
	dw MrFujiGift2
	dw MrFujiGift3
	dw MrFujiGift4
	dw MrFujiGift5
    dw MrFujiGift6
    dw MrFujiGift7
    
MrFujiGift1::     ; POKE FLUTE
	ld b, POKE_FLUTE
	ld c, 1
	call GiveItem
    call ReceivedItem
    pop bc
    ld hl, BridgeByeText
	call PrintText
	ret
   
MrFujiGift2::     ; Rogue Pokemon Rescue
	call GetRewardMonLevel
	ld c, a
    ld a, [wRoguePokemon1]
    ld b, a
	call GivePokemon
    ld hl, BridgeByeText
	call PrintText
    pop bc
	ret

MrFujiGift3::     ; THICK CLUB
	call GetRewardMonLevel
	ld c, a
    ld a, [wBattleCount]
    cp  a, 30
    ld  b, CUBONE
    jr nc, .cubone
    
    ld b, MAROWAK
    .cubone
	call GivePokemon
    ld hl, BridgeByeText
	call PrintText
    pop bc
	ret

MrFujiGift4::    ; GENE SPLICING PLACEHOLDER
    call GetRewardMonLevel
	ld c, a
    ld b, FLAREON
	call GivePokemon
    ld hl, BridgeByeText
	call PrintText
    pop bc
	ret
    
MrFujiGift5::    ; GHOST MOVE TUTOR
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
	ld a, NIGHT_SHADE
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
    
MrFujiGift6::     ; NUGGET
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
	ld a, CONFUSE_RAY
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
    
MrFujiGift7::     ; PLACEHOLDER
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
	ld a, LICK
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