PlayerPC::
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	ld a, ITEM_NAME
	ld [wNameListType], a
	call SaveScreenTilesToBuffer1
	xor a
	ld [wBagSavedMenuItem], a
	ld [wParentMenuItem], a
	ld a, [wMiscFlags]
	bit BIT_USING_GENERIC_PC, a
	jr nz, PlayerPCMenu
; accessing it directly
	ld a, SFX_TURN_ON_PC
	call PlaySound
	ld hl, TurnedOnPC2Text
	call PrintText

PlayerPCMenu:
	ld a, [wParentMenuItem]
	ldh [hCurrentMenuItem], a
	ld hl, wMiscFlags
	set BIT_NO_MENU_BUTTON_SOUND, [hl]
	call LoadScreenTilesFromBuffer2
	hlcoord 0, 0
	ld b, $6
	ld c, $e
	call TextBoxBorder
	call UpdateSprites
	hlcoord 2, 2
	ld de, PlayersPCMenuEntries
	call PlaceString
	ld hl, wTopMenuItemY
	ld a, 2
	ld [hli], a ; wTopMenuItemY
	dec a
	ld [hli], a ; wTopMenuItemX
	inc hl ; wTileBehindCursor
	ld a, 2
	ld [hli], a ; wMaxMenuItem (0=Withdraw, 1=Deposit, 2=LogOff)
	ld a, PAD_A | PAD_B
	ld [hli], a ; wMenuWatchedKeys
	xor a
	ld [hl], a
	ld hl, wListScrollOffset
	ld [hli], a ; wListScrollOffset
	ld [hl], a ; wMenuWatchMovingOutOfBounds
	ld [wPlayerMonNumber], a
	ld hl, WhatDoYouWantText
	call PrintText
	call HandleMenuInput
	bit B_PAD_B, a
	jp nz, ExitPlayerPC
	call PlaceUnfilledArrowMenuCursor
	ldh a, [hCurrentMenuItem]
	ld [wParentMenuItem], a
	and a
	jp z, PlayerPCWithdrawKeyItems
	dec a
	jp z, PlayerPCDepositKeyItems

ExitPlayerPC:
	ld hl, wBagPocketsFlags
	res BIT_PC_WITHDRAWING, [hl]   ; restore pocket switching for the bag
	ld a, [wMiscFlags]
	bit BIT_USING_GENERIC_PC, a
	jr nz, .next
; accessing it directly
	ld a, SFX_TURN_OFF_PC
	call PlaySound
	call WaitForSoundToFinish
.next
	ld hl, wMiscFlags
	res BIT_NO_MENU_BUTTON_SOUND, [hl]
	call LoadScreenTilesFromBuffer2
	xor a
	ld [wListScrollOffset], a
	ld [wBagSavedMenuItem], a
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	xor a
	ldh [hNoWaitAfterText], a
	ret

PlayerPCDeposit:
	xor a
	ldh [hCurrentMenuItem], a
	ld [wListScrollOffset], a
	ld a, [wNumBagItems]
	and a
	jr nz, .loop
	; PC deposit of count-array pocket items is future work — check legacy bag only
    
	ld hl, NothingToDepositText
	call PrintText
	jp PlayerPCMenu
.loop
	ld hl, WhatToDepositText
	call PrintText
    call SaveTextBoxTilesToBuffer ; marcelnote - for TM printing
	;;;;;;;;;; marcelnote - check which pocket we were last in, new for bag pockets
	ld a, [wBagPocketsFlags]
	bit BIT_KEY_ITEMS_POCKET, a
	ld hl, wNumBagItems
	jr z, .gotBagPocket
	ld hl, wNumBagItems
.gotBagPocket
	;;;;;;;;;;
	ld a, l
	ld [wListPointer], a
	ld a, h
	ld [wListPointer + 1], a
	xor a
	ld [wPrintItemPrices], a
	ld a, ITEMLISTMENU
	ld [wListMenuID], a
	call DisplayListMenuID
	jp c, PlayerPCMenu
	call IsKeyItem
	ld a, 1
	ld [wItemQuantity], a
	ld a, [wIsKeyItem]
	and a
	jr nz, .next
; if it's not a key item, there can be more than one of the item
	ld hl, DepositHowManyText
	call PrintText
	call DisplayChooseQuantityMenu
	cp $ff
	jp z, .loop
.next
	ld hl, wNumBoxItems
	call AddItemToInventory
	jr c, .roomAvailable
	ld hl, NoRoomToStoreText
	call PrintText
	jp .loop
