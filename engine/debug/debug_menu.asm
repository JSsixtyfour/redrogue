DebugMenu:
IF DEF(_DEBUG)
	call ClearScreen

	; These debug names are used for TestBattle.
	; StartNewGameDebug uses the debug names from PrepareOakSpeech.
	ld hl, DebugBattlePlayerName
	ld de, wPlayerName
	ld bc, NAME_LENGTH
	call CopyData

	ld hl, DebugBattleRivalName
	ld de, wRivalName
	ld bc, NAME_LENGTH
	call CopyData

	call LoadFontTilePatterns
	call LoadHpBarAndStatusTilePatterns
	call ClearSprites
	call RunDefaultPaletteCommand

	hlcoord 5, 6
	ld b, 4
	ld c, 9
	call TextBoxBorder

	hlcoord 7, 7
	ld de, DebugMenuOptions
	call PlaceString

	ld a, TEXT_DELAY_MEDIUM
	ld [wOptions], a

	ld a, PAD_A | PAD_B | PAD_START
	ld [wMenuWatchedKeys], a
	xor a
	ld [wMenuJoypadPollCount], a
	ld a, 3
	ld [wMaxMenuItem], a
	ld a, 7
	ld [wTopMenuItemY], a
	dec a
	ld [wTopMenuItemX], a
	xor a
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld [wMenuWatchMovingOutOfBounds], a

	call HandleMenuInput
	bit B_PAD_B, a
	jp nz, DisplayTitleScreen

	ldh a, [hCurrentMenuItem]
	and a ; FIGHT?
	jp z, TestBattle
	cp 1 ; FIGHT 2?
	jr nz, .notFight2
	farjp DebugFight2Entry
.notFight2
	cp 3 ; DEBUG 2?
	jr z, .debug2

	; DEBUG
	ld hl, wStatusFlags6
	set BIT_DEBUG_MODE, [hl]
	ld a, SILPH_CO_DORM
	ld [wDefaultMap], a
	jp StartNewGameDebug

.debug2
	; Debug 2: like DEBUG, but spawns at the Indigo Plateau lobby, gives the
	; rival a Porygon starter, and prompts for a starting battle count. The extra
	; behavior is gated on BIT_DEBUG2_MODE (checked in PrepareNewGameDebug and
	; PCWitchSetup).
	ld hl, wStatusFlags6
	set BIT_DEBUG_MODE, [hl]
	set BIT_DEBUG2_MODE, [hl]
	ld a, INDIGO_PLATEAU_LOBBY
	ld [wDefaultMap], a
	jp StartNewGameDebug

DebugBattlePlayerName:
	db "Tom@"

DebugBattleRivalName:
	db "Juerry@"

DebugMenuOptions:
	db   "FIGHT"
	next "FIGHT 2"
	next "DEBUG"
	next "DEBUG 2@"
ELSE
	ret
ENDC

TestBattle: ; unreferenced except in _DEBUG
.loop
	call GBPalNormal

	; Don't mess around with obedience.
	ld a, 1 << BIT_EARTHBADGE
	ld [wObtainedBadges], a

	ld hl, wStatusFlags7
	set BIT_TEST_BATTLE, [hl]

	; wNumBagItems and wBagItems are not initialized here,
	; and their garbage values happen to act as if EXP_ALL
	; is in the bag at the end of the test battle.
	; pokeyellow fixes this by initializing them with a
	; list of items.

	; Reset the party.
	ld hl, wPartyCount
	xor a
	ld [hli], a
	dec a
	ld [hl], a

	; Give the player a level 20 Rhydon.
	ld a, RHYDON
	ld [wCurPartySpecies], a
	ld a, 20
	ld [wCurEnemyLevel], a
	xor a
	ld [wMonDataLocation], a
	ldh [hCurMap], a
	call AddPartyMon

	; Fight against a level 20 Rhydon.
	ld a, RHYDON
	ld [wCurOpponent], a

	predef InitOpponent

	; When the battle ends, do it all again.
	; There are some graphical quirks in SGB mode.
	ld a, 1
	ldh [hUpdateSpritesEnabled], a
	ldh [hAutoBGTransferEnabled], a
	jr .loop
