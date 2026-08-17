PlayerStepOutFromDoor::
	ld hl, wStatusFlags5
	res BIT_UNKNOWN_5_1, [hl]
	call IsPlayerStandingOnDoorTile
	jr nc, .notStandingOnDoor
	ld a, PAD_SELECT | PAD_START | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld hl, wMovementFlags
	set BIT_EXITING_DOOR, [hl]
	ld a, $1
	ldh [hSimulatedJoypadStatesIndex], a
	ld a, PAD_DOWN
	ld [wSimulatedJoypadStatesEnd], a
	xor a
	ld [wSpritePlayerStateData1ImageIndex], a
	call StartSimulatingJoypadStates
	ret
.notStandingOnDoor
	xor a
	ldh [hSimulatedJoypadStatesIndex], a
	ld [wSimulatedJoypadStatesEnd], a
	ld hl, wMovementFlags
	res BIT_STANDING_ON_DOOR, [hl]
	res BIT_EXITING_DOOR, [hl]
	ld hl, wStatusFlags5
	res BIT_SCRIPTED_MOVEMENT_STATE, [hl]
	ret

_EndNPCMovementScript::
	ld hl, wStatusFlags5
	res BIT_SCRIPTED_MOVEMENT_STATE, [hl]
	ld hl, wStatusFlags4
	res BIT_INIT_SCRIPTED_MOVEMENT, [hl]
	ld hl, wMovementFlags
	res BIT_STANDING_ON_DOOR, [hl]
	res BIT_EXITING_DOOR, [hl]
	xor a
	ld [wNPCMovementScriptSpriteOffset], a
	ld [wNPCMovementScriptPointerTableNum], a
	ld [wNPCMovementScriptFunctionNum], a
	ldh [hSimulatedJoypadStatesIndex], a
	ld [wSimulatedJoypadStatesEnd], a
	ret

