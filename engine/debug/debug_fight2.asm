IF DEF(_DEBUG)
SECTION "Debug Fight 2", ROMX

DebugFight2Entry::
	; A small in-ROM seed entry keeps failures reproducible without consuming
	; persistent RAM. The host harness records the chosen seed in its report.
	xor a
	ld [wListMenuID], a
	ld a, 99
	ld [wMaxItemQuantity], a
	call DisplayChooseQuantityMenu
	call .seedRNG
.loop
	call GBPalNormal
	ld a, 1 << BIT_EARTHBADGE
	ld [wObtainedBadges], a
	ld hl, wStatusFlags7
	set BIT_TEST_BATTLE, [hl]
	call DebugFight2Setup
	predef InitOpponent
	ld a, 1
	ldh [hUpdateSpritesEnabled], a
	ldh [hAutoBGTransferEnabled], a
	jr .loop

.seedRNG
	; Expand the entered 1-99 value into all four xorshift state bytes. Each
	; byte differs so no valid entry can create the absorbing all-zero state.
	ld a, [wItemQuantity]
	ld b, a
	ldh [hRandomAdd], a
	xor $a5
	ldh [hRandomSub], a
	ld a, b
	rrca
	xor $3c
	ldh [hRandomLast], a
	ld a, b
	swap a
	xor $c3
	ldh [hRandomLast + 1], a
	ret

DebugFight2Setup::
	; Reset both parties before generating the next deterministic scenario.
	xor a
	ld [wPartyCount], a
	ld [wEnemyPartyCount], a
	dec a
	ld [wPartySpecies], a
	ld [wEnemyPartySpecies], a

	call .hasInjectedSpec
	jp z, .buildInjected

	ld b, PARTY_LENGTH
.playerLoop
	push bc
	ld a, $10 ; player party, skip naming screen
	ld [wMonDataLocation], a
	call .addRandomMon
	pop bc
	dec b
	jr nz, .playerLoop

	ld b, PARTY_LENGTH
.enemyLoop
	push bc
	ld a, ENEMY_PARTY_DATA
	ld [wMonDataLocation], a
	call .addRandomMon
	pop bc
	dec b
	jr nz, .enemyLoop

	; AddPartyMon skips the naming screen for generated test parties, leaving
	; nickname slots unterminated. Fill both sides with a safe debug name.
	ld de, wPartyMonNicks
	call .nameParty
	ld de, wEnemyMonNicks
	call .nameParty

	; Start from no key items, then grant 0-3 active items. The first index is
	; random; stepping five rows through the 15-row table guarantees uniqueness
	; for all three possible grants without a retry loop.
	farcall ClearKeyItemsBitfield
	call Random
	and 3
	ld b, a
	jr z, .itemsDone
	ld c, 15
	call Rangerandom
	ld c, a
.itemLoop
	push bc
	ld b, 0
	ld hl, .keyItems
	add hl, bc
	ld a, [hl]
	ld b, a
	ld c, 1
	call GiveItem
	pop bc
	ld a, c
	add 5
	cp 15
	jr c, .itemIndexReady
	sub 15
.itemIndexReady
	ld c, a
	dec b
	jr nz, .itemLoop
.itemsDone
	; Use a normal trainer presentation, but engine/battle/core.asm preserves
	; this prebuilt enemy party when BIT_TEST_BATTLE is set.
	ld a, OPP_COOLTRAINER_M
	ld [wCurOpponent], a
	ld a, 1
	ld [wIsTrainerBattle], a
	ld [wTrainerNo], a
	xor a
	ld [wMonDataLocation], a
	ret

.hasInjectedSpec
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, [sDebugFight2SpecMagic]
	cp $d2
	push af
	xor a
	ld [rRAMG], a
	pop af
	ret

.buildInjected
	ld c, 1
	call .readSpecByte
	cp PARTY_LENGTH + 1
	jr c, .playerCountReady
	ld a, PARTY_LENGTH
.playerCountReady
	ld b, a
	ld c, 0
