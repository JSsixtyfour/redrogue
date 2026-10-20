PlayerPC::
	call PlayerPCAllowed
	and a
	ret z
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
	ldh a, [hUILayoutFlags]
	res BIT_DOUBLE_SPACED_MENU, a
	ldh [hUILayoutFlags], a
	ld a, [wParentMenuItem]
	ldh [hCurrentMenuItem], a
	ld hl, wMiscFlags
	set BIT_NO_MENU_BUTTON_SOUND, [hl]
	call LoadScreenTilesFromBuffer2
	hlcoord 0, 0
	ld b, 10
	ld c, $e
	call TextBoxBorder
	call UpdateSprites
	hlcoord 2, 2
	ld de, PlayersPCMenuEntries
	call PlaceString
	farcall BuildKeyItemBagList
	hlcoord 2, 10
	ld de, PlayerPCEquippedText
	call PlaceString
	ld a, [wKeyItemPocketBuf]
	add '0'
	ldcoord_a 11, 10
	ld hl, wTopMenuItemY
	ld a, 2
	ld [hli], a ; wTopMenuItemY
	dec a
	ld [hli], a ; wTopMenuItemX
	inc hl ; wTileBehindCursor
	ld a, 3
	ld [hli], a ; wMaxMenuItem (0=Withdraw, 1=Deposit, 2=Cartridge, 3=LogOff)
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
	dec a
	jp z, PlayerPCCartridgeSwap
	; falls through to ExitPlayerPC for LOG OFF (item 3)

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

; ELEMENT PRISM cartridge swap (custom_functions/element_prism.asm). Returns
; to the PC menu rather than logging off, so the player can swap again or
; check the result.
PlayerPCCartridgeSwap:
	farcall RoguePrismCartridgeMenu
	jp PlayerPCMenu

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;PlayerPCDeposit:
;	xor a
;	ldh [hCurrentMenuItem], a
;	ld [wListScrollOffset], a
;	ld a, [wNumBagItems]
;	and a
;	jr nz, .loop
;	; PC deposit of count-array pocket items is future work — check legacy bag only
    
