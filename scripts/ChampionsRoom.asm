ChampionsRoom_Script:
	call ChampionsRoomPatchWarps
	call EnableAutoTextBoxDrawing
	ld hl, ChampionsRoom_ScriptPointers
	ld a, [wChampionsRoomCurScript]
	jp CallFunctionInTable

ChampionsRoomPatchWarps:
; Re-patches this room's south warps to match this run's shuffled Elite
; Four order (see custom_functions/final_sequence.asm) - the order is
; randomized, so the ROM-authored (vanilla, Lance-always-last) warps would
; misroute backtracking otherwise. Idempotent, safe to run on every load.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	farcall Elite4PatchChampionRoomWarps
	call ChampionsRoomHideUnusedChampion
	ret

; ============================================================
; ChampionsRoomHideUnusedChampion
; Exactly one of Blue/Lance/Oak-as-champion is this run's Champion
; (wRunChampion). All three are declared ON in
; data/maps/toggleable_objects.asm, so only the other two need a HideObject
; call, mirroring FuchsiaGymHideUnusedLeader's two-way form.
; CLOBBERS: a
; ============================================================
ChampionsRoomHideUnusedChampion:
	ld a, [wRunChampion]
	cp LANCE
	jr z, .lance
	cp PROF_OAK
	jr z, .oak
.rival3
	ld a, TOGGLE_CHAMPIONS_ROOM_LANCE
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_CHAMPIONS_ROOM_OAK_CHAMPION
	ld [wToggleableObjectIndex], a
	predef_jump HideObject
.lance
	ld a, TOGGLE_CHAMPIONS_ROOM_RIVAL
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_CHAMPIONS_ROOM_OAK_CHAMPION
	ld [wToggleableObjectIndex], a
	predef_jump HideObject
.oak
	ld a, TOGGLE_CHAMPIONS_ROOM_RIVAL
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_CHAMPIONS_ROOM_LANCE
	ld [wToggleableObjectIndex], a
	predef_jump HideObject

; ============================================================
; ChampionsRoomChampionSpriteIndex
; a = this run's Champion's own object_event index (CHAMPIONSROOM_RIVAL,
; _LANCE or _OAK_CHAMPION), read from wRunChampion. Used wherever the script
; needs to freeze/hide "whichever sprite actually fought" rather than
; assuming CHAMPIONSROOM_RIVAL.
; CLOBBERS: a
; ============================================================
ChampionsRoomChampionSpriteIndex:
	ld a, [wRunChampion]
	cp LANCE
	jr z, .lance
	cp PROF_OAK
	jr z, .oak
	ld a, CHAMPIONSROOM_RIVAL
	ret
.lance
	ld a, CHAMPIONSROOM_LANCE
	ret
.oak
	ld a, CHAMPIONSROOM_OAK_CHAMPION
	ret

