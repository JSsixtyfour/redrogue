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

.keyItems
	db LEFTOVERS, PP_TONIC, KO_DEFIANCE, EXP_ALL, SHINY_CHARM
	db AMULET_COIN, TURN_REWIND, RARE_SCOPE, RARE_LENS, DV_BOOSTER
	db STAT_BOOSTER, DOOR_DICE, MON_DICE, ITEM_DICE, ELEMENT_PRISM
ENDC
