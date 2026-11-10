; Field bag presentation only. The pocket builders still resolve ownership
; and quantities using the existing storage tables.

IsActiveFieldBag:
	ld a, [wFieldBagListActive]
	and a
	jr z, .inactive
	ld a, [wMenuWatchMovingOutOfBounds]
	and a
	jr z, .inactive
	ld a, [wListMenuID]
	cp ITEMLISTMENU
	jr nz, .inactive
	ldh a, [hIsInBattle]
	and a
	ret z
.inactive
	scf
	ret

; Carry: other menu. Carry clear: Z for held SELECT, NZ for a new toggle.
ToggleFieldBagSort::
	call IsActiveFieldBag
	ret c ; preserve legacy SELECT handling in other lists
	ldh a, [hJoyPressed]
	bit B_PAD_SELECT, a
	ret z ; consume auto-repeat without toggling again
	ldh a, [hCurrentMenuItem]
	ld c, a
	ld a, [wListScrollOffset]
	add c
	add a ; two bytes per entry
	ld c, a
	ld b, 0
	call GetBagListEntries
	add hl, bc
	ld a, [hl] ; item ID, or $ff for CANCEL
	push af
	ld a, [wOptions3]
	xor 1 << BIT_BAG_SORT_ALPHA
	ld [wOptions3], a
	rfarcall BuildBagPocketList
	pop bc ; b = previously highlighted item ID
	call GetBagListEntries
	ld c, 0
.findSelection
	ld a, [hli]
	cp b
	jr z, .foundSelection
	inc a
	jr z, .foundSelection ; fall back to CANCEL if the item is absent
	inc hl
	inc c
	jr .findSelection
.foundSelection
	; Keep the selection visible in the three navigable rows.
	xor a
	ld [wMenuItemToSwap], a
	ld a, c
	sub 2
	jr nc, .scrolled
	xor a
	jr .storePosition
.scrolled
	ld c, 2
.storePosition
	ld [wListScrollOffset], a
	ld a, c
	ldh [hCurrentMenuItem], a
	or 1 ; signal a toggle even if the new cursor row is zero
	ret

PrintFieldBagSortMode::
	call IsActiveFieldBag
	ret c
	ld de, .Type
	ld a, [wOptions3]
	bit BIT_BAG_SORT_ALPHA, a
	jr z, .draw
	ld de, .Alpha
.draw
	hlcoord 14, 3
	jp PlaceString
.Type
	db " TYPE@"
.Alpha
	db "ALPHA@"

; Walk the desired order and swap each owned pair into the next output
; slot. Both bytes travel together, and the count and sentinel stay put.
; The TYPE builders already give the requested order except for Recovery.
SortFieldBagPocket::
	ld a, [wBagPocketsFlags]
	and POCKET_INDEX_MASK
	ld c, a
	ld hl, wOptions3
	bit BIT_BAG_SORT_ALPHA, [hl]
	ld hl, BagRecoveryTypeOrder
	jr nz, .alpha
	and a ; POCKET_RECOVERY == 0
	ret nz
	jr .sort
.alpha
	cp NUM_POCKETS
	jr nc, .done
	ld hl, BagAlphaOrderPointers
	add a
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
.sort
	push hl
	call GetBagListEntries
	ld d, h
	ld e, l
	pop hl
.nextItem
	ld a, [hli]
	ld c, a
	inc a
	jr z, .done
	push hl
	ld h, d
	ld l, e
.scan
	ld a, [hli]
	cp c
	jr z, .found
	inc a
	jr z, .nextOrderEntry
	inc hl
	jr .scan
.found
	; hl = matched quantity, de = next output item
	ld b, [hl]
	inc de
	ld a, [de]
	ld [hld], a
	ld a, b
	ld [de], a
	dec de
	ld a, [de]
	ld [hl], a
	ld a, c
	ld [de], a
	inc de
	inc de
.nextOrderEntry
	pop hl
	jr .nextItem
.done
	and a ; PocketSwitchROMX returns carry clear on success
	ret

GetBagListEntries:
	ld hl, wListPointer
	ld a, [hli]
	ld h, [hl]
	ld l, a
	inc hl
	ret

