DisplayPokemartDialogue_::
	ld a, [wListScrollOffset]
	ld [wSavedListScrollOffset], a
	call UpdateSprites
	xor a
	ld [wBoughtOrSoldItemInMart], a
.loop
	xor a
	ld [wListScrollOffset], a
	ldh [hCurrentMenuItem], a
	ld [wPlayerMonNumber], a
	inc a
	ld [wPrintItemPrices], a
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ld a, BUY_SELL_QUIT_MENU
	ld [wTextBoxID], a
	call DisplayTextBoxID

; This code is useless. It copies the address of the pokemart's inventory to hl,
; but the address is never used.
	ld hl, wItemListPointer
	ld a, [hli]
	ld l, [hl]
	ld h, a

	ld a, [wMenuExitMethod]
	cp CANCELLED_MENU
	jp z, .done
	ld a, [wChosenMenuItem]
	and a ; buying?
	jp z, .buyMenu
	dec a ; selling?
	jp z, .sellMenu
	dec a ; quitting?
	jp z, .done
.sellMenu
	call SaveTextBoxTilesToBuffer   ; capture "Take your time." so PrintBagInfoText
	call Delay3                     ; restoreDefaultText path has correct data
; the same variables are set again below, so this code has no effect
	;xor a
	;ld [wPrintItemPrices], a
	ld a, INIT_BAG_ITEM_LIST
	ld [wInitListType], a
	callfar InitList

	; Build the current pocket's display list and check if anything to sell.
	; Recovery pocket is the default sell pocket (potions, etc. are most sellable).
	ld a, [wBagPocketsFlags]
	and POCKET_INDEX_MASK
	cp POCKET_RECOVERY
	jr z, .sellRecovery
	cp POCKET_STAT
	jr z, .sellStat
	cp POCKET_VALUABLE
	jr z, .sellValuable
	cp POCKET_TM_PACK
	jr z, .sellTM
	; Key items can't be sold — redirect to Recovery
	xor a
	ld [wBagPocketsFlags], a   ; switch to Recovery pocket
.sellRecovery
	farcall BuildRecoveryPocketList
	ld hl, wRecoveryPocketBuf
	jr .checkSellEmpty
.sellStat
	farcall BuildStatPocketList
	ld hl, wStatPocketBuf
	jr .checkSellEmpty
.sellValuable
	farcall BuildValuablePocketList
	ld hl, wValuablePocketBuf
	jr .checkSellEmpty
.sellTM
	farcall BuildTMPocketList
	ld hl, wTMPocketBuf
.checkSellEmpty
	ld a, [hl]                  ; a = count of items in this pocket
	and a
	jp z, .bagEmpty
	ld hl, PokemonSellingGreetingText
	call PrintText
	call SaveScreenTilesToBuffer1
.sellMenuLoop
	call LoadScreenTilesFromBuffer1
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	; Rebuild display list for current pocket
	ld a, [wBagPocketsFlags]
	and POCKET_INDEX_MASK
	cp POCKET_STAT
	jr z, .sellDisplayStat
	cp POCKET_VALUABLE
	jr z, .sellDisplayValuable
	cp POCKET_TM_PACK
	jr z, .sellDisplayTM
	farcall BuildRecoveryPocketList
	ld hl, wRecoveryPocketBuf
	jr .gotSellSource
.sellDisplayStat
	farcall BuildStatPocketList
	ld hl, wStatPocketBuf
	jr .gotSellSource
.sellDisplayValuable
	farcall BuildValuablePocketList
	ld hl, wValuablePocketBuf
	jr .gotSellSource
.sellDisplayTM
	farcall BuildTMPocketList
	ld hl, wTMPocketBuf
.gotSellSource
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
	jp c, .returnToMainPokemartMenu ; if the player closed the menu
.confirmItemSale ; if the player is trying to sell a specific item
	call IsKeyItem
	ld a, [wIsKeyItem]
	and a
	jr nz, .unsellableItem
	ld a, PRICEDITEMLISTMENU
	ld [wListMenuID], a
	ldh [hHalveItemPrices], a ; halve prices when selling
	; TMs are always qty 1 — skip quantity menu
	ld a, [wBagPocketsFlags]
	and POCKET_INDEX_MASK
	cp POCKET_TM_PACK
	jr z, .sellTMConfirm
	call DisplayChooseQuantityMenu
	inc a
	jp z, .sellMenuLoop ; if the player closed the choose quantity menu with the B button
	jr .sellShowPrice
.sellTMConfirm
	ld a, 1
	ld [wItemQuantity], a
.sellShowPrice
	ld hl, PokemartTellSellPriceText
	lb bc, 14, 1 ; location that PrintText always prints to, this is useless
	call PrintText
	hlcoord 14, 7
	lb bc, 8, 15
    xor a               ; NOLISTMENU
    ld [wListMenuID], a ; marcelnote - for TM printing
	ld a, TWO_OPTION_MENU
	ld [wTextBoxID], a
	call DisplayTextBoxID ; yes/no menu
	ld a, [wMenuExitMethod]
	cp CHOSE_SECOND_ITEM
	jp z, .sellMenuLoop ; if the player chose No or pressed the B button

; The following code is supposed to check if the player chose No, but the above
; check already catches it.
	ld a, [wChosenMenuItem]
	dec a
	jp z, .sellMenuLoop

; sell item
	ld a, [wBoughtOrSoldItemInMart]
	and a
	jr nz, .skipSettingFlag1
	inc a
	ld [wBoughtOrSoldItemInMart], a