;PalletMovementScriptPointerTable::
;	dw PalletMovementScript_OakMoveLeft
;	dw PalletMovementScript_PlayerMoveLeft
;	dw PalletMovementScript_WaitAndWalkToLab
;	dw PalletMovementScript_WalkToLab
;	dw PalletMovementScript_Done
;
;PalletMovementScript_OakMoveLeft:
;	ld a, [wXCoord]
;	sub $a
;	ld [wNumStepsToTake], a
;	jr z, .playerOnLeftTile
;; The player is on the right tile of the northern path out of Pallet Town and
;; Prof. Oak is below.
;; Make Prof. Oak step to the left.
;	ld b, 0
;	ld c, a
;	ld hl, wNPCMovementDirections2
;	ld a, NPC_MOVEMENT_LEFT
;	call FillMemory
;	ld [hl], $ff
;	ldh a, [hActiveSpriteIndex]
;	ldh [hSpriteIndex], a
;	ld de, wNPCMovementDirections2
;	call MoveSprite
;	ld a, $1
;	ld [wNPCMovementScriptFunctionNum], a
;	jr .done
;; The player is on the left tile of the northern path out of Pallet Town and
;; Prof. Oak is below.
;; Prof. Oak is already where he needs to be.
;.playerOnLeftTile
;	ld a, $3
;	ld [wNPCMovementScriptFunctionNum], a
;.done
;	ld hl, wStatusFlags7
;	set BIT_NO_MAP_MUSIC, [hl]
;	ld a, PAD_SELECT | PAD_START | PAD_CTRL_PAD
;	ldh [hJoyIgnore], a
;	ret
;
;PalletMovementScript_PlayerMoveLeft:
;	ld a, [wStatusFlags5]
;	bit BIT_SCRIPTED_NPC_MOVEMENT, a
;	ret nz ; return if Oak is still moving
;	ld a, [wNumStepsToTake]
;	ldh [hSimulatedJoypadStatesIndex], a
;	ldh [hNPCMovementDirections2Index], a
;	predef ConvertNPCMovementDirectionsToJoypadMasks
;	call StartSimulatingJoypadStates
;	ld a, $2
;	ld [wNPCMovementScriptFunctionNum], a
;	ret
;
;PalletMovementScript_WaitAndWalkToLab:
;	ldh a, [hSimulatedJoypadStatesIndex]
;	and a ; is the player done moving left yet?
;	ret nz
;
;PalletMovementScript_WalkToLab:
;	xor a
;	ld [wOverrideSimulatedJoypadStatesMask], a
;	ldh a, [hActiveSpriteIndex]
;	swap a
;	ld [wNPCMovementScriptSpriteOffset], a
;	xor a
;	ld [wSpritePlayerStateData2MovementByte1], a
;	ld hl, wSimulatedJoypadStatesEnd
;	ld de, RLEList_PlayerWalkToLab
;	call DecodeRLEList
;	dec a
;	ldh [hSimulatedJoypadStatesIndex], a
;	ld hl, wNPCMovementDirections2
;	ld de, RLEList_ProfOakWalkToLab
;	call DecodeRLEList
;	ld hl, wStatusFlags4
;	res BIT_INIT_SCRIPTED_MOVEMENT, [hl]
;	ld hl, wStatusFlags5
;	set BIT_SCRIPTED_MOVEMENT_STATE, [hl]
;	ld a, $4
;	ld [wNPCMovementScriptFunctionNum], a
;	ret
;
;RLEList_ProfOakWalkToLab:
;	db NPC_MOVEMENT_DOWN, 5
;	db NPC_MOVEMENT_LEFT, 1
;	db NPC_MOVEMENT_DOWN, 5
;	db NPC_MOVEMENT_RIGHT, 3
;	db NPC_MOVEMENT_UP, 1
;	db NPC_CHANGE_FACING, 1
;	db -1 ; end
;
;RLEList_PlayerWalkToLab:
;	db PAD_UP, 2
;	db PAD_RIGHT, 3
;	db PAD_DOWN, 5
;	db PAD_LEFT, 1
;	db PAD_DOWN, 6
;	db -1 ; end
;
;PalletMovementScript_Done:
;	ldh a, [hSimulatedJoypadStatesIndex]
;	and a
;	ret nz
;	ld a, TOGGLE_PALLET_TOWN_OAK
;	ld [wToggleableObjectIndex], a
;	predef HideObject
;	ld hl, wStatusFlags5
;	res BIT_SCRIPTED_MOVEMENT_STATE, [hl]
;	ld hl, wStatusFlags4
;	res BIT_INIT_SCRIPTED_MOVEMENT, [hl]
;	jp EndNPCMovementScript
;
;PewterMuseumGuyMovementScriptPointerTable::
;	dw PewterMovementScript_WalkToMuseum
;	dw PewterMovementScript_Done
;
;PewterMovementScript_WalkToMuseum:
;	ld a, BANK(Music_MuseumGuy)
;	ld [wAudioROMBank], a
;	ld [wAudioSavedROMBank], a
;	ld a, MUSIC_MUSEUM_GUY
;	ld [wNewSoundID], a
;	call PlaySound
;	ldh a, [hActiveSpriteIndex]
;	swap a
;	ld [wNPCMovementScriptSpriteOffset], a
;	call StartSimulatingJoypadStates
;	ld hl, wSimulatedJoypadStatesEnd
;	ld de, RLEList_PewterMuseumPlayer
;	call DecodeRLEList
;	dec a
;	ldh [hSimulatedJoypadStatesIndex], a
;	xor a
;	ld [wWhichPewterGuy], a
;	predef PewterGuys
;	ld hl, wNPCMovementDirections2
;	ld de, RLEList_PewterMuseumGuy
;	call DecodeRLEList
;	ld hl, wStatusFlags4
;	res BIT_INIT_SCRIPTED_MOVEMENT, [hl]
;	ld a, $1
;	ld [wNPCMovementScriptFunctionNum], a
;	ret
;
;RLEList_PewterMuseumPlayer:
;	db NO_INPUT, 1
;	db PAD_UP, 3
;	db PAD_LEFT, 13
;	db PAD_UP, 6
;	db -1 ; end
;
;RLEList_PewterMuseumGuy:
;	db NPC_MOVEMENT_UP, 6
;	db NPC_MOVEMENT_LEFT, 13
;	db NPC_MOVEMENT_UP, 3
;	db NPC_MOVEMENT_LEFT, 1
;	db -1 ; end
;
;PewterMovementScript_Done:
;	ldh a, [hSimulatedJoypadStatesIndex]
;	and a
;	ret nz
;	ld hl, wStatusFlags5
;	res BIT_SCRIPTED_MOVEMENT_STATE, [hl]
;	ld hl, wStatusFlags4
;	res BIT_INIT_SCRIPTED_MOVEMENT, [hl]
;	jp EndNPCMovementScript
;
;PewterGymGuyMovementScriptPointerTable::
;	dw PewterMovementScript_WalkToGym
;	dw PewterMovementScript_Done
;
;PewterMovementScript_WalkToGym:
;	ld a, BANK(Music_MuseumGuy)
;	ld [wAudioROMBank], a
;	ld [wAudioSavedROMBank], a
;	ld a, MUSIC_MUSEUM_GUY
;	ld [wNewSoundID], a
;	call PlaySound
;	ldh a, [hActiveSpriteIndex]
;	swap a
;	ld [wNPCMovementScriptSpriteOffset], a
;	xor a
;	ld [wSpritePlayerStateData2MovementByte1], a
;	ld hl, wSimulatedJoypadStatesEnd
;	ld de, RLEList_PewterGymPlayer
;	call DecodeRLEList
;	dec a
;	ldh [hSimulatedJoypadStatesIndex], a
;	ld a, 1
;	ld [wWhichPewterGuy], a
;	predef PewterGuys
;	ld hl, wNPCMovementDirections2
;	ld de, RLEList_PewterGymGuy
;	call DecodeRLEList
;	ld hl, wStatusFlags4
;	res BIT_INIT_SCRIPTED_MOVEMENT, [hl]
;	ld hl, wStatusFlags5
;	set BIT_SCRIPTED_MOVEMENT_STATE, [hl]
;	ld a, $1
;	ld [wNPCMovementScriptFunctionNum], a
;	ret
;
;RLEList_PewterGymPlayer:
;	db NO_INPUT, 1
;	db PAD_RIGHT, 2
;	db PAD_DOWN, 5
;	db PAD_LEFT, 11
;	db PAD_UP, 5
;	db PAD_LEFT, 15
;	db -1 ; end
;
;RLEList_PewterGymGuy:
;	db NPC_MOVEMENT_DOWN, 2
;	db NPC_MOVEMENT_LEFT, 15
;	db NPC_MOVEMENT_UP, 5
;	db NPC_MOVEMENT_LEFT, 11
;	db NPC_MOVEMENT_DOWN, 5
;	db NPC_MOVEMENT_RIGHT, 3
;	db -1 ; end

