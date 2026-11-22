; try to initiate a wild pokemon encounter
; returns success in Z
TryDoWildEncounter:
	ld a, [wNPCMovementScriptPointerTableNum]
	and a
	ret nz
	ld a, [wMovementFlags]
	and a ; is player exiting a door, jumping over a ledge, or fishing?
	ret nz
	callfar IsPlayerStandingOnDoorTileOrWarpTile
	jr nc, .notStandingOnDoorOrWarpTile
.CantEncounter
	ld a, $1
	and a
	ret
.notStandingOnDoorOrWarpTile
	callfar IsPlayerJustOutsideMap
	jr z, .CantEncounter
	ld a, [wRepelRemainingSteps]
	and a
	jr z, .next
	dec a
	jp z, .lastRepelStep
	ld [wRepelRemainingSteps], a
.next
; determine if wild pokemon can appear in the half-block we're standing in
; is the bottom right tile (9,9) of the half-block we're standing in a grass/water tile?
	hlcoord 9, 9
	ld c, [hl]
	ld a, [wGrassTile]
	cp c
	ld a, [wGrassRate]
	jr z, .CanEncounter
	ld a, $14 ; in all tilesets with a water tile, this is its id
	cp c
	ld a, [wWaterRate]
	jr z, .CanEncounter
; even if not in grass/water, standing anywhere we can encounter pokemon
; so long as the map is "indoor" and has wild pokemon defined.
; ...as long as it's not Viridian Forest or Safari Zone.
	ldh a, [hCurMap]
	cp FIRST_INDOOR_MAP ; is this an indoor map?
	jp c, .CantEncounter2 ; jp not jr: facility's cp/jr additions push .CantEncounter2 out of jr range
	ld a, [wCurMapTileset]
	cp FOREST ; Viridian Forest/Safari Zone
	jp z, .CantEncounter2
	ld a, [wGrassRate]
.CanEncounter
; compare encounter chance with a random number to determine if there will be an encounter
	ld b, a
	ldh a, [hRandomAdd]
	cp b
	jr nc, .CantEncounter2
	ldh a, [hRandomSub]
	ld b, a
	ld hl, WildMonEncounterSlotChances
.determineEncounterSlot
	ld a, [hli]
	cp b
	jr nc, .gotEncounterSlot
	inc hl
	jr .determineEncounterSlot
.gotEncounterSlot
; determine which wild pokemon (grass or water) can appear in the half-block we're standing in
	ld c, [hl]
; Procedural areas: ignore the static wild table; roll a battlecount-scaled
; species + level from the rarity-class pool instead.
	call IsProcWildMap
	jr nc, .normalEncounterData
.procEncounter ; test seam (test_wild_budget), no code
; A calmed area (budget 0) rejects here, before the species roll. It used to
; roll first and reject at .willEncounter, ~17.7k cycles and ~5 Random draws
; spent on every step that passed the rate roll (measured 2026-11-22).
	ld a, [wProcCaveWildBudget]
	and a
	jr z, .CantEncounter2   ; already 0 - silent, no repeat message
	farcall PCRollWildEncounter ; battlecount-scaled species/level, no ownership check
	jr .afterEncounterData
.normalEncounterData
	ld hl, wGrassMons
	lda_coord 8, 9
	cp $14 ; is the bottom left tile (8,9) of the half-block we're standing in a water tile?
	jr nz, .gotWildEncounterType ; else, it's treated as a grass tile by default
	ld hl, wWaterMons
; since the bottom right tile of a "left shore" half-block is $14 but the bottom left tile is not,
; "left shore" half-blocks (such as the one in the east coast of Cinnabar) load grass encounters.
.gotWildEncounterType
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld [wCurEnemyLevel], a
	ld a, [hl]
	ld [wCurPartySpecies], a
	ld [wEnemyMonSpecies2], a