.skipSettingFlag1
	call AddAmountSoldToMoney
	; Route removal: TMs clear bitfield bit; everything else uses count array
	ld a, [wBagPocketsFlags]
	and POCKET_INDEX_MASK
	cp POCKET_TM_PACK
	jr z, .removeTM
	farcall RemovePocketItem
	jp .sellMenuLoop
.removeTM
	farcall RemoveTMHM    ; clears sTMBitfield bit for wCurItem
	jp .sellMenuLoop
.unsellableItem
	ld hl, PokemartUnsellableItemText
	call PrintText
	jp .returnToMainPokemartMenu
.bagEmpty
	ld hl, PokemartItemBagEmptyText
	call PrintText
	call SaveScreenTilesToBuffer1
	jp .returnToMainPokemartMenu
.buyMenu

; the same variables are set again below, so this code has no effect
	ld a, 1
	ld [wPrintItemPrices], a
	ld a, INIT_OTHER_ITEM_LIST
	ld [wInitListType], a
	callfar InitList



	ld hl, PokemartBuyingGreetingText
	call PrintText
    call SaveTextBoxTilesToBuffer ; marcelnote - for TM printing
    call Delay3
	call SaveScreenTilesToBuffer1
.buyMenuLoop
	call LoadScreenTilesFromBuffer1
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ld hl, wItemList
	ld a, l
	ld [wListPointer], a
	ld a, h
	ld [wListPointer + 1], a
	xor a
	ldh [hCurrentMenuItem], a
	inc a
	ld [wPrintItemPrices], a
	ld a, PRICEDITEMLISTMENU
	ld [wListMenuID], a
	call DisplayListMenuID
	jr c, .returnToMainPokemartMenu ; if the player closed the menu
	ld a, 99
	ld [wMaxItemQuantity], a
	xor a
	ldh [hHalveItemPrices], a ; don't halve item prices when buying
	call DisplayChooseQuantityMenu
	inc a
	jr z, .buyMenuLoop ; if the player closed the choose quantity menu with the B button
	ld a, [wCurItem]
	ld [wNamedObjectIndex], a
	call GetItemName
	call CopyToStringBuffer
	ld hl, PokemartTellBuyPriceText
	call PrintText
	hlcoord 14, 7
	lb bc, 8, 15
	ld a, TWO_OPTION_MENU
	ld [wTextBoxID], a
	call DisplayTextBoxID ; yes/no menu
	ld a, [wMenuExitMethod]
	cp CHOSE_SECOND_ITEM
	jp z, .buyMenuLoop ; if the player chose No or pressed the B button

; The following code is supposed to check if the player chose No, but the above
; check already catches it.
	ld a, [wChosenMenuItem]
	dec a
	jr z, .buyMenuLoop

; buy item — route through GiveItem so it lands in the correct pocket
	call .isThereEnoughMoney
	jr c, .notEnoughMoney
	ld a, [wCurItem]       ; GiveItem reads wCurItem (farcall clobbers b)
	ld b, a
	ld a, [wItemQuantity]  ; GiveItem reads wItemQuantity (farcall clobbers c)
	ld c, a
	call GiveItem          ; HOME function, plain call OK; routes to correct pocket
	jr nc, .bagFull
	call SubtractAmountPaidFromMoney
	ld a, [wBoughtOrSoldItemInMart]
	and a
	jr nz, .skipSettingFlag2
	ld a, 1
	ld [wBoughtOrSoldItemInMart], a
.skipSettingFlag2
	ld a, SFX_PURCHASE
	call PlaySoundWaitForCurrent
	call WaitForSoundToFinish
	ld hl, PokemartBoughtItemText
	call PrintText
	jp .buyMenuLoop
.returnToMainPokemartMenu
	call LoadScreenTilesFromBuffer1
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ld hl, PokemartAnythingElseText
	call PrintText
	jp .loop
.isThereEnoughMoney
	ld de, wPlayerMoney
	ld hl, hMoney
	ld c, 3 ; length of money in bytes
	jp StringCmp
.notEnoughMoney
	ld hl, PokemartNotEnoughMoneyText
	call PrintText
	jr .returnToMainPokemartMenu
.bagFull
	ld hl, PokemartItemBagFullText
	call PrintText
	jr .returnToMainPokemartMenu
.done
	ld hl, PokemartThankYouText
	call PrintText
	ld a, 1
	ldh [hUpdateSpritesEnabled], a
	call UpdateSprites
	ld a, [wSavedListScrollOffset]
	ld [wListScrollOffset], a
	ret

PokemartBuyingGreetingText:
	text_far _PokemartBuyingGreetingText
	text_end

PokemartTellBuyPriceText:
	text_far _PokemartTellBuyPriceText
	text_end

PokemartBoughtItemText:
	text_far _PokemartBoughtItemText
	text_end

PokemartNotEnoughMoneyText:
	text_far _PokemartNotEnoughMoneyText
	text_end

PokemartItemBagFullText:
	text_far _PokemartItemBagFullText
	text_end

PokemonSellingGreetingText:
	text_far _PokemonSellingGreetingText
	text_end

PokemartTellSellPriceText:
	text_far _PokemartTellSellPriceText
	text_end

PokemartItemBagEmptyText:
	text_far _PokemartItemBagEmptyText
	text_end

PokemartUnsellableItemText:
	text_far _PokemartUnsellableItemText
	text_end

PokemartThankYouText:
	text_far _PokemartThankYouText
	text_end

PokemartAnythingElseText:
	text_far _PokemartAnythingElseText
	text_end
