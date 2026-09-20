DEF SILPHCOB1F_STATE_ELEVATOR_MOVING EQU $fe

SilphCoB1F_Script:
	call EnableAutoTextBoxDrawing
	call SilphCoB1FHandleMapEntry
	CheckEvent EVENT_INTRO_TOUR_COMPLETE
	jr z, .introTour
	ld a, [wSilphCoB1FCurScript]
	cp SCRIPT_SILPHCOB1F_JOHTO_APPROACH
	jp c, SilphCoB1FElevatorBlockerScript
	cp SCRIPT_SILPHCOB1F_FINAL_RETURN_GREETING + 1
	jp nc, SilphCoB1FElevatorBlockerScript
.introTour
	ld hl, SilphCoB1F_ScriptPointers
	ld a, [wSilphCoB1FCurScript]
	jp CallFunctionInTable

SilphCoB1F_ScriptPointers:
	def_script_pointers
	dw_const SilphCoB1FDefaultScript,              SCRIPT_SILPHCOB1F_DEFAULT
	dw_const SilphCoB1FWalkToDormScript,           SCRIPT_SILPHCOB1F_WALK_TO_DORM
	dw_const SilphCoB1FWaitAtDormScript,           SCRIPT_SILPHCOB1F_WAIT_AT_DORM
	dw_const SilphCoB1FWalkToCreditExchangeScript, SCRIPT_SILPHCOB1F_WALK_TO_CREDIT
	dw_const SilphCoB1FWaitAtCreditExchangeScript, SCRIPT_SILPHCOB1F_WAIT_AT_CREDIT
	dw_const SilphCoB1FWalkToVRScript,             SCRIPT_SILPHCOB1F_WALK_TO_VR
	dw_const SilphCoB1FWaitAtVRScript,             SCRIPT_SILPHCOB1F_WAIT_AT_VR
	dw_const SilphCoB1FEnterVRScript,              SCRIPT_SILPHCOB1F_ENTER_VR
	dw_const SilphCoB1FNoopScript,                 SCRIPT_SILPHCOB1F_NOOP
	dw_const SilphCoB1FJohtoApproachScript,         SCRIPT_SILPHCOB1F_JOHTO_APPROACH
	dw_const SilphCoB1FTimeWarpApproachScript,      SCRIPT_SILPHCOB1F_TIMEWARP_APPROACH
	dw_const SilphCoB1FActivationGreetingScript,    SCRIPT_SILPHCOB1F_JOHTO_GREETING
	dw_const SilphCoB1FActivationGreetingScript,    SCRIPT_SILPHCOB1F_TIMEWARP_GREETING
	dw_const SilphCoB1FActivationReturnScript,      SCRIPT_SILPHCOB1F_ACTIVATION_RETURN_DONE
	dw_const SilphCoB1FFinalLanceWarningScript,      SCRIPT_SILPHCOB1F_FINAL_LANCE_WARNING
	dw_const SilphCoB1FFinalPalmApproachScript,      SCRIPT_SILPHCOB1F_FINAL_PALM_APPROACH
	dw_const SilphCoB1FFinalPalmEscapeScript,        SCRIPT_SILPHCOB1F_FINAL_PALM_ESCAPE
	dw_const SilphCoB1FFinalWalkToDoorScript,        SCRIPT_SILPHCOB1F_FINAL_WALK_TO_DOOR
	dw_const SilphCoB1FFinalOpenDoorScript,          SCRIPT_SILPHCOB1F_FINAL_OPEN_DOOR
	dw_const SilphCoB1FFinalEnterRoomScript,         SCRIPT_SILPHCOB1F_FINAL_ENTER_ROOM
	dw_const SilphCoB1FFinalReturnApproachScript,     SCRIPT_SILPHCOB1F_FINAL_RETURN_APPROACH
	dw_const SilphCoB1FFinalReturnGreetingScript,     SCRIPT_SILPHCOB1F_FINAL_RETURN_GREETING