SetEnemyTrainerToStayAndFaceAnyDirection::
	ldh a, [hCurMap]
	cp POKEMON_TOWER_7F
	ret z ; the Rockets on Pokemon Tower 7F leave after battling, so don't set them
	ld hl, RivalIDs
	ld a, [wEngagedTrainerClass]
	ld b, a
.loop
	ld a, [hli]
	cp -1
	jr z, .notRival
	cp b
	ret z ; the rival leaves after battling, so don't set him
	jr .loop
.notRival
	ldh a, [hActiveSpriteIndex]
	ldh [hSpriteIndex], a
	jp SetSpriteMovementBytesToFF

RivalIDs:
	db OPP_RIVAL1
	db OPP_RIVAL2
	db OPP_RIVAL3
	db -1 ; end

SaffronPalmMovementScriptPointerTable::
; Functions 0-2 are the Mini Saffron leg, 3-6 the Silph Co 1F leg. They share one
; table because both are one-shot intro escorts that can never run at the same
; time, and .NPCMovementScriptPointerTables in HOME has no room for another entry.
	dw SaffronPalmMovementScript_WalkToSilphCo
	dw SaffronPalmMovementScript_PalmEntersSilphCo
	dw SaffronPalmMovementScript_Done
	dw SilphCoPalmMovementScript_WalkToDesk
	dw SilphCoPalmMovementScript_TalkToReceptionist
	dw SilphCoPalmMovementScript_PalmTakesStairs
	dw SilphCoPalmMovementScript_Done
    dw SilphCoPalmMovementScript_PalmWalkstoDorm
    dw SilphCoPalmMovementScriptPlayerWalkstoDorm
    dw SilphCoPalmMovementScript_PalmWalkstoCreditExchange
    dw SilphCoPalmMovementScript_PlayerWalkstoCreditExchange
    dw SilphCoPalmMovementScript_PalmWalkstoVRRoom
    dw SilphCoPalmMovementScript_PlayerWalkstoVRRoom

