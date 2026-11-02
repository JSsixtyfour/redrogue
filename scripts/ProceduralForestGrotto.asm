ProceduralForestGrotto_Script:
	ld a, [wOptionalEncounterState]
	bit 2, a
	jr z, .offer
	xor a
	ld [wSprite01StateData1 + SPRITESTATEDATA1_PICTUREID], a
	dec a
	ld [wSprite01StateData1ImageIndex], a
.offer
	ld a, [wOptionalEncounterState]
	and %111
	cp %010 ; defeated, automatic offer not shown, unresolved
	jr nz, .scripts
	ld a, [wStatusFlags3]
	bit BIT_PRINT_END_BATTLE_TEXT, a
	jr nz, .scripts
	ld hl, wOptionalEncounterState
	set 0, [hl] ; full storage retry is by talking, not every script tick
	call Delay3
	ld a, TEXT_PROCEDURALFORESTGROTTO_OFFER
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
.scripts
	call EnableAutoTextBoxDrawing
	ld hl, FGEncounterHeader
	ld de, .pointers
	ld a, [wOptionalEncounterScript]
	call ExecuteCurMapScriptInTable
	ld [wOptionalEncounterScript], a
	ret
.pointers
	dw CheckFightingMapTrainers
	dw DisplayEnemyTrainerTextAndStartBattle
	dw FGEndEncounterBattle

FGEndEncounterBattle:
	; Preserve object until the offer resolves, including no-room retry.
	ld a, 1
	ld [wWasTrainerBattle], a
	jp EndTrainerBattle

FGEncounterHeader:
	db 1, 0 ; object 1, talk-only
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

FGEncounterEndText:
	text_end

FGEncounterOffer:
	text_asm
	push bc
	ld a, [wOptionalEncounterSpecies]
	ld [wNamedObjectIndex], a
	call GetMonName
	ld hl, .join
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
	set 2, [hl]
	xor a
	ld [wSprite01StateData1 + SPRITESTATEDATA1_PICTUREID], a
	dec a
	ld [wSprite01StateData1ImageIndex], a
.done
	pop bc
	jp TextScriptEnd
.join
	text_far _PCBossJoinText
	text_end