; ============================================================
; ChampionsRoomOakExitSpriteAndToggle
; b = the Oak sprite object index to move/freeze for the walk to the Hall of
; Fame; c = its toggle constant to hide once he is off-screen. Oak-as-
; arriving-NPC (CHAMPIONSROOM_OAK) leads every run except when Oak himself is
; the Champion, in which case Oak-as-champion (CHAMPIONSROOM_OAK_CHAMPION,
; already on screen at the rival's tile) leads instead - there is no separate
; congratulator to walk in for that run.
; CLOBBERS: a
; ============================================================
ChampionsRoomOakExitSpriteAndToggle:
	ld a, [wRunChampion]
	cp PROF_OAK
	jr nz, .normalOak
	ld b, CHAMPIONSROOM_OAK_CHAMPION
	ld c, TOGGLE_CHAMPIONS_ROOM_OAK_CHAMPION
	ret
.normalOak
	ld b, CHAMPIONSROOM_OAK
	ld c, TOGGLE_CHAMPIONS_ROOM_OAK
	ret

ResetRivalScript:
	xor a ; SCRIPT_CHAMPIONSROOM_DEFAULT
	ldh [hJoyIgnore], a
	ld [wChampionsRoomCurScript], a
	ret

ChampionsRoom_ScriptPointers:
	def_script_pointers
	dw_const ChampionsRoomDefaultScript,                  SCRIPT_CHAMPIONSROOM_DEFAULT
	dw_const ChampionsRoomPlayerEntersScript,             SCRIPT_CHAMPIONSROOM_PLAYER_ENTERS
	EXPORT SCRIPT_CHAMPIONSROOM_PLAYER_ENTERS ; used by custom_functions/final_sequence.asm (Elite4PatchRoomWarps arms the Champion room from the "rogue" bank)
	dw_const ChampionsRoomRivalReadyToBattleScript,       SCRIPT_CHAMPIONSROOM_RIVAL_READY_TO_BATTLE
	dw_const ChampionsRoomRivalDefeatedScript,            SCRIPT_CHAMPIONSROOM_RIVAL_DEFEATED
	dw_const ChampionsRoomOakArrivesScript,               SCRIPT_CHAMPIONSROOM_OAK_ARRIVES
	dw_const ChampionsRoomOakCongratulatesPlayerScript,   SCRIPT_CHAMPIONSROOM_OAK_CONGRATULATES_PLAYER
	dw_const ChampionsRoomOakDisappointedWithRivalScript, SCRIPT_CHAMPIONSROOM_OAK_DISAPPOINTED_WITH_RIVAL
	dw_const ChampionsRoomOakChampionCongratulatesScript, SCRIPT_CHAMPIONSROOM_OAK_CHAMPION_CONGRATULATES
	dw_const ChampionsRoomOakComeWithMeScript,            SCRIPT_CHAMPIONSROOM_OAK_COME_WITH_ME
	dw_const ChampionsRoomOakExitsScript,                 SCRIPT_CHAMPIONSROOM_OAK_EXITS
	dw_const ChampionsRoomPlayerFollowsOakScript,         SCRIPT_CHAMPIONSROOM_PLAYER_FOLLOWS_OAK
	dw_const ChampionsRoomCleanupScript,                  SCRIPT_CHAMPIONSROOM_CLEANUP_SCRIPT

ChampionsRoomDefaultScript:
	ret

ChampionsRoomPlayerEntersScript:
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld hl, wSimulatedJoypadStatesEnd
	ld de, RivalEntrance_RLEMovement
	call DecodeRLEList
	dec a
	ldh [hSimulatedJoypadStatesIndex], a
	call StartSimulatingJoypadStates
	ld a, SCRIPT_CHAMPIONSROOM_RIVAL_READY_TO_BATTLE
	ld [wChampionsRoomCurScript], a
	ret

RivalEntrance_RLEMovement:
	db PAD_UP, 1
	db PAD_RIGHT, 1
	db PAD_UP, 3
	db -1 ; end

; ============================================================
; ChampionsRoomRivalReadyToBattleScript
; Branches on wRunChampion (rolled by RollElite4AndChampion,
; custom_functions/final_sequence.asm) to set up the correct opponent, team
; roll and end-of-battle text before starting the Champion battle. RIVAL3
; keeps its original 5-variant roll and RIVAL_STARTER_PLACEHOLDER ace; LANCE
; and PROF_OAK use their own OPP_ class and their own authored
; TrainerDataPointers team (LanceData's variants are all identical, so
; wTrainerNo just needs to be in range; ProfOakData has 3 distinct variants,
; the same "Unused" level-66-70 team already sitting in parties.asm, rolled
; the same way the rival's 5 variants are).
; ============================================================
ChampionsRoomRivalReadyToBattleScript:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	call Delay3
	xor a
	ldh [hJoyIgnore], a
	ld hl, wOptions
	res BIT_BATTLE_ANIMATION, [hl]

	ld a, [wRunChampion]
	cp LANCE
	jp z, .lance
	cp PROF_OAK
	jp z, .oak

.rival3
	ld a, TEXT_CHAMPIONSROOM_RIVAL
	ldh [hTextID], a
	call DisplayTextID
	call Delay3
	ld hl, wStatusFlags3
	set BIT_TALKED_TO_TRAINER, [hl]
	set BIT_PRINT_END_BATTLE_TEXT, [hl]
	ld hl, RivalDefeatedText
	ld de, RivalVictoryText
	call SaveEndBattleTextPointers
	ld a, OPP_RIVAL3
	ld [wCurOpponent], a

	; select which of the 5 Champion teams to use (each keeps the rival's
	; starter as the ace via RIVAL_STARTER_PLACEHOLDER - PatchRivalStarterSpecies
	; patches it in at battle setup, same as every other rival team)
	ld c, 5
	call Rangerandom
	inc a
	ld [wTrainerNo], a
	jr .startBattle

.lance
	ld a, TEXT_CHAMPIONSROOM_LANCE
	ldh [hTextID], a
	call DisplayTextID
	call Delay3
	ld hl, wStatusFlags3
	set BIT_TALKED_TO_TRAINER, [hl]
	set BIT_PRINT_END_BATTLE_TEXT, [hl]
	ld hl, LanceDefeatedText
	ld de, LanceVictoryText
	call SaveEndBattleTextPointers
	ld a, OPP_LANCE
	ld [wCurOpponent], a
	; Champion Lance takes the Elite Four's TOP tier (wTrainerNo 10-12, tier 4
	; of the 4x3 E4 grid - see e4_team_spec). Once LANCE is spec-driven, the old
	; fixed `1` would hand the Champion tier-1 E4 levels.
	ld c, 3
	call Rangerandom
	add 10
	ld [wTrainerNo], a
	jr .startBattle

.oak
	ld a, TEXT_CHAMPIONSROOM_OAK_CHAMPION
	ldh [hTextID], a
	call DisplayTextID
	call Delay3
	ld hl, wStatusFlags3
	set BIT_TALKED_TO_TRAINER, [hl]
	set BIT_PRINT_END_BATTLE_TEXT, [hl]
	ld hl, OakChampionDefeatedText
	ld de, OakChampionVictoryText
	call SaveEndBattleTextPointers
	ld a, OPP_PROF_OAK
	ld [wCurOpponent], a
	ld c, 3 ; ProfOakData's 3 authored variants
	call Rangerandom
	inc a
	ld [wTrainerNo], a

.startBattle
	ld a, 1
	ld [wIsTrainerBattle], a

	xor a
	ldh [hJoyHeld], a
	ld a, SCRIPT_CHAMPIONSROOM_RIVAL_DEFEATED
	ld [wChampionsRoomCurScript], a
	ret

; ============================================================
; ChampionsRoomRivalDefeatedScript
; PROF_OAK skips straight to SCRIPT_CHAMPIONSROOM_OAK_CHAMPION_CONGRATULATES
; (no separate arriving Oak to walk in - see the HANDOFF spec, user decision:
; Oak congratulates in place, no arrival walk, no disappointed-with-rival
; beat). RIVAL3 and LANCE both continue into the unchanged 7-script Oak
; epilogue.
; ============================================================
ChampionsRoomRivalDefeatedScript:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, ResetRivalScript
    xor a
	ld [wIsTrainerBattle], a
	call UpdateSprites
	SetEvent EVENT_BEAT_CHAMPION_RIVAL
	farcall RogueAwardCredits3
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a

	ld a, [wRunChampion]
	cp LANCE
	jr z, .lance
	cp PROF_OAK
	jr z, .oak
.rival3
	SetEvent EVENT_RIVAL_CHAMPION_DEFEATED
	ld a, TEXT_CHAMPIONSROOM_RIVAL
	jr .display
.lance
	SetEvent EVENT_LANCE_CHAMPION_DEFEATED
	ld a, TEXT_CHAMPIONSROOM_LANCE
	jr .display
.oak
	SetEvent EVENT_OAK_CHAMPION_DEFEATED
	ld a, TEXT_CHAMPIONSROOM_OAK_CHAMPION
.display
	ldh [hTextID], a
	call ChampionsRoom_DisplayTextID_AllowABSelectStart
	call ChampionsRoomChampionSpriteIndex ; a = this run's champion object index; re-derived AFTER the display call, which clobbers everything
	ldh [hSpriteIndex], a
	call SetSpriteMovementBytesToFF

	ld a, [wRunChampion]
	cp PROF_OAK
	ld a, SCRIPT_CHAMPIONSROOM_OAK_CHAMPION_CONGRATULATES
	jr z, .scriptChosen
	ld a, SCRIPT_CHAMPIONSROOM_OAK_ARRIVES
.scriptChosen
	ld [wChampionsRoomCurScript], a
; ELEMENT PRISM: NORMAL + FLYING + BUG, the three types no gym leader or Elite
; Four member owns. Announced from its own text id so PrintText runs inside
; DisplayTextID - fired raw from this script it drew an invisible box that
; silently waited for A (confirmed in BGB 2026-09-23 by pre-setting the event).
; Gated on the grant's own one-time event so a repeat win shows no empty box.
	CheckEvent EVENT_PRISM_CHAMPION_SHOWN
	ret nz
	ld a, TEXT_CHAMPIONSROOM_PRISM
	ldh [hTextID], a
	jp ChampionsRoom_DisplayTextID_AllowABSelectStart

ChampionsRoomOakArrivesScript:
	farcall Music_Cities1AlternateTempo
	ld a, TEXT_CHAMPIONSROOM_OAK
	ldh [hTextID], a
	call ChampionsRoom_DisplayTextID_AllowABSelectStart
	ld a, CHAMPIONSROOM_OAK
	ldh [hSpriteIndex], a
	call SetSpriteMovementBytesToFF
	ld de, OakEntranceAfterVictoryMovement
	ld a, CHAMPIONSROOM_OAK
	ldh [hSpriteIndex], a
	call MoveSprite
	ld a, TOGGLE_CHAMPIONS_ROOM_OAK
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, SCRIPT_CHAMPIONSROOM_OAK_CONGRATULATES_PLAYER
	ld [wChampionsRoomCurScript], a
	ret

OakEntranceAfterVictoryMovement:
	db NPC_MOVEMENT_UP
	db NPC_MOVEMENT_UP
	db NPC_MOVEMENT_UP
	db NPC_MOVEMENT_UP
	db NPC_MOVEMENT_UP
	db -1 ; end

ChampionsRoomOakCongratulatesPlayerScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz
	ld a, PLAYER_DIR_LEFT
	ld [wPlayerMovingDirection], a
	; The champion who actually fought, not a hard-coded CHAMPIONSROOM_RIVAL:
	; on a Lance run that turned the HIDDEN Blue and left Lance facing down.
	call ChampionsRoomChampionSpriteIndex
	ldh [hSpriteIndex], a
	ld a, SPRITE_FACING_LEFT
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirectionAndDelay
	ld a, CHAMPIONSROOM_OAK
	ldh [hSpriteIndex], a
	xor a ; SPRITE_FACING_DOWN
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirectionAndDelay
	ld a, TEXT_CHAMPIONSROOM_OAK_CONGRATULATES_PLAYER
	ldh [hTextID], a
	call ChampionsRoom_DisplayTextID_AllowABSelectStart
	ld a, SCRIPT_CHAMPIONSROOM_OAK_DISAPPOINTED_WITH_RIVAL
	ld [wChampionsRoomCurScript], a
	ret

; RIVAL3: Oak is disappointed with the rival. LANCE: full epilogue, same beat,
; rewritten to be about Lance instead (user decision, HANDOFF spec). PROF_OAK
; never reaches this state.
ChampionsRoomOakDisappointedWithRivalScript:
	ld a, CHAMPIONSROOM_OAK
	ldh [hSpriteIndex], a
	ld a, SPRITE_FACING_RIGHT
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirectionAndDelay
	ld a, [wRunChampion]
	cp LANCE
	ld a, TEXT_CHAMPIONSROOM_OAK_DISAPPOINTED_WITH_LANCE
	jr z, .textChosen
	ld a, TEXT_CHAMPIONSROOM_OAK_DISAPPOINTED_WITH_RIVAL
.textChosen
	ldh [hTextID], a
	call ChampionsRoom_DisplayTextID_AllowABSelectStart
	ld a, SCRIPT_CHAMPIONSROOM_OAK_COME_WITH_ME
	ld [wChampionsRoomCurScript], a
	ret

; PROF_OAK only: Oak congratulates the player in place (he is already on
; screen as the defeated Champion), then joins the same COME_WITH_ME tail
; every other Champion uses.
ChampionsRoomOakChampionCongratulatesScript:
	ld a, TEXT_CHAMPIONSROOM_OAK_CHAMPION_CONGRATULATES
	ldh [hTextID], a
	call ChampionsRoom_DisplayTextID_AllowABSelectStart
	ld a, SCRIPT_CHAMPIONSROOM_OAK_COME_WITH_ME
	ld [wChampionsRoomCurScript], a
	ret

ChampionsRoomOakComeWithMeScript:
	call ChampionsRoomOakExitSpriteAndToggle ; b = sprite, c = toggle
	ld a, b
	ldh [hSpriteIndex], a
	xor a ; SPRITE_FACING_DOWN
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirectionAndDelay
	ld a, TEXT_CHAMPIONSROOM_OAK_COME_WITH_ME
	ldh [hTextID], a
	call ChampionsRoom_DisplayTextID_AllowABSelectStart
	call ChampionsRoomOakExitSpriteAndToggle ; re-derive: the calls above clobber b/c
	ld de, OakExitChampionsRoomMovement
	ld a, b
	ldh [hSpriteIndex], a
	call MoveSprite
	ld a, SCRIPT_CHAMPIONSROOM_OAK_EXITS
	ld [wChampionsRoomCurScript], a
	ret

; UP x2 reaches a north warp (3,0 or 4,0) from either Oak's post-arrival rest
; tile (3,2) or Oak-as-champion's tile (4,2 - the rival's own tile), so one
; table serves both paths.
OakExitChampionsRoomMovement:
	db NPC_MOVEMENT_UP
	db NPC_MOVEMENT_UP
	db -1 ; end

ChampionsRoomOakExitsScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz
	call ChampionsRoomOakExitSpriteAndToggle ; c = toggle to hide
	ld a, c
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, SCRIPT_CHAMPIONSROOM_PLAYER_FOLLOWS_OAK
	ld [wChampionsRoomCurScript], a
	ret

ChampionsRoomPlayerFollowsOakScript:
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld hl, wSimulatedJoypadStatesEnd
	ld de, WalkToHallOfFame_RLEMovement
	call DecodeRLEList
	dec a
	ldh [hSimulatedJoypadStatesIndex], a
	call StartSimulatingJoypadStates
	ld a, SCRIPT_CHAMPIONSROOM_CLEANUP_SCRIPT
	ld [wChampionsRoomCurScript], a
	ret

WalkToHallOfFame_RLEMovement:
	db PAD_UP, 4
	db PAD_LEFT, 1
	db -1 ; end

ChampionsRoomCleanupScript:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	xor a
	ldh [hJoyIgnore], a
	ld a, SCRIPT_CHAMPIONSROOM_DEFAULT
	ld [wChampionsRoomCurScript], a
	ret

ChampionsRoom_DisplayTextID_AllowABSelectStart:
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	call DisplayTextID
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ret

ChampionsRoom_TextPointers:
	def_text_pointers
	dw_const ChampionsRoomRivalText,                    TEXT_CHAMPIONSROOM_RIVAL
	dw_const ChampionsRoomOakText,                      TEXT_CHAMPIONSROOM_OAK
	dw_const ChampionsRoomLanceText,                    TEXT_CHAMPIONSROOM_LANCE
	dw_const ChampionsRoomOakChampionText,              TEXT_CHAMPIONSROOM_OAK_CHAMPION
	dw_const ChampionsRoomOakCongratulatesPlayerText,   TEXT_CHAMPIONSROOM_OAK_CONGRATULATES_PLAYER
	dw_const ChampionsRoomOakDisappointedWithRivalText, TEXT_CHAMPIONSROOM_OAK_DISAPPOINTED_WITH_RIVAL
	dw_const ChampionsRoomOakDisappointedWithLanceText, TEXT_CHAMPIONSROOM_OAK_DISAPPOINTED_WITH_LANCE
	dw_const ChampionsRoomOakChampionCongratulatesText, TEXT_CHAMPIONSROOM_OAK_CHAMPION_CONGRATULATES
	dw_const ChampionsRoomOakComeWithMeText,            TEXT_CHAMPIONSROOM_OAK_COME_WITH_ME
	dw_const ChampionsRoomPrismText,                   TEXT_CHAMPIONSROOM_PRISM

