; engine/events/credit_mart.asm
;
; The three Credit Exchange vendors, reached from the CreditExchange map via
; script_credit_vendor. The vendor index comes from hTextID, exactly the way
; GetPrizeMenuId derives its window in engine/events/prize_menu.asm:
;
;   0 = key item seller  - the ten purchasable key items, prices shown inline
;   1 = upgrade seller   - owned key items below max tier
;   2 = room upgrades    - stub until the room system exists
;
; Currency is wPlayerCoins (the old Game Corner coin counter), so HasEnoughCoins
; and SubBCDPredef are reused unchanged. Costs are BCD throughout.
;
; Why the upgrade vendor quotes its price in text instead of an inline column:
; GetItemPrice can only key off an item id, but an upgrade's cost depends on the
; item's CURRENT tier, so the same id has three different prices over its life.
; Rather than rebuild a price table in RAM every redraw, the upgrade list runs
; with wPrintItemPrices = 0 and the cost appears in the confirmation box.

DEF CREDIT_VENDOR_ITEMS    EQU 0
DEF CREDIT_VENDOR_UPGRADES EQU 1
DEF CREDIT_VENDOR_ROOMS    EQU 2

; Internal tiers are 0-based; everything the player sees adds 1, so internal
; 0/1/2 display as TIER 1/2/3 and TIER 1 is the base state an item is bought
; in. Capping here at 2 therefore means two purchasable upgrades. The cost
; tables below still carry a third column - raise this to 3 to light it up.
DEF MAX_KEY_ITEM_TIER EQU 2

CreditVendorMenu::
	ldh a, [hTextID]
	sub TEXT_CREDITEXCHANGE_VENDOR_1
	ld [wWhichPrizeWindow], a
	cp CREDIT_VENDOR_ROOMS
	jr nz, .open
	ld hl, CreditRoomVendorClosedText
	jp PrintText

.open
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	call BuildCreditVendorList
	ld a, [wCreditItemList]
	and a
	jr nz, .haveStock

	; nothing to offer - say so instead of opening an empty menu
	ld a, [wWhichPrizeWindow]
	and a
	ld hl, CreditNothingToSellText
	jr z, .printAndExit
	ld hl, CreditNothingToUpgradeText
.printAndExit
	call PrintText
	jr .exit

.haveStock
	ld hl, CreditVendorGreetingText
	call PrintText
	ld a, INIT_OTHER_ITEM_LIST
	ld [wInitListType], a
	callfar InitList              ; sets wNameListType = ITEM_NAME for GetItemName
	call SaveScreenTilesToBuffer1

.menuLoop
	call LoadScreenTilesFromBuffer1
	call PrintCreditBalanceBox
	call PointListAtCreditStock
	xor a
	ldh [hCurrentMenuItem], a
	ld [wListScrollOffset], a
	call DisplayListMenuID
	jr c, .exit                   ; player backed out with B

	ld a, [wWhichPrizeWindow]
	and a
	jr nz, .doUpgrade
	call CreditBuyItem
	jr .afterPurchase
.doUpgrade
	call CreditBuyUpgrade
.afterPurchase
	; the purchased entry drops off the list (owned, or now max tier), so
	; rebuild and bail out if that emptied the shelf
	call BuildCreditVendorList
	ld a, [wCreditItemList]
	and a
	jr z, .exit
	; Re-establish the greeting and re-snapshot the screen. YesNoChoice
	; (home/yes_no.asm) calls SaveScreenTilesToBuffer1 itself on the way in, so
	; by now buffer 1 holds the "So, you want X?" confirmation rather than the
	; clean shopfront - without this the loop restores that stale prompt and it
	; sits under the menu for the rest of the visit. The Pokemart never hits
	; this because it confirms with TWO_OPTION_MENU instead of YesNoChoice.
	ld hl, CreditVendorGreetingText
	call PrintText
	call SaveScreenTilesToBuffer1
	jr .menuLoop

.exit
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	ret

; ============================================================
; PointListAtCreditStock — aim the list menu at our own stock buffer and,
; for the item seller, at the credit price table. Redone every redraw
; because DisplayListMenuID and InitList both overwrite these.
; ============================================================
PointListAtCreditStock:
	ld hl, wCreditItemList
	ld a, l
	ld [wListPointer], a
	ld a, h
	ld [wListPointer + 1], a
	ld a, CREDITLISTMENU          ; 1 byte per entry, and no bag info box
	ld [wListMenuID], a
	ld a, [wWhichPrizeWindow]
	and a
	ld a, 0                       ; ld does not disturb the flags set above
	jr nz, .noPriceColumn
	ld a, 2                       ; 2 = credit format (see home/list_menu.asm)