;	ld hl, NothingToDepositText
;	call PrintText
;	jp PlayerPCMenu
;.loop
;	ld hl, WhatToDepositText
;	call PrintText
;    call SaveTextBoxTilesToBuffer ; marcelnote - for TM printing
;	;;;;;;;;;; marcelnote - check which pocket we were last in, new for bag pockets
;	ld a, [wBagPocketsFlags]
;	bit BIT_KEY_ITEMS_POCKET, a
;	ld hl, wNumBagItems
;	jr z, .gotBagPocket
;	ld hl, wNumBagItems
;.gotBagPocket
;	;;;;;;;;;;
;	ld a, l
;	ld [wListPointer], a
;	ld a, h
;	ld [wListPointer + 1], a
;	xor a
;	ld [wPrintItemPrices], a
;	ld a, ITEMLISTMENU
;	ld [wListMenuID], a
;	call DisplayListMenuID
;	jp c, PlayerPCMenu
;	call IsKeyItem
;	ld a, 1
;	ld [wItemQuantity], a
;	ld a, [wIsKeyItem]
;	and a
;	jr nz, .next
;; if it's not a key item, there can be more than one of the item
;	ld hl, DepositHowManyText
;	call PrintText
;	call DisplayChooseQuantityMenu
;	cp $ff
;	jp z, .loop
;.next
;	ld hl, wNumBoxItems
;	call AddItemToInventory
;	jr c, .roomAvailable
;	ld hl, NoRoomToStoreText
;	call PrintText
;	jp .loop
;.roomAvailable
;	ld hl, wNumBagItems
;	call RemoveItemFromInventory
;	call WaitForSoundToFinish
;	ld a, SFX_WITHDRAW_DEPOSIT
;	call PlaySound
;	call WaitForSoundToFinish
;	ld hl, ItemWasStoredText
;	call PrintText
;	jp .loop

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;PlayerPCWithdraw:
;	xor a
;	ldh [hCurrentMenuItem], a
;	ld [wListScrollOffset], a
;	ld a, [wNumBoxItems]
;	and a
;	jr nz, .loop
;	ld hl, NothingStoredText
;	call PrintText
;	jp PlayerPCMenu
;.loop
;    ;;;;;;;;;; marcelnote - flag if withdrawing from PC (to prevent switching bag pocket), new for bag pockets
;	ld hl, wBagPocketsFlags
;	set BIT_PC_WITHDRAWING, [hl]
;	;;;;;;;;;;
;	ld hl, WhatToWithdrawText
;	call PrintText
;	ld hl, wNumBoxItems
;	ld a, l
;	ld [wListPointer], a
;	ld a, h
;	ld [wListPointer + 1], a
;	xor a
;	ld [wPrintItemPrices], a
;	ld a, ITEMLISTMENU
;	ld [wListMenuID], a
;	call DisplayListMenuID
;	jp c, PlayerPCMenu
;	call IsKeyItem
;	ld a, 1
;	ld [wItemQuantity], a
;	ld a, [wIsKeyItem]
;	and a
;    ld hl, wNumBagItems ; marcelnote - new for bag pockets
;	jr nz, .next
;; if it's not a key item, there can be more than one of the item
;	ld hl, WithdrawHowManyText
;	call PrintText
;	call DisplayChooseQuantityMenu
;	ld hl, wNumBagItems ; marcelnote - moved from below, new for bag pockets
;	cp $ff
;	jp z, .loop
;.next
;	ld hl, wNumBagItems
;	call AddItemToInventory
;	jr c, .roomAvailable
;	ld hl, CantCarryMoreText
;	call PrintText
;	jp .loop
;.roomAvailable
;	;;;;;;;;;; marcelnote - check which pocket we are in, new for bag pockets
;	ld a, [wBagPocketsFlags]
;	bit BIT_KEY_ITEMS_POCKET, a
;	ld hl, wNumBagItems
;	jr z, .gotBagPocket2
;	ld hl, wNumBagItems
;.gotBagPocket2
;	;;;;;;;;;;
;	call RemoveItemFromInventory
;	call WaitForSoundToFinish
;	ld a, SFX_WITHDRAW_DEPOSIT
;	call PlaySound
;	call WaitForSoundToFinish
;	ld hl, WithdrewItemText
;	call PrintText
;	jp .loop

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;PlayerPCToss:
;	xor a
;	ldh [hCurrentMenuItem], a
;	ld [wListScrollOffset], a
;	ld a, [wNumBoxItems]
;	and a
;	jr nz, .loop
;	ld hl, NothingStoredText
;	call PrintText
;	jp PlayerPCMenu
;.loop
;	ld hl, WhatToTossText
;	call PrintText
;	ld hl, wNumBoxItems
;	ld a, l
;	ld [wListPointer], a
;	ld a, h
;	ld [wListPointer + 1], a
;	xor a
;	ld [wPrintItemPrices], a
;	ld a, ITEMLISTMENU
;	ld [wListMenuID], a
;	push hl
;	call DisplayListMenuID
;	pop hl
;	jp c, PlayerPCMenu
;	push hl
;	call IsKeyItem
;	pop hl
;	ld a, 1
;	ld [wItemQuantity], a
;	ld a, [wIsKeyItem]
;	and a
;	jr nz, .next
;; if it's not a key item, there can be more than one of the item
;	push hl
;	ld hl, TossHowManyText
;	call PrintText
;	call DisplayChooseQuantityMenu
;	pop hl
;	cp $ff
;	jp z, .loop
;.next
;	call TossItem ; disallows tossing key items
;	jp .loop

PlayersPCMenuEntries:
	db   "WITHDRAW"
	next "DEPOSIT"
	next "CARTRIDGE"   ; ELEMENT PRISM cartridge swap (custom_functions/element_prism.asm)
	next "LOG OFF@"

TurnedOnPC2Text:
	text_far _TurnedOnPC2Text
	text_end

