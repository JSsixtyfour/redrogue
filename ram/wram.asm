SECTION "Audio RAM", WRAM0

wSoundID:: db

; bit 7: whether sound has been muted
; all bits: whether the effective is active
; Store 1 to activate effect (any value in the range [1, 127] works).
; All audio is muted and music is paused. Sfx continues playing until it
; ends normally.
; Store 0 to resume music.
wMuteAudioAndPauseMusic:: db

wDisableChannelOutputWhenSfxEnds:: db

wStereoPanning:: db

wSavedVolume:: db

wChannelCommandPointers:: ds NUM_CHANNELS * 2
wChannelReturnAddresses:: ds NUM_CHANNELS * 2

wChannelSoundIDs:: ds NUM_CHANNELS

wChannelFlags1:: ds NUM_CHANNELS
wChannelFlags2:: ds NUM_CHANNELS

wChannelDutyCycles:: ds NUM_CHANNELS
wChannelDutyCyclePatterns:: ds NUM_CHANNELS

; reloaded at the beginning of a note. counts down until the vibrato begins.
wChannelVibratoDelayCounters:: ds NUM_CHANNELS
wChannelVibratoExtents:: ds NUM_CHANNELS
; high nybble is rate (counter reload value) and low nybble is counter.
; time between applications of vibrato.
wChannelVibratoRates:: ds NUM_CHANNELS
wChannelFrequencyLowBytes:: ds NUM_CHANNELS
; delay of the beginning of the vibrato from the start of the note
wChannelVibratoDelayCounterReloadValues:: ds NUM_CHANNELS

wChannelPitchSlideLengthModifiers:: ds NUM_CHANNELS
wChannelPitchSlideFrequencySteps:: ds NUM_CHANNELS
wChannelPitchSlideFrequencyStepsFractionalPart:: ds NUM_CHANNELS
wChannelPitchSlideCurrentFrequencyFractionalPart:: ds NUM_CHANNELS
wChannelPitchSlideCurrentFrequencyHighBytes:: ds NUM_CHANNELS
wChannelPitchSlideCurrentFrequencyLowBytes:: ds NUM_CHANNELS
wChannelPitchSlideTargetFrequencyHighBytes:: ds NUM_CHANNELS
wChannelPitchSlideTargetFrequencyLowBytes:: ds NUM_CHANNELS

; Note delays are stored as 16-bit fixed-point numbers where the integer part
; is 8 bits and the fractional part is 8 bits.
wChannelNoteDelayCounters:: ds NUM_CHANNELS
wChannelLoopCounters:: ds NUM_CHANNELS
wChannelNoteSpeeds:: ds NUM_CHANNELS
wChannelNoteDelayCountersFractionalPart:: ds NUM_CHANNELS

wChannelOctaves:: ds NUM_CHANNELS
; also includes fade for hardware channels that support it
wChannelVolumes:: ds NUM_CHANNELS

wMusicWaveInstrument:: db
wSfxWaveInstrument:: db
wMusicTempo:: dw
wSfxTempo:: dw
wSfxHeaderPointer:: dw

wNewSoundID:: db

wAudioROMBank:: db
wAudioSavedROMBank:: db

wFrequencyModifier:: db
wTempoModifier:: db

	; Pocket-list builder scratch, relocated OUT of the enemy/wild UNION (bottom of
	; this file) so it can never overlap wGrassRate. Free WRAM0 tail padding
	; (WRAM_BIBLE §D4). 3 named bytes + ds 10 = 13 bytes total, so all following
	; addresses are unchanged.
	wPocketListWritePtr:: dw   ; scratch write-pointer for pocket list builders
	wPocketListCount::    db   ; scratch iteration counter for pocket list builders

	; Low-HP alarm tone-pair counter (Shin Red import Phase 2.10, WRAM_BIBLE.md
	; §D4 lever). Bit 7 = alarm active, bits 0-6 = tone-pairs remaining before
	; Music_DoLowHealthAlarm force-disables itself. Battle-transient scratch,
	; not saved, so this unsaved/non-union pad is the correct (and cheapest)
	; home for it - do NOT use the wMiscBattleData ds 13 pad a few hundred
	; lines below, that span is reserved for AI_OVERHAUL_PLAN.md.
	wLowHealthTonePairs:: db

	; EXP bar persistent state (Shin Red import Phase 9.1). Battle-transient and
	; unsaved, which is exactly what this pad is for (WRAM_BIBLE.md §D4). The 9
	; bytes of arithmetic scratch that go with these two live in the separate
	; unsaved gap after wMiscFlags - see there.
	wEXPBarPixelLength::  db ; 0-64, pixels of bar currently drawn
	wEXPBarKeepFullFlag:: db ; bit 0: force the next CalcEXPBarPixelLength to 64

	; Debug/test AI skill-tier override (AI_OVERHAUL_PLAN.md Phase 1).
	; 0 = resolve the tier normally from wBattleCount; otherwise tier+1, so 1
	; forces T0 and 4 forces T3. Deliberately lives HERE and not in the
	; wMiscBattleData AI block, because that span is zeroed at battle start and
	; this has to be set beforehand. Allocated in every build (not _DEBUG-gated)
	; so the release and debug WRAM layouts stay identical and the .sym files
	; agree - the PyBoy harness writes this by symbol name.
	wAIDebugTierOverride:: db

	ds 6


SECTION "Sprite State Data", WRAM0

wSpriteDataStart::

