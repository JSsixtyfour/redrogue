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

	; Box, option list, menu setup and the MUSIC sound test run from bank $3A.
	farcall DebugMenuRun
	ldh a, [hJoy5]
	bit B_PAD_B, a
	jp nz, DisplayTitleScreen

	ldh a, [hCurrentMenuItem]
	and a ; FIGHT?
	jp z, TestBattle
	cp 1 ; FIGHT 2?
	jr nz, .notFight2
	farjp DebugFight2Entry
.notFight2
	; Debug starts bypass MainMenu, but must obtain the same discard consent.
	push af
	rfarcall ConfirmNewGameOverwrite
	jr z, .overwriteConfirmed
	pop af
	jp DebugMenu
.overwriteConfirmed
	pop af
	cp 3 ; DEBUG 2?
	jr z, .debug2

	; DEBUG
	ld hl, wStatusFlags6
	set BIT_DEBUG_MODE, [hl]
	ld a, SILPH_CO_DORM
.startDebugGame ; a = spawn map
	ld [wDefaultMap], a
	; This path never runs MainMenu, the only code that zeroes
	; wOptionsInitialized, and that byte is a UNION shared with scratch, so it
	; holds junk here. Nonzero junk made PrepareOakSpeech skip InitOptions and
	; left wOptions2 zeroed: Enhanced Colors and 60 FPS off for the session.
	xor a
	ld [wOptionsInitialized], a
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
	jr .startDebugGame

DebugBattlePlayerName:
	db "Tom@"

DebugBattleRivalName:
	db "Juerry@"
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
	; TestBattle rebuilds the party in-place, so discard any selected bridge
	; effect owners from the previous debug iteration.
	farcall RentalPrepareDebugParty

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