.noPriceColumn
	ld [wPrintItemPrices], a
	; bias the table so item $66 resolves to CreditItemPrices' first row
	ld bc, CreditItemPrices - (SHINY_CHARM - 1) * 3
	ld a, c
	ld [wItemPrices], a
	ld a, b
	ld [wItemPrices + 1], a
	ret

; ============================================================
; PrintCreditBalanceBox — the balance counter, modelled on PrintPrizePrice
; (engine/events/prize_menu.asm). "CREDIT" is 6 characters, which is exactly
; what fits the 7-wide box; "CREDITS" does not.
; ============================================================
PrintCreditBalanceBox:
	hlcoord 11, 0
	ld b, 1
	ld c, 7
	call TextBoxBorder
	call UpdateSprites
	hlcoord 12, 0
	ld de, .CreditString
	call PlaceString
	hlcoord 13, 1
	ld de, .BlankString
	call PlaceString
	hlcoord 13, 1
	ld de, wPlayerCoins
	ld c, 2 | LEADING_ZEROES
	call PrintBCDNumber
	ret

.CreditString:
	db "CREDIT@"
.BlankString:
	db "      @"

; ============================================================
; CreditBuyItem — sell wCurItem to the player for its credit price.
; ============================================================
CreditBuyItem:
	call LoadCreditPriceOfCurItem
	call HasEnoughCoins
	jr c, .notEnough
	ld a, [wCurItem]
	ld [wNamedObjectIndex], a
	call GetItemName              ; fills wNameBuffer for the confirm text
	ld hl, CreditBuyConfirmText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ret nz                        ; declined

	ld a, [wCurItem]
	ld b, a                       ; GiveItem reads b/c, and it is a HOME routine
	ld c, 1
	call GiveItem                 ; routes into the key items pocket
	; Carry clear here does NOT mean failure for a key item - the grant always
	; succeeds, and clear just means all 3 active slots were taken so it went to
	; the PC. Either way the player owns it, so the sale completes and the
	; credits come out; only the closing message differs.
	push af
	call LoadCreditPriceOfCurItem ; GiveItem may have disturbed hCoins
	call SubtractCredits
	ld a, SFX_PURCHASE
	call PlaySoundWaitForCurrent
	call WaitForSoundToFinish
	pop af
	ld hl, CreditBoughtText
	jp c, PrintText
	ld hl, CreditSentToPCText
	jp PrintText
.notEnough
	ld hl, CreditNotEnoughText
	jp PrintText

; ============================================================
; LoadCreditPriceOfCurItem — hCoins = credit cost of wCurItem, 2-byte BCD.
; GetItemPrice honours the redirected wItemPrices and handles its own
; bankswitch, leaving a 3-byte BCD value at hItemPrice; credits never exceed
; four digits, so the top byte is dropped.
; ============================================================
LoadCreditPriceOfCurItem:
	call GetItemPrice
	xor a
	ldh [hUnusedCoinsByte], a
	ldh a, [hItemPrice + 1]
	ldh [hCoins], a
	ldh a, [hItemPrice + 2]
	ldh [hCoins + 1], a
	ret

; ============================================================
; SubtractCredits — wPlayerCoins -= hCoins (both 2-byte BCD).
; Same call shape prize_menu.asm uses to charge for a prize.
; ============================================================
SubtractCredits:
	ld hl, hCoins + 1
	ld de, wPlayerCoins + 1
	ld c, 2
	predef SubBCDPredef
	ret

