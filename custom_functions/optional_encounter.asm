; Same bank as grove. Seven saved padding bytes, schema 17.
OptionalEncounterClear::
	xor a
	ld hl, wOptionalEncounterSpecies
	ld bc, 7
	jp FillMemory

; Fresh-stage reset; Debug 2 retains its forced fixture for quick testing.
OptionalForestResetEncounter::
	call OptionalEncounterClear
IF DEF(_DEBUG)
	ld a, [wStatusFlags6]
	bit BIT_DEBUG2_MODE, a
	ret z
	jp OptionalForcePink
ENDC
	ret

; SRAM0 is already open; use after the stage's season/theme has been latched.
OptionalForestAssignEncounter::
IF DEF(_DEBUG)
	ld a, [wStatusFlags6]
	bit BIT_DEBUG2_MODE, a
	jr z, .production
	ld a, [sProcForestPalette]
	cp 3
	ret nz
	call OptionalForceSnorlax
	call FGOpenParentSRAM
	ret
ENDC
.production
	ld c, 100
	call Rangerandom
	call OptionalForestOutcome
	jp FGOpenParentSRAM

; A=unbiased0..99, SRAM0 open. One categorical outcome, no geometry reroll.
OptionalForestOutcome::
	ld c, a
	ld a, [sProcForestPalette]
	cp PROC_FOREST_PAL_COUNT
	ret nc
	ld e, a
	ld d, 0
	ld hl, .odds
	add hl, de
	ld a, c
	cp [hl]
	ret nc
	ld a, e
	cp 3
	jp z, OptionalForceSnorlax
	jp OptionalForcePink
.odds
	db 24, 4, 12, 20 ; saved IDs: spring, fall, summer, winter
	ASSERT PROC_FOREST_PAL_COUNT == 4

OptionalCaveAssignEncounter::
	call OptionalEncounterClear
IF DEF(_DEBUG)
	ld a, [wStatusFlags6]
	bit BIT_DEBUG2_MODE, a
	jr z, .production
	ld a, [sProcCavePalette]
	cp 1
	ret nz
	call Random
	and 1
	jr z, .onix
	call OptionalForceSnorlax
	jr .map
.onix
	call OptionalForceOnix
.map
	ld a, PROCEDURAL_CAVE_SUBROOM
	ld [wOptionalEncounterMap], a
	call FGOpenParentSRAM
	ret
ENDC
.production
	ld a, [sProcCavePalette]
	cp 1
	ret nz
	ld c, 33 ; matches33% cold theme:10/33 Onix and5/33 Snowlax give10%/5% overall
	call Rangerandom
	call OptionalCaveOutcome
	jp FGOpenParentSRAM

; Cold only, A=0..32:10 bins Onix,5 Snowlax,18 none. With33% cold caves,
; overall selection is exactly10%/5%, before accepted no-ladder losses.
OptionalCaveOutcome::
	cp 10
	jp c, OptionalForceOnix
	cp 15
	ret nc
	call OptionalForceSnorlax
	ld a, PROCEDURAL_CAVE_SUBROOM
	ld [wOptionalEncounterMap], a
	ret

OptionalForceSnorlax::
	call OptionalForcePink ; shared reset and reduced-level calculation
	ld a, SNORLAX
	ld [wOptionalEncounterSpecies], a
	jr OptionalRollColdPackage

OptionalForceOnix::
	call OptionalForcePink
	ld a, ONIX
	ld [wOptionalEncounterSpecies], a
	ld a, PROCEDURAL_CAVE_SUBROOM
	ld [wOptionalEncounterMap], a
OptionalRollColdPackage:
	call Random
	and 1
	add 2 ; appended package ids: 2=Mist, 3=Haze. Pink remains 1.
	ld [wOptionalEncounterPackage], a
	ret

; Nonzero species only for a complete valid assigned identity.
OptionalEncounterAssigned::
	ld a, [wOptionalEncounterPackage]
	cp 1
	jr z, .pink
	sub 2
	cp 2
	jr nc, .no
	ld a, [wOptionalEncounterSpecies]
	cp SNORLAX
	ret z
	cp ONIX
	ret z
	jr .no
.pink
	ld a, [wOptionalEncounterSpecies]
	cp BUTTERFREE
	ret z
.no
	xor a
	ret

OptionalEncounterIsCurrent:
	ldh a, [hCurMap]
	ld hl, wOptionalEncounterMap
	cp [hl]
	jr nz, .no
	call OptionalEncounterAssigned
	and a
	ret z
	scf
	ret
.no
	xor a
	ret

OptionalForcePink::
	call OptionalEncounterClear
	farcall PCGetBossLevel
	ld a, [wCurEnemyLevel]
	push af
	call GetRunProgress
	cp ROUND_BATTLES + 1 ; through first leader: -1, later: -2
	jr c, .one
	pop af
	dec a
	jr z, .minimum
	jr .reduce
.one
	pop af