WhatDoYouWantText:
	text_far _WhatDoYouWantText
	text_end

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;WhatToDepositText:
;	text_far _WhatToDepositText
;	text_end

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;DepositHowManyText:
;	text_far _DepositHowManyText
;	text_end

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;ItemWasStoredText:
;	text_far _ItemWasStoredText
;	text_end

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;NothingToDepositText:
;	text_far _NothingToDepositText
;	text_end

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;NoRoomToStoreText:
;	text_far _NoRoomToStoreText
;	text_end

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;WhatToWithdrawText:
;	text_far _WhatToWithdrawText
;	text_end

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;WithdrawHowManyText:
;	text_far _WithdrawHowManyText
;	text_end

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;WithdrewItemText:
;	text_far _WithdrewItemText
;	text_end

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;NothingStoredText:
;	text_far _NothingStoredText
;	text_end

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;CantCarryMoreText:
;	text_far _CantCarryMoreText
;	text_end

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;WhatToTossText:
;	text_far _WhatToTossText
;	text_end

; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;TossHowManyText:
;	text_far _TossHowManyText
;	text_end

;; TMItContainsText was replaced by item descriptions
;; (custom_functions/item_descriptions.asm)
;	text_end

; ============================================================
; PlayerPCWithdrawKeyItems — take a key item from PC into bag.
; Shows owned-but-not-active items. Blocks if bag already has 3.
; ============================================================
PlayerPCWithdrawKeyItems:
	xor a
	ldh [hCurrentMenuItem], a
	ld [wListScrollOffset], a
	ld hl, wBagPocketsFlags
	res BIT_PRINT_INFO_BOX, [hl]
	set BIT_PC_WITHDRAWING, [hl]   ; block LEFT/RIGHT pocket switching in the list menu
	call LoadScreenTilesFromBuffer2
	call GBPalWhiteOut
	call ClearScreen
.withdrawLoop
	call GBPalNormal
	call PlayerPCBlankTransferText
	farcall BuildKeyItemPCWithdrawList
	ld a, [wKeyItemPocketBuf]
	and a
	jr nz, .withdrawHasItems
	ld hl, .nothingToWithdrawText
	call PrintText
	jp PlayerPCMenu
.withdrawHasItems
	call PlayerPCClampSelection
	ld hl, wKeyItemPocketBuf
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
	ldh a, [hCurrentMenuItem]
	push af
	farcall WithdrawKeyItem
	jr c, .withdrawn
	ld hl, .bagFullText
	call PrintText
	pop af
	ldh [hCurrentMenuItem], a
	jr .withdrawLoop
.withdrawn
	ld hl, .withdrawnText
	call PrintText
	pop af
	ldh [hCurrentMenuItem], a
	jr .withdrawLoop

.nothingToWithdrawText
	text "Nothing to"
	line "withdraw."
	prompt
.bagFullText
	text "Bag is full!"
	line "Deposit one"
	cont "first."
	prompt
.withdrawnText
	text "Moved to bag."
	prompt

; ============================================================
; PlayerPCDepositKeyItems — put a bag key item into PC storage.
; Shows active items. Depositing clears the active bit.
; ============================================================
PlayerPCDepositKeyItems:
	xor a
	ldh [hCurrentMenuItem], a
	ld [wListScrollOffset], a
	ld hl, wBagPocketsFlags
	res BIT_PRINT_INFO_BOX, [hl]
	set BIT_PC_WITHDRAWING, [hl]
	call LoadScreenTilesFromBuffer2
	call GBPalWhiteOut
	call ClearScreen
.depositLoop
	call GBPalNormal
	call PlayerPCBlankTransferText
	farcall BuildKeyItemBagList
	ld a, [wKeyItemPocketBuf]
	and a
	jr nz, .depositHasItems
	ld hl, .bagEmptyText
	call PrintText
	jp PlayerPCMenu
.depositHasItems
	call PlayerPCClampSelection
	ld hl, wKeyItemPocketBuf
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
	ldh a, [hCurrentMenuItem]
	push af
	farcall DepositKeyItem
	ld hl, .depositedText
	call PrintText
	pop af
	ldh [hCurrentMenuItem], a
	jr .depositLoop

.bagEmptyText
	text "Bag is empty."
	prompt
.depositedText
	text "Stored in PC."
	prompt

PlayerPCEquippedText:
	db "EQUIPPED  /3@"

; List feedback must not become the next iteration's description background.
PlayerPCBlankTransferText:
	ld hl, wTextBoxBuffer
	ld bc, 36
	ld a, ' '
	jp FillMemory

