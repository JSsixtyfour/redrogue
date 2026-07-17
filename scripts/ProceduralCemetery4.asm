ProceduralCemetery4_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall PCemRefreshBall
.afterSetup
	call PCemCalmedCheck
	call EnableAutoTextBoxDrawing
	ld hl, ProceduralCemetery4TrainerHeaders
	ld de, ProceduralCemetery4_ScriptPointers
	ld a, [wProceduralCemetery4CurScript]
	call ExecuteCurMapScriptInTable
	ld [wProceduralCemetery4CurScript], a
	ret
ProceduralCemetery4TrainerHeaders:

ProceduralCemetery4SetDefaultScript:
	xor a
	ldh [hJoyIgnore], a
	ld [wProceduralCemetery4CurScript], a ; SCRIPT_PROCEDURALCEMETERY4_DEFAULT
	ld [wCurMapScript], a ; SCRIPT_PROCEDURALCEMETERY4_DEFAULT
	ret
    
ProceduralCemetery4_ScriptPointers:
	def_script_pointers
	dw_const ProceduralCemetery4DefaultScript,           SCRIPT_PROCEDURALCEMETERY4_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_PROCEDURALCEMETERY4_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_PROCEDURALCEMETERY4_END_BATTLE
	dw_const ProceduralCemetery4PlayerMovingScript,      SCRIPT_PROCEDURALCEMETERY4_PLAYER_MOVING
	dw_const ProceduralCemetery4BossBattleScript,     SCRIPT_PROCEDURALCEMETERY4_BOSS_BATTLE


ProceduralCemetery4DefaultScript:
	CheckEvent EVENT_BEAT_PC_BOSS
	jp nz, CheckFightingMapTrainers
	ld hl, ProceduralCemetery4BossCoords
	call ArePlayerCoordsInArray
	jp nc, CheckFightingMapTrainers
	xor a
	ldh [hJoyHeld], a
	ld a, TEXT_PROCEDURALCEMETERY4_BEGONE
	ldh [hTextID], a
	call DisplayTextID
	ld a, [wRoguePokemon1]
	ld [wCurOpponent], a
    farcall PCGetBossLevel        ; sets wCurEnemyLevel from wBattleCount
	ld a, SCRIPT_PROCEDURALCEMETERY4_BOSS_BATTLE
	ld [wProceduralCemetery4CurScript], a
	ld [wCurMapScript], a
	ret
    
ProceduralCemetery4BossCoords:
	dbmapcoord 10, 16
    dbmapcoord 9, 15
	db -1 ; end
    
ProceduralCemetery4BossBattleScript:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, ProceduralCemetery4DefaultScript
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld a, [wStatusFlags3]
	bit BIT_TALKED_TO_TRAINER, a
	ret nz
	call UpdateSprites
	xor a
	ldh [hJoyIgnore], a
	SetEvent  EVENT_BEAT_PC_BOSS
	ld a, TEXT_PROCEDURALCEMETERY4_BOSS_OFFER
	ldh [hTextID], a
	call DisplayTextID
	ld a, SCRIPT_PROCEDURALCEMETERY4_DEFAULT
	ld [wProceduralCemetery4CurScript], a
	ld [wCurMapScript], a
	ret
    
; The join offer itself. Shown via DisplayTextID so the text box / font are set
; up properly (raw PrintText from a map-script state left the tiles unloaded,
; which is what produced glitched graphics and no visible text).
ProceduralCemetery4BossOfferText:
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


ProceduralCemetery4PlayerMovingScript:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	call Delay3
	xor a
	ld [wProceduralCemetery4CurScript], a
	ld [wCurMapScript], a
	ret

; PCemCalmedText is exported from ProceduralCemetery1.asm — just referenced here
; via the dw_const in TextPointers above.

PCemBossJoinTextWrap:
	text_far _PCBossJoinText
	text_end

ProceduralCemetery4_TextPointers:
	def_text_pointers
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCEMETERY4_POKEBALL
	dw_const ProceduralCemetery4BeGoneText,    TEXT_PROCEDURALCEMETERY4_BEGONE
	dw_const ProceduralCemetery4BossOfferText, TEXT_PROCEDURALCEMETERY4_BOSS_OFFER
	dw_const PCemCalmedText, TEXT_PROCEDURALCEMETERY4_CALMED

ProceduralCemetery4BeGoneText:
	text_far _PokemonTower6FBeGoneText
	text_end
    
ProceduralCemetery4JoinText:
	text_far _PCBossJoinText
	text_end