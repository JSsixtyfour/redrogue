; Close copy of scripts/ProceduralCave1.asm (the fundamentals-mandated baseline
; for a stage with a real overworld boss sprite - see PROCEDURAL_STAGE_FUNDAMENTALS.md).
; Reused events (never concurrent with cave/forest/cemetery, all reset at Pallet
; Town entry by PFacPreload):
;   EVENT_BEAT_PC_BOSS  - boss defeated / offered (bit-aligned for slot-1 trainer)
;   EVENT_PC_BOSS_OFFERED
;   EVENT_PC_BUDGET_ENDED / EVENT_PC_CALMED_SHOWN - wild budget calmed message

ProceduralFacility_Script:
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
	ld a, TEXT_PROCEDURALFACILITY_CALMED
	ldh [hTextID], a
	call DisplayTextID
.afterCalm
	; One-time join offer, shown after the boss is beaten and the end-battle
	; text has fully cleared (same shape cave/forest use).
	CheckEvent EVENT_PC_BOSS_OFFERED
	jr nz, .runScripts
	CheckEvent EVENT_BEAT_PC_BOSS
	jr z, .runScripts
	ld a, [wStatusFlags3]
	bit BIT_PRINT_END_BATTLE_TEXT, a
	jr nz, .runScripts
	SetEvent EVENT_PC_BOSS_OFFERED
	farcall Delay3
	ld a, TEXT_PROCEDURALFACILITY_BOSS_OFFER
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
.runScripts
	call EnableAutoTextBoxDrawing
	ld hl, ProceduralFacilityTrainerHeaders
	ld de, ProceduralFacility_ScriptPointers
	ld a, [wProceduralCave1CurScript]
	call ExecuteCurMapScriptInTable
	ld [wProceduralCave1CurScript], a
	ret

ProceduralFacility_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_PROCEDURALFACILITY_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_PROCEDURALFACILITY_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_PROCEDURALFACILITY_END_BATTLE

; The join offer itself. Shown via DisplayTextID so the text box / font are set
; up properly (raw PrintText from a map-script state left the tiles unloaded,
; which is what produced glitched graphics and no visible text on the cave).
ProceduralFacilityBossOfferText:
	text_asm
	ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
	call GetMonName               ; fill wNameBuffer for the offer text
	ld hl, PFacBossJoinText
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

PFacBossJoinText:
	text_far _PCBossJoinText
	text_end

PFacWildCalmedText:
	text_far _PCWildCalmedText
	text_end

PFacSignText:
	text_asm
	; Read sign variant from SRAM (rolled at preload, stable for the whole run).
	; Use call PrintText — ld hl/ret causes TX_START to pop the text stream
	; pointer as the tile cursor, so line 1 writes off-screen (invisible).
	; PrintText sets up its own tile cursor through the normal init path.
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sProcFacilityStagingBuffer)  ; facility SRAM is bank 1
	ld [rRAMB], a
	ld a, [sProcFacilitySignVariant]
	ld b, a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ld [rRAMG], a
	ld a, b
	and a
	jr nz, .showBoss
	ld hl, PFacSignItemsText
	jr .show
.showBoss
	ld hl, PFacSignBossText
.show
	call PrintText
	ld hl, .signEnd    ; point NextTextCommand at TX_END for clean exit
	jp TextScriptEnd
.signEnd
	text_end

PFacSignItemsText:
	text_far _PFacSignItemsText
	text_end

PFacSignBossText:
	text_far _PFacSignBossText
	text_end

ProceduralFacility_TextPointers:
	def_text_pointers
    dw_const ProceduralFacilityBossText, TEXT_PROCEDURALFACILITY_BOSS
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFACILITY_WILD_AREA_POKEBALL_1
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFACILITY_WILD_AREA_POKEBALL_2
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFACILITY_WILD_AREA_POKEBALL_3
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFACILITY_WILD_AREA_POKEBALL_4
	dw_const ProceduralFacilityBossOfferText, TEXT_PROCEDURALFACILITY_BOSS_OFFER
	dw_const PFacWildCalmedText, TEXT_PROCEDURALFACILITY_CALMED
	EXPORT TEXT_PROCEDURALFACILITY_CALMED ; used by engine/battle/wild_encounters.asm
	dw_const PFacSignText, TEXT_PROCEDURALFACILITY_SIGN

ProceduralFacilityTrainerHeaders:
	def_trainers 1  ; boss is slot 1; CheckForEngagingTrainers uses CURRENT_TRAINER_BIT
	                ; as the sprite slot, so this must match the boss's object_event position.
	                ; EVENT_BEAT_PC_BOSS % 8 == 1 == 1 % 8 to satisfy trainer ASSERT.
PFacBossTrainerHeader:
	trainer EVENT_BEAT_PC_BOSS, 0, ProceduralFacilityBossBattleText, ProceduralFacilityBossBattleText, ProceduralFacilityBossBattleText
	db -1 ; end

ProceduralFacilityInitBattleScript:
	call TalkToTrainer
	ld a, [wCurMapScript]
	ld [wProceduralCave1CurScript], a
	jp TextScriptEnd

ProceduralFacilityBossText:
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
	; Go straight to battle - name display is in ProceduralFacilityBossBattleText
	; (what TalkToTrainer shows), so there's only one text box, one A press.
	text_asm
	ld hl, PFacBossTrainerHeader
	jr ProceduralFacilityInitBattleScript

; TalkToTrainer shows this as its "before battle text".
; Shows "<NAME>!" → player presses A → cry plays → battle starts.
; wNameBuffer was filled by ProceduralFacilityBossText before TalkToTrainer ran.
ProceduralFacilityBossBattleText:
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