SaffronPalmMovementScript_WalkToSilphCo:
	xor a
	ld [wOverrideSimulatedJoypadStatesMask], a
	ldh a, [hActiveSpriteIndex]
	swap a
	ld [wNPCMovementScriptSpriteOffset], a
; Force Palm's screen position to be derived from his map position before the
; walk starts. DoScriptedNPCMovement (engine/overworld/movement.asm) drives
; these escorts purely in SCREEN PIXEL space - it adds +/-2 px per frame and
; never looks at MapX/MapY - so it inherits whatever coordinates the slot
; already holds. Without this the NPC walks the correct route from a wrong
; origin. Relying on the normal per-sprite update to have placed him is not
; safe: it skips InitializeSpriteScreenPosition while a textbox is open, while
; the sprite is already walking, or while wWalkCounter is nonzero.
	ldh [hCurrentSpriteOffset], a
	farcall InitializeSpriteScreenPosition
	xor a
	ld [wSpritePlayerStateData2MovementByte1], a
	ld hl, wSimulatedJoypadStatesEnd
	ld de, RLEList_SaffronPlayerFollowsPalm
	call DecodeRLEList
	dec a
	ldh [hSimulatedJoypadStatesIndex], a
	ld hl, wNPCMovementDirections2
	ld de, RLEList_SaffronPalmWalkToSilphCo
	call DecodeRLEList
	ld hl, wStatusFlags4
	res BIT_INIT_SCRIPTED_MOVEMENT, [hl]
	ld hl, wStatusFlags5
	set BIT_SCRIPTED_MOVEMENT_STATE, [hl]
	ld a, $1
	ld [wNPCMovementScriptFunctionNum], a
	ret

; Palm's single step finishes while the player is still on their NO_INPUT beat,
; so hiding him here clears the doorway before the player's second step tries to
; enter it. This CANNOT be deferred to _Done: _Done only runs once the player has
; finished moving, and the player can never finish while Palm is stood on their
; destination tile.
SaffronPalmMovementScript_PalmEntersSilphCo:
	ld hl, wStatusFlags5
	bit BIT_SCRIPTED_NPC_MOVEMENT, [hl]
	ret nz ; Palm is still walking
	ld a, TOGGLE_MINI_SAFFRON_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, $2
	ld [wNPCMovementScriptFunctionNum], a
	ret

SaffronPalmMovementScript_Done:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	ld hl, wStatusFlags5
	res BIT_SCRIPTED_MOVEMENT_STATE, [hl]
	ld hl, wStatusFlags4
	res BIT_INIT_SCRIPTED_MOVEMENT, [hl]
	jp EndNPCMovementScript

RLEList_SaffronPalmWalkToSilphCo:
	db NPC_MOVEMENT_UP, 1
	db -1 ; end

; The leading NO_INPUT lets Palm vacate (12,10) before the player steps into it.
; Three PAD_UP beats are required here: the simulated-joypad engine consumes
; one while the first tile step is still settling, and the remaining two move
; the player from (12,11) through (12,10) onto the Silph Co door at (12,9).
; Simulated joypad entries execute from the end of the decoded buffer, so this
; source list is written in reverse order.
RLEList_SaffronPlayerFollowsPalm:
	db PAD_UP, 3
	db NO_INPUT, 1
	db -1 ; end

; --- Silph Co 1F leg of the intro escort ---
; Shares SaffronPalmMovementScriptPointerTable (see below); entered at function 3.

SilphCoPalmMovementScript_WalkToDesk:
	xor a
	ld [wOverrideSimulatedJoypadStatesMask], a
	ldh a, [hActiveSpriteIndex]
	swap a
	ld [wNPCMovementScriptSpriteOffset], a
; Absolute placement before the relative walk begins - see the identical block
; in SaffronPalmMovementScript_WalkToSilphCo for why this is mandatory.
	ldh [hCurrentSpriteOffset], a
	farcall InitializeSpriteScreenPosition
	xor a
	ld [wSpritePlayerStateData2MovementByte1], a
	ld hl, wSimulatedJoypadStatesEnd
	ld de, RLEList_SilphCoPlayerToDesk
	call DecodeRLEList
	dec a
	ldh [hSimulatedJoypadStatesIndex], a
	ld hl, wNPCMovementDirections2
	ld de, RLEList_SilphCoPalmToDesk
	call DecodeRLEList
	ld hl, wStatusFlags4
	res BIT_INIT_SCRIPTED_MOVEMENT, [hl]
	ld hl, wStatusFlags5
	set BIT_SCRIPTED_MOVEMENT_STATE, [hl]
	ld a, $4
	ld [wNPCMovementScriptFunctionNum], a
	ret