; ============================================================
; CreditBuyUpgrade — raise wCurItem's tier by one.
; ============================================================
CreditBuyUpgrade:
	call FindUpgradeRowForCurItem ; hl = row, c = key item index
	ret nc
	push hl
	push bc
	call GetKeyItemTier           ; a = current tier
	pop bc
	pop hl
	push bc
	push af
	; cost = row[2 + tier], stored as 1-byte BCD
	ld b, 0
	ld c, a
	inc hl
	inc hl                        ; hl = &row.costs[0]
	add hl, bc
	ld a, [hl]
	ld c, a
	xor a
	ldh [hUnusedCoinsByte], a
	ldh [hCoins], a
	ld a, c
	ldh [hCoins + 1], a
	call HasEnoughCoins
	jr c, .notEnough

	ld a, [wCurItem]
	ld [wNamedObjectIndex], a
	call GetItemName
	ld hl, CreditUpgradeConfirmText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jr nz, .declined

	pop af
	inc a                         ; new internal tier
	push af
	inc a                         ; +1 again: displayed tier is internal + 1
	; stash for CreditUpgradedText's text_bcd - wCreditItemList's last byte is
	; spare scratch (17 owned-item bytes is the true worst case, buffer is 18)
	ld [wCreditItemList + 17], a
	pop af
	pop bc                        ; c = key item index
	call SetKeyItemTier
	call SubtractCredits
	call ApplyKeyItemTierEffects
	ld a, SFX_PURCHASE
	call PlaySoundWaitForCurrent
	call WaitForSoundToFinish
	ld hl, CreditUpgradedText
	jp PrintText
.declined
	pop af
	pop bc
	ret
.notEnough
	pop af
	pop bc
	ld hl, CreditNotEnoughText
	jp PrintText

; ============================================================
; BuildCreditVendorList — fill wCreditItemList for the active vendor.
; Format matches a mart list: count, one-byte ids, $ff terminator.
; ============================================================
BuildCreditVendorList:
	ld hl, wCreditItemList
	inc hl                        ; leave room for the count
	ld d, 0                       ; d = running count
	ld a, [wWhichPrizeWindow]
	and a
	jr nz, .upgrades

	; --- seller: every purchasable item the player does not already own ---
	ld bc, CreditSaleTable
.saleLoop
	ld a, [bc]
	cp $ff
	jr z, .done
	ld e, a                       ; e = item id
	inc bc
	ld a, [bc]                    ; a = key item index
	inc bc                        ; bc = next row (rows are 2 bytes)
	push bc
	ld c, a
	call IsKeyItemOwnedLocal      ; preserves hl/de, returns Z = not owned
	pop bc
	jr nz, .saleLoop              ; already owned, skip
	ld a, e
	ld [hli], a
	inc d
	jr .saleLoop

	; --- upgrades: every key item in the bag still below max tier ---
.upgrades
	ld bc, CreditUpgradeTable
.upgradeLoop
	ld a, [bc]
	cp $ff
	jr z, .done
	ld e, a                       ; e = item id
	inc bc
	ld a, [bc]                    ; a = key item index
	inc bc
	inc bc
	inc bc
	inc bc                        ; bc = next row (rows are 5 bytes)
	push bc
	ld c, a                       ; c = key item index, kept across both calls
	call IsKeyItemOwnedLocal      ; owned, not active - PC items upgrade too
	jr z, .upgradeNext            ; not owned at all
	call GetKeyItemTier
	cp MAX_KEY_ITEM_TIER
	jr nc, .upgradeNext           ; already maxed
	ld a, e
	ld [hli], a
	inc d
.upgradeNext
	pop bc
	jr .upgradeLoop

.done
	ld [hl], $ff
	ld a, d
	ld [wCreditItemList], a
	ret

; ============================================================
; FindUpgradeRowForCurItem — locate wCurItem's row in CreditUpgradeTable.
; OUTPUT: carry set + hl = row, c = key item index; carry clear if absent.
; ============================================================
FindUpgradeRowForCurItem:
	ld a, [wCurItem]
	ld e, a
	ld hl, CreditUpgradeTable
.loop
	ld a, [hl]
	cp $ff
	jr z, .notFound
	cp e
	jr z, .found
	ld bc, 5
	add hl, bc
	jr .loop
.found
	inc hl
	ld a, [hl]
	ld c, a                       ; c = key item index
	dec hl
	scf
	ret
.notFound
	and a
	ret

; ============================================================
; SRAM helpers. These read sKeyItemsBitfield / sKeyItemTiers directly rather
; than farcalling key_item_pocket.asm: farcall's Bankswitch clobbers bc on the
; way back, so IsKeyPocketItem's "own bit in c" return value cannot survive the
; trip out of this bank.
;
; Both arrays are indexed the same way - key item N owns bits 2N and 2N+1 of
; byte N>>2 - so all three helpers share the same address math.
;
; All three preserve hl, de and bc, returning only in a (plus flags). This is
; load-bearing, not politeness: BuildCreditVendorList calls them inside a loop
; while holding its output write pointer in hl, its running count in d and its
; table cursor in bc. An earlier version let the address math scribble on hl,
; which sent the list writes to a garbage address - the list rendered as rows
; of "888?" with a nonsense entry count.
; ============================================================