; Normalize the distinct Palm and stair-scientist objects on every map load,
; then stage Checkpoint 2 on the first fresh return from the Dorm after the
; Rival Champion. wWarpedFromWhichMap is written by the common warp handler
; before hCurMap changes, so it is authoritative rather than wLastMap.
SilphCoB1FHandleMapEntry:
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	res BIT_CUR_MAP_LOADED_1, [hl]
	call SilphCoB1FRestorePalmRoomDoor
	call SilphCoB1FApplyStoryMusic
	; A warp can interrupt the shared 1F/B1F dispatcher before its Done state.
	; Clear that inherited movement owner before staging any B1F actor.
	call SilphCoB1FClearMovementState
	CheckEvent EVENT_INTRO_TOUR_COMPLETE
	jp z, SilphCoB1FIntroTourActors
	call SilphCoB1FShouldStageFinalReturn
	jp c, SilphCoB1FStageFinalReturn
	; The Dorm preloads Lance's toggle before B1F object data is created. Branch
	; into final staging before ordinary actor normalization can hide him again.
	call SilphCoB1FShouldStageFinalOpening
	jp c, SilphCoB1FStageFinalOpening
	ld a, TOGGLE_SILPH_CO_B1F_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_SILPH_CO_B1F_SCIENTIST
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_SILPH_CO_B1F_LANCE
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_SILPH_CO_B1F_ROCKET
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, SCRIPT_SILPHCOB1F_NOOP
	ld [wSilphCoB1FCurScript], a
	ld a, [wWarpedFromWhichMap]
	cp SILPH_CO_DORM
	ret nz
	ld a, [wYCoord]
	and a
	ret nz
	ld a, [wXCoord]
	cp 2
	jr z, .eligibleDormWarp
	cp 3
	ret nz
.eligibleDormWarp
	; Later story beats take priority if debug progression or an imported save
	; leaves more than one activation pending at once.
.checkTimeWarpActivation
	CheckEvent EVENT_LANCE_CHAMPION_DEFEATED
	jr z, .checkRivalActivation
	CheckEvent EVENT_KANTO_TIMEWARP_ACTIVATED
	jr nz, .checkRivalActivation
	ld a, SCRIPT_SILPHCOB1F_TIMEWARP_APPROACH
	jr .stageActivation
.checkRivalActivation
	CheckEvent EVENT_RIVAL_CHAMPION_DEFEATED
	ret z
	CheckEvent EVENT_JOHTO_ACTIVATED
	ret nz
	ld a, SCRIPT_SILPHCOB1F_JOHTO_APPROACH
.stageActivation
	ld [wSilphCoB1FCurScript], a
	ld a, TOGGLE_SILPH_CO_B1F_SCIENTIST
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_SILPH_CO_B1F_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef ShowObject

	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld a, PLAYER_DIR_DOWN
	ld [wPlayerMovingDirection], a
	ld a, SPRITE_FACING_DOWN
	ld [wSpritePlayerStateData1FacingDirection], a

	; Sprite map coordinates include the four-tile map border.
	ld a, 1 + 4
	ld [wSprite02StateData2MapY], a
	ld a, 9 + 4
	ld [wSprite02StateData2MapX], a
	ld a, SILPHCOB1F_PROF_PALM
	swap a
	ldh [hCurrentSpriteOffset], a
	farcall InitializeSpriteScreenPosition
	ret

; Carry set only for the first final-opening entry from either Dorm warp.
SilphCoB1FShouldStageFinalOpening:
	ld a, [wWarpedFromWhichMap]
	cp SILPH_CO_DORM
	jr nz, .no
	ld a, [wYCoord]
	and a
	jr nz, .no
	ld a, [wXCoord]
	cp 2
	jr z, .events
	cp 3
	jr nz, .no
