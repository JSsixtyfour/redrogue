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

; PFacPreload, SRAM bank 1 open and left open. The roll is here and not at
; generation because the sprite is patched before a fresh Facility generates:
; rolled later, the first entry draws nothing. Clears first: nothing else resets
; it between Facilities. Debug 2 forces it on palette 1, as the cave forces its
; own on one theme.
OptionalFacilityAssignEncounter::
	ld a, [wCurEnemyLevel]          ; the shared level calculation writes it
	push af
	call OptionalEncounterClear
IF DEF(_DEBUG)
	ld a, [wStatusFlags6]
	bit BIT_DEBUG2_MODE, a
	jr z, .production
	ld a, [sProcFacilityPalette]
	cp 1
	jr nz, .done
	call OptionalForcePsychic
	jr .done
.production
ENDC
	ld c, 100
	call Rangerandom
	call OptionalFacilityOutcome
.done
	pop af
	ld [wCurEnemyLevel], a
	jp OptionalFacilityOpenSRAM

; PFacFinalize's first visit, last of all; SRAM bank 1 open and left open. It
; stands in the Facility itself, on a block picked by the rule the pads and the
; Super Nerd use. Only a Facility with no such block sends it to the warp room,
; and one with neither goes without. The 90% that rolled nothing skip the search.
OptionalFacilityPlaceEncounter::
	call OptionalEncounterIsCurrent
	ret nc
	call OptionalFacilityFindSpot
.haveSpot
	ret c
	call OptionalEncounterHide      ; patched already, and it is not staying
	ld a, [sProcFacilityGenScratch + FACSUB_SCRATCH_PAD]
	cp NUM_FACILITY_PAD_SITES
	jp nc, OptionalEncounterClear
	ld a, PROCEDURAL_FACILITY_SUBROOM
	ld [wOptionalEncounterMap], a
	ret

; A uniform pick over every block PFacPadBlockValid passes, in one pass: the k-th
; passing block replaces the pick with odds 1/k. Never the Super Nerd's block.
; Out: carry = found, in FACSUB_SCRATCH_MON_X/Y. SRAM bank 1 stays open.
OptionalFacilityFindSpot:
	call OptionalFacilityOpenSRAM
	ld b, 0                         ; blocks passed so far
	ld e, FACSUB_FALLBACK_TOP
.row
	ld d, 1
.block
	push bc
	farcall PFacPadBlockValid       ; carry = it passes; keeps d/e
	pop bc                          ; keeps the carry
	jr nc, .next
	ld a, [sProcFacilityGenScratch + FACSUB_SCRATCH_PIECE]
	xor FACSUB_FALLBACK
	cp d
	jr nz, .notNerd
	ld a, [sProcFacilityGenScratch + FACSUB_SCRATCH_PAD]
	xor FACSUB_FALLBACK_ROW
	cp e
	jr z, .next
.notNerd
	inc b
	jr nz, .count
	dec b                           ; 255 is plenty: keep the odds byte valid
.count
	ld c, b
	call Rangerandom                ; keeps bc and de
	and a
	jr nz, .next
	ld a, d
	ld [sProcFacilityGenScratch + FACSUB_SCRATCH_MON_X], a
	ld a, e
	ld [sProcFacilityGenScratch + FACSUB_SCRATCH_MON_Y], a
.next
	inc d
	ld a, d
	cp FACSUB_FALLBACK_MAX + 1
	jr c, .block
	inc e
	ld a, e
	cp FACSUB_FALLBACK_MAX + 1
	jr c, .row
	ld a, b
	and a
	ret z                           ; carry clear
	scf
	ret

; A=unbiased0..99. 10%.
OptionalFacilityOutcome::
	cp 10
	ret nc
	; fall through

; Psyduck evolves at 33 (data/pokemon/evos_moves.asm; test_optional_facility
; holds this to it). The package carries its support move, rolled once here so
; the battle and the gift agree.
OptionalForcePsychic::
	call OptionalForcePink
	ld a, [wOptionalEncounterLevel]
	cp 33
	ld a, PSYDUCK
	jr c, .species
	ld a, GOLDUCK
.species
	ld [wOptionalEncounterSpecies], a
	ld c, NUM_OPTIONAL_PSYCHIC_PACKAGES
	call Rangerandom
	add OPTIONAL_PACKAGE_PSYCHIC
	ld [wOptionalEncounterPackage], a
	ld a, PROCEDURAL_FACILITY
	ld [wOptionalEncounterMap], a
	ret

OptionalFacilityOpenSRAM:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
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
	cp OPTIONAL_PACKAGE_PSYCHIC
	jr nc, .psychic
	sub 2
	cp 2
	jr nc, .no
	ld a, [wOptionalEncounterSpecies]
	cp SNORLAX
	ret z
	cp ONIX
	ret z
	jr .no
.psychic
	cp OPTIONAL_PACKAGE_PSYCHIC + NUM_OPTIONAL_PSYCHIC_PACKAGES
	jr nc, .no
	ld a, [wOptionalEncounterSpecies]
	cp PSYDUCK
	ret z
	cp GOLDUCK
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
	; The species' own overworld sheet, resolved like the stage bosses'. A fixed
	; SPRITE_MONSTER here drew Butterfree, Psyduck and Snorlax as the generic
	; monster although each has its own sheet.
	ld a, [wOptionalEncounterSpecies]
	ld e, a
	ld d, 0                         ; base appearance: the package is not a form
	farcall PCGetSpeciesOWSprite
	ld a, e
.store
	push af
	call OptionalSpriteAddress
	pop af
	ld [hl], a
	ret

OptionalSpriteAddress:
	ldh a, [hCurMap]
	ld hl, wSprite{d:FACILITY_OPTIONAL_MON}StateData1
	cp PROCEDURAL_FACILITY
	ret z
	ld hl, wSprite03StateData1
	cp PROCEDURAL_FACILITY_SUBROOM
	ret z
	ld hl, wSprite06StateData1
	cp PROCEDURAL_CAVE_SUBROOM
	ret z
	ld hl, wSprite01StateData1
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
	set BIT_TYPE_VARIANT, e ; these packages have no special stat capability
	cp OPTIONAL_PACKAGE_PSYCHIC
	jr c, .cold
	ld a, WATER
	ld [wEnemyMonType1], a
	ld a, PSYCHIC_TYPE
	jr .type2
.cold
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