.injectedPlayerLoop
	push bc
	call .loadSpecMon
	ld a, $10
	ld [wMonDataLocation], a
	call .addSpecMon
	pop bc
	inc c
	dec b
	jr nz, .injectedPlayerLoop

	ld c, 2
	call .readSpecByte
	cp PARTY_LENGTH + 1
	jr c, .enemyCountReady
	ld a, PARTY_LENGTH
.enemyCountReady
	ld b, a
	ld c, PARTY_LENGTH
.injectedEnemyLoop
	push bc
	call .loadSpecMon
	ld a, ENEMY_PARTY_DATA
	ld [wMonDataLocation], a
	call .addSpecMon
	pop bc
	inc c
	dec b
	jr nz, .injectedEnemyLoop

	ld de, wPartyMonNicks
	call .nameParty
	ld de, wEnemyMonNicks
	call .nameParty
	farcall ClearKeyItemsBitfield
	ld c, 3
	call .readSpecByte
	ld [wCurOpponent], a
	ld a, 1
	ld [wIsTrainerBattle], a
	ld [wTrainerNo], a
	ld c, 4
	call .readSpecByte
	ld [wAIDebugTierOverride], a
	xor a
	ld [wMonDataLocation], a
	ret

; Read fixture byte c while restoring SRAM-disabled state. Only called before
; battle initialization, when no ambient SRAM access is active.
.readSpecByte
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, 1
	ld [rRAMB], a
	ld hl, sDebugFight2Spec
	ld b, 0
	add hl, bc
	ld a, [hl]
	ld b, a
	xor a
	ld [rRAMG], a
	ld a, b
	ret

; Load fixture entry c into wBuffer.
.loadSpecMon
	ld a, c
	add a
	ld b, a
	add a
	add b ; c * 6
	add sDebugFight2Mons - sDebugFight2Spec
	ld c, a
	ld b, 0
	ld hl, sDebugFight2Spec
	add hl, bc
	ld de, wBuffer
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, 1
	ld [rRAMB], a
	ld b, 6
.copySpecMon
	ld a, [hli]
	ld [de], a
	inc de
	dec b
	jr nz, .copySpecMon
	xor a
	ld [rRAMG], a
	ret

.addSpecMon
	ld a, [wBuffer]
	ld [wCurPartySpecies], a
	ld a, [wBuffer + 1]
	ld [wCurEnemyLevel], a
	call AddPartyMon
	ld hl, wPartyMons
	ld a, [wMonDataLocation]
	and $f
	ld a, [wPartyCount]
	jr z, .gotSpecParty
	ld hl, wEnemyMons
	ld a, [wEnemyPartyCount]
.gotSpecParty
	dec a
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld bc, MON_MOVES
	add hl, bc
	push hl
	ld de, wBuffer + 2
	ld b, NUM_MOVES
.copySpecMoves
	ld a, [de]
	ld [hli], a
	inc de
	dec b
	jr nz, .copySpecMoves
	pop hl
	push hl
	ld de, MON_PP - MON_MOVES - 1
	add hl, de
	ld d, h
	ld e, l
	pop hl
	predef LoadMovePPs
	ret

.addRandomMon
	push af
	ld c, 96
	call Rangerandom
	add 5 ; level 5-100
	ld [wCurEnemyLevel], a
	call Random
	ld c, 0
	farcall Random_Pokemon_Selection_Any
	ld a, d
	ld [wCurPartySpecies], a
	pop af
	ld [wMonDataLocation], a
	jp AddPartyMon

.nameParty
	ld b, PARTY_LENGTH
.nameLoop
	push bc
	push de
	ld hl, .testName
	ld bc, .testNameEnd - .testName
	call CopyData
	pop de
	ld hl, NAME_LENGTH
	add hl, de
	ld d, h
	ld e, l
	pop bc
	dec b
	jr nz, .nameLoop
	ret

.testName
	db "TEST@"
.testNameEnd

.keyItems
	db LEFTOVERS, PP_TONIC, KO_DEFIANCE, EXP_ALL, SHINY_CHARM
	db AMULET_COIN, TURN_REWIND, RARE_SCOPE, RARE_LENS, DV_BOOSTER
	db STAT_BOOSTER, DOOR_DICE, MON_DICE, ITEM_DICE, ELEMENT_PRISM
ENDC