.events
	CheckEvent EVENT_OAK_CHAMPION_DEFEATED
	jr z, .no
	CheckEvent EVENT_FINAL_BRIEFING_COMPLETE
	jr nz, .no
	CheckEvent EVENT_PALMS_ROOM_OPEN
	jr nz, .no
	scf
	ret
.no
	and a
	ret

SilphCoB1FShouldStageFinalReturn:
	ld a, [wWarpedFromWhichMap]
	cp PALMS_ROOM
	jr nz, .no
	CheckEvent EVENT_OAK_CHAMPION_DEFEATED
	jr z, .no
	CheckEvent EVENT_PALMS_ROOM_OPEN
	jr z, .no
	CheckEvent EVENT_FINAL_BRIEFING_COMPLETE
	jr nz, .no
	scf
	ret
.no
	and a
	ret
SilphCoB1FIntroTourActors:
	ld a, TOGGLE_SILPH_CO_B1F_SCIENTIST
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_SILPH_CO_B1F_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef_jump ShowObject

; Match Saffron Gym's reload convention exactly: the authored map contains the
; open block, and every load reconstructs the persistent locked/open state.
SilphCoB1FRestorePalmRoomDoor:
	CheckEvent EVENT_PALMS_ROOM_OPEN
	ld a, $54
	jr z, SilphCoB1FReplacePalmRoomDoor
	ld a, $0e
	jr SilphCoB1FReplacePalmRoomDoor

SilphCoB1FOpenPalmRoomDoor::
	SetEvent EVENT_PALMS_ROOM_OPEN
	ld a, $0e
SilphCoB1FReplacePalmRoomDoor:
	ld [wNewTileBlockID], a
	lb bc, 0, 10
	predef_jump ReplaceTileBlock

; The crisis theme begins on the first post-Oak B1F entry and remains the B1F
; default until the AI is defeated. Later checkpoints extend the same override
; to the other facility maps.
SilphCoB1FApplyStoryMusic:
	CheckEvent EVENT_OAK_CHAMPION_DEFEATED
	ret z
	CheckEvent EVENT_AI_DEFEATED
	ret nz
	ld a, MUSIC_SILPH_CO
	ld [wMapMusicSoundID], a
	ld a, BANK(Music_SilphCo)
	ld [wMapMusicROMBank], a
	jp PlayDefaultMusic

