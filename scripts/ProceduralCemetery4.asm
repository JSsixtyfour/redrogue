ProceduralCemetery4_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	call PCemStageEnterSetup
.afterSetup
	call PCemCalmedCheck
	; Phase 7 rollout: floor 4 can be the rolled hideout like floors 2 and 3,
	; so it runs the same shared recovery. It sits BEFORE the script dispatch
	; below, so the boss trigger is untouched by it.
	ld d, TEXT_PROCEDURALCEMETERY4_STAGE_RECOVER
	call PCemStageEventRecoverCheck
	call EnableAutoTextBoxDrawing
	; FIXED 2026-09-17. This used to pass ProceduralCemetery4TrainerHeaders,
	; a label with ZERO bytes of trainer data behind it - it pointed straight
	; at the opcodes of the routine that followed it, which
	; CheckFightingMapTrainers then walked as if they were header records.
	; It was reachable the moment the boss was beaten (the `jp nz,
	; CheckFightingMapTrainers` in the default script below). The cemetery now
	; has real trainers, so it points at the real shared table.
	ld hl, PCemStageTrainerHeaders
	ld de, ProceduralCemetery4_ScriptPointers
	ld a, [wProceduralCemetery4CurScript]
	call ExecuteCurMapScriptInTable
	ld [wProceduralCemetery4CurScript], a
	ret

ProceduralCemetery4_ScriptPointers:
	def_script_pointers
	dw_const ProceduralCemetery4DefaultScript,           SCRIPT_PROCEDURALCEMETERY4_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_PROCEDURALCEMETERY4_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_PROCEDURALCEMETERY4_END_BATTLE
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
	; wRoguePokemon1 (the boss species) was rolled + persisted to SRAM at preload
	; (PCemRollBoss); wild battles on floors 1-4 clobber it in the meantime, so
	; restore it from SRAM right before the battle uses it.
	farcall PCemRestoreBossSpecies
	ld a, [wRoguePokemon1]
	ld [wCurOpponent], a
    farcall PCGetBossLevel        ; sets wCurEnemyLevel from wBattleCount
	; flag the upcoming enemy load as the cemetery ghost boss so LoadEnemyMonData
	; (PCemMaybeApplyGhostBoss) makes it a ghost variant with the rolled ghost move
	ld a, 1
	ld [wProcCemBossBattle], a
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
	farcall RogueAwardCredits1
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
	; Restore the SRAM-persisted boss species (the battle just clobbered
	; wRoguePokemon1). Safe to clobber bc here: this handler prints via
	; call PrintText, not the return-hl cursor pattern.
	farcall PCemRestoreBossSpecies
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
	jr nc, .cemDone               ; party AND box full: nothing was added
	; make the gifted mon identical to the boss just fought: ghost variant + move
	farcall PCemApplyGhostToGivenMon
.cemDone
	; No physical boss sprite in cemetery — nothing to hide
	ld hl, .textEnd
	jp TextScriptEnd
.textEnd
	text_end


; PCemCalmedText is exported from ProceduralCemetery1.asm — just referenced here
; via the dw_const in TextPointers above.

PCemBossJoinTextWrap:
	text_far _PCBossJoinText
	text_end

ProceduralCemetery4_TextPointers:
	def_text_pointers
	; ORDER IS LOAD-BEARING: see scripts/ProceduralCave1.asm's copy of this
	; note. The first wNumSprites entries must be the objects' own text, in
	; slot order, or DisplayTextID's .spriteHandling branch reroutes any
	; script-fired constant whose value is <= the object count. Measured here
	; before the reorder: CALMED printed the stage NPC's line.
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCEMETERY4_POKEBALL
	dw_const PCemStageEventNpc1Text, TEXT_PROCEDURALCEMETERY4_STAGE_NPC_1
	dw_const PCemStageEventNpc2Text, TEXT_PROCEDURALCEMETERY4_STAGE_NPC_2
	; --- end of the object block (3 objects); script-only ids follow ---
	dw_const ProceduralCemetery4BeGoneText,    TEXT_PROCEDURALCEMETERY4_BEGONE
	dw_const ProceduralCemetery4BossOfferText, TEXT_PROCEDURALCEMETERY4_BOSS_OFFER
	dw_const PCemCalmedText, TEXT_PROCEDURALCEMETERY4_CALMED
	dw_const PCemStageEventArrivalText, TEXT_PROCEDURALCEMETERY4_STAGE_EVENT
	dw_const PCemStageEventRecoverText, TEXT_PROCEDURALCEMETERY4_STAGE_RECOVER

ProceduralCemetery4BeGoneText:
	text_far _PokemonTower6FBeGoneText
	text_end
    