ChampionsRoomRivalText:
	text_asm
	CheckEvent EVENT_BEAT_CHAMPION_RIVAL
	ld hl, .IntroText
	jr z, .printText
	ld hl, ChampionsRoomRivalAfterBattleText
.printText
	call PrintText
	jp TextScriptEnd

.IntroText:
	text_far _ChampionsRoomRivalIntroText
	text_end

RivalDefeatedText:
	text_far _RivalDefeatedText
	text_end

RivalVictoryText:
	text_far _RivalVictoryText
	text_end

ChampionsRoomRivalAfterBattleText:
	text_far _ChampionsRoomRivalAfterBattleText
	text_end

ChampionsRoomOakText:
	text_far _ChampionsRoomOakText
	text_end

; Lance-as-Champion. Same before/after-battle shape as ChampionsRoomRivalText.
ChampionsRoomLanceText:
	text_asm
	CheckEvent EVENT_BEAT_CHAMPION_RIVAL
	ld hl, .IntroText
	jr z, .printText
	ld hl, ChampionsRoomLanceAfterBattleText
.printText
	call PrintText
	jp TextScriptEnd

.IntroText:
	text_far _ChampionsRoomLanceIntroText
	text_end

LanceDefeatedText:
	text_far _LanceDefeatedText
	text_end