SilphCoB1FStageFinalOpening:
	ld a, TOGGLE_SILPH_CO_B1F_SCIENTIST
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_SILPH_CO_B1F_ROCKET
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_SILPH_CO_B1F_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_SILPH_CO_B1F_LANCE
	ld [wToggleableObjectIndex], a
	predef ShowObject

	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	call SilphCoB1FFaceLanceAndPlayer

	; Stage Fake Palm offscreen at (9,1).
	ld a, 1 + 4
	ld [wSprite02StateData2MapY], a
	ld a, 9 + 4
	ld [wSprite02StateData2MapX], a
	ld a, SILPHCOB1F_PROF_PALM
	swap a
	ldh [hCurrentSpriteOffset], a
	farcall InitializeSpriteScreenPosition

	; Stage Lance one row below whichever Dorm warp the player used.
	ld a, 1 + 4
	ld [wSprite03StateData2MapY], a
	ld a, [wXCoord]
	add 4
	ld [wSprite03StateData2MapX], a
	ld a, SILPHCOB1F_LANCE
	swap a
	ldh [hCurrentSpriteOffset], a
	farcall InitializeSpriteScreenPosition

	ld a, SCRIPT_SILPHCOB1F_FINAL_LANCE_WARNING
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FFinalLanceWarningScript:
	call SilphCoB1FFaceLanceAndPlayer
	call UpdateSprites
	ld a, TEXT_SILPHCOB1F_FINAL_LANCE_WARNING
	call SilphCoB1FDisplayFinalText
	ld de, SilphCoB1FFakePalmApproachMovement
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hSpriteIndex], a
	call MoveSprite
	ld a, SCRIPT_SILPHCOB1F_FINAL_PALM_APPROACH
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FFinalPalmApproachScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hSpriteIndex], a
	; MoveSprite replaces the authored facing constraint with NONE. Restore the
	; fixed direction as well as the displayed frame so the bubble/text wait
	; cannot let Palm's idle animation turn him down.
	call GetSpriteMovementByte2Pointer
	ld [hl], LEFT
	ld a, SPRITE_FACING_LEFT
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirection
	call UpdateSprites
	ld a, SILPHCOB1F_PROF_PALM
	ld [wEmotionBubbleSpriteIndex], a
	xor a ; EXCLAMATION_BUBBLE
	ld [wWhichEmotionBubble], a
	predef EmotionBubble
	ld a, TEXT_SILPHCOB1F_FINAL_FAKE_PALM
	call SilphCoB1FDisplayFinalText
	ld de, SilphCoB1FFakePalmEscapeMovement
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hSpriteIndex], a
	call MoveSprite
	ld a, SCRIPT_SILPHCOB1F_FINAL_PALM_ESCAPE
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FFinalPalmEscapeScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz
	ld a, TOGGLE_SILPH_CO_B1F_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef HideObject
	call SilphCoB1FFaceLanceAndPlayer
	call UpdateSprites
	ld a, TEXT_SILPHCOB1F_FINAL_LANCE_REACTION
	call SilphCoB1FDisplayFinalText
	ld a, SILPHCOB1F_LANCE
	ldh [hActiveSpriteIndex], a
	ld a, 15
	call SilphCoB1FStartMovementDispatcher
	ld a, SCRIPT_SILPHCOB1F_FINAL_WALK_TO_DOOR
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FFinalWalkToDoorScript:
	ld a, [wNPCMovementScriptPointerTableNum]
	and a
	ret nz
	ld a, SILPHCOB1F_LANCE
	ldh [hSpriteIndex], a
	; The synchronized MoveSprite path clears the authored STAY/UP constraint.
	; Restore the constraint as well as the frame so Lance remains facing up.
	call GetSpriteMovementByte2Pointer
	ld [hl], UP
	ld a, SPRITE_FACING_UP
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirection
	ld a, SCRIPT_SILPHCOB1F_FINAL_OPEN_DOOR
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FFinalOpenDoorScript:
	call SilphCoB1FOpenPalmRoomDoor
	; Preload Palm's Room actors before its object data is created.
	ld a, TOGGLE_PALMS_ROOM_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_PALMS_ROOM_LANCE
	ld [wToggleableObjectIndex], a
	predef ShowObject
	call UpdateSprites
	ld a, SCRIPT_SILPHCOB1F_FINAL_ENTER_ROOM
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FFinalEnterRoomScript:
	ld a, SILPHCOB1F_LANCE
	ldh [hActiveSpriteIndex], a
	ld a, 17
	call SilphCoB1FStartMovementDispatcher
	ld a, SCRIPT_SILPHCOB1F_NOOP
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FStageFinalReturn:
	ld a, TOGGLE_SILPH_CO_B1F_SCIENTIST
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_SILPH_CO_B1F_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_SILPH_CO_B1F_LANCE
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_SILPH_CO_B1F_ROCKET
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a

	; Palm returns on the left warp at (20,0).
	ld a, 0 + 4
	ld [wSprite02StateData2MapY], a
	ld a, 20 + 4
	ld [wSprite02StateData2MapX], a
	ld a, SILPHCOB1F_PROF_PALM
	call SilphCoB1FInitializeStagedSprite

	; Lance and the Rocket block the stairs.
	ld a, 1 + 4
	ld [wSprite03StateData2MapY], a
	ld a, 16 + 4
	ld [wSprite03StateData2MapX], a
	ld a, SILPHCOB1F_LANCE
	call SilphCoB1FInitializeStagedSprite
	ld a, 0 + 4
	ld [wSprite04StateData2MapY], a
	ld a, 16 + 4
	ld [wSprite04StateData2MapX], a
	ld a, SILPHCOB1F_ROCKET
	call SilphCoB1FInitializeStagedSprite

	ld a, SCRIPT_SILPHCOB1F_FINAL_RETURN_APPROACH
	ld [wSilphCoB1FCurScript], a
	ret

