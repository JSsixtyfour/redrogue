ProceduralCave1_Script:
	; Each entry is a fresh generated layout (GenerateProceduralCave reruns
	; every map load) and EVENT_ENTER_ROOM gets reset on every warp
	; (WarpFound2, home/overworld.asm), so this always re-runs per visit -
	; matches the freshly-regenerated cave/items each time.
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	; item rolls + position patches already happened inside
	; GenerateProceduralCave (custom_functions/procedural_cave_gen.asm) at
	; map-load time - just reset all 4 wild area pokeballs to visible here,
	; same reasoning as Route1's RogueRefresh resetting TOGGLE_STAGE_RANDOM_ITEM
	; on every fresh entry (the toggle flags are persistent WRAM state that
	; could still be set from a previous visit/pickup).
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
.afterSetup
	call EnableAutoTextBoxDrawing
    ld hl, ProceduralCave1TrainerHeaders
	ld de, ProceduralCave1_ScriptPointers
	ld a, [wProceduralCave1CurScript]
	call ExecuteCurMapScriptInTable
	ld [wProceduralCave1CurScript], a
	ret

; TODO: boss encounter trigger. The species/level roll (PCPlaceBoss,
; custom_functions/procedural_cave_gen.asm) and the object_event declaration
; (data/maps/objects/ProceduralCave1.asm, species+level|OW_POKEMON in the
; "trainer" slot) are in place and confirmed working via PyBoy memory reads.
; What's still missing is the actual battle trigger - real Zapdos uses a
; text_asm entry (PowerPlantZapdosText: text_asm / ld hl, ZapdosTrainerHeader
; / jr PowerPlantInitBattleScript), not the CheckFightingMapTrainers/
; def_trainers sight-detection machinery this file tried first (reverted -
; it technically worked but needed a finicky event-constant bit-alignment
; hack to satisfy the `trainer` macro's ASSERT, see git history on this
; file if curious). Follow the real Zapdos pattern instead.


    
ProceduralCave1_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_PROCEDURALCAVE1_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_PROCEDURALCAVE1_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_PROCEDURALCAVE1_END_BATTLE

ProceduralCave1_TextPointers:
	def_text_pointers
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_1
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_2
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_3
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_4
	dw_const ProceduralCave1BossText, TEXT_PROCEDURALCAVE1_BOSS
    
ProceduralCave1TrainerHeaders:
	def_trainers 6
PCBossTrainerHeader:
	trainer EVENT_BEAT_PC_BOSS, 0, ProceduralCave1BossBattleText, ProceduralCave1BossBattleText, ProceduralCave1BossBattleText
	db -1 ; end
    
ProceduralCave1InitBattleScript:
	call TalkToTrainer
	ld a, [wCurMapScript]
	ld [wPowerPlantCurScript], a
	jp TextScriptEnd    
    

    
ProceduralCave1BossText:
	text_asm
	ld hl, PCBossTrainerHeader
	call TalkToTrainer
	jp TextScriptEnd

ProceduralCave1BossBattleText:
	text_far _ProceduralCave1BossBattleText
	text_asm
	ld a, PINSIR
	call PlayCry
	call WaitForSoundToFinish
	jp TextScriptEnd