.afterEncounterData
IF FORCE_WILD_FORM_TEST
; ⚠ TEMPORARY - see FORCE_WILD_FORM_TEST in pokemon_data_constants.asm.
; The single chokepoint both wild paths converge on: PCRollWildEncounter for the
; procedural stages, the wGrassMons/wWaterMons tables for vanilla routes.
; Change the species and form on the two `ld a,` lines below to test any record.
	ld a, MEOWTH            ; <- species to force
	ld [wCurPartySpecies], a
	ld [wEnemyMonSpecies2], a ; BOTH are needed: LoadEnemyMonData reads the latter
	ld a, 1                 ; <- form index (ameowth.asm is form_record MEOWTH, 1)
	ld [wSpawnForm], a
ENDC
	ld a, [wRepelRemainingSteps]
	and a
	jr z, .willEncounter
	ld a, [wPartyMon1Level]
	ld b, a
	ld a, [wCurEnemyLevel]
	cp b
	jr c, .CantEncounter2 ; repel prevents encounters if the leading party mon's level is higher than the wild mon
	jr .willEncounter
.lastRepelStep
	ld [wRepelRemainingSteps], a
	ld a, TEXT_REPEL_WORE_OFF
	ldh [hTextID], a
	call EnableAutoTextBoxDrawing
	call DisplayTextID
.CantEncounter2
	ld a, $1
	and a
	ret
.willEncounter
; Procedural areas: spend one battle of the per-visit wild-battle budget. It is
; nonzero here: the zero case was rejected before the species roll, and nothing
; since has written it.
	call IsProcWildMap
	jr nc, .commitEncounter
	ld hl, wProcCaveWildBudget
	dec [hl]
	jr nz, .commitEncounter
; Last battle: the map script shows the calmed message after it returns.
; Cave, Forest and Facility share EVENT_PC_BUDGET_ENDED, safe because they
; never run concurrently and Pallet Town entry resets it before any stage reads
; it (see PFPreloadForest). The Cemetery has its own event.
	ldh a, [hCurMap]
	cp PROCEDURAL_CAVE_1
	jr c, .cemBudgetEnded   ; every Cemetery floor is below the $F1-$F3 block
	SetEvent EVENT_PC_BUDGET_ENDED
	jr .signalCalmed
.cemBudgetEnded
	SetEvent EVENT_PC_CEM_BUDGET_ENDED
.signalCalmed
	ld hl, wCurrentMapScriptFlags
	set BIT_CUR_MAP_LOADED_1, [hl]
.commitEncounter
	xor a
    ld [wIsTrainerBattle], a
	ret

; IsProcWildMap: carry set when hCurMap is a procedural wild area (Cave,
; Forest, Facility, Cemetery floors 1-4). Clobbers a only; bc, de, hl survive,
; and c (the encounter slot) is live in TryDoWildEncounter across the call.
; All four areas keep their wild-battle budget in one shared byte.
ASSERT wProcCemWildBudget == wProcCaveWildBudget
ASSERT wProcForestWildBudget == wProcCaveWildBudget
ASSERT wProcFacilityWildBudget == wProcCaveWildBudget
ASSERT PROCEDURAL_FOREST == PROCEDURAL_CAVE_1 + 1
ASSERT PROCEDURAL_FACILITY == PROCEDURAL_CAVE_1 + 2
ASSERT PROCEDURAL_CEMETERY_2 == PROCEDURAL_CEMETERY_1 + 1
ASSERT PROCEDURAL_CEMETERY_3 == PROCEDURAL_CEMETERY_1 + 2
ASSERT PROCEDURAL_CEMETERY_4 < PROCEDURAL_CAVE_1
IsProcWildMap:
	ldh a, [hCurMap]
	cp PROCEDURAL_CEMETERY_4
	jr z, .yes
	sub PROCEDURAL_CAVE_1
	cp PROCEDURAL_FACILITY - PROCEDURAL_CAVE_1 + 1
	ret c
	add PROCEDURAL_CAVE_1 - PROCEDURAL_CEMETERY_1
	cp PROCEDURAL_CEMETERY_3 - PROCEDURAL_CEMETERY_1 + 1
	ret
.yes
	scf
	ret

INCLUDE "data/wild/probabilities.asm"
