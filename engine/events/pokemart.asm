DisplayPokemartDialogue_::
	ld a, [wListScrollOffset]
	ld [wSavedListScrollOffset], a
	call UpdateSprites
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

	; Open on the pocket the bag was last left on. Key items can't be sold, so
	; that one opens on Recovery instead.
	ld a, [wBagPocketsFlags]
	and POCKET_INDEX_MASK
	cp POCKET_KEY_ITEMS
	jr nz, .tryLastPocket
	ld a, [wBagPocketsFlags]
	and ~POCKET_INDEX_MASK
	ld [wBagPocketsFlags], a   ; POCKET_RECOVERY = 0
.tryLastPocket
	call BuildSellPocketList
	ld a, [hl]                  ; a = count of items in this pocket
	and a
	jr nz, .haveSellItems
	; That pocket is empty, but another may not be: only say the bag is empty
	; when every sellable pocket is. Open on the first one holding something.
	ld a, [wBagPocketsFlags]
	push af                     ; restored if the whole bag turns out empty
	ld e, POCKET_RECOVERY
.findSellablePocket
	ld a, e
	cp POCKET_KEY_ITEMS
	jr z, .nextSellablePocket
	ld a, [wBagPocketsFlags]
	and ~POCKET_INDEX_MASK
	or e
	ld [wBagPocketsFlags], a
	push de                     ; farcall and the builders clobber e
	call BuildSellPocketList
	pop de
	ld a, [hl]
	and a
	jr nz, .foundSellablePocket
.nextSellablePocket
	inc e
	ld a, e
	cp NUM_POCKETS
	jr c, .findSellablePocket
	pop af
	ld [wBagPocketsFlags], a
	jp .bagEmpty
.foundSellablePocket
	pop af                      ; drop the saved pocket, keep the new one
.haveSellItems
	ld hl, PokemonSellingGreetingText
	call PrintText
	call SaveScreenTilesToBuffer1
.resetSellCursor
	xor a
	ldh [hCurrentMenuItem], a
.sellMenuLoop
	call LoadScreenTilesFromBuffer1
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	; Rebuild display list for current pocket
	call BuildSellPocketList
	ld a, l
	ld [wListPointer], a
	ld a, h
	ld [wListPointer + 1], a
	xor a
	ld [wPrintItemPrices], a
	ld a, ITEMLISTMENU
	ld [wListMenuID], a
	call DisplayListMenuID
	jp c, .returnToMainPokemartMenu ; if the player closed the menu
.confirmItemSale ; if the player is trying to sell a specific item
	call IsKeyItem
	ld a, [wIsKeyItem]
	and a
	jr nz, .unsellableItem
	; Quantity and yes/no menus reuse the cursor. Keep the selected row
	; on the stack until the sale is confirmed or cancelled.
	ldh a, [hCurrentMenuItem]
	push af
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
	jp z, .cancelItemSale ; if the player closed the choose quantity menu with the B button
	jr .sellShowPrice
.sellTMConfirm
	ld a, 1
	ld [wItemQuantity], a
	call CalculateItemQuantityPrice
.sellShowPrice
	ld hl, PokemartTellSellPriceText
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
	jp z, .cancelItemSale ; if the player chose No or pressed the B button

; sell item
	pop af ; discard the saved row; a completed sale resets the cursor
	call AddAmountSoldToMoney
	; Route removal: TMs clear bitfield bit; everything else uses count array
	ld a, [wBagPocketsFlags]
	and POCKET_INDEX_MASK
	cp POCKET_TM_PACK
	jr z, .removeTM
	farcall RemovePocketItem
	jp .resetSellCursor
.removeTM
	farcall RemoveTMHM    ; clears sTMBitfield bit for wCurItem
	jp .resetSellCursor
.cancelItemSale
	pop af
	ldh [hCurrentMenuItem], a
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
	xor a
	ld [wMartBuyCursor], a      ; a fresh BUY visit starts at the top
.buyMenuLoop
	farcall MartHideOwnedTMs    ; drop owned TMs/HMs (incl. one just bought); clamps wMartBuyCursor
	call LoadScreenTilesFromBuffer1
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	ld hl, wItemList
	ld a, l
	ld [wListPointer], a
	ld a, h
	ld [wListPointer + 1], a
	ld a, [wMartBuyCursor]      ; back on the row last chosen (wListScrollOffset
	ldh [hCurrentMenuItem], a   ; already survives the loop), not the top
	ld a, 1
	ld [wPrintItemPrices], a
	ld a, PRICEDITEMLISTMENU
	ld [wListMenuID], a
	call DisplayListMenuID
	jr c, .returnToMainPokemartMenu ; if the player closed the menu
	ldh a, [hCurrentMenuItem]   ; the quantity and yes/no menus reuse
	ld [wMartBuyCursor], a      ; hCurrentMenuItem, so keep the row here
	ld a, 99
	ld [wMaxItemQuantity], a
	xor a
	ldh [hHalveItemPrices], a ; don't halve item prices when buying
	call DisplayChooseQuantityMenu
	inc a
	jr z, .buyMenuLoop ; if the player closed the choose quantity menu with the B button
	; Witch prize j (PRIZE_CHEAP_ITEMS): hMoney holds the final computed total
	; here (DisplayChooseQuantityMenu has already summed quantity * unit price),
	; and the quoted price text below, .isThereEnoughMoney, and
	; SubtractAmountPaidFromMoney all read hMoney from this point on - so one
	; discount here covers display, affordability, and payment, and composes
	; on top of whatever produced this total. a is dead here (reloaded from
	; wCurItem next), so the farcall's clobbers are free.
	farcall RogueWitchDiscountBuyPrice
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

; Builds the display list for the sell menu's current pocket (wBagPocketsFlags)
; and returns hl = that pocket's buffer, whose first byte is its item count.
; The key item pocket isn't sellable and builds Recovery instead.
BuildSellPocketList:
	ld a, [wBagPocketsFlags]
	and POCKET_INDEX_MASK
	cp POCKET_STAT
	jr z, .stat
	cp POCKET_VALUABLE
	jr z, .valuable
	cp POCKET_TM_PACK
	jr z, .tm
	farcall BuildRecoveryPocketList
	ld hl, wRecoveryPocketBuf
	ret
.stat
	farcall BuildStatPocketList
	ld hl, wStatPocketBuf
	ret
.valuable
	farcall BuildValuablePocketList
	ld hl, wValuablePocketBuf
	ret
.tm
	farcall BuildTMPocketList
	ld hl, wTMPocketBuf
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
