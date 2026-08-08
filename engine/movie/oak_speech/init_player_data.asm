InitPlayerData:
InitPlayerData2:
	; clear TM/HM bitfield so SRAM $FF default doesn't grant all TMs
	farcall ClearTMBitfield
	; clear key items ownership bitfield (true new game only — death/run-reset does NOT clear this)
	farcall ClearKeyItemsBitfield
	; clear room decoration state, same reason as the two above: SRAM's $FF
	; default would index past several option tables (see RoomClearState)
	farcall RoomClearState

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
	; Key items are pure bitfield in sKeyItemsBitfield (SRAM) — no WRAM slots.
	; ClearKeyItemsBitfield above already handles the SRAM side.
	; Clear count arrays for Recovery, Stat, Valuable pockets.
	ld hl, wRecoveryItemCounts
	xor a
	ld bc, NUM_RECOVERY_ITEMS + NUM_STAT_ITEMS + NUM_VALUABLE_ITEMS
.clearCounts
	ld [hli], a
	dec bc
	ld a, b
	or c
	ld a, 0
	jr nz, .clearCounts
	; Clear the legacy bag stub
	ld [wNumBagItems], a
	ld [wBagItems], a
	ld [wNumBagKeyItems], a
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
	; Rogue: auto-set Pokedex and Town Map events so Daisy skips her
	; "rival is at the lab" gate and goes straight to the fusion trigger.
	SetEvent EVENT_GOT_POKEDEX
	SetEvent EVENT_GOT_TOWN_MAP

	jp InitializeToggleableObjectsFlags

InitializeEmptyList:
	xor a ; count
	ld [hli], a
	dec a ; terminator
	ld [hl], a
	ret