; INPUT: c = key item index. OUTPUT: Z = not owned, NZ = owned.
; "Owned" spans bag AND PC, which is what both vendors want: the seller must
; not offer a second copy of something already in the PC, and the upgrade
; vendor upgrades by ownership, so a PC-stored item is still upgradeable.
IsKeyItemOwnedLocal:
	push hl
	push de
	push bc
	ld de, sKeyItemsBitfield
	call CreditReadKeyBits
	and 1                         ; even bit of the pair = owned
	pop bc
	pop de
	pop hl
	ret                           ; pops do not disturb the Z flag set above

; INPUT: c = key item index. OUTPUT: a = tier (0-3).
GetKeyItemTier:
	push hl
	push de
	push bc
	ld de, sKeyItemTiers
	call CreditReadKeyBits
	and 3
	pop bc
	pop de
	pop hl
	ret

; INPUT: c = key item index, de = array base. OUTPUT: a = that item's bit pair,
; shifted down to bits 0-1. Clobbers hl/bc - callers above own the save/restore.
CreditReadKeyBits:
	ld a, c
	and 3
	add a
	ld b, a                       ; b = shift = (index & 3) * 2
	ld a, c
	srl a
	srl a
	ld l, a                       ; byte offset = index >> 2
	ld h, 0
	add hl, de
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, [hl]
	ld c, a
	xor a
	ld [rRAMG], a                 ; never leave SRAM enabled across a return
	ld a, c
	inc b
.shiftLoop
	dec b
	ret z
	srl a
	jr .shiftLoop

; INPUT: c = key item index, a = new tier (0-3).
SetKeyItemTier:
	push hl
	push de
	push bc
	ld e, a                       ; e = new tier
	ld a, c
	and 3
	add a
	ld b, a                       ; b = shift
	ld a, c
	srl a
	srl a
	ld l, a
	ld h, 0
	ld d, HIGH(sKeyItemTiers)
	ld a, LOW(sKeyItemTiers)
	add l
	ld l, a
	ld a, d
	adc h
	ld h, a                       ; hl = &sKeyItemTiers[index >> 2]
	; shift the new tier and its mask into position
	ld c, e                       ; c = tier value
	ld d, 3                       ; d = mask
	inc b
.shiftLoop
	dec b
	jr z, .apply
	sla c
	sla d
	jr .shiftLoop
.apply
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, d
	cpl
	and [hl]                      ; clear the old 2-bit field
	or c                          ; drop the new tier in
	ld [hl], a
	xor a
	ld [rRAMG], a
	pop bc
	pop de
	pop hl
	ret

; ============================================================
; ApplyKeyItemTierEffects — re-derive the WRAM caches the battle//end-of-battle
; code reads from the tiers now stored in SRAM. sKeyItemTiers is the source of
; truth; these bytes are just a fast copy, refreshed here so an upgrade takes
; effect immediately rather than at the next run boundary.
;
; LEFTOVERS and PP_TONIC heal maxHP/(16 - level), so the tier maps onto the
; level curve 0/2/4/8 -> 1/16, 1/14, 1/12, 1/8.
; ============================================================
ApplyKeyItemTierEffects:
	ld c, KEY_ITEM_BIT_LEFTOVERS_OWNED / 2
	call GetKeyItemTier
	call TierToHealLevel
	ld [wHealAllItemLevel], a

	ld c, KEY_ITEM_BIT_PP_TONIC_OWNED / 2
	call GetKeyItemTier
	call TierToHealLevel
	ld [wRestorePPItemLevel], a

	ld c, KEY_ITEM_BIT_KO_DEFIANCE_OWNED / 2
	call GetKeyItemTier
	inc a                         ; charges = 1 + tier
	ld [wKODefianceUsages], a

	ld c, KEY_ITEM_BIT_EXP_ALL_OWNED / 2
	call GetKeyItemTier
	ld [wExpAllLevel], a
	ret

TierToHealLevel:
	ld hl, .Table
	ld b, 0
	ld c, a
	add hl, bc
	ld a, [hl]
	ret
.Table:
	db 0, 2, 4, 8

