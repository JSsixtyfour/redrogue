ProceduralCave1_Script:
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
	ld a, TEXT_PROCEDURALCAVE1_BOSS_OFFER
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
.runScripts
	call EnableAutoTextBoxDrawing
	ld hl, ProceduralCave1TrainerHeaders
	ld de, ProceduralCave1_ScriptPointers
	ld a, [wProceduralCave1CurScript]
	call ExecuteCurMapScriptInTable
	ld [wProceduralCave1CurScript], a
	ret

ProceduralCave1_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_PROCEDURALCAVE1_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_PROCEDURALCAVE1_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_PROCEDURALCAVE1_END_BATTLE

; The join offer itself. Shown via DisplayTextID so the text box / font are set
; up properly (raw PrintText from a map-script state left the tiles unloaded,
; which is what produced glitched graphics and no visible text).
ProceduralCave1BossOfferText:
	text_asm
	ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
	call GetMonName               ; fill wNameBuffer for the offer text
	ld hl, PCBossJoinText
	call PrintText
	call YesNoChoice              ; yes -> carry set
    ld a, [hCurrentMenuItem]
	and a
	jr nz, .done ; if player chose No
	farcall PCGetBossLevel        ; sets wCurEnemyLevel from wBattleCount
	ld a, [wRoguePokemon1]
	ld b, a                       ; b = species
	ld a, [wCurEnemyLevel]
	ld c, a                       ; c = level
	call GivePokemon
.done
	ld a, TOGGLE_WILD_AREA_BOSS
	ld [wToggleableObjectIndex], a
	predef HideObject
	jp TextScriptEnd

PCBossJoinText:
	text_far _PCBossJoinText
	text_end

ProceduralCave1_TextPointers:
	def_text_pointers
    dw_const ProceduralCave1BossText, TEXT_PROCEDURALCAVE1_BOSS
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_1
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_2
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_3
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_4
	dw_const ProceduralCave1BossOfferText, TEXT_PROCEDURALCAVE1_BOSS_OFFER
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
	jp TextScriptEnd
	; NOTE: do NOT touch wCurMapScript or wProceduralCave1CurScript here.
	; TalkToTrainer increments wCurMapScript after this text returns, and
	; StartTrainerBattle increments it again. Setting it here corrupts
	; the state machine and causes a post-battle freeze.