BagRecoveryTypeOrder::
	db POTION, SUPER_POTION, FRESH_WATER, SODA_POP, LEMONADE
	db HYPER_POTION, MAX_POTION, FULL_RESTORE, REVIVE, MAX_REVIVE
	db ANTIDOTE, BURN_HEAL, ICE_HEAL, AWAKENING, PARLYZ_HEAL, FULL_HEAL
	db ETHER, MAX_ETHER, ELIXER, MAX_ELIXER, POKE_FLUTE
	db $ff
	assert @ - BagRecoveryTypeOrder == NUM_RECOVERY_ITEMS + 1

BagAlphaOrderPointers:
	table_width 2
	dw BagRecoveryAlphaOrder
	dw BagKeyAlphaOrder
	dw BagTMAlphaOrder
	dw BagStatAlphaOrder
	dw BagValuableAlphaOrder
	assert_table_length NUM_POCKETS

; Sorted by the displayed names in data/items/names.asm.
BagRecoveryAlphaOrder::
	db ANTIDOTE, AWAKENING, BURN_HEAL, ELIXER, ETHER, FRESH_WATER
	db FULL_HEAL, FULL_RESTORE, HYPER_POTION, ICE_HEAL, LEMONADE
	db MAX_ELIXER, MAX_ETHER, MAX_POTION, MAX_REVIVE, PARLYZ_HEAL
	db POKE_FLUTE, POTION, REVIVE, SODA_POP, SUPER_POTION
	db $ff
	assert @ - BagRecoveryAlphaOrder == NUM_RECOVERY_ITEMS + 1

BagKeyAlphaOrder::
	db AMULET_COIN, DOOR_DICE, DV_BOOSTER, ELEMENT_PRISM, ITEM_DICE
	db KO_DEFIANCE, LEFTOVERS, MON_DICE, PP_TONIC, RARE_LENS
	db RARE_SCOPE, SHINY_CHARM, STAT_BOOSTER, TURN_REWIND
	db $ff

; Sort on MoveNames through the TM/HM mapping, with numeric identity for ties.
BagTMAlphaOrder::
	db TM_BIDE, TM_BLIZZARD, TM_BODY_SLAM, TM_BUBBLEBEAM, TM_COUNTER
	db HM_CUT, TM_DIG, TM_DOUBLE_TEAM, TM_DOUBLE_EDGE, TM_DRAGON_RAGE
	db TM_DREAM_EATER, TM_EARTHQUAKE, TM_EGG_BOMB, TM_EXPLOSION, TM_FIRE_BLAST
	db TM_FISSURE, TM_FLAMETHROWER, HM_FLASH, HM_FLY, TM_HORN_DRILL
	db TM_HYPER_BEAM, TM_ICE_BEAM, TM_LIGHT_SCREEN, TM_MEGA_DRAIN, TM_MEGA_KICK
	db TM_MEGA_PUNCH, TM_METRONOME, TM_MIMIC, TM_PAY_DAY, TM_PSYCHIC_M
	db TM_PSYWAVE, TM_RAGE, TM_RAZOR_WIND, TM_REFLECT, TM_REST
	db TM_ROCK_SLIDE, TM_SEISMIC_TOSS, TM_SELFDESTRUCT, TM_SKULL_BASH, TM_SKY_ATTACK
	db TM_SOFTBOILED, TM_SOLARBEAM, HM_STRENGTH, TM_SUBMISSION, TM_SUBSTITUTE
	db HM_SURF, TM_SWIFT, TM_SWORDS_DANCE, TM_TAKE_DOWN, TM_THUNDER
	db TM_THUNDER_WAVE, TM_THUNDERBOLT, TM_TOXIC, TM_TRI_ATTACK, TM_WATER_GUN
	db $ff
	assert @ - BagTMAlphaOrder == NUM_TM_HM + 1

BagStatAlphaOrder::
	db CALCIUM, CARBOS, DUSK_STONE, FIRE_STONE, HP_UP, ICE_STONE, IRON
	db LEAF_STONE, M_GENE, M_TOME, MIST_STONE, MOON_STONE, PP_UP
	db PROTEIN, RARE_CANDY, SUN_STONE, THUNDER_STONE, WATER_STONE
	db $ff
	assert @ - BagStatAlphaOrder == NUM_STAT_ITEMS + 1

BagValuableAlphaOrder::
	db BIG_NUGGET, BIG_PEARL, NUGGET, PEARL
	db $ff
	assert @ - BagValuableAlphaOrder == NUM_VALUABLE_ITEMS + 1
