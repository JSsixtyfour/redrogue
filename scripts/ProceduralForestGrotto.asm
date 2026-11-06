ProceduralForestGrotto_Script:
OptionalEncounterMapScript::
	call OptionalEncounterIsCurrent
	ret nc
	ld a, [wOptionalEncounterState]
	bit BIT_OPTIONAL_RESOLVED, a
	jr z, .offer
	call OptionalEncounterHide
.offer
	ld a, [wOptionalEncounterState]
	and OPTIONAL_ENCOUNTER_STATE_MASK
	cp 1 << BIT_OPTIONAL_DEFEATED ; automatic offer not shown, unresolved
	jr nz, .scripts
	ld a, [wStatusFlags3]
	bit BIT_PRINT_END_BATTLE_TEXT, a
	jr nz, .scripts
	ld hl, wOptionalEncounterState
	set BIT_OPTIONAL_OFFER_SHOWN, [hl] ; full storage retry is by talking
	call Delay3
	ldh a, [hCurMap]
	ld b, a
	cp PROCEDURAL_CAVE_SUBROOM
	ld a, TEXT_CAVESUB_OPTIONAL_OFFER
	jr z, .offerID
	ld a, b
	cp PROCEDURAL_FACILITY_SUBROOM
	ld a, TEXT_FACSUBROOM_OPTIONAL_OFFER
	jr z, .offerID
	ld a, b
	cp PROCEDURAL_FACILITY
	ld a, TEXT_PROCEDURALFACILITY_OPTIONAL_OFFER
	jr z, .offerID
	ld a, TEXT_PROCEDURALFORESTGROTTO_OFFER
.offerID
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
.scripts
	; The resident owns the ordinary cave script while our battle is idle.
	; Dispatching index0 here would overwrite its pending reward index.
	ld a, [wOptionalEncounterScript]
	and a
	jp z, OptionalEncounterContact
	call EnableAutoTextBoxDrawing
	ld hl, FGEncounterHeader
	ld de, .pointers
	ld a, [wOptionalEncounterScript]
	call ExecuteCurMapScriptInTable
	ld [wOptionalEncounterScript], a
	ret
.pointers
	dw OptionalEncounterIdle
	dw DisplayEnemyTrainerTextAndStartBattle
	dw FGEndEncounterBattle

OptionalEncounterIdle:
	ret ; explicit talk-only header, never scan cave resident slots

FGEndEncounterBattle:
	; Preserve object until the offer resolves, including no-room retry.
	ld a, 1
	ld [wWasTrainerBattle], a
	jp EndTrainerBattle

FGEncounterHeader:
	db BIT_OPTIONAL_DEFEATED, 0 ; no sight range; used by slots 1, 3, 6 or 13
	dw wOptionalEncounterState
	dw FGEncounterCry, FGEncounterOffer ; before, after
	dw FGEncounterEndText, FGEncounterEndText ; win, loss
	db -1

ProceduralForestGrotto_TextPointers:
	def_text_pointers
	dw_const FGEncounterText, TEXT_PROCEDURALFORESTGROTTO_POKEMON
	dw_const FGEncounterOffer, TEXT_PROCEDURALFORESTGROTTO_OFFER

FGEncounterText:
	text_asm
	push bc
	ld a, [wOptionalEncounterSpecies]
	ld [wNamedObjectIndex], a
	xor a
	ld [wFormContextForm], a
	ld a, [wOptionalEncounterSpecies]
	ld [wFormContextSpecies], a
	call GetMonName
	pop bc
	ld hl, FGEncounterHeader
	call TalkToTrainer
	ld a, [wCurMapScript]
	ld [wOptionalEncounterScript], a
	jp TextScriptEnd

FGEncounterCry:
	text_far _PCBossEncounterText
	text_asm
	ld a, [wOptionalEncounterSpecies]
	call PlayCry
	call WaitForSoundToFinish
	jp TextScriptEnd

; Join offer only: special display names (the encounter line and battle keep
; the normal species names). The longer names need a line of their own.
; In: hl = table of 5 text pointers (Onix, Snorlax, Psyduck, Golduck, Butterfree).
; Out: hl = selected pointer. Clobbers a, bc.
FGPickSpecialText:
	ld a, [wOptionalEncounterSpecies]
	ld c, 0
	cp ONIX
	jr z, .pick
	inc c
	cp SNORLAX
	jr z, .pick
	inc c
	cp PSYDUCK
	jr z, .pick
	inc c
	cp GOLDUCK
	jr z, .pick
	inc c
.pick
	ld b, 0
	sla c
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret

FGEncounterEndText:
	text_end

FGEncounterOffer:
	text_asm
	push bc
	ld hl, FGJoinTexts
	call FGPickSpecialText
	call PrintText
	call YesNoChoice
.choiceMade
	ld a, [hCurrentMenuItem]
	and a
	jr nz, .resolve
	xor a
	ld [wSpawnForm], a
	ld [wSpawnDVSlot], a
	ld a, [wOptionalEncounterSpecies]
	ld b, a
	ld a, [wOptionalEncounterLevel]
	ld c, a
	call GivePokemon
	jr nc, .done
	call OptionalEncounterFinalizeGift
.resolve
	ld hl, wOptionalEncounterState
	set BIT_OPTIONAL_RESOLVED, [hl]
	call OptionalEncounterHide
.done
	pop bc
	jp TextScriptEnd

FGJoinTexts:
	dw .onix, .snowlax, .psyduck, .golduck, .pink
.onix
	text "The wild"
	line "CRYSTAL ONIX wants"
	cont "to join your"
	cont "party!@"
	text_end
.snowlax
	text "The wild"
	line "SNOWLAX wants"
	cont "to join your"
	cont "party!@"
	text_end
.psyduck
	text "The wild"
	line "PSYCHIC PSYDUCK"
	cont "wants to join your"
	cont "party!@"
	text_end
.golduck
	text "The wild"
	line "PSYCHIC GOLDUCK"
	cont "wants to join your"
	cont "party!@"
	text_end
.pink
	text "The wild"
	line "COMPOUND EYES"
	cont "BUTTERFREE wants"
	cont "to join your"
	cont "party!@"
	text_end