; Preserve the current window unless its selected item vanished.
; Nonempty wKeyItemPocketBuf, list cursor is at most row two.
PlayerPCClampSelection:
	ld a, [wKeyItemPocketBuf]
	ld b, a
	ld a, [wListScrollOffset]
	ld c, a
	ldh a, [hCurrentMenuItem]
	add c
	cp b
	ret c
	dec b
	ld a, b
	sub c
	jr nc, .cursor
	ld a, b
	ld [wListScrollOffset], a
	xor a
.cursor
	ldh [hCurrentMenuItem], a
	ret

; Query the final equipped state, rather than transient grant scratch RAM.
PrismShowGrantDestination::
	ld a, [wCurItem]
	push af
	ld a, ELEMENT_PRISM
	ld [wCurItem], a
	farcall IsKeyItemActive
	ld hl, .stored
	jr z, .print
	ld hl, .equipped
.print
	pop af
	ld [wCurItem], a
	jp PrintText
.equipped
	text "Equipped in bag."
	prompt
.stored
	text "Sent to Dorm PC."
	prompt

; Personal storage is permanent in the Dorm and temporary at three lobby
; arrivals. All callers, including direct PC text scripts, use this guard.
PlayerPCAllowed::
	ldh a, [hCurMap]
	cp SILPH_CO_DORM
	jr z, LobbyKeySwapOpen.open
	; fall through

; A = 1/NZ when open, 0/Z otherwise. No new saved state: the source map is
; already save-backed and WarpFound2 replaces it on every departure/return.
; Thus even returning from the next gym before fighting cannot reopen access.
LobbyKeySwapOpen::
	ldh a, [hCurMap]
	cp INDIGO_PLATEAU_LOBBY
	jr nz, .closed
	ld a, [wWarpedFromWhichMap]
	cp REWARD_ROOM
	jr z, .pair
	cp VICTORY_ROAD_1F
	jr nz, .closed
	ld a, [wObtainedBadges]
	cp $ff
	jr nz, .closed
	CheckEvent EVENT_VICTORY_ROAD_CLEARED
	jr z, .closed
	ld a, [wBattleCount]
	cp E4_FIRST_BATTLECOUNT
	jr z, .open
	jr .closed
.pair
	; This also runs inside sprite updates: keep the count in registers,
	; without overwriting the caller's shared wNumSetBits scratch byte.
	ld a, [wObtainedBadges]
	ld c, a
	ld b, 0
.countBadges
	srl c
	jr nc, .nextBadge
	inc b
.nextBadge
	ld a, c
	and a
	jr nz, .countBadges
	ld a, b
	cp PAIR_BADGES_A
	jr z, .firstPair
	cp PAIR_BADGES_B
	jr nz, .closed
	ld a, [wBattleCount]
	cp PAIR_BADGES_B * ROUND_BATTLES + FIRST_GYM_STEP
	jr z, .open
	jr .closed
.firstPair
	ld a, [wBattleCount]
	cp PAIR_BADGES_A * ROUND_BATTLES + FIRST_GYM_STEP
	jr nz, .closed
.open
	ld a, 1
	and a
	ret
.closed
	xor a
	ret

; Dynamic IsObjectHidden override, like the stage-slot overrides. No global
; toggle index is added or renumbered, so existing save flags remain intact.
LobbyKeySwapObjectHidden::
	call LobbyKeySwapOpen
	xor 1
	ldh [hIsToggleableObjectOff], a
	ret

; Called only from the lobby's fresh-entry block, after stage selection.
LobbyKeySwapAnnounce::
	call LobbyKeySwapOpen
	and a
	ret z
	call UpdateSprites
	ld a, TEXT_LOBBY_KEY_SWAP_ANNOUNCEMENT
	ldh [hTextID], a
	jp DisplayTextID

LobbyKeySwapTalk::
	call LobbyKeySwapOpen
	and a
	ret z
	call SaveScreenTilesToBuffer2
	jp PlayerPC

_LobbyKeySwapAnnouncementText::
	text "KEY ITEM SWAP"
	line "NOW AVAILABLE!"
	para "See the attendant"
	line "beside the PC."
	done