; Palm ends leg 1 at (4,4), the player behind him at (4,5). He speaks to the
; receptionist at (4,2) across the counter tile at (4,3), then leg 2 starts.
SilphCoPalmMovementScript_TalkToReceptionist:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz ; player still walking
; Commit both sprites' screen positions BEFORE the textbox opens. UpdateNPCSprite
; skips InitializeSpriteScreenPosition whenever wFontLoaded is set
; (engine/overworld/movement.asm), so a sprite whose position was not settled
; when the box opened stays drawn at stale coordinates for the whole
; conversation. Same fix as the one in scripts/MiniSaffron.asm.
	call UpdateSprites
	ld a, TEXT_SILPHCO1F_LINK_RECEPTIONIST
	ldh [hTextID], a
	call DisplayTextID
	xor a
	ld [wOverrideSimulatedJoypadStatesMask], a
	ld hl, wSimulatedJoypadStatesEnd
	ld de, RLEList_SilphCoPlayerToStairs
	call DecodeRLEList
	dec a
	ldh [hSimulatedJoypadStatesIndex], a
	ld hl, wNPCMovementDirections2
	ld de, RLEList_SilphCoPalmToStairs
	call DecodeRLEList
	ld hl, wStatusFlags4
	res BIT_INIT_SCRIPTED_MOVEMENT, [hl]
	ld hl, wStatusFlags5
	set BIT_SCRIPTED_MOVEMENT_STATE, [hl]
	ld a, $5
	ld [wNPCMovementScriptFunctionNum], a
	ret

; Palm's last step puts him ON the stairs at (24,0) - the player's destination.
; He must be hidden as soon as HIS movement ends, not in _Done, because _Done
; only runs once the player has finished and the player can never finish while
; Palm occupies their destination tile.
SilphCoPalmMovementScript_PalmTakesStairs:
	ld hl, wStatusFlags5
	bit BIT_SCRIPTED_NPC_MOVEMENT, [hl]
	ret nz ; Palm still walking
	ld a, TOGGLE_SILPH_CO_1F_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, $6
	ld [wNPCMovementScriptFunctionNum], a
	ret

SilphCoPalmMovementScript_Done:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	ld hl, wStatusFlags5
	res BIT_SCRIPTED_MOVEMENT_STATE, [hl]
	ld hl, wStatusFlags4
	res BIT_INIT_SCRIPTED_MOVEMENT, [hl]
	jp EndNPCMovementScript

; Leg 1: (10,16) -> (4,4). y=8 is walled from x=10-21, so the route cuts left
; along y=9 rather than going straight up.
RLEList_SilphCoPalmToDesk:
	db NPC_MOVEMENT_UP, 5
	db NPC_MOVEMENT_LEFT, 6
	db NPC_MOVEMENT_UP, 7
	db -1 ; end

; (10,17) -> (4,5), one tile behind Palm the whole way. The leading NO_INPUT
; gives him a head start so the player never walks into the tile he is leaving.
RLEList_SilphCoPlayerToDesk:
	db NO_INPUT, 1
	db PAD_UP, 6
	db PAD_LEFT, 6
	db PAD_UP, 6
	db -1 ; end

; Leg 2: (4,4) -> the stairs at (24,0), out via y=4 then along y=1.
RLEList_SilphCoPalmToStairs:
	db NPC_MOVEMENT_RIGHT, 4
	db NPC_MOVEMENT_UP, 3
	db NPC_MOVEMENT_RIGHT, 16
	db NPC_MOVEMENT_UP, 1
	db -1 ; end

; (4,5) -> (24,0).
; The final PAD_UP lands them on
; the stairs, which is what fires the warp to SILPH_CO_B1F.
RLEList_SilphCoPlayerToStairs:
	db PAD_UP, 2
    db PAD_RIGHT, 16
    db PAD_UP, 3
    db PAD_RIGHT, 4
    db PAD_UP, 1
    db NO_INPUT, 1
	db -1 ; end