; ============================================================
; Data tables.
;
; The key item index column MUST stay in step with KeyItemPocketTable's row
; order in custom_functions/key_item_pocket.asm - that order is what defines
; each item's bit pair in sKeyItemsBitfield and sKeyItemTiers.
; ============================================================

; item id, key item index
CreditSaleTable:
	db SHINY_CHARM,   KEY_ITEM_BIT_SHINY_CHARM_OWNED / 2
	db AMULET_COIN,   KEY_ITEM_BIT_AMULET_COIN_OWNED / 2
	db TURN_REWIND,   KEY_ITEM_BIT_TURN_REWIND_OWNED / 2
	db RARE_SCOPE,    KEY_ITEM_BIT_RARE_SCOPE_OWNED / 2
	db RARE_LENS,     KEY_ITEM_BIT_RARE_LENS_OWNED / 2
	db IV_BOOSTER,    KEY_ITEM_BIT_IV_BOOSTER_OWNED / 2
	db STAT_BOOSTER,  KEY_ITEM_BIT_STAT_BOOSTER_OWNED / 2
	db DOOR_DICE,     KEY_ITEM_BIT_DOOR_DICE_OWNED / 2
	db MON_DICE,      KEY_ITEM_BIT_MON_DICE_OWNED / 2
	db ITEM_DICE,     KEY_ITEM_BIT_ITEM_DICE_OWNED / 2
	db $ff

; item id, key item index, cost to reach tier 1 / 2 / 3 (1-byte BCD each)
CreditUpgradeTable:
	db LEFTOVERS,     KEY_ITEM_BIT_LEFTOVERS_OWNED / 2,     $10, $20, $40
	db PP_TONIC,      KEY_ITEM_BIT_PP_TONIC_OWNED / 2,      $10, $20, $40
	db KO_DEFIANCE,   KEY_ITEM_BIT_KO_DEFIANCE_OWNED / 2,   $20, $40, $80
	db EXP_ALL,       KEY_ITEM_BIT_EXP_ALL_OWNED / 2,       $15, $30, $60
	db SHINY_CHARM,   KEY_ITEM_BIT_SHINY_CHARM_OWNED / 2,   $30, $60, $99
	db AMULET_COIN,   KEY_ITEM_BIT_AMULET_COIN_OWNED / 2,   $15, $30, $60
	db TURN_REWIND,   KEY_ITEM_BIT_TURN_REWIND_OWNED / 2,   $25, $50, $75
	db RARE_SCOPE,    KEY_ITEM_BIT_RARE_SCOPE_OWNED / 2,    $20, $40, $80
	db RARE_LENS,     KEY_ITEM_BIT_RARE_LENS_OWNED / 2,     $20, $40, $80
	db IV_BOOSTER,    KEY_ITEM_BIT_IV_BOOSTER_OWNED / 2,    $25, $50, $75
	db STAT_BOOSTER,  KEY_ITEM_BIT_STAT_BOOSTER_OWNED / 2,  $20, $40, $80
	db DOOR_DICE,     KEY_ITEM_BIT_DOOR_DICE_OWNED / 2,     $15, $30, $60
	db MON_DICE,      KEY_ITEM_BIT_MON_DICE_OWNED / 2,      $15, $30, $60
	db ITEM_DICE,     KEY_ITEM_BIT_ITEM_DICE_OWNED / 2,     $15, $30, $60
	db ELEMENT_PRISM, KEY_ITEM_BIT_ELEMENT_PRISM_OWNED / 2, $20, $40, $80
	db $ff

CreditVendorGreetingText:
	text_far _CreditVendorGreetingText
	text_end

CreditBuyConfirmText:
	text_far _CreditBuyConfirmText
	text_end

CreditBoughtText:
	text_far _CreditBoughtText
	text_waitbutton
	text_end

CreditUpgradeConfirmText:
	text_far _CreditUpgradeConfirmText
	text_end

CreditUpgradedText:
	text_far _CreditUpgradedText
	text_waitbutton
	text_end

CreditNotEnoughText:
	text_far _CreditNotEnoughText
	text_waitbutton
	text_end

CreditSentToPCText:
	text_far _CreditSentToPCText
	text_waitbutton
	text_end

CreditNothingToSellText:
	text_far _CreditNothingToSellText
	text_waitbutton
	text_end

CreditNothingToUpgradeText:
	text_far _CreditNothingToUpgradeText
	text_waitbutton
	text_end

CreditRoomVendorClosedText:
	text_far _CreditRoomVendorClosedText
	text_waitbutton
	text_end
