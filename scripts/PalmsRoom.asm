PalmsRoom_Script:
	call EnableAutoTextBoxDrawing
	call PalmsRoomHandleMapEntry
	ld a, [wSilphCoB1FCurScript]
	cp SCRIPT_PALMSROOM_NOOP + 1
	jr c, .validState
	ld a, SCRIPT_PALMSROOM_NOOP
	ld [wSilphCoB1FCurScript], a
.validState
	ld hl, PalmsRoom_ScriptPointers
	ld a, [wSilphCoB1FCurScript]
	jp CallFunctionInTable

PalmsRoom_ScriptPointers:
	def_script_pointers
	dw_const PalmsRoomStartApproachScript, SCRIPT_PALMSROOM_START_APPROACH
	dw_const PalmsRoomWaitApproachScript,  SCRIPT_PALMSROOM_WAIT_APPROACH
	dw_const PalmsRoomWaitLanceExitScript, SCRIPT_PALMSROOM_WAIT_LANCE_EXIT
	dw_const PalmsRoomNoopScript,          SCRIPT_PALMSROOM_NOOP

PalmsRoomHandleMapEntry:
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	res BIT_CUR_MAP_LOADED_1, [hl]
	call EndNPCMovementScript
	call PalmsRoomApplyCrisisMusic
	call PalmsRoomShouldStageRescue
	jr c, .stageRescue
	xor a
	ldh [hJoyIgnore], a
	ld a, SCRIPT_PALMSROOM_NOOP
	ld [wSilphCoB1FCurScript], a
	ret
.stageRescue
	ld a, TOGGLE_PALMS_ROOM_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_PALMS_ROOM_LANCE
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a

	; Reassert the authored staging coordinates before the sprites are shown.
	ld a, 3 + 4
	ld [wSprite01StateData2MapY], a
	ld a, 6 + 4
	ld [wSprite01StateData2MapX], a
	ld a, PALMSROOM_PROF_PALM
	call PalmsRoomInitializeStagedSprite
	ld a, 4 + 4
	ld [wSprite02StateData2MapY], a
	ld a, 6 + 4
	ld [wSprite02StateData2MapX], a
	ld a, PALMSROOM_LANCE
	call PalmsRoomInitializeStagedSprite
	ld a, SCRIPT_PALMSROOM_START_APPROACH
	ld [wSilphCoB1FCurScript], a
	ret

PalmsRoomShouldStageRescue:
	ld a, [wWarpedFromWhichMap]
	cp SILPH_CO_B1F
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

PalmsRoomApplyCrisisMusic:
	CheckEvent EVENT_OAK_CHAMPION_DEFEATED
	ret z
	CheckEvent EVENT_FINAL_BRIEFING_COMPLETE
	ret nz
	ld a, MUSIC_SILPH_CO
	ld [wMapMusicSoundID], a
	ld a, BANK(Music_SilphCo)
	ld [wMapMusicROMBank], a
	jp PlayDefaultMusic

; IN: a = object index after its bordered map coordinates have been written.
PalmsRoomInitializeStagedSprite:
	swap a
	ldh [hCurrentSpriteOffset], a
	farcall InitializeSpriteScreenPosition
	ret

PalmsRoomStartApproachScript:
	ld a, 23
	call SilphCoB1FStartMovementDispatcher
	ld a, SCRIPT_PALMSROOM_WAIT_APPROACH
	ld [wSilphCoB1FCurScript], a
	ret

PalmsRoomWaitApproachScript:
	ld a, [wNPCMovementScriptPointerTableNum]
	and a
	ret nz
	call PalmsRoomFaceRescueActors
	call UpdateSprites
	ld a, TEXT_PALMSROOM_RESCUE
	call PalmsRoomDisplayCutsceneText
	ld a, TEXT_PALMSROOM_ROCKET
	call PalmsRoomDisplayCutsceneText
	ld a, TEXT_PALMSROOM_LANCE_HURRY
	call PalmsRoomDisplayCutsceneText
	ld a, 25
	call SilphCoB1FStartMovementDispatcher
	ld a, SCRIPT_PALMSROOM_WAIT_LANCE_EXIT
	ld [wSilphCoB1FCurScript], a
	ret

PalmsRoomWaitLanceExitScript:
	ld a, [wNPCMovementScriptPointerTableNum]
	and a
	ret nz
	ld a, TOGGLE_PALMS_ROOM_LANCE
	ld [wToggleableObjectIndex], a
	predef HideObject
	; Preload the B1F confrontation before that map creates its object sprites.
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
	ld a, PALMSROOM_PROF_PALM
	ldh [hActiveSpriteIndex], a
	ld a, 19
	call SilphCoB1FStartMovementDispatcher
	ld a, SCRIPT_PALMSROOM_NOOP
	ld [wSilphCoB1FCurScript], a
	ret

PalmsRoomFaceRescueActors:
	ld a, PLAYER_DIR_RIGHT
	ld [wPlayerMovingDirection], a
	ld a, SPRITE_FACING_RIGHT
	ld [wSpritePlayerStateData1FacingDirection], a
	ld a, PALMSROOM_PROF_PALM
	ldh [hSpriteIndex], a
	call GetSpriteMovementByte2Pointer
	ld [hl], LEFT
	ld a, SPRITE_FACING_LEFT
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirection
	ld a, PALMSROOM_LANCE
	ldh [hSpriteIndex], a
	call GetSpriteMovementByte2Pointer
	ld [hl], UP
	ld a, SPRITE_FACING_UP
	ldh [hSpriteFacingDirection], a
	jp SetSpriteFacingDirection

; IN: a = text ID. Directional input stays blocked while dialogue remains usable.
PalmsRoomDisplayCutsceneText:
	ldh [hTextID], a
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	call DisplayTextID
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ret

PalmsRoomNoopScript:
	ret

PalmsRoom_TextPointers:
	def_text_pointers
	dw_const PalmsRoomPalmText,       TEXT_PALMSROOM_PALM
	dw_const PalmsRoomLanceText,      TEXT_PALMSROOM_LANCE
	dw_const PalmsRoomRescueText,     TEXT_PALMSROOM_RESCUE
	dw_const PalmsRoomRocketText,     TEXT_PALMSROOM_ROCKET
	dw_const PalmsRoomLanceHurryText, TEXT_PALMSROOM_LANCE_HURRY

PalmsRoomPalmText:
	text_far _PalmsRoomRescueText
	text_end

PalmsRoomLanceText:
	text_far _PalmsRoomLanceHurryText
	text_end

PalmsRoomRescueText:
	text_far _PalmsRoomRescueText
	text_end

PalmsRoomRocketText:
	text_far _PalmsRoomRocketText
	text_end

PalmsRoomLanceHurryText:
	text_far _PalmsRoomLanceHurryText
	text_end