.reduce
	dec a
	jr nz, .level
.minimum
	ld a, 1
.level
	ld [wOptionalEncounterLevel], a
	ld a, BUTTERFREE
	ld [wOptionalEncounterSpecies], a
	ld a, 1
	ld [wOptionalEncounterPackage], a
	ld a, PROCEDURAL_FOREST_GROTTO
	ld [wOptionalEncounterMap], a
	ret

OptionalEncounterPatchSprite::
	call OptionalEncounterIsCurrent
	and a
	ld a, 0
	jr z, .store
	ld a, [wOptionalEncounterState]
	bit BIT_OPTIONAL_RESOLVED, a
	ld a, 0
	jr nz, .store
	ld a, SPRITE_MONSTER
.store
	push af
	call OptionalSpriteAddress
	pop af
	ld [hl], a
	ret

OptionalSpriteAddress:
	ld hl, wSprite01StateData1
	ldh a, [hCurMap]
	cp PROCEDURAL_CAVE_SUBROOM
	ret nz
	ld hl, wSprite06StateData1
	ret

OptionalEncounterHide::
	call OptionalSpriteAddress
	xor a
	ld [hli], a
	inc hl ; ImageIndex
	dec a
	ld [hl], a
	ret

; EngageMapTrainer OW_POKEMON seam. Carry means this owns the request.
OptionalEncounterEngage::
	call OptionalEncounterIsCurrent
	jr nc, .no
	ld a, [wOptionalEncounterState]
	and (1 << BIT_OPTIONAL_DEFEATED) | (1 << BIT_OPTIONAL_RESOLVED)
	jr nz, .no
	xor a
	ld [wSpawnForm], a
	ld a, [wOptionalEncounterSpecies]
	ld [wEngagedTrainerClass], a
	ld a, [wOptionalEncounterLevel]
	ld [wEngagedTrainerSet], a ; includes true level >127
	ld a, 1
	ld [wOptionalEncounterBattle], a
	scf
	ret
.no
	and a
	ret

; After the ordinary catch-rate clear. e = flags byte. Consume even rejected
; requests; map/species/package guard prevents leakage into other battles.
OptionalEncounterEnemyFlags::
	push bc
	push hl
	ld a, [wOptionalEncounterBattle]
	and a
	jr z, .done
	ldh a, [hIsInBattle]
	cp 1
	jr nz, .reject
	call OptionalEncounterIsCurrent
	jr nc, .reject
	ld a, [wEnemyMonSpecies]
	ld hl, wOptionalEncounterSpecies
	cp [hl]
	jr nz, .reject
	set BIT_SPECIAL_FORM, e
	ld a, [wOptionalEncounterPackage]
	cp 2
	jr c, .done
	set BIT_TYPE_VARIANT, e ; cold packages have no special stat capability
	ld a, ICE
	ld [wEnemyMonType1], a
	ld a, [wOptionalEncounterSpecies]
	cp ONIX
	ld a, ICE
	jr nz, .type2
	ld a, GROUND
.type2
	ld [wEnemyMonType2], a
	jr .done
.reject
	xor a
	ld [wOptionalEncounterBattle], a
.done
	pop hl
	pop bc
	ret

; GivePokemon carry required. Existing helper locates actual party/box gift.
OptionalEncounterFinalizeGift::
	ld e, BRIDGE_MON_FINALIZE_SPECIAL
	farcall BridgeFinalizeGiftMonFar
	ld b, MON_PP - MON_MOVES
	jp OptionalGrantColdMoves

; Replaces the existing tail hook without growing the crowded Battle Core.
; Preserve the cemetery hook's original order and behavior before our grant.
OptionalEncounterAfterEnemyLoad::
	farcall PCemMaybeApplyGhostBoss
	ld a, [wOptionalEncounterBattle]
	ld b, a
	xor a
	ld [wOptionalEncounterBattle], a
	ld a, b
	and a
	ret z
	call OptionalEncounterIsCurrent
	ret nc
	ldh a, [hIsInBattle]
	cp 1
	ret nz
	ld a, [wEnemyMonSpecies]
	ld hl, wOptionalEncounterSpecies
	cp [hl]
	ret nz
	ld de, wEnemyMon
	farcall ApplySpecialForm
	ld b, wEnemyMonPP - wEnemyMonMoves
	jp OptionalGrantColdMoves

; Existing battle-item gate calls here only in an ordinary active battle.
; A failed capture request consumes neither the ball nor the player's turn.
OptionalEncounterCaptureGate::
	call OptionalEncounterIsCurrent
	jr nc, .no
	ld a, [wCurItem]
	cp SAFARI_BALL
	jr z, .reject
	cp POKE_BALL + 1
	jr nc, .no
.reject
	xor a
	ld [wActionResultOrTookBattleTurn], a
	ld hl, .text
	call PrintText
	scf
	ret
.no
	and a
	ret
.text
	text "Win its trust!"
	prompt