LanceVictoryText:
	text_far _LanceVictoryText
	text_end

ChampionsRoomLanceAfterBattleText:
	text_far _ChampionsRoomLanceAfterBattleText
	text_end

; Oak-as-Champion. Same before/after-battle shape as ChampionsRoomRivalText.
ChampionsRoomOakChampionText:
	text_asm
	CheckEvent EVENT_BEAT_CHAMPION_RIVAL
	ld hl, .IntroText
	jr z, .printText
	ld hl, ChampionsRoomOakChampionAfterBattleText
.printText
	call PrintText
	jp TextScriptEnd

.IntroText:
	text_far _ChampionsRoomOakChampionIntroText
	text_end

OakChampionDefeatedText:
	text_far _OakChampionDefeatedText
	text_end

OakChampionVictoryText:
	text_far _OakChampionVictoryText
	text_end

ChampionsRoomOakChampionAfterBattleText:
	text_far _ChampionsRoomOakChampionAfterBattleText
	text_end

ChampionsRoomOakCongratulatesPlayerText:
	text_asm
	ld a, [wPlayerStarter]
	ld [wNamedObjectIndex], a
	call GetMonName
	ld hl, .Text
	call PrintText
	jp TextScriptEnd

.Text:
	text_far _ChampionsRoomOakCongratulatesPlayerText
	text_end

ChampionsRoomOakDisappointedWithRivalText:
	text_far _ChampionsRoomOakDisappointedWithRivalText
	text_end

ChampionsRoomOakDisappointedWithLanceText:
	text_far _ChampionsRoomOakDisappointedWithLanceText
	text_end

ChampionsRoomOakChampionCongratulatesText:
	text_asm
	ld a, [wPlayerStarter]
	ld [wNamedObjectIndex], a
	call GetMonName
	ld hl, .Text
	call PrintText
	jp TextScriptEnd

.Text:
	text_far _ChampionsRoomOakChampionCongratulatesText
	text_end

ChampionsRoomOakComeWithMeText:
	text_far _ChampionsRoomOakComeWithMeText
	text_end

ChampionsRoomPrismText:
	text_asm
	farcall RogueChampionCartridges
	call DisableWaitingAfterTextDisplay ; the message carries its own prompt
	jp TextScriptEnd