; data for all sprites on the current map
; holds info for 16 sprites with $10 bytes each
wSpriteStateData1::
; struct fields:
; - 0: picture ID (fixed, loaded at map init)
; - 1: movement status (0: uninitialized, 1: ready, 2: delayed, 3: moving)
; - 2: sprite image index (changed on update, $ff if off screen, includes facing direction, progress in walking animation and a sprite-specific offset)
; - 3: Y screen position delta (-1,0 or 1; added to Y pixels on each walking animation update)
; - 4: Y screen position (in pixels, always 4 pixels above grid which makes sprites appear to be in the center of a tile)
; - 5: X screen position delta (-1,0 or 1; added to field X pixels on each walking animation update)
; - 6: X screen position (in pixels, snaps to grid if not currently walking)
; - 7: intra-animation-frame counter (counting upwards to 4 until animation frame counter is incremented)
; - 8: animation frame counter (increased every 4 updates, hold four states (totalling to 16 walking frames)
; - 9: facing direction ($0: down, $4: up, $8: left, $c: right)
; - A: adjusted Y coordinate
; - B: adjusted X coordinate
; - C: direction of collision
; - D
; - E
; - F
wSpritePlayerStateData1::  spritestatedata1 wSpritePlayerStateData1 ; player is struct 0
; wSprite01StateData1 - wSprite15StateData1
FOR n, 1, NUM_SPRITESTATEDATA_STRUCTS
wSprite{02d:n}StateData1:: spritestatedata1 wSprite{02d:n}StateData1
ENDR

; more data for all sprites on the current map
; holds info for 16 sprites with $10 bytes each
wSpriteStateData2::
; struct fields:
; - 0: walk animation counter (counting from $10 backwards when moving)
; - 1:
; - 2: Y displacement (initialized at 8, supposed to keep moving sprites from moving too far, but bugged)
; - 3: X displacement (initialized at 8, supposed to keep moving sprites from moving too far, but bugged)
; - 4: Y position (in 2x2 tile grid steps, topmost 2x2 tile has value 4)
; - 5: X position (in 2x2 tile grid steps, leftmost 2x2 tile has value 4)
; - 6: movement byte 1 (determines whether a sprite can move, $ff:not moving, $fe:random movements, others unknown)
; - 7: (?) (set to $80 when in grass, else $0; may be used to draw grass above the sprite)
; - 8: delay until next movement (counted downwards, movement status is set to ready if reached 0)
; - 9: original facing direction (backed up by DisplayTextIDInit, restored by CloseTextDisplay)
; - A
; - B
; - C
; - D: picture ID
; - E: sprite image base offset (in video ram, player always has value 1, used to compute sprite image index)
; - F
wSpritePlayerStateData2::  spritestatedata2 wSpritePlayerStateData2 ; player is struct 0
; wSprite01StateData2 - wSprite15StateData2
FOR n, 1, NUM_SPRITESTATEDATA_STRUCTS
wSprite{02d:n}StateData2:: spritestatedata2 wSprite{02d:n}StateData2
ENDR

; The high byte of a pointer to anywhere within wSpriteStateData1 can be incremented
; to reach within wSpriteStateData2, and vice-versa for decrementing.
ASSERT HIGH(wSpriteStateData1) + 1 == HIGH(wSpriteStateData2)
ASSERT LOW(wSpriteStateData1) == 0 && LOW(wSpriteStateData2) == 0

wSpriteDataEnd::


SECTION "OAM Buffer", WRAM0

; buffer for OAM data. Copied to OAM by DMA
wShadowOAM::
; wShadowOAMSprite00 - wShadowOAMSprite39
FOR n, OAM_COUNT
wShadowOAMSprite{02d:n}:: sprite_oam_struct wShadowOAMSprite{02d:n}
ENDR
wShadowOAMEnd::


SECTION "Tilemap", WRAM0

; buffer for tiles that are visible on screen (20 columns by 18 rows)
wTileMap:: ds SCREEN_AREA

; This union spans 480 bytes.
UNION
; buffer for temporarily saving and restoring current screen's tiles
; (e.g. if menus are drawn on top)
wTileMapBackup:: ds SCREEN_AREA

NEXTU
; buffer for the blocks surrounding the player (6 columns by 5 rows of 4x4-tile blocks)
wSurroundingTiles:: ds SURROUNDING_WIDTH * SURROUNDING_HEIGHT

NEXTU
; buffer for temporarily saving and restoring shadow OAM
wShadowOAMBackup::
; wShadowOAMBackupSprite00 - wShadowOAMBackupSprite39
FOR n, OAM_COUNT
wShadowOAMBackupSprite{02d:n}:: sprite_oam_struct wShadowOAMBackupSprite{02d:n}
ENDR
wShadowOAMBackupEnd::

NEXTU
; list of indexes to patch with SERIAL_NO_DATA_BYTE after transfer
wSerialPartyMonsPatchList:: ;ds 200



; list of indexes to patch with SERIAL_NO_DATA_BYTE after transfer
wSerialEnemyMonsPatchList:: ;ds 200
ENDU


SECTION "Overworld Map", WRAM0

UNION
wOverworldMap:: ds 1300
wOverworldMapEnd::

NEXTU
wTempPic:: ds PIC_SIZE tiles
ENDU


SECTION "WRAM", WRAM0

; the tiles of the row or column to be redrawn by RedrawRowOrColumn
wRedrawRowOrColumnSrcTiles:: ds SCREEN_WIDTH * 2

; coordinates of the position of the cursor for the top menu item (id 0)
wTopMenuItemY:: db
wTopMenuItemX:: db

; the tile that was behind the menu cursor's current location
wTileBehindCursor:: db

; id of the bottom menu item
wMaxMenuItem:: db

; bit mask of keys that the menu will respond to
wMenuWatchedKeys:: db

; id of previously selected menu item
wLastMenuItem:: db

; It is mainly used by the party menu to remember the cursor position while the
; menu isn't active.
; It is also used to remember the cursor position of mon lists (for the
; withdraw/deposit/release actions) in Bill's PC so that it doesn't get lost
; when you choose a mon from the list and a sub-menu is shown. It's reset when
; you return to the main Bill's PC menu.
wPartyAndBillsPCSavedMenuItem:: db

; It is used by the bag list to remember the cursor position while the menu
; isn't active.
wBagSavedMenuItem:: db

; It is used by the start menu to remember the cursor position while the menu
; isn't active.
; The battle menu uses it so that the cursor position doesn't get lost when
; a sub-menu is shown. It's reset at the start of each battle.
wBattleAndStartSavedMenuItem:: db

wPlayerMoveListIndex:: db

; index in party of currently battling mon
wPlayerMonNumber:: db

; the address of the menu cursor's current location within wTileMap
wMenuCursorLocation:: dw

	ds 2

; how many times should HandleMenuInput poll the joypad state before it returns?
wMenuJoypadPollCount:: db

; id of menu item selected for swapping (counts from 1) (0 means that no menu item has been selected for swapping)
wMenuItemToSwap:: db

; offset of the current top menu item from the beginning of the list
; keeps track of what section of the list is on screen
wListScrollOffset:: db

; If non-zero, then when wrapping is disabled and the player tries to go past
; the top or bottom of the menu, return from HandleMenuInput. This is useful for
; menus that have too many items to display at once on the screen because it
; allows the caller to scroll the entire menu up or down when this happens.
wMenuWatchMovingOutOfBounds:: db

wTradeCenterPointerTableIndex:: db

	ds 1

; destination pointer for text output
; this variable is written to, but is never read from
wTextDest:: dw

UNION
; the received menu selection is stored twice
wLinkMenuSelectionReceiveBuffer:: dw
	ds 3
; the menu selection byte is stored twice before sending
wLinkMenuSelectionSendBuffer:: dw
	ds 3
wEnteringCableClub::
wLinkTimeoutCounter:: db

NEXTU
; temporary nybble used by Serial_ExchangeNybble
wSerialExchangeNybbleTempReceiveData::
; the final received nybble is stored here by Serial_SyncAndExchangeNybble
wSerialSyncAndExchangeNybbleReceiveData:: ;db
; the final received nybble is stored here by Serial_ExchangeNybble
wSerialExchangeNybbleReceiveData:: ;db
	;ds 3
; this nybble is sent when using Serial_SyncAndExchangeNybble or Serial_ExchangeNybble
wSerialExchangeNybbleSendData:: ;db
;	ds 4
wUnknownSerialCounter:: ;dw
ENDU

; $00 = player mons
; $01 = enemy mons
wWhichTradeMonSelectionMenu::
; 0 = player's party
; 1 = enemy party
; 2 = current box
; 3 = daycare
; 4 = in-battle mon
;
; AddPartyMon uses it slightly differently.
; If the lower nybble is 0, the mon is added to the player's party, else the enemy's.
; If the entire value is 0, then the player is allowed to name the mon.
wMonDataLocation:: db

; set to 1 if you can go from the bottom to the top or top to bottom of a menu
; set to 0 if you can't go past the top or bottom of the menu
wMenuWrappingEnabled:: db

; whether to check for 180-degree turn (0 = don't, 1 = do)
wCheckFor180DegreeTurn:: db

	ds 1

wToggleableObjectIndex:: db

wPredefID:: db
wPredefHL:: dw
wPredefDE:: dw
wPredefBC:: dw

wTrainerHeaderFlagBit:: db

	ds 1

; which NPC movement script pointer is being used
; 0 if an NPC movement script is not running
wNPCMovementScriptPointerTableNum:: db

; ROM bank of current NPC movement script
wNPCMovementScriptBank:: db

	ds 2

; This union spans 180 bytes.
UNION
wVermilionDockTileMapBuffer:: ds 5 * TILEMAP_WIDTH + SCREEN_WIDTH
wVermilionDockTileMapBufferEnd::

NEXTU
wOaksAideRewardItemName:: ds ITEM_NAME_LENGTH

NEXTU
wElevatorWarpMaps:: ds 11 * 2

NEXTU
; List of bag items that has been filtered to a certain type of items,
; such as drinks or fossils.
wFilteredBagItems:: ds 4

NEXTU
; Saved copy of OAM for the first frame of the animation to make it easy to
; flip back from the second frame.
wMonPartySpritesSavedOAM:: ds OBJ_SIZE * 4 * PARTY_LENGTH

NEXTU
wTrainerCardBlkPacket:: ds $40

NEXTU
wHallOfFame:: ds HOF_TEAM

NEXTU

wTileMapBackup3:: ; partial tilemap backup for saving a portion of the screen's contents.
ds 160 

NEXTU
wNPCMovementDirections:: ds 180

NEXTU
wDexRatingNumMonsSeen:: db
wDexRatingNumMonsOwned:: db
wDexRatingText:: db

NEXTU
; If a random number greater than this value is generated, then the player is
; allowed to have three 7 symbols or bar symbols line up.
; So, this value is actually the chance of NOT entering that mode.
; If the slot is lucky, it equals 250, giving a 5/256 (~2%) chance.
; Otherwise, it equals 253, giving a 2/256 (~0.8%) chance.
wSlotMachineSevenAndBarModeChance:: db
	ds 2
; ROM back to return to when the player is done with the slot machine
wSlotMachineSavedROMBank:: db
;ds 166
; removed ds stack here for move relearner
; Move Buffer stuff for Mateo's code
wTextBoxBuffer::
wMoveBuffer::
wRelearnableMoves::
	ds 164
; Current static data needs at most 14 bytes: count, 12 relearnable moves, and
; the $ff terminator. Keep a compile-time floor so future layout edits cannot
; silently shrink the shared list buffer below the proven requirement.
ASSERT wLuckySlotHiddenEventIndex - wMoveBuffer >= 14
; Try not to use this stack. 
; A good amount of space is needed to store data for the move relearner.
; If it's like, 2, it'll lag like crazy and show garbage from elsewhere
wLuckySlotHiddenEventIndex:: db

NEXTU
; values between 0-6. Shake screen horizontally, shake screen vertically, blink Pokemon...
wAnimationType:: db
	ds 29
wAnimPalette:: db

NEXTU
	ds 60
; temporary buffer when swapping party mon data
wSwitchPartyMonTempBuffer:: ds PARTYMON_STRUCT_LENGTH

NEXTU
	ds 120
; this is the end of the joypad states
; the list starts above this address and extends downwards in memory until here
; overloaded with below labels
wSimulatedJoypadStatesEnd::

NEXTU
wUnusedFlag::
wBoostExpByExpAll:: db

	ds 59

wNPCMovementDirections2:: ds 10
; used in Pallet Town scripted movement
wNumStepsToTake:: db

	ds 48

wRLEByteCount:: db

wParentMenuItem::
; 0 = not added
; 1 = added
wAddedToParty::
; 1 flag for each party member indicating whether it can evolve
; The purpose of these flags is to track which mons levelled up during the
; current battle at the end of the battle when evolution occurs.
; Other methods of evolution simply set it by calling TryEvolvingMon.
wMiscBattleData::
wCanEvolveFlags:: db

wForceEvolution:: db

; if [wAILayer2Encouragement] != 1, the second AI layer is not applied
wAILayer2Encouragement:: db

	ds 1

; current HP of player and enemy substitutes
wPlayerSubstituteHP:: db
wEnemySubstituteHP:: db

; used for TestBattle (unused in non-debug builds)
wTestBattlePlayerSelectedMove:: db

	ds 1

; 0=regular, 1=mimic, 2=above message box (relearn, heal pp..)
wMoveMenuType:: db

wPlayerSelectedMove:: db
wEnemySelectedMove:: db

wLinkBattleRandomNumberListIndex:: db

; number of times remaining that AI action can occur
wAICount:: db

; Output of the AI damage/KO simulator (Phase 3). Carved from this block's
; in-branch ds 2 so it lands inside the span InitBattleVariables zeroes.
wAIDamageEstimate:: dw

wEnemyMoveListIndex:: db

; The enemy mon's HP when it was switched in or when the current player mon
; was switched in, which was more recent.
; It's used to determine the message to print when switching out the player mon.
wLastSwitchInEnemyMonHP:: dw

; total amount of money made using Pay Day during the current battle
wTotalPayDayMoney:: ds 3

wSafariEscapeFactor:: db
wSafariBaitFactor:: db

	ds 1

wTransformedEnemyMonOriginalDVs:: dw

wMonIsDisobedient:: db

wPlayerDisabledMoveNumber:: db
wEnemyDisabledMoveNumber:: db

; When running in the scope of HandlePlayerMonFainted, it equals 1.
; When running in the scope of HandleEnemyMonFainted, it equals 0.
wInHandlePlayerMonFainted:: db

wPlayerUsedMove:: db
wEnemyUsedMove:: db

wEnemyMonMinimized:: db

wMoveDidntMiss:: db

; flags that indicate which party members have fought the current enemy mon
wPartyFoughtCurrentEnemyFlags:: flag_array PARTY_LENGTH

; Whether the low health alarm has been disabled due to the player winning the
; battle.
wLowHealthAlarmDisabled:: db

wPlayerMonMinimized:: db

; --- Trainer AI battle state (AI_OVERHAUL_PLAN.md) ---
; Carved out of this block's reserved ds 13 pad. Everything here is
; battle-scoped: wMiscBattleData..wMiscBattleDataEnd is bulk-zeroed at battle
; start by InitBattleVariables and is NOT saved, so these cost zero WRAM0 and
; are initialised for free every battle.
;
; wAITier holds tier+1, so the zeroing above naturally reads as "unresolved"
; and AIGetTier resolves lazily on first use. That removes any dependency on
; call ordering during battle init.
wAITier:: db            ; 0 = unresolved, else resolved tier + 1
wAILastMovePower:: db   ; power of the enemy's previous move (anti-spam)
wAILastMoveNum:: db     ; the enemy's previous move id (repeated-move fatigue)
wAISameMoveCount:: db   ; consecutive uses of that same move
wAISentOutFlags:: db    ; bit per party slot: has this mon been sent out yet
wAISwitchedFlags:: db   ; bit per party slot: switch-loop guard
wAIPlan:: db            ; active strategy plan id (0 = none)
wAIPlanStep:: db        ; progress within that plan

; Revealed-move memory (Gen 2's wPlayerUsedMoves). Allocated now so the
; player-state accessor seam has a home; populated in Phase 7, when clearing
; AI_OMNISCIENT on the low tiers makes the AI reason only from what it has
; actually seen. Zero means "no move revealed in this slot", which is exactly
; what the battle-start zeroing gives us - hence it MUST live in this branch.
wAISeenPlayerMoves:: ds NUM_MOVES

	ds 1
    
NEXTU

wAllSpecies::
ds $40

UNION
; the amount of damage accumulated by the enemy while biding
wEnemyBideAccumulatedDamage:: dw
NEXTU
; number of hits by enemy in attacks like Double Slap, etc.
wEnemyNumHits:: db
ENDU

	; NOTE: this pad is in the wAllSpecies union branch, which is NOT the branch
	; InitBattleVariables zeroes, and it aliases wNPCMovementDirections2. It is
	; therefore NOT usable for battle-scoped AI state - see AI_OVERHAUL_PLAN.md.
	ds 8
wMiscBattleDataEnd::
ENDU

; This union spans 39 bytes.
UNION
wInGameTradeGiveMonSpecies:: db
wInGameTradeTextPointerTablePointer:: dw
wInGameTradeTextPointerTableIndex:: db
wInGameTradeGiveMonName:: ds NAME_LENGTH
wInGameTradeReceiveMonName:: ds NAME_LENGTH
wInGameTradeMonNick:: ds NAME_LENGTH
wInGameTradeReceiveMonSpecies:: db

NEXTU
wPlayerMonUnmodifiedLevel:: db
wPlayerMonUnmodifiedMaxHP:: dw
wPlayerMonUnmodifiedAttack:: dw
wPlayerMonUnmodifiedDefense:: dw
wPlayerMonUnmodifiedSpeed:: dw
wPlayerMonUnmodifiedSpecial:: dw

; stat modifiers for the player's current pokemon
; value can range from 1 - 13 ($1 to $D)
; 7 is normal
wPlayerMonStatMods::
wPlayerMonAttackMod:: db
wPlayerMonDefenseMod:: db
wPlayerMonSpeedMod:: db
wPlayerMonSpecialMod:: db
wPlayerMonAccuracyMod:: db
wPlayerMonEvasionMod:: db
	ds 2
wPlayerMonStatModsEnd::

	ds 1

wEnemyMonUnmodifiedLevel:: db
wEnemyMonUnmodifiedMaxHP:: dw
wEnemyMonUnmodifiedAttack:: dw
wEnemyMonUnmodifiedDefense:: dw
wEnemyMonUnmodifiedSpeed:: dw
wEnemyMonUnmodifiedSpecial:: dw

; stat modifiers for the enemy's current pokemon
; value can range from 1 - 13 ($1 to $D)
; 7 is normal
wEnemyMonStatMods::
wEnemyMonAttackMod:: db
wEnemyMonDefenseMod:: db
wEnemyMonSpeedMod:: db
wEnemyMonSpecialMod:: db
wEnemyMonAccuracyMod:: db
wEnemyMonEvasionMod:: db
	ds 2
wEnemyMonStatModsEnd::

NEXTU
	ds 30
wEngagedTrainerClass:: db
wEngagedTrainerSet:: db
ENDU

	ds 1

wNPCMovementDirections2Index::
wUnusedLinkMenuByte::
; number of items in wFilteredBagItems list
wFilteredBagItemsCount:: db

; mask indicating which real button presses can override simulated ones
; XXX is it ever not 0?
wOverrideSimulatedJoypadStatesMask:: db

	ds 1

; This union spans 30 bytes.
UNION
wTradedPlayerMonSpecies:: db
wTradedEnemyMonSpecies:: db
	ds 2
wTradedPlayerMonOT:: ds NAME_LENGTH
wTradedPlayerMonOTID:: dw
wTradedEnemyMonOT:: ds NAME_LENGTH
wTradedEnemyMonOTID:: dw

NEXTU
wTradingWhichPlayerMon:: db
wTradingWhichEnemyMon:: db
wNameOfPlayerMonToBeTraded:: ds NAME_LENGTH

NEXTU
; one byte for each falling object
wFallingObjectsMovementData:: ds 20

NEXTU
; array of the number of mons in each box
wBoxMonCounts:: ds NUM_BOXES

NEXTU
wPriceTemp:: ds 3 ; BCD

NEXTU
; the current mon's field moves
wFieldMoves:: ds NUM_MOVES
wNumFieldMoves:: db
wFieldMovesLeftmostXCoord:: db
NEXTU
wBoxNumString:: ds 3

NEXTU
; 0 = upper half (Y < 9)
; 1 = lower half (Y >= 9)
wBattleTransitionCircleScreenQuadrantY:: db
wBattleTransitionCircleScreenQuadrantX:: db

NEXTU
; after 1 row/column has been copied, the offset to the next one to copy from
wBattleTransitionCopyTilesOffset:: dw

NEXTU
; counts down from 7 so that every time 7 more tiles of the spiral have been
; placed, the tile map buffer is copied to VRAM so that progress is visible
wInwardSpiralUpdateScreenCounter:: db
	ds 9
; 0 = outward, 1 = inward
wBattleTransitionSpiralDirection:: db

NEXTU
; multiplied by 16 to get the number of times to go right by 2 pixels
wSSAnneSmokeDriftAmount:: db
; 0 = left half (X < 10)
; 1 = right half (X >= 10)
wSSAnneSmokeX:: db

NEXTU
wHoFMonSpecies::
wHoFTeamIndex:: db
wHoFPartyMonIndex:: db
wHoFMonLevel:: db
; 0 = mon, 1 = player
wHoFMonOrPlayer:: db
wHoFTeamIndex2:: db
wHoFTeamNo:: db

; NOTE: wRivalStarterTemp / wRivalStarterBallSpriteIndex used to be a member of
; this union. That was a live bug: the Oak's Lab starter sequence has to hold
; the rival's pick across several FRAMES (RivalPickStarter writes it, then
; OaksLabRivalChoosesStarterScript reads it once his walk finishes), but offsets
; 0-1 of this union are constantly rewritten by other scratch users, so the
; values decayed to garbage (rival "received" species $02 / walked to the wrong
; ball). The ball index now lives in stable WRAM next to wRivalStarter, and the
; species is written straight to wRivalStarter - no union, no temp.

NEXTU
wFlyAnimUsingCoordList:: db
; $ff sentinel values at each end
wFlyLocationsList:: ds NUM_CITY_MAPS + 2

NEXTU
wWhichTownMapLocation:: db
wFlyAnimCounter:: db
wFlyAnimBirdSpriteImageIndex:: db

NEXTU
	ds 1
; difference in X between the next ball and the current one
wHUDPokeballGfxOffsetX:: db
wHUDGraphicsTiles::
wHUDUnusedTopTile:: db
wHUDCornerTile:: db
wHUDTriangleTile:: db
wHUDGraphicsTilesEnd::

NEXTU
; the level of the mon at the time it entered day care
wDayCareStartLevel:: db
wDayCareNumLevelsGrown:: db
wDayCareTotalCost:: dw ; BCD
wDayCarePerLevelCost:: dw ; BCD (always $100)
wDayCareDepositBattleCount:: db ; wBattleCount snapshot at deposit time

NEXTU
; the level of the mon at the time it entered day care
wDayCareStartLevel2:: db
wDayCareNumLevelsGrown2:: db
wDayCareTotalCost2:: dw ; BCD
wDayCarePerLevelCost2:: dw ; BCD (always $100)
wDayCareDepositBattleCount2:: db ; wBattleCount snapshot at deposit time

NEXTU
; which wheel the player is trying to stop
; 0 = none, 1 = wheel 1, 2 = wheel 2, 3 or greater = wheel 3
wStoppingWhichSlotMachineWheel:: db
wSlotMachineWheel1Offset:: db
wSlotMachineWheel2Offset:: db
wSlotMachineWheel3Offset:: db
; the OAM tile number of the upper left corner of the winning symbol minus 2
wSlotMachineWinningSymbol::
wSlotMachineWheel1BottomTile:: db
wSlotMachineWheel1MiddleTile:: db
wSlotMachineWheel1TopTile:: db
wSlotMachineWheel2BottomTile:: db
wSlotMachineWheel2MiddleTile:: db
wSlotMachineWheel2TopTile:: db
wSlotMachineWheel3BottomTile:: db
wSlotMachineWheel3MiddleTile:: db
wSlotMachineWheel3TopTile:: db
wPayoutCoins:: dw
; These flags are set randomly and control when the wheels stop.
; bit 6: allow the player to win in general
; bit 7: allow the player to win with 7 or bar (plus the effect of bit 6)
wSlotMachineFlags:: db
; wheel 1 can "slip" while this is non-zero
wSlotMachineWheel1SlipCounter:: db
; wheel 2 can "slip" while this is non-zero
wSlotMachineWheel2SlipCounter:: db
; The remaining number of times wheel 3 will roll down a symbol until a match is
; found, when winning is enabled. It's initialized to 4 each bet.
wSlotMachineRerollCounter:: db
; how many coins the player bet on the slot machine (1 to 3)
wSlotMachineBet:: db

NEXTU
wCanPlaySlots:: db
	ds 8
; temporary variable used to add payout amount to the player's coins
wTempCoins1:: dw
	ds 2
; temporary variable used to subtract the bet amount from the player's coins
wTempCoins2:: dw

NEXTU
wHiddenEventFunctionArgument:: db
wHiddenEventFunctionRomBank:: db
wHiddenEventIndex:: db
wHiddenEventY:: db
wHiddenItemOrCoinsIndex::
wHiddenEventX:: db

NEXTU
wPlayerSpinInPlaceAnimFrameDelay:: db
wPlayerSpinInPlaceAnimFrameDelayDelta:: db
wPlayerSpinInPlaceAnimFrameDelayEndValue:: db
wPlayerSpinInPlaceAnimSoundID:: db
	ds 6
	db ; temporary space used when wFacingDirectionList is rotated
; used when spinning the player's sprite
wFacingDirectionList:: ds 4
	ds 3
wSavedPlayerScreenY:: db
wSavedPlayerFacingDirection:: db

NEXTU
wPlayerSpinWhileMovingUpOrDownAnimDeltaY:: db
wPlayerSpinWhileMovingUpOrDownAnimMaxY:: db
wPlayerSpinWhileMovingUpOrDownAnimFrameDelay:: db

NEXTU
wTrainerSpriteOffset:: db
wTrainerEngageDistance:: db
wTrainerFacingDirection:: db
wTrainerScreenY:: db
wTrainerScreenX:: db

NEXTU
wTrainerInfoTextBoxWidthPlus1:: db
wTrainerInfoTextBoxWidth:: db
wTrainerInfoTextBoxNextRowOffset:: db

NEXTU
wOptionsTextSpeedCursorX:: db
wOptionsBattleAnimCursorX:: db
wOptionsBattleStyleCursorX:: db
wOptionsCancelCursorX:: db

NEXTU
; tile ID of the badge number being drawn
wBadgeNumberTile:: db
; first tile ID of the name being drawn
wBadgeNameTile:: db
; a list of the first tile IDs of each badge or face (depending on whether the
; badge is owned) to be drawn on the trainer screen
; the byte after the list gets read when shifting back one byte
wBadgeOrFaceTiles:: ds NUM_BADGES + 1
	ds 1
; temporary list created when displaying the badges on the trainer screen
; one byte for each badge; 0 = not obtained, 1 = obtained
wTempObtainedBadgesBooleans:: ds NUM_BADGES

NEXTU
; the number of credits mons that have been displayed so far
wNumCreditsMonsDisplayed:: db

NEXTU
	ds 1
	db ; temporary space used when wJigglypuffFacingDirections is rotated
wJigglypuffFacingDirections:: ds 4

NEXTU
	ds 16
; $3d = tree tile, $52 = grass tile
wCutTile:: db
	ds 2
; 0 = cut animation, 1 = boulder dust animation
wWhichAnimationOffsets:: db

NEXTU
	ds 18
; the index of the sprite the emotion bubble is to be displayed above
wEmotionBubbleSpriteIndex:: db
wWhichEmotionBubble:: db

NEXTU
wChangeBoxSavedMapTextPointer:: dw

NEXTU
wSavedY::
wTempSCX::
; which entry from TradeMons to select
wWhichTrade::
wDexMaxSeenMon::
wPPRestoreItem::
wWereAnyMonsAsleep::
wNumShakes::
wWhichBadge::
wTitleMonSpecies::
wPlayerCharacterOAMTile::
; the number of small stars OAM entries to move down
wMoveDownSmallStarsOAMCount::
wChargeMoveNum::
wCoordIndex::
wSwappedMenuItem::
; 0 = no bite
; 1 = bite
; 2 = no fish on map
wRodResponse::
	db
ENDU

; 0 = neither
; 1 = warp pad
; 2 = hole
wStandingOnWarpPadOrHole::
wOAMBaseTile::
wGymTrashCanIndex:: db

wSymmetricSpriteOAMAttributes:: db

wMonPartySpriteSpecies:: db

; in the trade animation, the mon that leaves the left gameboy
wLeftGBMonSpecies:: db

; in the trade animation, the mon that leaves the right gameboy
wRightGBMonSpecies:: db

wMiscFlags:: db

	; CalcEXPBarPixelLength scratch (Shin Red import Phase 9.1). Pure
	; intra-routine scratch: written and consumed inside one call, before any
	; DelayFrame, so nothing can land between the write and the read. Unsaved
	; padding, so this costs zero real WRAM0 and does not move the save format
	; (WRAM_BIBLE.md §D2). wMiscFlags above is only ever accessed by name as a
	; single byte - no hl-walk runs into this gap.
	wEXPBarBaseEXP::   ds 3 ; exp needed for the mon's CURRENT level
	wEXPBarCurEXP::    ds 3 ; current exp, minus base
	wEXPBarNeededEXP:: ds 3 ; exp needed for the NEXT level, minus base

; This has overlapping related uses.
; When the player tries to use an item or use certain field moves, 0 is stored
; when the attempt fails and 1 is stored when the attempt succeeds.
; In addition, some items store 2 for certain types of failures, but this
; cannot happen in battle.
; In battle, a non-zero value indicates the player has taken their turn using
; something other than a move (e.g. using an item or switching pokemon).
; So, when an item is successfully used in battle, this value becomes non-zero
; and the player is not allowed to make a move and the two uses are compatible.
wActionResultOrTookBattleTurn:: db

; size of downscaled mon pic used in pokeball entering/exiting animation
; $00 = 5×5
; $01 = 3×3
wDownscaledMonSize::
; FormatMovesString stores the number of moves minus one here
wNumMovesMinusOne:: db

; This union spans 20 bytes.
UNION
; storage buffer for various name strings
wNameBuffer:: ds NAME_BUFFER_LENGTH

NEXTU
; data copied from Moves for one move
wMoveData:: ds MOVE_LENGTH
wPPUpCountAndMaxPP:: db

NEXTU
; amount of money made from one use of Pay Day
wPayDayMoney:: ds 3

NEXTU
; evolution data for one mon
wEvoDataBuffer:: ds NUM_EVOS_IN_BUFFER * 4 + 1 ; enough for Eevee's three 4-byte evolutions and 0 terminator
wEvoDataBufferEnd::

NEXTU
wBattleMenuCurrentPP:: db
	ds 3
wStatusScreenCurrentPP:: db
	ds 6
; list of normal max PP (without PP up) values
wNormalMaxPPList:: ds NUM_MOVES
ENDU

UNION
; buffer for transferring the random number list generated by the other gameboy
wSerialOtherGameboyRandomNumberListBlock:: ;ds $11
NEXTU
; second buffer for temporarily saving and restoring current screen's tiles (e.g. if menus are drawn on top)
wTileMapBackup2:: ds SCREEN_AREA
ENDU

; This union spans 30 bytes.
UNION
; Temporary storage area
wBuffer:: ds 30

NEXTU
wEvoOldSpecies:: db
wEvoNewSpecies:: db
wEvoMonTileOffset:: db
wEvoCancelled:: db

NEXTU
wNamingScreenNameLength:: db
; non-zero when the player has chosen to submit the name
wNamingScreenSubmitName:: db
; 0 = upper case
; 1 = lower case
wAlphabetCase:: db
	ds 1
wNamingScreenLetter:: db

NEXTU
wChangeMonPicEnemyTurnSpecies:: db
wChangeMonPicPlayerTurnSpecies:: db

NEXTU
wHPBarMaxHP:: dw
wHPBarOldHP:: dw
wHPBarNewHP:: dw
wHPBarDelta:: db
wHPBarTempHP:: dw
	ds 11
wHPBarHPDifference:: dw

NEXTU
; lower nybble is x, upper nybble is y
wTownMapCoords::
; whether WriteMonMoves is being used to make a mon learn moves from day care
; non-zero if so
wLearningMovesFromDayCare::
	db

	ds 27

; the item that the AI used
wAIItem:: db
wUsedItemOnWhichPokemon:: db
ENDU

; sound ID during battle animations
wAnimSoundID:: db

; used as a storage value for the bank to return to after a BankswitchHome (bankswitch in homebank)
wBankswitchHomeSavedROMBank:: db

; used as a temp storage value for the bank to switch to
wBankswitchHomeTemp:: db

; 0 = nothing bought or sold in pokemart
; 1 = bought or sold something in pokemart
; this value is not used for anything
wBoughtOrSoldItemInMart:: db

; $00 - win
; $01 - lose
; $02 - draw
wBattleResult:: db

; bit 0: if set, prevents DisplayTextID from automatically drawing a text box
wAutoTextBoxDrawingControl:: db

; used in some overworld scripts to vary scripted movement
wSavedCoordIndex::
wOakWalkedToPlayer::
wNextSafariZoneGateScript:: db

; used in CheckForTilePairCollisions2 to store the tile the player is on
wTilePlayerStandingOn:: db

wNPCNumScriptedSteps:: db

; which script function within the pointer table indicated by
; wNPCMovementScriptPointerTableNum
wNPCMovementScriptFunctionNum:: db

; bit 0: set when printing a text predef so that DisplayTextID doesn't switch
;        to the current map's bank
wTextPredefFlag:: db

wPredefParentBank:: db

; movement byte 2 of current sprite
wCurSpriteMovement2:: db

	ds 2

; sprite offset of sprite being controlled by NPC movement script
wNPCMovementScriptSpriteOffset:: db

wScriptedNPCWalkCounter:: db

	ds 1

; always 0 since full CGB support was not implemented
wOnCGB:: db

; if running on SGB, it's 1, else it's 0
wOnSGB:: db

wDefaultPaletteCommand:: db

UNION
wPlayerHPBarColor:: db

NEXTU
; species of the mon whose palette is used for the whole screen
wWholeScreenPaletteMonSpecies:: db
ENDU

wEnemyHPBarColor:: db

; 0: green
; 1: yellow
; 2: red
wPartyMenuHPBarColors:: ds PARTY_LENGTH

wStatusScreenHPBarColor:: db

; Phase 11 (M.GENE/M.TOME): 2 B taken from this pad to fund wStatItemCounts
; growing 12->14. Phase - spinner speedup fix: 1 more B taken for
; wSpinnerTileFrameCount (WRAM_BIBLE.md D2 gap, unsaved, below wMainDataStart).
wSpinnerTileFrameCount:: db
	ds 4

wCopyingSGBTileData::
wWhichPartyMenuHPBar::
wPalPacket::
	db

; This union spans 49 bytes.
UNION
wPartyMenuBlkPacket:: ds $30

NEXTU
	ds 29
; storage buffer for various strings
wStringBuffer:: ds NAME_BUFFER_LENGTH

NEXTU
	ds 29
; the total amount of exp a mon gained
wExpAmountGained:: dw
wGainBoostedExp:: db
ENDU

wGymCityName:: ds GYM_CITY_LENGTH

wGymLeaderName:: ds NAME_LENGTH

wItemList:: ds 16

wListPointer:: dw

wItemPrices:: dw

; !! ALIAS HAZARD - READ BEFORE WRITING TO ANY OF THESE THREE !!
; These are THREE NAMES FOR ONE BYTE, not three variables. Writing wCurItem
; overwrites wCurPartySpecies and vice versa. This is vanilla pokered layout and
; is safe in vanilla, because item code and species code never run interleaved
; there. Red Rogue breaks that assumption constantly: the key-item system
; (custom_functions/key_item_pocket.asm) is queried via `ld [wCurItem], a` +
; GetKeyItemPower/IsKeyItemActive from inside battle start, damage calc,
; experience, mon creation and the random species/item rollers - all places where
; a caller may have a LIVE species sitting in this byte.
;
; Two real bugs this has already caused, both hard to find:
;   1. _AddPartyMon (engine/pokemon/add_mon.asm) - DV_BOOSTER/SHINY_CHARM lookups
;      corrupted the species before it escaped to callers.
;   2. RoguePrismRefreshCache (custom_functions/element_prism.asm) - runs at EVERY
;      battle start and left ELEMENT_PRISM ($70) here. The battle intro's pic load
;      reads wCurSpecies for the pic POINTER (GetMonHeader, home/pokemon.asm) but
;      wCurPartySpecies for the pic BANK (UncompressMonSprite, home/pics.asm), so
;      the enemy sprite was drawn from the wrong bank -> scrambled tiles. It only
;      glitched for species whose pic is NOT in BANK("Pics 3"), which made it look
;      intermittent/random.
;
; RULE: if you set wCurItem in code that can run while a species is live (battle,
; pic loading, party/box writes, species rolls), save this byte first and restore
; it before returning. See RoguePrismRefreshCache for the wrapper pattern.
wCurPartySpecies::
wCurItem::
wCurListMenuItem::
	db

; if non-zero, then print item prices when displaying lists
wPrintItemPrices:: db

; type of HP bar
; $00 = enemy HUD in battle
; $01 = player HUD in battle / status screen
; $02 = party menu
wHPBarType::
; ID used by DisplayListMenuID
wListMenuID:: db

; if non-zero, RemovePokemon will remove the mon from the current box,
; else it will remove the mon from the party
wRemoveMonFromBox::
; 0 = move from box to party
; 1 = move from party to box
; 2 = move from daycare to party
; 3 = move from party to daycare
wMoveMonType:: db

wItemQuantity:: db

wMaxItemQuantity:: db

; LoadMonData copies mon data here
wLoadedMon:: party_struct wLoadedMon

; bit 0: The space in VRAM that is used to store walk animation tile patterns
;        for the player and NPCs is in use for font tile patterns.
;        This means that NPC movement must be disabled.
; The other bits are unused.
wFontLoaded:: db

; walk animation counter
wWalkCounter:: db

; background tile number in front of the player (either 1 or 2 steps ahead)
wTileInFrontOfPlayer:: db

; The desired fade counter reload value is stored here prior to calling
; PlaySound in order to cause the current music to fade out before the new
; music begins playing. Storing 0 causes no fade out to occur and the new music
; to begin immediately.
; This variable has another use related to fade-out, as well. PlaySound stores
; the sound ID of the music that should be played after the fade-out is finished
; in this variable. FadeOutAudio checks if it's non-zero every V-Blank and
; fades out the current audio if it is. Once it has finished fading out the
; audio, it zeroes this variable and starts playing the sound ID stored in it.
wAudioFadeOutControl:: db

wAudioFadeOutCounterReloadValue:: db

wAudioFadeOutCounter:: db

; This is used to determine whether the default music is already playing when
; attempting to play the default music (in order to avoid restarting the same
; music) and whether the music has already been stopped when attempting to
; fade out the current music (so that the new music can be begin immediately
; instead of waiting).
; It sometimes contains the sound ID of the last music played, but it may also
; contain $ff (if the music has been stopped) or 0 (because some routines zero
; it in order to prevent assumptions from being made about the current state of
; the music).
wLastMusicSoundID:: db

wEnemyMoveNum:: db
wEnemyMoveEffect:: db
wEnemyMovePower:: db
wEnemyMoveType:: db
wEnemyMoveAccuracy:: db
wEnemyMoveMaxPP:: db
wPlayerMoveNum:: db
wPlayerMoveEffect:: db
wPlayerMovePower:: db
wPlayerMoveType:: db
wPlayerMoveAccuracy:: db
wPlayerMoveMaxPP:: db

wEnemyMonSpecies2:: db
wBattleMonSpecies2:: db

wEnemyMonNick:: ds NAME_LENGTH

wEnemyMon:: battle_struct wEnemyMon



wEnemyMonBaseStats:: ds NUM_STATS
wEnemyMonActualCatchRate:: db
wEnemyMonBaseExp:: db



wBattleMonNick:: ds NAME_LENGTH
wBattleMon:: battle_struct wBattleMon

wTrainerClass:: db

	ds 1

wTrainerPicPointer:: dw

	ds 1

UNION
wTempMoveNameBuffer:: ds MOVE_NAME_LENGTH

NEXTU
; The name of the mon that is learning a move.
wLearnMoveMonName:: ds NAME_LENGTH
ENDU

	ds 2

; money received after battle = base money × level of last enemy mon
wTrainerBaseMoney:: ds 3 ; BCD

wToggleableObjectCounter:: db

	ds 1

; 13 bytes for the letters of the opposing trainer
; the name is terminated with $50 with possible
; unused trailing letters
wTrainerName:: ds 13

; flags that indicate which party members should be be given exp when GainExperience is called
wPartyGainExpFlags:: flag_array PARTY_LENGTH

; in a wild battle, this is the species of pokemon
; in a trainer battle, this is the trainer class + OPP_ID_OFFSET
wCurOpponent:: db

; in normal battle, this is 0
; in old man battle, this is 1
; in safari battle, this is 2
wBattleType:: db

; bits 0-6: Effectiveness
   ;  $0 = immune
   ;  $5 = not very effective
   ;  $a = neutral
   ; $14 = super-effective
; bit 7: STAB
wDamageMultipliers:: db

; which entry in LoneAttacks to use
; it's actually the same thing as ^
wLoneAttackNo::
wGymLeaderNo:: db
; which instance of [youngster, lass, etc] is this?
wTrainerNo:: db

; $00 = normal attack
; $01 = critical hit
; $02 = successful OHKO
; $ff = failed OHKO
wCriticalHitOrOHKO:: db

wMoveMissed:: db

wBattleStatusData::
; always 0
wPlayerStatsToDouble:: db
; always 0
wPlayerStatsToHalve:: db

wPlayerBattleStatus1:: db
wPlayerBattleStatus2:: db
wPlayerBattleStatus3:: db

; always 0
wEnemyStatsToDouble:: db
; always 0
wEnemyStatsToHalve:: db

wEnemyBattleStatus1:: db
wEnemyBattleStatus2:: db
wEnemyBattleStatus3:: db

; when the player is attacking multiple times, the number of attacks left
wPlayerNumAttacksLeft:: db

wPlayerConfusedCounter:: db

wPlayerToxicCounter:: db

; high nibble: which move is disabled (1-4)
; low nibble: disable turns left
wPlayerDisabledMove:: db

	ds 1

; when the enemy is attacking multiple times, the number of attacks left
wEnemyNumAttacksLeft:: db

wEnemyConfusedCounter:: db

wEnemyToxicCounter:: db

; high nibble: which move is disabled (1-4)
; low nibble: disable turns left
wEnemyDisabledMove:: db

	ds 1

UNION
; the amount of damage accumulated by the player while biding
wPlayerBideAccumulatedDamage:: dw

NEXTU
wUnknownSerialCounter2:: dw

NEXTU
; number of hits by player in attacks like Double Slap, etc.
wPlayerNumHits:: db
ENDU

	ds 2
wBattleStatusDataEnd::

; non-zero when an item or move that allows escape from battle was used
wEscapedFromBattle:: db

UNION
wAmountMoneyWon:: ds 3 ; BCD

NEXTU
wObjectToHide:: db
wObjectToShow:: db

NEXTU
; loop counters for PPTonicRecovery; safe to alias here because by the time
; EndOfBattle reaches PPTonicRecovery, wAmountMoneyWon has already been
; printed (PickUpPayDayMoneyText) and wObjectToHide/wObjectToShow are only
; used by Seafoam Islands boulder scripts, never during battle
wPPTonicMonsLeft:: db
wPPTonicMovesLeft:: db
ENDU

; the map you will start at when the debug bit is set
wDefaultMap::
wMenuItemOffset::
; ID number of the current battle animation
wAnimationID:: db

wNamingScreenType::
wPartyMenuTypeOrMessageID::
; temporary storage for the number of tiles in a tileset
wTempTilesetNumTiles:: db

; used by the pokemart code to save the existing value of wListScrollOffset
; so that it can be restored when the player is done with the pokemart NPC
wSavedListScrollOffset:: db

	ds 2

; base coordinates of frame block
wBaseCoordX:: db
wBaseCoordY:: db

; low health alarm counter/enable
; high bit = enable, others = timer to cycle frequencies
wLowHealthAlarm:: db

; counts how many tiles of the current frame block have been drawn
wFBTileCounter:: db

wMovingBGTilesCounter2:: db

; duration of each frame of the current subanimation in terms of screen refreshes
wSubAnimFrameDelay:: db
; counts the number of subentries left in the current subanimation
wSubAnimCounter:: db

; 1 = no save file or save file is corrupted
; 2 = save file exists and no corruption has been detected
wSaveFileStatus:: db

; number of tiles in current battle animation frame block
wNumFBTiles:: db

UNION
wSpiralBallsBaseY:: db
wSpiralBallsBaseX:: db

NEXTU
; bits 0-6: index into FallingObjects_DeltaXs array (0 - 8)
; bit 7: direction; 0 = right, 1 = left
wFallingObjectMovementByte:: db
wNumFallingObjects:: db

NEXTU
wFlashScreenLongCounter::
wNumShootingBalls::
; $01 if mon is moving from left gameboy to right gameboy; $00 if vice versa
wTradedMonMovingRight::
wOptionsInitialized::
wNewSlotMachineBallTile::
; how much to add to the X/Y coord
wCoordAdjustmentAmount::
wUnusedWaterDropletsByte::
	db

wSlideMonDelay::
; generic counter variable for various animations
wAnimCounter::
; controls what transformations are applied to the subanimation
; 01: flip horizontally and vertically
; 02: flip horizontally and translate downwards 40 pixels
; 03: translate base coordinates of frame blocks, but don't change their internal coordinates or flip their tiles
; 04: reverse the subanimation
wSubAnimTransform::
	db
ENDU

wEndBattleWinTextPointer:: dw
wEndBattleLoseTextPointer:: dw
	ds 2
wEndBattleTextRomBank:: db

	ds 1

; the address _of the address_ of the current subanimation entry
wSubAnimAddrPtr:: dw

UNION
; the address of the current subentry of the current subanimation
wSubAnimSubEntryAddr:: dw

NEXTU
; If non-zero, the allow matches flag is always set.
; There is a 1/256 (~0.4%) chance that this value will be set to 60, which is
; the only way it can increase. Winning certain payout amounts will decrement it
; or zero it.
wSlotMachineAllowMatchesCounter:: db
ENDU

	ds 2

wOutwardSpiralTileMapPointer:: db

wPartyMenuAnimMonEnabled::
; non-zero when enabled. causes nest locations to blink on and off.
; the town selection cursor will blink regardless of what this value is
wTownMapSpriteBlinkingEnabled:: db

; current destination address in OAM for frame blocks (big endian)
wFBDestAddr:: dw

; controls how the frame blocks are put together to form frames
; specifically, after finishing drawing the frame block, the frame block's mode determines what happens
; 00: clean OAM buffer and delay
; 02: move onto the next frame block with no delay and no cleaning OAM buffer
; 03: delay, but don't clean OAM buffer
; 04: delay, without cleaning OAM buffer, and do not advance [wFBDestAddr], so that the next frame block will overwrite this one
wFBMode:: db

; 0 = small
; 1 = big
wLinkCableAnimBulgeToggle::
wIntroNidorinoBaseTile::
wOutwardSpiralCurrentDirection::
wDropletTile::
wNewTileBlockID::
wWhichBattleAnimTileset::
; 0 = left
; 1 = right
wSquishMonCurrentDirection::
; the tile ID of the leftmost tile in the bottom row in AnimationSlideMonUp_
wSlideMonUpBottomRowLeftTile::
	db

wDisableVBlankWYUpdate:: db ; if non-zero, don't update WY during V-blank

wSpriteCurPosX:: db
wSpriteCurPosY:: db
wSpriteWidth:: db
wSpriteHeight:: db
; current input byte
wSpriteInputCurByte:: db
; bit offset of last read input bit
wSpriteInputBitCounter:: db

; determines where in the output byte the two bits are placed. Each byte contains four columns (2bpp data)
; 3 -> XX000000   1st column
; 2 -> 00XX0000   2nd column
; 1 -> 0000XX00   3rd column
; 0 -> 000000XX   4th column
wSpriteOutputBitOffset:: db

; bit 0 determines used buffer (0 -> sSpriteBuffer1, 1 -> sSpriteBuffer2)
; bit 1 loading last sprite chunk? (there are at most 2 chunks per load operation)
wSpriteLoadFlags:: db
wSpriteUnpackMode:: db
wSpriteFlipped:: db

; pointer to next input byte
wSpriteInputPtr:: dw
; pointer to current output byte
wSpriteOutputPtr:: dw
; used to revert pointer for different bit offsets
wSpriteOutputPtrCached:: dw
; pointer to differential decoding table (assuming initial value 0)
wSpriteDecodeTable0Ptr:: dw
; pointer to differential decoding table (assuming initial value 1)
wSpriteDecodeTable1Ptr:: dw

; input for GetMonHeader
wCurSpecies::
; input for GetName
wNameListIndex:: db
wNameListType:: db

wPredefBank:: db

wMonHeader::
; In the ROM base stats data structure, this is the dex number, but it is
; overwritten with the internal index number after the header is copied to WRAM.
wMonHIndex:: db
wMonHBaseStats::
wMonHBaseHP:: db
wMonHBaseAttack:: db
wMonHBaseDefense:: db
wMonHBaseSpeed:: db
wMonHBaseSpecial:: db
wMonHTypes::
wMonHType1:: db
wMonHType2:: db
wMonHCatchRate:: db
wMonHBaseEXP:: db
wMonHSpriteDim:: db
wMonHFrontSprite:: dw
wMonHBackSprite:: dw
wMonHMoves:: ds NUM_MOVES
wMonHGrowthRate:: db
wMonHLearnset:: flag_array NUM_TMS + NUM_HMS
	ds 1
wMonHeaderEnd::

; saved at the start of a battle and then written back at the end of the battle
wSavedTileAnimations:: db

	ds 2

wDamage:: dw

	ds 2

wRepelRemainingSteps:: db

; list of moves for FormatMovesString
wMoves:: ds NUM_MOVES

wMoveNum:: db

; concatenated move name list where intermediate '@' are replaced with '<NEXT>'
wMovesString:: ds NUM_MOVES * MOVE_NAME_LENGTH


; wWalkBikeSurfState is sometimes copied here, but it doesn't seem to be used for anything
wWalkBikeSurfStateCopy:: db

; the type of list for InitList to init
wInitListType:: db

; 0 if no mon was captured
wCapturedMonSpecies:: db

; Non-zero when the first player mon and enemy mon haven't been sent out yet.
; It prevents the game from asking if the player wants to choose another mon
; when the enemy sends out their first mon and suppresses the "no will to fight"
; message when the game searches for the first non-fainted mon in the party,
; which will be the first mon sent out.
wFirstMonsNotOutYet:: db

wNamedObjectIndex::
wTempByteValue::
wNumSetBits::
wTypeEffectiveness::
wMoveType::
wPokedexNum::
wTempTMHM::
wUsingPPUp::
wMaxPP::
wMoveGrammar::
; 0 for player, non-zero for enemy
wCalculateWhoseStats::
wPokeBallCaptureCalcTemp::
; lower nybble: number of shakes
; upper nybble: number of animations to play
wPokeBallAnimData::
	db

; When this value is non-zero, the player isn't allowed to exit the party menu
; by pressing B and not choosing a mon.
wForcePlayerToChooseMon:: db

; number of times the player has tried to run from battle
wNumRunAttempts:: db

wEvolutionOccurred:: db

wVBlankSavedROMBank:: db

	ds 1

wIsKeyItem:: db

wTextBoxID:: db

; bit 5: set when maps first load; can be reset to re-run a script
; bit 6: set when maps first load; can be reset to re-run a script (used less often than bit 5)
; bit 7: set when using an elevator map's menu; triggers the shaking animation
wCurrentMapScriptFlags:: db

wCurEnemyLevel:: db

; pointer to list of items terminated by $FF
wItemListPointer:: dw

; number of entries in a list
wListCount:: db

wLinkState:: db

wTwoOptionMenuID:: db

; the id of the menu item the player ultimately chose
wChosenMenuItem::
; non-zero when the whole party has fainted due to out-of-battle poison damage
wOutOfBattleBlackout:: db

; the way the user exited a menu
; for list menus and the buy/sell/quit menu:
; $01 = the user pressed A to choose a menu item
; $02 = the user pressed B to cancel
; for two-option menus:
; $01 = the user pressed A with the first menu item selected
; $02 = the user pressed B or pressed A with the second menu item selected
wMenuExitMethod:: db

; the size is always 6, so they didn't need a variable in RAM for this
wDungeonWarpDataEntrySize::
; 0 = museum guy
; 1 = gym guy
wWhichPewterGuy::
; there are 3 windows, from 0 to 2
wWhichPrizeWindow::
; a horizontal or vertical gate block
wGymGateTileBlock:: db

wSavedSpriteScreenY:: db
wSavedSpriteScreenX:: db
wSavedSpriteMapY:: db
wSavedSpriteMapX:: db

	ds 5

wWhichPrize:: db

; counts downward each frame
; when it hits 0, BIT_DISABLE_JOYPAD of wStatusFlags5 is reset
wIgnoreInputCounter:: db

; counts down once every step
wStepCounter:: db

; after a battle, you have at least 3 steps before a random battle can occur
wNumberOfNoRandomBattleStepsLeft:: db

wPrize1:: db
wPrize2:: db
wPrize3:: db

	ds 1

UNION
wSerialRandomNumberListBlock:: ds $11

NEXTU
wPrize1Price:: dw
wPrize2Price:: dw
wPrize3Price:: dw

	ds 1

; shared list of 9 random numbers, indexed by wLinkBattleRandomNumberListIndex
wLinkBattleRandomNumberList:: ds 10
ENDU

wSerialPlayerDataBlock:: ; ds $1a8

; When a real item is being used, this is 0.
; When a move is acting as an item, this is the ID of the item it's acting as.
; For example, out-of-battle Dig is executed using a fake Escape Rope item. In
; that case, this would be ESCAPE_ROPE.
wPseudoItemID:: db

wIsTrainerBattle:: db

wWasTrainerBattle:: db

wEvoStoneItemID:: db

wSavedNPCMovementDirections2Index:: db

wPlayerName:: ds NAME_LENGTH


SECTION "Party Data", WRAM0

wPartyDataStart::

wPartyCount:: db
wPartySpecies:: ds PARTY_LENGTH + 1

wPartyMons::
; wPartyMon1 - wPartyMon6
FOR n, 1, PARTY_LENGTH + 1
wPartyMon{d:n}:: party_struct wPartyMon{d:n}
ENDR

wPartyMonOT::
; wPartyMon1OT - wPartyMon6OT
FOR n, 1, PARTY_LENGTH + 1
wPartyMon{d:n}OT:: ds NAME_LENGTH
ENDR

wPartyMonNicks::
; wPartyMon1Nick - wPartyMon6Nick
FOR n, 1, PARTY_LENGTH + 1
wPartyMon{d:n}Nick:: ds NAME_LENGTH
ENDR
wPartyMonNicksEnd::

wPartyDataEnd::


SECTION "Main Data", WRAM0

wMainDataStart::

wPokedexOwned:: flag_array NUM_POKEMON
wPokedexOwnedEnd::

wPokedexSeen:: flag_array NUM_POKEMON
wPokedexSeenEnd::

; Recovery pocket — one count byte per item type (0=none, N=have N).
; Display order matches RecoveryItemTable in custom_functions/pocket_items.asm.
wRecoveryItemCounts:: ds NUM_RECOVERY_ITEMS  ; 21 bytes

; Stat pocket — evolution stones, vitamins, Rare Candy, PP Up.
wStatItemCounts:: ds NUM_STAT_ITEMS          ; 14 bytes (Phase 11: +M_GENE, +M_TOME)

; Valuable pocket — sell-only items (Nugget, Pearl, etc.).
wValuableItemCounts:: ds NUM_VALUABLE_ITEMS  ; 4 bytes

; Key items pocket is pure bitfield in sKeyItemsBitfield (SRAM), no WRAM needed.
; The display list is built on demand by BuildKeyItemPocketList (ROMX).

; Legacy stubs — wBagItems/wNumBagItems kept at minimal size so old item-use,
; pokemart, and inventory code compiles while it is migrated to the new system.
; Nothing should route here in normal play (GiveItem dispatches to count arrays).
wNumBagItems:: db
wBagItems:: ds 7        ; padded — enough clearance so sentinel can't reach wPlayerMoney
; wNumBagKeyItems alias pointing at the old byte; now meaningless (0 always)
wNumBagKeyItems:: db

; bits related to bag pockets (see ram_constants.asm) ; marcelnote - new for bag pockets
wBagPocketsFlags:: db

wPlayerMoney:: ds 3 ; BCD

wRivalName:: ds NAME_LENGTH

wOptions:: db

wObtainedBadges:: flag_array NUM_BADGES

wLetterPrintingDelayFlags:: db

wPlayerID:: dw

wMapMusicSoundID:: db
wMapMusicROMBank:: db

; offset subtracted from FadePal4 to get the background and object palettes for the current map
; normally, it is 0. it is 6 when Flash is needed, causing FadePal2 to be used instead of FadePal4
wMapPalOffset:: db

; pointer to the upper left corner of the current view in the tile block map
wCurrentTileBlockMapViewPointer:: dw

; player's position on the current map
wYCoord:: db
wXCoord:: db

; player's position (by block)
wYBlockCoord:: db
wXBlockCoord:: db

wLastMap:: db

wCurMapHeader::
wCurMapTileset:: db
wCurMapHeight:: db
wCurMapWidth:: db
wCurMapDataPtr:: dw
wCurMapTextPtr:: dw
wCurMapScriptPtr:: dw
wCurMapConnections:: db
wCurMapHeaderEnd::

wNorthConnectionHeader:: map_connection_struct wNorth
wSouthConnectionHeader:: map_connection_struct wSouth
wWestConnectionHeader::  map_connection_struct wWest
wEastConnectionHeader::  map_connection_struct wEast

; sprite set for the current map (11 sprite picture ID's)
wSpriteSet:: ds SPRITE_SET_LENGTH
; sprite set ID for the current map
wSpriteSetID:: db

wObjectDataPointerTemp:: dw

	ds 2

; the tile shown outside the boundaries of the map
wMapBackgroundTile:: db

; number of warps in current map (up to MAX_WARP_EVENTS)
wNumberOfWarps:: db

; current map warp entries
wWarpEntries:: ds MAX_WARP_EVENTS * 4 ; Y, X, warp ID, map ID

; if $ff, the player's coordinates are not updated when entering the map
wDestinationWarpID:: db

wFollowerDataStart::
; Fixed-Pikachu Yellow follower test slice. The command-buffer size is the
; last occupied index: $ff means empty, 0 means the one lag command remains.
wFollowerCommandBufferSize:: db
wFollowerCommandBuffer:: ds 16
; Yellow wPikachuSpawnState. Ordinary indoor warps use 0 (overlap), while
; connected-map transitions use 2 (one tile behind the player).
wFollowerSpawnState:: db
; Yellow wPikachuOverworldStateFlags bit 6. HandleLedges reaches the accepted
; step seam twice; the first call queues a two-tile command and the second
; clears this latch without queuing another command.
wFollowerLedgeLatch:: db
	ds 128 - 19
wFollowerDataEnd::
ASSERT wFollowerDataEnd - wFollowerDataStart == 128

; number of signs in the current map (up to MAX_BG_EVENTS)
wNumSigns:: db

wSignCoords:: ds MAX_BG_EVENTS * 2 ; Y, X
wSignTextIDs:: ds MAX_BG_EVENTS

; number of sprites on the current map (up to MAX_OBJECT_EVENTS)
wNumSprites:: db

; these two variables track the X and Y offset in blocks from the last special warp used
; they don't seem to be used for anything
wYOffsetSinceLastSpecialWarp:: db
wXOffsetSinceLastSpecialWarp:: db

wMapSpriteData:: ds MAX_OBJECT_EVENTS * 2 ; movement byte 2, text ID
wMapSpriteExtraData:: ds MAX_OBJECT_EVENTS * 2 ; trainer class/item ID, trainer set ID

; map height in 2x2 meta-tiles
wCurrentMapHeight2:: db

; map width in 2x2 meta-tiles
wCurrentMapWidth2:: db

; the address of the upper left corner of the visible portion of the BG tile map in VRAM
wMapViewVRAMPointer:: dw

; In the comments for the player direction variables below, "moving" refers to
; both walking and changing facing direction without taking a step.

; if the player is moving, the current direction
; if the player is not moving, zero
; map scripts write to this in order to change the player's facing direction
wPlayerMovingDirection:: db

; the direction in which the player was moving before the player last stopped
wPlayerLastStopDirection:: db

; if the player is moving, the current direction
; if the player is not moving, the last the direction in which the player moved
wPlayerDirection:: db

wTilesetBank:: db

; maps blocks (4x4 tiles) to tiles
wTilesetBlocksPtr:: dw

wTilesetGfxPtr:: dw

; list of all walkable tiles
wTilesetCollisionPtr:: dw

wTilesetTalkingOverTiles:: ds 3

wGrassTile:: db

	ds 4

wNumBoxItems:: db
; item, quantity
wBoxItems:: ds PC_ITEM_CAPACITY * 2 + 1

; bits 0-6: box number
; bit 7: whether the player has changed boxes before
wCurrentBoxNum:: db

	ds 1

; number of HOF teams
wNumHoFTeams:: db

wPlayerCoins:: dw ; BCD

; bit array of toggleable objects; bit set = toggled off
wToggleableObjectFlags:: flag_array $100
wToggleableObjectFlagsEnd::

	ds 7

; saved copy of SPRITESTATEDATA1_IMAGEINDEX (used for sprite facing/anim)
wSavedSpriteImageIndex:: db

; each entry consists of 2 bytes
; * the sprite ID (depending on the current map)
; * the toggleable object index (global, used for wToggleableObjectFlags)
; terminated with $FF
wToggleableObjectList:: ds 16 * 2 + 1

	ds 1

wGameProgressFlags::
wOaksLabCurScript:: db
wPalletTownCurScript:: db
	ds 1
wBluesHouseCurScript:: db
wViridianCityCurScript:: db
	ds 2
wPewterCityCurScript:: db
wRoute3CurScript:: db
wRoute4CurScript:: db
	ds 1
wViridianGymCurScript:: db
wPewterGymCurScript:: db
wCeruleanGymCurScript:: db
wVermilionGymCurScript:: db
wCeladonGymCurScript:: db
wRoute6CurScript:: db
wRoute8CurScript:: db
wRoute24CurScript:: db
wRoute25CurScript:: db
wRoute9CurScript:: db
wRoute10CurScript:: db
wMtMoon1FCurScript:: db
wMtMoonB2FCurScript:: db
wSSAnne1FRoomsCurScript:: db
wSSAnne2FRoomsCurScript:: db
wRoute22CurScript:: db
	ds 1
wRedsHouse2FCurScript:: db
wSilphCoB1FCurScript:: db
wRoute22GateCurScript:: db
wCeruleanCityCurScript:: db
	; ds 7 will this cause an issue? Probably not
wSSAnneBowCurScript:: db
wViridianForestCurScript:: db
wMuseum1FCurScript:: db
wRoute13CurScript:: db
wRoute14CurScript:: db
wRoute17CurScript:: db
wRoute19CurScript:: db
wRoute21CurScript:: db
wSafariZoneGateCurScript:: db
wRockTunnelB1FCurScript:: db
wRockTunnel1FCurScript:: db
	ds 1
wRoute11CurScript:: db
wRoute12CurScript:: db
wRoute15CurScript:: db
wRoute16CurScript:: db
wRoute18CurScript:: db
wRoute20CurScript:: db
wSSAnneB1FRoomsCurScript:: db
wVermilionCityCurScript:: db
wPokemonTower2FCurScript:: db
wPokemonTower3FCurScript:: db
wPokemonTower4FCurScript:: db
wPokemonTower5FCurScript:: db
wPokemonTower6FCurScript:: db
wPokemonTower7FCurScript:: db
wRocketHideoutB1FCurScript:: db
wRocketHideoutB2FCurScript:: db
wRocketHideoutB3FCurScript:: db
wRocketHideoutB4FCurScript:: db
	ds 1
wRoute6GateCurScript:: db
wRoute8GateCurScript:: db
	ds 1
wCinnabarIslandCurScript:: db
wPokemonMansion1FCurScript:: db
	ds 1
wPokemonMansion2FCurScript:: db
wPokemonMansion3FCurScript:: db
wPokemonMansionB1FCurScript:: db
wVictoryRoad2FCurScript:: db
wVictoryRoad3FCurScript:: db
	ds 1
wFightingDojoCurScript:: db
wSilphCo2FCurScript:: db
wSilphCo3FCurScript:: db
wSilphCo4FCurScript:: db
wSilphCo5FCurScript:: db
wSilphCo6FCurScript:: db
wSilphCo7FCurScript:: db
wSilphCo8FCurScript:: db
wSilphCo9FCurScript:: db
wHallOfFameCurScript:: db
wChampionsRoomCurScript:: db
wLoreleisRoomCurScript:: db
wBrunosRoomCurScript:: db
wAgathasRoomCurScript:: db
wCeruleanCaveB1FCurScript:: db
wVictoryRoad1FCurScript:: db
	ds 1
wLancesRoomCurScript:: db
	ds 4
wSilphCo10FCurScript:: db
wSilphCo11FCurScript:: db
	ds 1
wFuchsiaGymCurScript:: db
wSaffronGymCurScript:: db
	ds 1
wCinnabarGymCurScript:: db
wGameCornerCurScript:: db
wRoute16Gate1FCurScript:: db
wBillsHouseCurScript:: db
wRoute5GateCurScript:: db
wPowerPlantCurScript:: ; overload
wRoute7GateCurScript:: db
	;ds 1
wSSAnne2FCurScript:: db
wSeafoamIslandsB3FCurScript:: db
wRoute23CurScript:: db
wSeafoamIslandsB4FCurScript:: db
wRoute18Gate1FCurScript:: db
	;ds 78  I REMOVED THIS, COULD BE AN ISSUE
; Rogue stage map script (added for rogue stages that lacked trainers and such in the past)
wDiglettsCaveCurScript:: db
wSeafoamIslands1FCurScript:: db
wSilphCo1FCurScript:: db
wSSAnneB1FCurScript:: db
wRoute1CurScript:: db
wRoute5CurScript:: db
wUndergroundPathRoute5CurScript:: db
wProceduralCave1CurScript:: db ; also reused by the procedural facility script
                               ; (scripts/ProceduralFacility.asm) - WRAM0 is full,
                               ; and cave/facility are never loaded concurrently, so
                               ; they share this map-script-index byte
wProceduralCemetery4CurScript:: db
wProceduralForestCurScript:: db
wRoguePokemon1:: db
wRoguePokemon2:: db
wRoguePokemon3:: db
wRogueMap:: db

; scratch for GetRewardMonLevel's cross-bank table read - must NOT be wEvoDataBuffer
; or any other union member, since some callers (e.g. Daycare's withdraw text) still
; need wNameBuffer intact after calling GetRewardMonLevel
; POTENTIAL CUT if WRAM gets tight: only 2 bytes, but FarCopyData needs a real
; addressable WRAM destination (can't target registers/stack), so reclaiming
; this would mean pointing it at some other existing scratch buffer instead -
; safe only if that buffer is never live across GetRewardMonLevel's callers
; (re-review the note above before doing that, to avoid reintroducing the same
; union-clobbering bug class that caused the Mr. Mime name glitch)
wRewardLevelDataBuffer:: ds 2

; 32-bit bitfield: bit N = stage N visited this run (by index in RogueStageMapTable)
wVisitedStagesBitfield:: ds 4
; Bit constants: constants/ram_constants.asm BIT_ROGUE_* / BIT_WITCH_ACCEPTED / BIT_MINIBOSS_*.
;   bit 0 (BIT_ROGUE_GYM_NEXT)      - set on route entry, cleared on badge receipt;
;                                     route is next after this gym / gym is next after this route
;   bit 1 (BIT_ROGUE_FINAL_TRAINER) - set by GetRandRoster when the current trainer is the
;                                     final (5th route / 9th gym) trainer of the tier, signalling
;                                     GetRandRosterLoop to apply the level bonus and rarer class
;                                     distribution from trainer_difficulty_settings
;   bit 2 (BIT_ROGUE_TRADE_ACTIVE)  - trade offer is live for this RogueRewardMenu batch
;   bit 3 (BIT_WITCH_ACCEPTED)      - player accepted the active witch challenge
;   bits 4-5 (MINIBOSS_TYPE_MASK)   - offered mini-boss type, 2-bit field (see MINIBOSS_TYPE_SHIFT)
;   bit 6 (BIT_MINIBOSS_DOOR)       - which lobby door holds the mini-boss (0 = door 1, 1 = door 2)
;   bit 7 (BIT_MINIBOSS_ACTIVE)     - a mini-boss is active on the stage being entered
; All 8 bits are allocated - there is no free bit here for new state.
wRogueFlagsBitfield:: db
wRogueItem:: dw
; Random_Item_Selection's TM-ownership retry (AllTMCheck) recurses via jp on a
; hit; if every item in the forced class is already owned (e.g. Debug 2's
; all-TMs default forcing a gym's TM-only roll), it would retry forever with
; no way out. This caps the retries; past MAX_ITEM_SELECTION_RETRIES it just
; accepts the (possibly-owned) item instead of looping.
wItemSelectionRetryCount:: db
wRogueItem2:: dw  ; wild area pokeball 2-4 (custom_functions/procedural_cave_gen.asm) -
wRogueItem3:: dw  ; same single-byte-in-practice convention as wRogueItem above,
wRogueItem4:: db  ; nothing reads/writes the high byte of any of these, so item4's
; high byte is reclaimed below. The wild-area code indexes these by a 2-byte stride
; off wRogueItem (offsets 0,2,4,6) and only ever touches the low bytes, so keeping
; item4 at the same address with a db + db preserves that stride.
; Cemetery generator debug selector (poke via emulator, default 0):
; 0 = normal (dense fill), 1/4 = force procedural (dense fill),
; 2 = force procedural sparse plots, 3 = force prefab. Any other value
; behaves as normal. See CEMETERY_DESIGN_LAPTOP.md Section 5i. Reclaimed
; from item4's dead high byte, so WRAM0 does not grow; relies on the boot
; WRAM clear for its default of 0.
wProcCemDebugMode:: db
; Lobby door sign data: map IDs of the two staged stages currently behind each door
wLobbyDoor1StageMap:: db  ; door 1 (Y=7,X=11) — option 1 stage map ID
wLobbyDoor2StageMap:: db  ; door 2 (Y=8,X=11) — option 2 stage map ID
wRogueDoor1:: db
wRogueDoor2:: db
wRogueDoorSelection:: db
wBattleCount:: db
; Mini-boss framework run-state (see MINIBOSS_FRAMEWORK.md). Both live inside
; wGameProgressFlags so they are zeroed on new game (fresh run starts at 0) and
; saved. The 2 bytes are offset by shrinking the ds 40 padding below
; wGameProgressFlagsEnd (ds 40 -> ds 38) so WRAM0 stays net-zero. Transient
; per-selection state (offered type, which door, active-this-stage) lives in
; wRogueFlagsBitfield bits 4-7 at zero byte cost.
wRoutesSinceSpecial:: db ; non-special routes since the last special (miniboss OR wild area); drives the escalating chance
wMiniBossCount:: db       ; mini-bosses encountered this run; drives the >=2 guarantee
wWildAreaState:: db ; bits 0-2 = cave/forest/cemetery offered-this-cycle mask;
                    ; bits 3-4 = saturating wild-area offered-count (0-3) for the
                    ; >=2-per-run guarantee. Run-scoped: zeroed by FillMemory on new
                    ; game (inside wGameProgressFlags). See WILD_AREA_* in ram_constants.
wProcCemBossBattle:: db ; 1 = the next enemy-mon load is the cemetery ghost boss.
                    ; Set by ProceduralCemetery4's boss trigger, checked+cleared in
                    ; LoadEnemyMonData (PCemMaybeApplyGhostBoss) so only the boss mon
                    ; gets the ghost variant + move, not floor-4 wild encounters.
; Bridge System run-state (twice-per-run gift-room interludes; see
; custom_functions/bridge_selection.asm). Run-scoped (inside wGameProgressFlags:
; zeroed on new game, saved), offset by the ds below to stay net-zero WRAM0.
wBridgeOfferedLo:: db ; offered-this-run bitmask for bridge room indices 0-7
wBridgeState:: db ; bits 0-5 = offered-this-run mask for bridge room indices 8-13;
                  ; bits 6-7 = saturating bridge count (0-3) for the 2-per-run guarantee.
                  ; Packs to exactly 14 rooms; if the roster grows past 14, split the
                  ; count out to its own byte (shrink the ds below by 1 more).
                    ; Zeroed on new game (must default 0 - it gates every enemy load).
; Debug 2 only: low 5 bits hold a 1-based gym (1-8) or route (1-22) index
; to force onto each lobby door independently; 0 = random. Door 1 bits 6-7
; hold the one-shot encounter selector (0 normal, 1 bridge, 2 mini-boss,
; 3 wild area). Consumed after one lobby visit. See SelectAndPatchLobbyExit /
; Debug2ApplyRoundState.
wDebug2ForcedDoor1:: db
wDebug2ForcedDoor2:: db
; LEFTOVERS fraction level: heals 1/(16-level) of each mon's max HP.
; Level 0 = 1/16 ... level 15 = 1/1 (full heal). Increment to "upgrade" the item.
wHealAllItemLevel:: db

; PP_TONIC fraction level: restores 1/(16-level) of max PP for every move.
; Level 0 = 1/16 ... level 15 = 1/1 (full restore). Increment to "upgrade" the item.
wRestorePPItemLevel:: db

; KO_DEFIANCE remaining activations. 0 = exhausted (item stays in bag but does
; nothing). Does not auto-replenish; only increased by future upgrades.
wKODefianceUsages:: db

wroguenpctradegive:: db
wroguenpctradeget:: db
wroguenpctradedialogue:: db
wroguenpctradename:: ds NAME_LENGTH

wroguenpcsell:: db
wroguenpcclass:: db

wItemBonusRarity:: db

UNION
PCClerkText1::
	db ;TX_SCRIPT_MART
    db ;$9
PCClerkText1Items::
    db
    db
    db
    db
    db
    db
    db
    db
    db
    db
    db ;-1 ; end

PCClerkText2::
	db ;TX_SCRIPT_MART
    db ;$9
PCClerkText2Items::
    db
    db
    db
    db
    db
    db
    db
    db
    db
    db
    db ;-1 ; end
    
NEXTU

wProcCaveWildBudget::

NEXTU

wProcCemWildBudget::  ; per-floor wild battle budget for cemetery (same mechanic as cave)

NEXTU

wProcForestWildBudget:: ; forest wild battle budget (same mechanic as cave); never
                        ; concurrent with cave/cemetery, safe to share this byte

NEXTU

wProcFacilityWildBudget:: ; facility wild battle budget (same mechanic as cave); never
                          ; concurrent with cave/cemetery/forest, safe to share this byte
                          
NEXTU
wCurrentGiftGiver:: db
wGift1:: db
wGift2:: db
wGift3:: db

ENDU

; Lobby witch challenge/prize state. wWitchChallenge/wWitchPrize are re-rolled
; (or zeroed) every lobby entry; wWitchAccepted lives in wRogueFlagsBitfield
; (BIT_WITCH_ACCEPTED) since it's a plain flag, not a value.
;
; Challenge effect parameters share a union: only one challenge is ever
; active at a time, so only one of these interpretations is ever live.
; Prize effect parameters do NOT share a union: challenges vary in how long
; they last (some end with the current map, some linger for the rest of the
; run), so it's possible to complete more than one over a run and have more
; than one prize permanently active simultaneously - each needs its own byte.
wWitchChallenge:: db      ; 0 = no witch/challenge this lobby visit, 1-NUM_WITCH_CHALLENGES = challenge id
wWitchPrize:: db          ; 0 = none, 1-NUM_WITCH_PRIZES = prize id, rolled independently of the challenge

UNION
wWitchLevelBonus:: db     ; CHALLENGE_INCREASED_LEVELS: added to enemy levels
NEXTU
wPartyLimit:: db          ; CHALLENGE_PARTY_LIMIT: max party size (default PARTY_LENGTH)
NEXTU
wBattleTurnLimit:: db     ; CHALLENGE_TURN_LIMIT: turns before HP drain begins
wBattleTurnCount:: db     ; CHALLENGE_TURN_LIMIT: current turn count this battle
ENDU

wRewardClassBonus:: db    ; prize a: added to reward mon class arg
wItemClassBonus:: db      ; prize b: added to item tier
wMoneyMultiplier:: db     ; prize c: multiplier for wAmountMoneyWon
wPrizeExpBoost:: db       ; prize d: extra BoostExp pass in GainExperience
; wPrizeCritBoost/wPrizeAccBoost (prizes e/f reserved magnitude bytes) were
; declared but never read - both prizes use fixed magnitudes directly in code
; (matching the same precedent already set by prizes c/d, see
; project-witch-challenge-plan memory), so these 2 bytes were deleted and
; reused below for Phase 2 fusion scratch (WRAM0 is nearly full).

wFusionSecondarySpecies:: db  ; 0 = no fusion active this run; else = secondary mon's species ID
; Dynamic max-base fusion stats (Phase 2). Transient scratch: PrepareFusionCalcStats
; sets it immediately before CalcStats, and _CalcStats auto-clears byte 0 when
; the recalc finishes. Read only by _CalcStat during that one call.
; SAVED: yes - this sits inside the wGameProgressFlags / wMainData region, so it
; IS written to SRAM (5 wasted save bytes). Intentional: staying in that block
; guarantees it's ZEROED on new game, which the sentinel below depends on, and
; WRAM0/HRAM had no spare unsaved-but-zeroed byte to relocate it to. At save time
; byte 0 is always 0 (auto-cleared after every recalc), so the loaded value is a
; harmless 0 = "not active" - no correctness cost, just the wasted save bytes.
; SENTINEL: byte 0 (HP) doubles as the "is this CalcStats call for the fusion
; mon" flag - 0 is impossible for any real species' base HP, so 0 safely means
; "not active" (no spare byte existed for a dedicated flag). The zero-on-new-game
; guarantee above is what makes byte 0 reliably 0 for any CalcStats caller that
; ISN'T wrapped with PrepareFusionCalcStats (enemy mons, single-stat CalcStat,
; etc.); wrapped callers set it, _CalcStats clears it right after.
wFusionSecondaryBaseStats:: ds NUM_STATS  ; secondary's BASE_HP..BASE_SPC only
                               ; (index 0=HP..4=SPC - NOTE this is offset by
                               ; one from wMonHeader's own 1=HP..5=SPC
                               ; convention; _CalcStat's hook accounts for
                               ; this, see calc_stats.asm), pre-cached via
                               ; CacheFusionSecondaryBaseStats so _CalcStat
                               ; never needs to call GetMonHeader mid-read

; Credits currency (see CREDITS_SYSTEM_PLAN_PC.md). Credits themselves live in
; wPlayerCoins; these are run-scoped state, above wGameProgressFlagsEnd so they
; zero on new game.
wCreditsEarnedThisRun:: db   ; tally for the respawn popup; nonzero IS "popup pending"
wExpAllLevel::          db   ; EXP_ALL upgrade tier 0-3 (EXP_ALL had no level byte)

; General-purpose second rogue-run bitfield: wRogueFlagsBitfield (above) has
; zero free bits (see its own comment), so new run-scoped flags land here
; instead of on that byte. 6 of its 8 bits are still free - see WRAM_BIBLE.md
; §0/§K for current WRAM0 headroom. Document every bit here as it's claimed;
; do not add a bit without a comment.
;   bits 0-1: Credit Exchange slot pulls USED this run (0-3, see
;             engine/slots/slot_machine.asm MainSlotMachineLoop and
;             custom_functions/credit_popup.asm RogueOnBlackout, which
;             clears them on the next blackout - i.e. bits, not "remaining",
;             so an untouched/new-game byte already means "3 available")
; the below is from hFlagsFFFA from Shinred
;bit 2 - When set, the CopyData function will only copy when safe to do so for VRAM
;bit 3 - When set, the enhanced GBC overworld BG Map Attributes are being used, was bit 4 in Shinred hFlagsFFFA
;bit 4 - When set, enhanced GBC overworld BG Map Attributes should not be done during RunDefaultPaletteCommand
;bit 5 - DMARoutine will not run in Vblank while this bit is set, was bit 0 in Shinred hFlagsFFFA
;bit 6 - BGmap update functions will not run in Vblank while this bit is set
; bit 7: unused; the saved enhanced-color option now lives in wOptions2 bit 6
wRogueFlagsBitfield2:: db

; Key Item Effects (see KEY_ITEM_EFFECTS_PLAN_PC.md). Run-scoped state, above
; wGameProgressFlagsEnd so it zeroes on new game. sElementPrismType/
; sKeyItemTiers (SRAM) are the source of truth; the two prism bytes here are
; caches resolved once at battle start (see ApplyKeyItemTierEffects /
; RogueOnBlackout), not general-purpose mirrors - see the plan doc for why a
; full WRAM mirror of the SRAM tier/active bits was rejected.
wPrismType::        db   ; cached ELEMENT PRISM type, $FF = none/inactive
wPrismDamageBonus:: db   ; cached percent bonus, 0 = no boost this battle
; Dice charges remaining (not "used", unlike wRogueFlagsBitfield2's slot-pull
; bits) - a fresh/new-game byte reading 0 correctly means "own no dice yet".
; bits 0-1 = DOOR_DICE, bits 2-3 = MON_DICE, bits 4-5 = ITEM_DICE (0-3 each).
; Refilled to 1+tier per die by RogueOnBlackout (custom_functions/credit_popup.asm).
wDiceCharges::      db
wStatExpPasses::    db   ; scratch: STAT_BOOSTER pass count, set once per GainExperience call
; ELEMENT PRISM encounter-bias retry budget, set once per Random_Pokemon_Selection
; call (1 normally, 16 during starter selection) and spent by
; RoguePrismShouldRerollSpecies. Scratch, not persistent state.
wPrismRerollsLeft:: db

wGameProgressFlagsEnd::

; Elite Four room order for the final sequence: index (0-23) into
; Elite4OrderTable (data/trainers/parties.asm), rolled once when the Victory
; Road Rival is defeated (see BIT_VICTORY_ROAD_CLEARED). Below
; wGameProgressFlagsEnd, so NOT auto-zeroed on new game - harmless here since
; it is only ever read after being freshly rolled that same run, and is
; explicitly reset in HallOfFame.asm on run completion.
wElite4Order:: db

; Second options byte, for the extra options menu (SELECT on the OPTION screen).
; Deliberately NOT extra bits on wOptions: bits 0-3 of that byte are consumed by
; home/print_text.asm:17 (`and $f`, four bits, not the three TEXT_DELAY_MASK
; suggests), and SetCursorPositionsFromOptions does `and $3f` then IsInArray over
; TextSpeedOptionData, so any nonzero value in bits 3-5 runs past the table
; terminator. A separate byte avoids both hazards entirely.
; Inside wMainData so it is saved, but BELOW wGameProgressFlagsEnd so it is NOT
; auto-zeroed on new game - InitOptions writes it explicitly instead, the same
; way it already seeds wOptions.
;   bits 0-2: DIFFICULTY_MASK - enemy level difficulty (LEVELS row, extra options menu).
;   bit 3: unused.
;   bits 4-5: SOUND_MASK2 - sound mode (Shin Red import Phase 2.11).
;             0=MONO, 1=EARPHONE1, 2=EARPHONE2, 3=EARPHONE3. Read by
;             Audio1_ApplyMonoStereo (audio/engine_1.asm), set by the AUDIO
;             row in the extra options menu (engine/menus/extra_options.asm).
;   bit 6: enhanced CGB overworld colors (default on)
;   bit 7: ShinRed 60 FPS/double-speed mode (default on)
wOptions2:: db

wRGB:: ds 3
; former hRGB in shinred

	ds 8  ; was ds 36 on master. Shrunk by 10 to offset the procedural-cave merge's
	      ; net WRAM0 growth (3 CurScript bytes minus 1 reclaimed ds, wRogueItem2-4 +
	      ; wProcCemDebugMode, wProcCavePreloadReady, +1 wEventFlags byte from the
	      ; relocated EVENT_BEAT_PC_BOSS). This ds is dead padding below
	      ; wGameProgressFlagsEnd (unnamed, never read/written), so shrinking only
	      ; shifts saved offsets (save-break, acceptable per WRAM_BIBLE.md) with zero
	      ; runtime effect. Tune this number if the linker reports a WRAM0 overflow.
	      ; -3 more for wCreditsEarnedThisRun + wRogueFlagsBitfield2 + wExpAllLevel (Credits system), still net-zero WRAM0
	      ; -1 more for wWildAreaState (wild-area door integration), still net-zero WRAM0
	      ; -1 more for wProcCemBossBattle (cemetery ghost boss flag), still net-zero WRAM0
	      ; -2 more for wBridgeOfferedLo + wBridgeState (Bridge System), still net-zero WRAM0
	      ; -4 more for wPrismType + wPrismDamageBonus + wDiceCharges + wStatExpPasses
	      ;   (Key Item Effects), still net-zero WRAM0
	      ; -1 more for wPrismRerollsLeft (ELEMENT PRISM encounter bias), still net-zero WRAM0
	      ; -1 more for wEventFlags growing by 13 bits / 1 byte (ELEMENT PRISM one-time
	      ;   grant messages, constants/event_constants.asm), still net-zero WRAM0
	      ; -1 more for wPlayerAppearance (selectable player character), still net-zero WRAM0
	      ; -1 more for wOptions2 (extra options menu, Shin Red import Phase 0), still net-zero WRAM0
          ; -3 for wRGB

; Which trainer class the player looks like: index into PlayerAppearanceTable
; (data/player/appearance.asm). 0 = PLAYER_APPEARANCE_RED, so the zero-fill in
; PrepareOakSpeech (wPlayerName..wBoxDataEnd covers this address) already gives a
; valid default on every new game, including the debug .skipSpeech path.
wPlayerAppearance:: db

wObtainedHiddenItemsFlags:: flag_array MAX_HIDDEN_ITEMS

wObtainedHiddenCoinsFlags:: flag_array MAX_HIDDEN_COINS

; $00 = walking
; $01 = biking
; $02 = surfing
wWalkBikeSurfState:: db

	ds 10

wTownVisitedFlag:: flag_array NUM_CITY_MAPS

; starts at 502
wSafariSteps:: dw

; item given to cinnabar lab
wFossilItem:: db
; mon that will result from the item
wFossilMon:: db

	ds 2

; trainer classes start at OPP_ID_OFFSET
wEnemyMonOrTrainerClass:: db

wPlayerJumpingYScreenCoordsIndex:: db

wRivalStarter:: db

; Which ball (ROGUE_STARTER_POKEBALL_1/2/3) the rival picked. Must live in
; stable WRAM, NOT a union: it has to survive the frames between the pick and
; the rival's walk finishing. Claimed from the anonymous ds 1 padding that used
; to sit here, so WRAM0 usage is unchanged.
wRivalStarterBallSpriteIndex:: db

wPlayerStarter:: db

; sprite index of the boulder the player is trying to push
wBoulderSpriteIndex:: db

wLastBlackoutMap:: db

; destination map (for certain types of special warps, not ordinary walking)
wDestinationMap:: db


; used to store the tile in front of the boulder when trying to push a boulder
; also used to store the result of the collision check ($ff for a collision and $00 for no collision)
wTileInFrontOfBoulderAndBoulderCollisionResult:: db

; destination map for dungeon warps
wDungeonWarpDestinationMap:: db

; which dungeon warp within the source map was used
wWhichDungeonWarp:: db

	ds 8

wStatusFlags1:: db
	ds 1
wStatusFlags2:: db
wCableClubDestinationMap::
wStatusFlags3:: db
wStatusFlags4:: db
	ds 1
wStatusFlags5:: db
	ds 1
wStatusFlags6:: db
wStatusFlags7:: db
wElite4Flags:: db
	ds 1
wMovementFlags:: db

wCompletedInGameTradeFlags:: dw

	ds 2

wWarpedFromWhichWarp:: db
wWarpedFromWhichMap:: db

	ds 2

wCardKeyDoorY:: db
wCardKeyDoorX:: db

	ds 2

wFirstLockTrashCanIndex:: db
wSecondLockTrashCanIndex:: db

wEventFlags:: flag_array NUM_EVENTS


UNION
wGrassRate:: db
wGrassMons:: ds WILDDATA_LENGTH - 1

	ds 8

wWaterRate:: db
wWaterMons:: ds WILDDATA_LENGTH - 1

NEXTU
; linked game's trainer name
wLinkEnemyTrainerName:: ds NAME_LENGTH

	ds 1

wSerialEnemyDataBlock:: ; ds $1a8

	ds 9

wEnemyPartyCount:: db
wEnemyPartySpecies:: ds PARTY_LENGTH + 1

wEnemyMons::
; wEnemyMon1 - wEnemyMon6
FOR n, 1, PARTY_LENGTH + 1
wEnemyMon{d:n}:: party_struct wEnemyMon{d:n}
ENDR

wEnemyMonOT::
; wEnemyMon1OT - wEnemyMon6OT
FOR n, 1, PARTY_LENGTH + 1
wEnemyMon{d:n}OT:: ds NAME_LENGTH
ENDR

wEnemyMonNicks::
; wEnemyMon1Nick - wEnemyMon6Nick
FOR n, 1, PARTY_LENGTH + 1
wEnemyMon{d:n}Nick:: ds NAME_LENGTH
ENDR

NEXTU
; Bag pocket display buffers — mutually exclusive with enemy/wild/link data above.
; Only used during overworld bag display; the union members above are only used
; during battle, encounter setup, or link battles. Zero net WRAM cost.
;
; NOTE: wTMPocketBuf uses 1-byte-per-entry format (PRICEDITEMLISTMENU, no qty byte)
; NOTE: This placement causes issues if ITEMS are allowed to be used in battle, it would need to be removed from the union if we wanted to allow that
; because TMs are binary own/not-own. Could be eliminated entirely with a custom
; display function that reads sTMBitfield directly per-render frame if more space
; is ever needed.
;
; Format: count + item_id bytes (TM: 1 byte each) or {item_id,qty} pairs (others) + $FF
	; 73-byte pad so the pocket buffers start at wEnemyMon2's offset (union base+73).
	; This clears BOTH overworld-live and wild-battle-live state of the other two
	; union members:
	;   - member A wild data: wGrassRate/wGrassMons/wWaterRate/wWaterMons = base+0..49
	;     (read every overworld step). Building a pocket in the field must not touch it.
	;   - member B wEnemyMon1 = base+29..72, the only enemy mon live in a WILD battle.
	; Buffers therefore land in wEnemyMon2..6 / OT / nicks (base+73+), which are dead
	; in the overworld and unused in wild battles, so the bag can never corrupt the
	; field's wild data or the active wild mon. Zero WRAM cost: member C stays smaller
	; than the 425-byte enemy member that sets the union size. (Trainer-battle bag still
	; overlaps benched mons wEnemyMon2..6 — pre-existing, masked, out of scope.)
	; The ASSERT after ENDU guards this invariant at build time.
	; wPocketListWritePtr/wPocketListCount no longer live here — they were moved to
	; free WRAM0 (the wTempoModifier tail near the top of this file) to fix a separate
	; wGrassRate-aliasing bug.
	ds 73
wTMPocketBuf::      ds 128  ; 1 + 55×2 + 1 = 113 bytes; 128 for slack
; WRAM tightening options if space is ever needed:
;   A) Switch to 1-byte-per-entry (no qty) + PRICEDITEMLISTMENU format → 57 bytes.
;      Requires fixing PrintListMenuEntries advance (currently assumes 2 bytes/entry)
;      and .switchBagPocket ITEMLISTMENU check. See custom_functions/tm_bag.asm.
;   B) Custom display function reading sTMBitfield directly → 0 bytes (no buffer).
; Sized for 15 key items (the Credits system adds 11 to the existing 4).
; BuildKeyItemPCWithdrawList (custom_functions/key_item_pocket.asm:343) lists
; every OWNED item, so the old ds 10 would overrun into wRecoveryPocketBuf.
wKeyItemPocketBuf:: ds 34   ; 1 + 15×2 + 1 = 32 bytes, 34 for slack
wRecoveryPocketBuf:: ds 44  ; 1 + 21×2 + 1 = 44 bytes
wStatPocketBuf::    ds 30   ; 1 + 14×2 + 1 = 30 bytes (Phase 11: +M_GENE, +M_TOME)
wValuablePocketBuf:: ds 10  ; 1 + 4×2 + 1 = 10 bytes
; Credit Exchange vendor stock (engine/events/credit_mart.asm): count + up to
; 15 one-byte item ids + $ff terminator. Cannot share wItemList (ds 16) - the
; upgrade vendor lists every owned key item, which overflows it at 15 owned.
; Lives here because this union is shadowed by the 425-byte enemy party, so it
; costs zero real WRAM0; the vendor only ever runs in the overworld, where the
; enemy party and wild-encounter data are both dead.
wCreditItemList::   ds 18
ENDU

; The pocket buffers share this union with the wild-encounter data (member A) and
; the enemy party (member B). Building a pocket in the field must not touch the
; wild data, and building it in a wild battle must not touch the active enemy mon
; (wEnemyMon1). Both hold iff the buffers start at or after wEnemyMon2. See the
; ds 73 pad comment above.
ASSERT wTMPocketBuf >= wEnemyMon2, "pocket buffers must start past wEnemyMon1 (overworld + wild-battle safety)"


wTrainerHeaderPtr:: dw

	ds 6

; the trainer the player must face after getting a wrong answer in the Cinnabar
; gym quiz
wOpponentAfterWrongAnswer:: db

; index of current map script, mostly used as index for function pointer array
; mostly copied from map-specific map script pointer and written back later
wCurMapScript:: db

	ds 7

wPlayTimeHours:: db
wPlayTimeMaxed:: db
wPlayTimeMinutes:: db
wPlayTimeSeconds:: db
wPlayTimeFrames:: db

wSafariZoneGameOver:: db

wNumSafariBalls:: db


; 0 if no pokemon is in the daycare
; 1 if pokemon is in the daycare
wDayCareInUse:: db

wDayCareMonName:: ds NAME_LENGTH
wDayCareMonOT::   ds NAME_LENGTH

wDayCareMon:: box_struct wDayCareMon

wDayCareInUse2:: db

wDayCareMonName2:: ds NAME_LENGTH
wDayCareMonOT2::   ds NAME_LENGTH

wDayCareMon2:: box_struct wDayCareMon2


wMainDataEnd::


SECTION "Current Box Data", WRAM0

wBoxDataStart::

wBoxCount:: db
wBoxSpecies:: ds MONS_PER_BOX + 1

wBoxMons::
; wBoxMon1 - wBoxMon20
FOR n, 1, MONS_PER_BOX + 1
wBoxMon{d:n}:: box_struct wBoxMon{d:n}
ENDR

wBoxMonOT::
; wBoxMon1OT - wBoxMon20OT
FOR n, 1, MONS_PER_BOX + 1
wBoxMon{d:n}OT:: ds NAME_LENGTH
ENDR

wBoxMonNicks::
; wBoxMon1Nick - wBoxMon20Nick
FOR n, 1, MONS_PER_BOX + 1
wBoxMon{d:n}Nick:: ds NAME_LENGTH
ENDR
wBoxMonNicksEnd::

wBoxDataEnd::


SECTION "ProcCaveReadyFlag", WRAM0

; 1 = SRAM preload is ready in sProcCaveStagingBuffer; 0 = not ready.
; WRAM (not SRAM) so PyBoy test scripts can poll it without SRAM enabled.
wProcCavePreloadReady:: db


SECTION "Stack", WRAM0

; the stack grows downward
	ds $100 - 1
wStack:: db

ENDSECTION