.roomAvailable
	ld hl, wNumBagItems
	call RemoveItemFromInventory
	call WaitForSoundToFinish
	ld a, SFX_WITHDRAW_DEPOSIT
	call PlaySound
	call WaitForSoundToFinish
	ld hl, ItemWasStoredText
	call PrintText
	jp .loop

PlayerPCWithdraw:
	xor a
	ldh [hCurrentMenuItem], a
	ld [wListScrollOffset], a
	ld a, [wNumBoxItems]
	and a
	jr nz, .loop
	ld hl, NothingStoredText
	call PrintText
	jp PlayerPCMenu
.loop
    ;;;;;;;;;; marcelnote - flag if withdrawing from PC (to prevent switching bag pocket), new for bag pockets
	ld hl, wBagPocketsFlags
	set BIT_PC_WITHDRAWING, [hl]
	;;;;;;;;;;
	ld hl, WhatToWithdrawText
	call PrintText
	ld hl, wNumBoxItems
	ld a, l
	ld [wListPointer], a
	ld a, h
	ld [wListPointer + 1], a
	xor a
	ld [wPrintItemPrices], a
	ld a, ITEMLISTMENU
	ld [wListMenuID], a
	call DisplayListMenuID
	jp c, PlayerPCMenu
	call IsKeyItem
	ld a, 1
	ld [wItemQuantity], a
	ld a, [wIsKeyItem]
	and a
    ld hl, wNumBagItems ; marcelnote - new for bag pockets
	jr nz, .next
; if it's not a key item, there can be more than one of the item
	ld hl, WithdrawHowManyText
	call PrintText
	call DisplayChooseQuantityMenu
	ld hl, wNumBagItems ; marcelnote - moved from below, new for bag pockets
	cp $ff
	jp z, .loop
.next
	ld hl, wNumBagItems
	call AddItemToInventory
	jr c, .roomAvailable
	ld hl, CantCarryMoreText
	call PrintText
	jp .loop
.roomAvailable
	;;;;;;;;;; marcelnote - check which pocket we are in, new for bag pockets
	ld a, [wBagPocketsFlags]
	bit BIT_KEY_ITEMS_POCKET, a
	ld hl, wNumBagItems
	jr z, .gotBagPocket2
	ld hl, wNumBagItems
.gotBagPocket2
	;;;;;;;;;;
	call RemoveItemFromInventory
	call WaitForSoundToFinish
	ld a, SFX_WITHDRAW_DEPOSIT
	call PlaySound
	call WaitForSoundToFinish
	ld hl, WithdrewItemText
	call PrintText
	jp .loop

PlayerPCToss:
	xor a
	ldh [hCurrentMenuItem], a
	ld [wListScrollOffset], a
	ld a, [wNumBoxItems]
	and a
	jr nz, .loop
	ld hl, NothingStoredText
	call PrintText
	jp PlayerPCMenu
.loop
	ld hl, WhatToTossText
	call PrintText
	ld hl, wNumBoxItems
	ld a, l
	ld [wListPointer], a
	ld a, h
	ld [wListPointer + 1], a
	xor a
	ld [wPrintItemPrices], a
	ld a, ITEMLISTMENU
	ld [wListMenuID], a
	push hl
	call DisplayListMenuID
	pop hl
	jp c, PlayerPCMenu
	push hl
	call IsKeyItem
	pop hl
	ld a, 1
	ld [wItemQuantity], a
	ld a, [wIsKeyItem]
	and a
	jr nz, .next
	ld a, [wCurItem]
	call IsItemHM
	jr c, .next
; if it's not a key item, there can be more than one of the item
	push hl
	ld hl, TossHowManyText
	call PrintText
	call DisplayChooseQuantityMenu
	pop hl
	cp $ff
	jp z, .loop
.next
	call TossItem ; disallows tossing key items
	jp .loop

PlayersPCMenuEntries:
	db   "WITHDRAW"
	next "DEPOSIT"
	next "LOG OFF@"

TurnedOnPC2Text:
	text_far _TurnedOnPC2Text
	text_end

WhatDoYouWantText:
	text_far _WhatDoYouWantText
	text_end

WhatToDepositText:
	text_far _WhatToDepositText
	text_end

DepositHowManyText:
	text_far _DepositHowManyText
	text_end

ItemWasStoredText:
	text_far _ItemWasStoredText
	text_end

NothingToDepositText:
	text_far _NothingToDepositText
	text_end