; IN: a = object index after its bordered map coordinates have been written.
SilphCoB1FInitializeStagedSprite:
	swap a
	ldh [hCurrentSpriteOffset], a
	farcall InitializeSpriteScreenPosition
	ret

SilphCoB1FFinalReturnApproachScript:
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hActiveSpriteIndex], a
	ld a, 21
	call SilphCoB1FStartMovementDispatcher
	ld a, SCRIPT_SILPHCOB1F_FINAL_RETURN_GREETING
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FFinalReturnGreetingScript:
	ld a, [wNPCMovementScriptPointerTableNum]
	and a
	ret nz
	ld a, PLAYER_DIR_UP
	ld [wPlayerMovingDirection], a
	ld a, SPRITE_FACING_UP
	ld [wSpritePlayerStateData1FacingDirection], a
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hSpriteIndex], a
	call GetSpriteMovementByte2Pointer
	ld [hl], UP
	ld a, SPRITE_FACING_UP
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirection
	ld a, SILPHCOB1F_LANCE
	ldh [hSpriteIndex], a
	call GetSpriteMovementByte2Pointer
	ld [hl], DOWN
	ld a, SPRITE_FACING_DOWN
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirection
	call UpdateSprites
	ld a, TEXT_SILPHCOB1F_FINAL_LANCE_HOLD_OFF
	call SilphCoB1FDisplayFinalText
	; Lance turns back toward the Rocket after addressing the player.
	ld a, SILPHCOB1F_LANCE
	ldh [hSpriteIndex], a
	call GetSpriteMovementByte2Pointer
	ld [hl], UP
	ld a, SPRITE_FACING_UP
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirection
	call UpdateSprites
	xor a
	ldh [hJoyIgnore], a
	ld a, SCRIPT_SILPHCOB1F_NOOP
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FFaceLanceAndPlayer:
	ld a, PLAYER_DIR_DOWN
	ld [wPlayerMovingDirection], a
	ld a, SPRITE_FACING_DOWN
	ld [wSpritePlayerStateData1FacingDirection], a
	ld a, SILPHCOB1F_LANCE
	ldh [hSpriteIndex], a
	ld a, SPRITE_FACING_UP
	ldh [hSpriteFacingDirection], a
	jp SetSpriteFacingDirection

SilphCoB1FDisplayFinalText:
	ldh [hTextID], a
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	call DisplayTextID
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ret

SilphCoB1FFakePalmApproachMovement:
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db -1

SilphCoB1FFakePalmEscapeMovement:
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db -1

SilphCoB1FJohtoApproachScript:
	ld a, SCRIPT_SILPHCOB1F_JOHTO_GREETING
	jr SilphCoB1FStartActivationApproach

SilphCoB1FTimeWarpApproachScript:
	ld a, SCRIPT_SILPHCOB1F_TIMEWARP_GREETING

SilphCoB1FStartActivationApproach:
	push af
	ld de, SilphCoB1FPalmLeftSevenMovement
	ld a, [wXCoord]
	cp 2
	jr z, .start
	ld de, SilphCoB1FPalmLeftSixMovement
