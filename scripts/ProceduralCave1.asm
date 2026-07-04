ProceduralCave1_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	; Reset pokeballs to visible on each fresh entry.
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
	; Keep boss hidden on re-entry once beaten.
;    CheckEvent EVENT_PC_BOSS_OFFERED
;	jr nz, .noOffer
;	CheckEvent EVENT_BEAT_PC_BOSS
;	jr z, .bossNotDefeated
;	ld a, TOGGLE_WILD_AREA_BOSS
;	ld [wToggleableObjectIndex], a
;	predef HideObject
;.bossNotDefeated
.afterSetup
	; Post-battle join offer: only once, only after screen fully returns from
	; battle (BIT_PRINT_END_BATTLE_TEXT clear = transition done, matching the
	; pattern PowerPlant uses for its own post-battle reward display).
	CheckEvent EVENT_BEAT_PC_BOSS
	jr z, .noOffer
	CheckEvent EVENT_PC_BOSS_OFFERED
	jr nz, .noOffer
	;call PCBossOffer
.noOffer
	call EnableAutoTextBoxDrawing
	ld hl, ProceduralCave1TrainerHeaders
	ld de, ProceduralCave1_ScriptPointers
	ld a, [wProceduralCave1CurScript]
	call ExecuteCurMapScriptInTable
	ld [wProceduralCave1CurScript], a
	ret

; Offer to join the party: shown once after boss beaten.
; Species from wRoguePokemon1 (set by PCPlaceBoss, persists across battle).
; Level re-derived from PCGetBossLevel (deterministic from wBattleCount).
; Hides boss at end regardless of yes/no - player has made their choice.
PCBossOffer:
	ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
	call GetMonName
	ld hl, PCBossJoinText
	call PrintText
	ld hl, PCBossJoinText2
	call PrintText
	call YesNoChoice              ; carry = YES
	jr nc, .declined
	ld a, [wRoguePokemon1]
	ld b, a
	farcall PCGetBossLevel
	ld a, [wCurEnemyLevel]
	ld c, a
	call GivePokemon
.declined
	; Hide boss now that the offer is done (yes or no).
	ld a, TOGGLE_WILD_AREA_BOSS
	ld [wToggleableObjectIndex], a
	predef HideObject
	ret

PCBossJoinText:
	text_far _PCBossJoinText
	text_end

PCBossJoinText2:
	text_far _PCBossJoinText2
	text_end


ProceduralCave1_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_PROCEDURALCAVE1_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_PROCEDURALCAVE1_START_BATTLE
    dw_const EndTrainerBattle,                      SCRIPT_PROCEDURALCAVE1_END_BATTLE
	dw_const PCBossOffer,                           SCRIPT_PROCEDURALCAVE1_OFFER

ProceduralCave1_TextPointers:
	def_text_pointers
    dw_const ProceduralCave1BossText, TEXT_PROCEDURALCAVE1_BOSS
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_1
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_2
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_3
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_4
    ;dw_const PCBossEncounterText, TEXT_PROCEDURALCAVE1_BOSS_ENCOUNTER
    ;dw_const ProceduralCave1BossRoarText, TEXT_PROCEDURALCAVE1_BOSS_ROAR

ProceduralCave1TrainerHeaders:
	def_trainers 1  ; boss is slot 1; CheckForEngagingTrainers uses CURRENT_TRAINER_BIT
	                ; as the sprite slot, so this must match the boss's object_event position.
	                ; EVENT_BEAT_PC_BOSS % 8 == 1 == 1 % 8 to satisfy trainer ASSERT.
PCBossTrainerHeader:
	trainer EVENT_BEAT_PC_BOSS, 0, ProceduralCave1BossBattleText, ProceduralCave1BossBattleText, ProceduralCave1BossBattleText
	db -1 ; end

ProceduralCaveInitBattleScript:
	call TalkToTrainer
	ld a, [wCurMapScript]
	ld [wProceduralCave1CurScript], a
	jp TextScriptEnd

ProceduralCave1BossText:
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
	ld hl, PCBossTrainerHeader
	jr ProceduralCaveInitBattleScript

; TalkToTrainer shows this as its "before battle text".
; Shows "<NAME>!" → player presses A → cry plays → battle starts.
; wNameBuffer was filled by ProceduralCave1BossText before TalkToTrainer ran.
ProceduralCave1BossBattleText:
	text_far _PCBossEncounterText   ; "<NAME>!" + text_promptbutton (one A press)
	text_asm
	ld a, [wRoguePokemon1]
	call PlayCry
	call WaitForSoundToFinish
	ld a, SCRIPT_PROCEDURALCAVE1_OFFER
	ld [wProceduralCave1CurScript], a
	ld [wCurMapScript], a
	jp TextScriptEnd