NoRoomToStoreText:
	text_far _NoRoomToStoreText
	text_end

WhatToWithdrawText:
	text_far _WhatToWithdrawText
	text_end

WithdrawHowManyText:
	text_far _WithdrawHowManyText
	text_end

WithdrewItemText:
	text_far _WithdrewItemText
	text_end

NothingStoredText:
	text_far _NothingStoredText
	text_end

CantCarryMoreText:
	text_far _CantCarryMoreText
	text_end

WhatToTossText:
	text_far _WhatToTossText
	text_end

TossHowManyText:
	text_far _TossHowManyText
	text_end

; TMItContainsText moved to custom_functions/tm_bag.asm (same ROMX bank as
; PrintBagInfoText, which needs to read it with that bank active)
	text_end

; ============================================================
; PlayerPCWithdrawKeyItems — take a key item from PC into bag.
; Shows owned-but-not-active items. Blocks if bag already has 3.
; ============================================================
PlayerPCWithdrawKeyItems:
	ld hl, wBagPocketsFlags
	res BIT_PRINT_INFO_BOX, [hl]
	set BIT_PC_WITHDRAWING, [hl]   ; block LEFT/RIGHT pocket switching in the list menu
	call LoadScreenTilesFromBuffer2
	call GBPalWhiteOut
	call ClearScreen
.withdrawLoop
	call GBPalNormal
	; Blank wTextBoxBuffer's text-box rows directly so PrintBagInfoText's
	; restoreDefaultText path always restores blank tiles, never stale text.
	; SaveTextBoxTilesToBuffer would capture "Moved to bag." etc. from wTileMap
	; if a previous action printed text, contaminating the buffer.
	ld hl, wTextBoxBuffer
	ld bc, 36              ; 2 rows × 18 tiles of text box area
	ld a, $7F              ; blank space tile
	call FillMemory
	farcall BuildKeyItemPCWithdrawList
	ld a, [wKeyItemPocketBuf]
	and a
	jr nz, .withdrawHasItems
	ld hl, .nothingToWithdrawText
	call PrintText
	jp PlayerPCMenu
.withdrawHasItems
	ld hl, wKeyItemPocketBuf
	ld a, l
	ld [wListPointer], a
	ld a, h
	ld [wListPointer + 1], a
	xor a
	ld [wPrintItemPrices], a
	ldh [hCurrentMenuItem], a
	ld a, ITEMLISTMENU
	ld [wListMenuID], a
	call DisplayListMenuID
	jp c, PlayerPCMenu
	farcall WithdrawKeyItem
	jr c, .withdrawn
	ld hl, .bagFullText
	call PrintText
	jr .withdrawLoop
.withdrawn
	ld hl, .withdrawnText
	call PrintText
	jr .withdrawLoop

.nothingToWithdrawText
	text "Nothing to"
	line "withdraw.@"
	text_end
.bagFullText
	text "Bag is full!"
	line "Deposit one"
	cont "first.@"
	text_end
.withdrawnText
	text "Moved to bag.@"
	text_end

; ============================================================
; PlayerPCDepositKeyItems — put a bag key item into PC storage.
; Shows active items. Depositing clears the active bit.
; ============================================================
PlayerPCDepositKeyItems:
	ld hl, wBagPocketsFlags
	res BIT_PRINT_INFO_BOX, [hl]
	set BIT_PC_WITHDRAWING, [hl]
	call LoadScreenTilesFromBuffer2
	call GBPalWhiteOut
	call ClearScreen
.depositLoop
	call GBPalNormal
	call SaveTextBoxTilesToBuffer   ; refresh each iteration
	farcall BuildKeyItemBagList
	ld a, [wKeyItemPocketBuf]
	and a
	jr nz, .depositHasItems
	ld hl, .bagEmptyText
	call PrintText
	jp PlayerPCMenu
.depositHasItems
	ld hl, wKeyItemPocketBuf
	ld a, l
	ld [wListPointer], a
	ld a, h
	ld [wListPointer + 1], a
	xor a
	ld [wPrintItemPrices], a
	ldh [hCurrentMenuItem], a
	ld a, ITEMLISTMENU
	ld [wListMenuID], a
	call DisplayListMenuID
	jp c, PlayerPCMenu
	farcall DepositKeyItem
	ld hl, .depositedText
	call PrintText
	jr .depositLoop

.bagEmptyText
	text "Bag is empty.@"
	text_end
.depositedText
	text "Stored in PC.@"
	text_end