.start
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hSpriteIndex], a
	call MoveSprite
	pop af
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FActivationGreetingScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz
	ld a, PLAYER_DIR_DOWN
	ld [wPlayerMovingDirection], a
	ld a, SPRITE_FACING_DOWN
	ld [wSpritePlayerStateData1FacingDirection], a
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hSpriteIndex], a
	call GetSpriteMovementByte2Pointer
	ld [hl], UP
	ld a, SPRITE_FACING_UP
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirection
	call UpdateSprites
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	call SilphCoB1FGetActivationParameters
	ldh [hTextID], a
	call DisplayTextID
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a

	; Match the Room PC's short SRAM transaction and preserve every other group
	; toggle. The parameter mask enables Johto alone for Event 1, or Johto plus
	; Kanto Time Warp for Event 2, without replacing the complete option mask.
	call SilphCoB1FGetActivationParameters
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, [sRogueSpeciesGroupsEnabled]
	or c
	ld [sRogueSpeciesGroupsEnabled], a
	xor a
	ld [rRAMG], a
	ld hl, wEventFlags
	ld c, e
	ld b, FLAG_SET
	predef FlagActionPredef
	farcall SaveGameData

	ld de, SilphCoB1FPalmRightSevenMovement
	ld a, [wXCoord]
	cp 2
	jr z, .startReturn
	ld de, SilphCoB1FPalmRightSixMovement
.startReturn
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hSpriteIndex], a
	call MoveSprite
	ld a, SCRIPT_SILPHCOB1F_ACTIVATION_RETURN_DONE
	ld [wSilphCoB1FCurScript], a
	ret

; Returns a = dialogue text id, c = group-enable mask, e = completion event.
; The current greeting state selects one of two three-byte parameter rows.
SilphCoB1FGetActivationParameters:
	ld a, [wSilphCoB1FCurScript]
	sub SCRIPT_SILPHCOB1F_JOHTO_GREETING
	ld c, a
	add a
	add c
	ld c, a
	ld b, 0
	ld hl, SilphCoB1FActivationParameters
	add hl, bc
	ld a, [hli]
	ld c, [hl]
	inc hl
	ld e, [hl]
	ret

SilphCoB1FActivationParameters:
	db TEXT_SILPHCOB1F_JOHTO_ACTIVATION
	db 1 << BIT_GROUP_JOHTO
	db EVENT_JOHTO_ACTIVATED
	db TEXT_SILPHCOB1F_TIMEWARP_ACTIVATION
	db (1 << BIT_GROUP_JOHTO) | (1 << BIT_GROUP_WARP)
	db EVENT_KANTO_TIMEWARP_ACTIVATED

SilphCoB1FActivationReturnScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz
	; Palm has returned to his offscreen (9,1) start. Hide his dedicated story
	; object and restore the separate stair scientist for ordinary B1F play.
	ld a, TOGGLE_SILPH_CO_B1F_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_SILPH_CO_B1F_SCIENTIST
	ld [wToggleableObjectIndex], a
	predef ShowObject
	call UpdateSprites
	xor a
	ldh [hJoyIgnore], a
	ld a, SCRIPT_SILPHCOB1F_NOOP
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FPalmLeftSevenMovement:
	db NPC_MOVEMENT_LEFT
SilphCoB1FPalmLeftSixMovement:
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db -1

SilphCoB1FPalmRightSevenMovement:
	db NPC_MOVEMENT_RIGHT
SilphCoB1FPalmRightSixMovement:
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db -1

SilphCoB1FDefaultScript:
	;ld hl, wCurrentMapScriptFlags
	;bit BIT_CUR_MAP_LOADED_1, [hl]
	;jr z, .checkPosition
	;res BIT_CUR_MAP_LOADED_1, [hl]
	; The 1F stairs warp can change maps before its dispatcher reaches Done.
	; Clear that inherited dispatcher before B1F starts its own Pallet-style leg.

