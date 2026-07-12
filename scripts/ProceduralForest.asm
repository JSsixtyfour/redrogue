; Boss battle uses the cave's real TalkToTrainer/def_trainers path (see
; PROCEDURAL_STAGE_FUNDAMENTALS.md) - the boss is sprite slot 1, engaged
; normally by pressing A on it, or forced via the flank-tile guard in
; ProceduralForestDefaultScript below (see that function's comment).
;
; Reused events (never concurrent with cave/cemetery, all reset at Pallet Town
; entry by PFPreloadForest/PFRollBoss):
;   EVENT_BEAT_PC_BOSS  - boss defeated / offered (bit-aligned for slot-1 trainer)
;   EVENT_PC_BUDGET_ENDED / EVENT_PC_CALMED_SHOWN - wild budget calmed message

ProceduralForest_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
; Fresh entry: show the four item pokeballs.
	ld a, TOGGLE_WILD_AREA_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_WILD_AREA_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_WILD_AREA_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_WILD_AREA_POKEBALL_4
	ld [wToggleableObjectIndex], a
	predef ShowObject
	; Show the boss only if it hasn't been beaten yet.
	CheckEvent EVENT_BEAT_PC_BOSS
	jr nz, .afterSetup
	ld a, TOGGLE_WILD_AREA_BOSS
	ld [wToggleableObjectIndex], a
	predef ShowObject
.afterSetup
	; Wild budget calmed check — runs every frame, independent of boss state.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	jr z, .afterCalm
	CheckEvent EVENT_PC_CALMED_SHOWN
	jr nz, .afterCalm
	CheckEvent EVENT_PC_BUDGET_ENDED
	jr z, .afterCalm
	SetEvent EVENT_PC_CALMED_SHOWN
	ld a, TEXT_PROCEDURALFOREST_CALMED
	ldh [hTextID], a
	call DisplayTextID
.afterCalm
	; One-time join offer, shown after the boss is beaten and the end-battle
	; text has fully cleared (same shape PowerPlant uses for its reward).
	CheckEvent EVENT_PC_BOSS_OFFERED
	jr nz, .runScripts
	CheckEvent EVENT_BEAT_PC_BOSS
	jr z, .runScripts
	ld a, [wStatusFlags3]
	bit BIT_PRINT_END_BATTLE_TEXT, a
	jr nz, .runScripts
	SetEvent EVENT_PC_BOSS_OFFERED
	farcall Delay3
	ld a, TEXT_PROCEDURALFOREST_BOSS_OFFER
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
.runScripts
	call EnableAutoTextBoxDrawing
	ld hl, ProceduralForestTrainerHeaders
	ld de, ProceduralForest_ScriptPointers
	ld a, [wProceduralForestCurScript]
	call ExecuteCurMapScriptInTable
	ld [wProceduralForestCurScript], a
	ret

ProceduralForestTrainerHeaders:
	def_trainers 1  ; boss is slot 1; CheckForEngagingTrainers uses CURRENT_TRAINER_BIT
	                ; as the sprite slot, so this must match the boss's object_event position.
	                ; EVENT_BEAT_PC_BOSS % 8 == 1 == 1 % 8 to satisfy trainer ASSERT.
PFBossTrainerHeader:
	trainer EVENT_BEAT_PC_BOSS, 0, ProceduralForestBossBattleText, ProceduralForestBossBattleText, ProceduralForestBossBattleText
	db -1 ; end

ProceduralForest_ScriptPointers:
	def_script_pointers
	dw_const ProceduralForestDefaultScript,     SCRIPT_PROCEDURALFOREST_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle,  SCRIPT_PROCEDURALFOREST_START_BATTLE
	dw_const EndTrainerBattle,                       SCRIPT_PROCEDURALFOREST_END_BATTLE
	;dw_const ProceduralForestPlayerMovingScript,     SCRIPT_PROCEDURALFOREST_PLAYER_MOVING
	;dw_const ProceduralForestBossBattleScript,       SCRIPT_PROCEDURALFOREST_BOSS_BATTLE

; Default state: normal sight-range trainer check, PLUS a flank-tile guard.
; The boss is STAY and faces DOWN, so CheckForEngagingTrainers/TrainerEngage's
; sight-range scan only ever looks south of it - it can never catch a player
; slipping past on the tile directly to its right, which is the uncovered
; half of the 2-tile-wide exit gap (the boss and the exit share the exact
; same left-anchored tile X - see PFinalizeForest's boss-placement math in
; procedural_forest_gen.asm: both use the identical `block*2+4` formula, so
; neither ever covers the exit's right-hand tile). Rather than inventing a
; parallel wCurOpponent-driven battle (cemetery's mechanism - see
; PROCEDURAL_STAGE_FUNDAMENTALS.md's warning against mixing the two for a
; stage with a real boss sprite), force the EXACT SAME TalkToTrainer sequence
; that pressing A on the boss would run.
ProceduralForestDefaultScript:
	CheckEvent EVENT_BEAT_PC_BOSS
	jp nz, CheckFightingMapTrainers
	ld a, [wSprite01StateData2MapY]
	ld b, a
	ld a, [wYCoord]
	cp b
	jp nz, CheckFightingMapTrainers
	ld a, [wSprite01StateData2MapX]
	inc a                            ; one tile right of the boss
	ld b, a
	ld a, [wXCoord]
	cp b
	jp nz, CheckFightingMapTrainers
	; Trigger the EXACT interaction pressing A on the boss runs: dispatch its
	; object text. TEXT_PROCEDURALFOREST_BOSS == 1 == the boss's sprite slot, so
	; DisplayTextID sets hActiveSpriteIndex = 1 and the whole
	; ProceduralForestBossText -> TalkToTrainer chain runs THROUGH the text
	; engine, which is what actually starts the battle. (Calling TalkToTrainer
	; directly from here does not - it just sets the end-battle flags without
	; ever entering battle, so the offer code fires on the next frame instead.)
	xor a
	ldh [hJoyHeld], a
	ld a, TEXT_PROCEDURALFOREST_BOSS
	ldh [hTextID], a
	call DisplayTextID
	ret

; Old cemetery-4-style proximity design, superseded by ProceduralForestDefaultScript
; above (kept only as historical reference - do not reintroduce wCurOpponent here).
;ProceduralForestDefaultScriptOLD:
;	CheckEvent EVENT_BEAT_PC_BOSS
;	jp nz, CheckFightingMapTrainers
;	; Read the per-run exit column from SRAM → boss tile X = 4*exitI+2 / +3.
;	ld a, RAMG_SRAM_ENABLE
;	ld [rRAMG], a
;	ld a, BMODE_ADVANCED
;	ld [rBMODE], a
;	xor a
;	ld [rRAMB], a
;	ld a, [sProcForestExitI]
;	ld b, a
;	ld a, BMODE_SIMPLE
;	ld [rBMODE], a
;	ld [rRAMG], a
;	ld a, b
;	add a, a
;	add a, a
;	add a, 2                    ; a = bossX = 4*exitI+2 (left exit tile X)
;	ld b, a                     ; b = bossX
;	; Player must be near the top of the map (exit is on the north edge).
;	ld a, [wYCoord]
;	cp 5
;	jp nc, CheckFightingMapTrainers
;	; Player X must be in [bossX, bossX+1] (the 2-tile-wide exit column).
;	ld a, [wXCoord]
;	cp b
;	jp c, CheckFightingMapTrainers    ; playerX < bossX
;	sub b
;	cp 2
;	jp nc, CheckFightingMapTrainers   ; playerX >= bossX+2
;	; --- trigger the boss battle (cemetery-4 mechanism) ---
;	xor a
;	ldh [hJoyHeld], a
;	ld a, TEXT_PROCEDURALFOREST_BOSS
;	ldh [hTextID], a
;	call DisplayTextID
;	ld a, [wRoguePokemon1]
;	ld [wCurOpponent], a               ; overworld loop starts a wild battle
;	farcall PCGetBossLevel             ; wCurEnemyLevel from wBattleCount
;	ld a, SCRIPT_PROCEDURALFOREST_BOSS_BATTLE
;	ld [wProceduralCave1CurScript], a
;	ld [wCurMapScript], a
;	ret

; Wait for the boss battle to finish, then either offer to join (win) or push
; the player back down the corridor (loss/flee — though fleeing is blocked, a
; whiteout or the enemy fainting the player returns here). Mirrors cemetery 4.
;ProceduralForestBossBattleScript:
;	ldh a, [hIsInBattle]
;	cp $ff
;	jp z, ProceduralForestDefaultScript
;	ld a, PAD_BUTTONS | PAD_CTRL_PAD
;	ldh [hJoyIgnore], a
;	ld a, [wStatusFlags3]
;	bit BIT_TALKED_TO_TRAINER, a
;	ret nz
;	call UpdateSprites
;	ld a, PAD_CTRL_PAD
;	ldh [hJoyIgnore], a
;	ld a, [wBattleResult]
;	and a
;	jr nz, .didNotDefeat
;	; Won — offer the boss to join, then hide its sprite (frees the exit).
;	SetEvent EVENT_BEAT_PC_BOSS
;	ld a, TEXT_PROCEDURALFOREST_BOSS_OFFER
;	ldh [hTextID], a
;	call DisplayTextID
;	ld a, TOGGLE_FOREST_BOSS
;	ld [wToggleableObjectIndex], a
;	predef HideObject
;	xor a
;	ldh [hJoyIgnore], a
;	ld a, SCRIPT_PROCEDURALFOREST_DEFAULT
;	ld [wProceduralCave1CurScript], a
;	ld [wCurMapScript], a
;	ret
;.didNotDefeat
;	ld a, $1
;	ldh [hSimulatedJoypadStatesIndex], a
;	ld a, PAD_DOWN
;	ld [wSimulatedJoypadStatesEnd], a
;	xor a
;	ld [wSpritePlayerStateData2MovementByte1], a
;	ld [wOverrideSimulatedJoypadStatesMask], a
;	ld hl, wStatusFlags5
;	set BIT_SCRIPTED_MOVEMENT_STATE, [hl]
;	;ld a, SCRIPT_PROCEDURALFOREST_PLAYER_MOVING
;	ld [wProceduralCave1CurScript], a
;	ld [wCurMapScript], a
;	ret

ProceduralForestPlayerMovingScript:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	call Delay3
	xor a
	ld [wProceduralCave1CurScript], a
	ld [wCurMapScript], a
	ret

; Join offer — same shape as cave/cemetery. Shown via DisplayTextID (from the
; BossBattle win path) so the text box/font are set up properly.
ProceduralForestBossOfferText:
	text_asm
	ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
	call GetMonName
	ld hl, PFBossJoinText
	call PrintText
	call YesNoChoice
	ld a, [hCurrentMenuItem]
	and a
	jr nz, .done
	farcall PCGetBossLevel
	ld a, [wRoguePokemon1]
	ld b, a
	ld a, [wCurEnemyLevel]
	ld c, a
	call GivePokemon
.done
	ld a, TOGGLE_WILD_AREA_BOSS
	ld [wToggleableObjectIndex], a
	predef HideObject
	jp TextScriptEnd

ProceduralForestInitBattleScript:
	call TalkToTrainer
	ld a, [wCurMapScript]
	ld [wProceduralForestCurScript], a
	jp TextScriptEnd

; Shown the instant the boss battle triggers ("<NAME> blocks the path!").
ProceduralForestBossText:
; text_asm MUST be first byte - this is a text pointer, raw opcodes
	; would be read as text commands without it.
	text_asm
	push bc
	ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
	call GetMonName             ; fill wNameBuffer before TalkToTrainer runs
	pop bc
	ld hl, .goBattle
	ret
.goBattle:
	; Go straight to battle - name display is in ProceduralCave1BossBattleText
	; (what TalkToTrainer shows), so there's only one text box, one A press.
	text_asm
	ld hl, PFBossTrainerHeader
	jr ProceduralForestInitBattleScript
    
; TalkToTrainer shows this as its "before battle text".
; Shows "<NAME>!" → player presses A → cry plays → battle starts.
; wNameBuffer was filled by ProceduralCave1BossText before TalkToTrainer ran.
ProceduralForestBossBattleText:
	text_far _PCBossEncounterText   ; "<NAME>!" + text_promptbutton (one A press)
	text_asm
	ld a, [wRoguePokemon1]
	call PlayCry
	call WaitForSoundToFinish
	jp TextScriptEnd
	; NOTE: do NOT touch wCurMapScript or wProceduralCave1CurScript here.
	; TalkToTrainer increments wCurMapScript after this text returns, and
	; StartTrainerBattle increments it again. Setting it here corrupts
	; the state machine and causes a post-battle freeze.

PFBossBlocksText:
	text_ram wNameBuffer
	text " blocks"
	line "the path!"
	prompt

PFBossJoinText:
	text_far _PCBossJoinText
	text_end

ProceduralForestCalmedText:
	text_far _PCWildCalmedText
	text_end

ProceduralForest_TextPointers:
	def_text_pointers
	dw_const ProceduralForestBossText, TEXT_PROCEDURALFOREST_BOSS
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFOREST_POKEBALL_1
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFOREST_POKEBALL_2
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFOREST_POKEBALL_3
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFOREST_POKEBALL_4
	dw_const ProceduralForestBossOfferText, TEXT_PROCEDURALFOREST_BOSS_OFFER
	dw_const PCWildCalmedText, TEXT_PROCEDURALFOREST_CALMED
	EXPORT TEXT_PROCEDURALFOREST_CALMED ; used by engine/battle/wild_encounters.asm
	;dw_const PCSignText, TEXT_PROCEDURALCAVE1_SIGN
