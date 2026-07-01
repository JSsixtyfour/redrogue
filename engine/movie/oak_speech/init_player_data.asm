InitPlayerData:
InitPlayerData2:
	; clear TM/HM bitfield so SRAM $FF default doesn't grant all TMs
	farcall ClearTMBitfield
	; clear key items ownership bitfield (true new game only — death/run-reset does NOT clear this)
	farcall ClearKeyItemsBitfield

	call Random
	ldh a, [hRandomSub]
	ld [wPlayerID], a

	call Random
	ldh a, [hRandomAdd]
	ld [wPlayerID + 1], a

	ld hl, wPartyCount
	call InitializeEmptyList
	ld hl, wBoxCount
	call InitializeEmptyList
	ld hl, wNumBagItems
	call InitializeEmptyList
	; Zero key item carry slots (count + 8 item slots) on new game.
	; Ownership bitfield (sKeyItemsBitfield) is cleared separately above.
	ld hl, wNumBagKeyItems
	xor a
	ld [hli], a    ; wNumBagKeyItems = 0
	ld [hli], a    ; wKeyItemSlot1
	ld [hli], a    ; wKeyItemSlot2
	ld [hli], a    ; wKeyItemSlot3
	ld [hli], a    ; wKeyItemSlot4
	ld [hli], a    ; wKeyItemSlot5
	ld [hli], a    ; wKeyItemSlot6
	ld [hli], a    ; wKeyItemSlot7
	ld [hl], a     ; wKeyItemSlot8
	ld hl, wNumBoxItems
	call InitializeEmptyList

DEF START_MONEY EQU $3000
	ld hl, wPlayerMoney + 1
	ld a, HIGH(START_MONEY)
	ld [hld], a
	xor a ; LOW(START_MONEY)
	ld [hli], a
	inc hl
	ld [hl], a

	ld [wMonDataLocation], a

	ld hl, wObtainedBadges
	ld [hli], a
	ld [hl], a

	ld hl, wPlayerCoins
	ld [hli], a
	ld [hl], a

	ld hl, wGameProgressFlags
	ld bc, wGameProgressFlagsEnd - wGameProgressFlags
	call FillMemory ; clear all game progress flags
   
	jp InitializeToggleableObjectsFlags

InitializeEmptyList:
	xor a ; count
	ld [hli], a
	dec a ; terminator
	ld [hl], a
	ret