.checkPosition
	;ld a, [wYCoord]
	;cp 1
	;ret nz
    call EndNPCMovementScript
	ld c, 8
	call DelayFrames
	ld a, PLAYER_DIR_DOWN
	ld [wPlayerMovingDirection], a
	ld a, SPRITE_FACING_DOWN
	ld [wSpritePlayerStateData1FacingDirection], a
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld a, SCRIPT_SILPHCOB1F_WALK_TO_DORM
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FWalkToDormScript:
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hActiveSpriteIndex], a
	ld a, 7
	call SilphCoB1FStartMovementDispatcher
	ld a, SCRIPT_SILPHCOB1F_WAIT_AT_DORM
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FWaitAtDormScript:
	ld a, [wNPCMovementScriptPointerTableNum]
	and a
	ret nz
	call SilphCoB1FFaceTourUp
	call UpdateSprites
	ld a, TEXT_SILPHCOB1F_DORM
	call SilphCoB1FDisplayTourText
	ld a, SCRIPT_SILPHCOB1F_WALK_TO_CREDIT
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FWalkToCreditExchangeScript:
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hActiveSpriteIndex], a
	ld a, 9
	call SilphCoB1FStartMovementDispatcher
	ld a, SCRIPT_SILPHCOB1F_WAIT_AT_CREDIT
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FWaitAtCreditExchangeScript:
	ld a, [wNPCMovementScriptPointerTableNum]
	and a
	ret nz
	call SilphCoB1FFaceTourUp
	call UpdateSprites
	ld a, TEXT_SILPHCOB1F_CREDIT_EXCHANGE
	call SilphCoB1FDisplayTourText
	ld a, SCRIPT_SILPHCOB1F_WALK_TO_VR
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FWalkToVRScript:
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hActiveSpriteIndex], a
	ld a, 11
	call SilphCoB1FStartMovementDispatcher
	ld a, SCRIPT_SILPHCOB1F_WAIT_AT_VR
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FWaitAtVRScript:
	ld a, [wNPCMovementScriptPointerTableNum]
	and a
	ret nz
	call SilphCoB1FFaceTourUp
	call UpdateSprites
	ld a, TEXT_SILPHCOB1F_VR
	call SilphCoB1FDisplayTourText
	ld a, SCRIPT_SILPHCOB1F_ENTER_VR
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FEnterVRScript:
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hActiveSpriteIndex], a
	ld a, 13
	call SilphCoB1FStartMovementDispatcher
	ld a, SCRIPT_SILPHCOB1F_NOOP
	ld [wSilphCoB1FCurScript], a
	ret

; IN: a = function index in SaffronPalmMovementScriptPointerTable.
SilphCoB1FStartMovementDispatcher:
	ld [wNPCMovementScriptFunctionNum], a
	ld a, 1
	ld [wNPCMovementScriptPointerTableNum], a
	ld a, BANK(SaffronPalmMovementScriptPointerTable)
	ld [wNPCMovementScriptBank], a
	ret

SilphCoB1FFaceTourUp:
	ld a, PLAYER_DIR_UP
	ld [wPlayerMovingDirection], a
	ld a, SPRITE_FACING_UP
	ld [wSpritePlayerStateData1FacingDirection], a
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hSpriteIndex], a
	ld a, SPRITE_FACING_UP
	ldh [hSpriteFacingDirection], a
	jp SetSpriteFacingDirection

; IN: a = text ID.
SilphCoB1FDisplayTourText:
	ldh [hTextID], a
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	call DisplayTextID
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ret

SilphCoB1FNoopScript:
	ret

; The final B1F warp can interrupt the dispatcher before its Done function.
; VR calls this standard cleanup on entry before starting its own script.
SilphCoB1FClearMovementState:
	jp EndNPCMovementScript

; Viridian City's closed Gym establishes the convention: detect entry onto a
; forbidden warp, explain why it is blocked, then simulate one step back out.
SilphCoB1FElevatorBlockerScript:
	ld a, [wSilphCoB1FCurScript]
	cp SILPHCOB1F_STATE_ELEVATOR_MOVING
	jr z, .waitForMovement
	ld a, [wYCoord]
	and a
	ret nz
	ld a, [wXCoord]
	cp 18
	ret nz
	ld a, TEXT_SILPHCOB1F_ELEVATOR
	ldh [hTextID], a
	call DisplayTextID
	xor a
	ldh [hJoyHeld], a
	call StartSimulatingJoypadStates
	ld a, 1
	ldh [hSimulatedJoypadStatesIndex], a
	ld a, PAD_DOWN
	ld [wSimulatedJoypadStatesEnd], a
	ld a, SPRITE_FACING_DOWN
	ld [wSpritePlayerStateData1FacingDirection], a
	ld a, SILPHCOB1F_STATE_ELEVATOR_MOVING
	ld [wSilphCoB1FCurScript], a
	ret
