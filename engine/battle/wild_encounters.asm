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
	jr z, .lastRepelStep
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
	jr c, .CantEncounter2
	ld a, [wCurMapTileset]
	cp FOREST ; Viridian Forest/Safari Zone
	jr z, .CantEncounter2
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
; Procedural cave: ignore the static wild table; roll a battlecount-scaled
; species + level from the rarity-class pool instead.
	ldh a, [hCurMap]
	cp PROCEDURAL_CAVE_1
	jr z, .isProcedural
	cp PROCEDURAL_FOREST
	jr z, .isProcedural
	;cp PROCEDURAL_CEMETERY_1
	;jr z, .isProcedural
	;cp PROCEDURAL_CEMETERY_2
	;jr z, .isProcedural
	;cp PROCEDURAL_CEMETERY_3
	;jr z, .isProcedural
	;cp PROCEDURAL_CEMETERY_4
	jr nz, .normalEncounterData
.isProcedural
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
; Procedural areas: enforce per-visit wild-battle budget.
	ldh a, [hCurMap]
	cp PROCEDURAL_CAVE_1
	jr z, .checkCaveBudget
	cp PROCEDURAL_FOREST
	jr z, .checkForestBudget
	cp PROCEDURAL_CEMETERY_1
	jr z, .checkCemBudget
	cp PROCEDURAL_CEMETERY_2
	jr z, .checkCemBudget
	cp PROCEDURAL_CEMETERY_3
	jr z, .checkCemBudget
	cp PROCEDURAL_CEMETERY_4
	jr z, .checkCemBudget
	jr .commitEncounter
.checkCemBudget
	ld a, [wProcCemWildBudget]
	and a
	jr z, .CantEncounter2   ; already 0, silent
	dec a
	ld [wProcCemWildBudget], a
	jr nz, .commitEncounter
	SetEvent EVENT_PC_CEM_BUDGET_ENDED
	ld hl, wCurrentMapScriptFlags
	set BIT_CUR_MAP_LOADED_1, [hl]
	jr .commitEncounter
.checkCaveBudget
	ld a, [wProcCaveWildBudget]
	and a
	jr z, .CantEncounter2 ; already 0 - silent, no repeat message
	dec a
	ld [wProcCaveWildBudget], a
	jr nz, .commitEncounter
	SetEvent EVENT_PC_BUDGET_ENDED
	ld hl, wCurrentMapScriptFlags   ; signal map script to show calmed message
	set BIT_CUR_MAP_LOADED_1, [hl]  ; after this battle returns
	jr .commitEncounter
.checkForestBudget
	; Reuses EVENT_PC_BUDGET_ENDED (cave's event) — safe, see PFPreloadForest's
	; comment: cave/forest never run concurrently and this event is always
	; reset at Pallet Town entry before either stage could read it.
	ld a, [wProcForestWildBudget]
	and a
	jr z, .CantEncounter2
	dec a
	ld [wProcForestWildBudget], a
	jr nz, .commitEncounter
	SetEvent EVENT_PC_BUDGET_ENDED
	ld hl, wCurrentMapScriptFlags
	set BIT_CUR_MAP_LOADED_1, [hl]
.commitEncounter
	xor a
    ld [wIsTrainerBattle], a
	ret

INCLUDE "data/wild/probabilities.asm"
