ProceduralCemetary4_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	ld a, TOGGLE_CEMETARY_4_POKEBALL
	ld [wToggleableObjectIndex], a
	predef ShowObject
.afterSetup
	call PCemCalmedCheck
	call EnableAutoTextBoxDrawing
	ld hl, ProceduralCemetary4TrainerHeaders
	ld de, ProceduralCemetary4_ScriptPointers
	ld a, [wProceduralCemetary4CurScript]
	call ExecuteCurMapScriptInTable
	ld [wProceduralCemetary4CurScript], a
	ret
ProceduralCemetary4TrainerHeaders:

ProceduralCemetary4SetDefaultScript:
	xor a
	ldh [hJoyIgnore], a
	ld [wProceduralCemetary4CurScript], a ; SCRIPT_PROCEDURALCEMETARY4_DEFAULT
	ld [wCurMapScript], a ; SCRIPT_PROCEDURALCEMETARY4_DEFAULT
	ret
    
ProceduralCemetary4_ScriptPointers:
	def_script_pointers
	dw_const ProceduralCemetary4DefaultScript,           SCRIPT_PROCEDURALCEMETARY4_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_PROCEDURALCEMETARY4_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_PROCEDURALCEMETARY4_END_BATTLE
	dw_const ProceduralCemetary4PlayerMovingScript,      SCRIPT_PROCEDURALCEMETARY4_PLAYER_MOVING
	dw_const ProceduralCemetary4BossBattleScript,     SCRIPT_PROCEDURALCEMETARY4_BOSS_BATTLE


ProceduralCemetary4DefaultScript:
	CheckEvent EVENT_BEAT_PC_BOSS
	jp nz, CheckFightingMapTrainers
	ld hl, ProceduralCemetary4BossCoords
	call ArePlayerCoordsInArray
	jp nc, CheckFightingMapTrainers
	xor a
	ldh [hJoyHeld], a
	ld a, TEXT_PROCEDURALCEMETARY4_BEGONE
	ldh [hTextID], a
	call DisplayTextID
	ld a, [wRoguePokemon1]
	ld [wCurOpponent], a
    farcall PCGetBossLevel        ; sets wCurEnemyLevel from wBattleCount
	ld a, SCRIPT_PROCEDURALCEMETARY4_BOSS_BATTLE
	ld [wProceduralCemetary4CurScript], a
	ld [wCurMapScript], a
	ret
    
ProceduralCemetary4BossCoords:
	dbmapcoord 10, 16
    dbmapcoord 9, 15
	db -1 ; end
    
ProceduralCemetary4BossBattleScript:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, ProceduralCemetary4DefaultScript
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld a, [wStatusFlags3]
	bit BIT_TALKED_TO_TRAINER, a
	ret nz
	call UpdateSprites
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld a, [wBattleResult]
	and a
	jr nz, .did_not_defeat
	SetEvent  EVENT_BEAT_PC_BOSS
	ld a, TEXT_PROCEDURALCEMETARY4_BOSS_OFFER
	ldh [hTextID], a
	call DisplayTextID
	xor a
	ldh [hJoyIgnore], a
	ld a, SCRIPT_PROCEDURALCEMETARY4_DEFAULT
	ld [wProceduralCemetary4CurScript], a
	ld [wCurMapScript], a
	ret
.did_not_defeat
	ld a, $1
	ldh [hSimulatedJoypadStatesIndex], a
	ld a, PAD_RIGHT
	ld [wSimulatedJoypadStatesEnd], a
	xor a
	ld [wSpritePlayerStateData2MovementByte1], a
	ld [wOverrideSimulatedJoypadStatesMask], a
	ld hl, wStatusFlags5
	set BIT_SCRIPTED_MOVEMENT_STATE, [hl]
	ld a, SCRIPT_PROCEDURALCEMETARY4_PLAYER_MOVING
	ld [wProceduralCemetary4CurScript], a
	ld [wCurMapScript], a
	ret
    
; The join offer itself. Shown via DisplayTextID so the text box / font are set
; up properly (raw PrintText from a map-script state left the tiles unloaded,
; which is what produced glitched graphics and no visible text).
ProceduralCemetary4BossOfferText:
	text_asm
	ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
	call GetMonName
	; Use PCBossJoinText (cave's join text) for the offer message
	ld hl, PCemBossJoinTextWrap
	call PrintText
	call YesNoChoice
	ld a, [hCurrentMenuItem]
	and a
	jr nz, .cemDone
	farcall PCGetBossLevel
	ld a, [wRoguePokemon1]
	ld b, a
	ld a, [wCurEnemyLevel]
	ld c, a
	call GivePokemon
.cemDone
	; No physical boss sprite in cemetery — nothing to hide
	ld hl, .textEnd
	jp TextScriptEnd
.textEnd
	text_end


ProceduralCemetary4PlayerMovingScript:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	call Delay3
	xor a
	ld [wProceduralCemetary4CurScript], a
	ld [wCurMapScript], a
	ret

; PCemCalmedText is exported from ProceduralCemetary1.asm — just referenced here
; via the dw_const in TextPointers above.

PCemBossJoinTextWrap:
	text_far _PCBossJoinText
	text_end

ProceduralCemetary4_TextPointers:
	def_text_pointers
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCEMETARY4_POKEBALL
	dw_const ProceduralCemetary4BeGoneText,    TEXT_PROCEDURALCEMETARY4_BEGONE
	dw_const ProceduralCemetary4BossOfferText, TEXT_PROCEDURALCEMETARY4_BOSS_OFFER
	dw_const PCemCalmedText, TEXT_PROCEDURALCEMETARY4_CALMED

ProceduralCemetary4BeGoneText:
	text_far _PokemonTower6FBeGoneText
	text_end
    
ProceduralCemetary4JoinText:
	text_far _PCBossJoinText
	text_end