.waitForMovement
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	ld a, SCRIPT_SILPHCOB1F_NOOP
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1F_TextPointers:
	def_text_pointers
	dw_const SilphCoB1FScientistText,      TEXT_SILPHCOB1F_SCIENTIST
	dw_const SilphCoB1FProfPalmText,       TEXT_SILPHCOB1F_PROF_PALM
	dw_const SilphCoB1FLanceText,          TEXT_SILPHCOB1F_LANCE
	dw_const SilphCoB1FRocketText,         TEXT_SILPHCOB1F_ROCKET
	dw_const SilphCoB1FElevatorText,       TEXT_SILPHCOB1F_ELEVATOR
	dw_const SilphCoB1FDormText,           TEXT_SILPHCOB1F_DORM
	dw_const SilphCoB1FCreditExchangeText, TEXT_SILPHCOB1F_CREDIT_EXCHANGE
	dw_const SilphCoB1FVRText,             TEXT_SILPHCOB1F_VR
	dw_const SilphCoB1FJohtoActivationText, TEXT_SILPHCOB1F_JOHTO_ACTIVATION
	dw_const SilphCoB1FTimeWarpActivationText, TEXT_SILPHCOB1F_TIMEWARP_ACTIVATION
	dw_const SilphCoB1FFinalLanceWarningText, TEXT_SILPHCOB1F_FINAL_LANCE_WARNING
	dw_const SilphCoB1FFinalFakePalmText,      TEXT_SILPHCOB1F_FINAL_FAKE_PALM
	dw_const SilphCoB1FFinalLanceReactionText, TEXT_SILPHCOB1F_FINAL_LANCE_REACTION
	dw_const SilphCoB1FFinalLanceHoldOffText,  TEXT_SILPHCOB1F_FINAL_LANCE_HOLD_OFF

SilphCoB1FScientistText:
	text_far _SilphCoB1FScientistText
	text_end

; Palm is controlled by map scripts while visible. This fallback keeps the
; object-slot text table aligned if he is ever interacted with unexpectedly.
SilphCoB1FProfPalmText:
	text_far _SilphCoB1FScientistText
	text_end

SilphCoB1FElevatorText:
	text_far _SilphCoB1FElevatorText
	text_end

SilphCoB1FDormText:
	text_far _SilphCoB1FDormText
	text_end

SilphCoB1FCreditExchangeText:
	text_far _SilphCoB1FCreditExchangeText
	text_end

SilphCoB1FVRText:
	text_far _SilphCoB1FVRText
	text_end

SilphCoB1FJohtoActivationText:
	text_far _SilphCoB1FJohtoActivationText
	text_end

SilphCoB1FTimeWarpActivationText:
	text_far _SilphCoB1FTimeWarpActivationText
	text_end

SilphCoB1FFinalLanceWarningText:
	text_far _SilphCoB1FFinalLanceWarningText
	text_end

SilphCoB1FFinalFakePalmText:
	text_far _SilphCoB1FFinalFakePalmText
	text_end

SilphCoB1FFinalLanceReactionText:
	text_far _SilphCoB1FFinalLanceReactionText
	text_end

SilphCoB1FFinalLanceHoldOffText:
	text_far _SilphCoB1FFinalLanceHoldOffText
	text_end

SilphCoB1FLanceText:
	text_far _SilphCoB1FFinalLanceHoldOffText
	text_end

SilphCoB1FRocketText:
	text "..."
	text_end
