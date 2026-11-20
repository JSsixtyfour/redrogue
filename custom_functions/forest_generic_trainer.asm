; The wild areas' generic route trainer (GENERIC_TRAINER_TRIAL_SPEC.md, built for
; the Forest; GENERIC_TRAINER_ALL_AREAS_SPEC.md, every wild area). One per area,
; on one floor chosen at random (A2), his class from the area's pool (A3). His
; own object slot, independent of the stage event; no toggle: picture 0 and
; parked when absent or on another floor.
;
; LIFECYCLE, each piece riding an existing hook (the generators' banks are full):
;   preload   ForestGenericRoll      OptionalForestAssignEncounter ($26), after
;                                    ForestDeepLobbyDecide: row, floor, cell pending
;   generate  ForestGenericPick      PFScanForBall, after the hideout ($3F), on
;                                    his floor's generation only
;   each load ForestGenericPatch     ForestDeepPatchSprites ($34), the picture
;             ForestGenericPlace     ForestDeepAfterFinalize ($34): cell,
;                                    facing, class
; State: sWildGenericRow, sWildGenericFloor, sWildGenericCell (ram/sram.asm),
; SRAM bank 0.
;
; Every entry is farcalled. INCLUDEd after the Forest generator, whose
; PF_* and wPF* constants it uses.
SECTION "Wild Generic Trainer", ROMX, BANK[$1A]

	ASSERT BANK(sWildGenericRow) == 0
	ASSERT BANK(sProcForestGenScratch) == 0
	ASSERT BANK(sProcForestBaked) == 0
	ASSERT FOREST_GENERIC == 9

DEF FGT_CELL_PENDING EQU $ff ; not picked yet (the roll's value)
DEF FGT_CELL_NONE    EQU $fe ; the pick found no cell

; Every class a generic trainer can be (A3), with its vanilla overworld sheet
; (the classes' own objects in vanilla) and its three lines (D4). Every class is
; a roster class: ReadTrainer finds no authored team and GetRandRoster rolls one.
; Camper and Picnicker are Gen 2 classes; Gen 1's are the Jr. Trainers.
	const_def
	const WGT_YOUNGSTER
	const WGT_BUG_CATCHER
	const WGT_LASS
	const WGT_HIKER
	const WGT_JR_TRAINER_M
	const WGT_JR_TRAINER_F
	const WGT_SUPER_NERD
	const WGT_POKEMANIAC
	const WGT_BLACKBELT
	const WGT_COOLTRAINER_M
	const WGT_CHANNELER
	const WGT_GENTLEMAN
	const WGT_SCIENTIST
	const WGT_ROCKET
	const WGT_BURGLAR
	const WGT_ENGINEER
	const WGT_JUGGLER
DEF NUM_WGT_CLASSES EQU const_value

MACRO wgt_class ; trainer class, overworld sprite, line label stem
	db \1, \2
	dw FGT\3Intro, FGT\3Defeat, FGT\3After
ENDM
DEF WGT_CLASS_SIZE EQU 8

WGTClasses:
	wgt_class OPP_YOUNGSTER,     SPRITE_YOUNGSTER,     Youngster
	wgt_class OPP_BUG_CATCHER,   SPRITE_YOUNGSTER,     BugCatcher
	wgt_class OPP_LASS,          SPRITE_COOLTRAINER_F, Lass
	wgt_class OPP_HIKER,         SPRITE_HIKER,         Hiker
	wgt_class OPP_JR_TRAINER_M,  SPRITE_COOLTRAINER_M, JrM
	wgt_class OPP_JR_TRAINER_F,  SPRITE_COOLTRAINER_F, JrF
	wgt_class OPP_SUPER_NERD,    SPRITE_SUPER_NERD,    SuperNerd
	wgt_class OPP_POKEMANIAC,    SPRITE_SUPER_NERD,    Pokemaniac
	wgt_class OPP_BLACKBELT,     SPRITE_HIKER,         Blackbelt
	wgt_class OPP_COOLTRAINER_M, SPRITE_COOLTRAINER_M, CooltrainerM
	wgt_class OPP_CHANNELER,     SPRITE_CHANNELER,     Channeler
	wgt_class OPP_GENTLEMAN,     SPRITE_GENTLEMAN,     Gentleman
	wgt_class OPP_SCIENTIST,     SPRITE_SCIENTIST,     Scientist
	wgt_class OPP_ROCKET,        SPRITE_ROCKET,        Rocket
	wgt_class OPP_BURGLAR,       SPRITE_SUPER_NERD,    Burglar
	wgt_class OPP_ENGINEER,      SPRITE_SUPER_NERD,    Engineer
	wgt_class OPP_JUGGLER,       SPRITE_ROCKER,        Juggler
	ASSERT @ - WGTClasses == NUM_WGT_CLASSES * WGT_CLASS_SIZE

; The pools (A3): a count, then WGTClasses indices. A pool's index + 1 is the
; row stored in sWildGenericRow.
WGTForestPool:
	db 6, WGT_YOUNGSTER, WGT_BUG_CATCHER, WGT_LASS, WGT_HIKER, WGT_JR_TRAINER_M, WGT_JR_TRAINER_F
WGTCavePool:
	db 6, WGT_HIKER, WGT_SUPER_NERD, WGT_POKEMANIAC, WGT_BLACKBELT, WGT_JR_TRAINER_F, WGT_COOLTRAINER_M
WGTCemeteryPool:
	db 2, WGT_CHANNELER, WGT_GENTLEMAN
WGTFacilityPool:
	db 6, WGT_SCIENTIST, WGT_ROCKET, WGT_BURGLAR, WGT_SUPER_NERD, WGT_ENGINEER, WGT_JUGGLER
DEF WGT_MAX_POOL EQU 6 ; rows are 4 bits

; One row per map that carries him: the map, his object slot, his area's pool.
; (Phase 3 adds the Cemetery's four floor maps and the Facility.)
WGTAreas:
WGTForestArea:
	db PROCEDURAL_FOREST, FOREST_GENERIC
	dw WGTForestPool
WGTCaveArea:
	db PROCEDURAL_CAVE_1, CAVE_GENERIC
	dw WGTCavePool
WGTFacilityArea:
	db PROCEDURAL_FACILITY, FACILITY_GENERIC
	dw WGTFacilityPool
WGTCemeteryArea:                         ; one row per floor map, the same pool
FOR n, 1, 5
	db PROCEDURAL_CEMETERY_{d:n}, CEMETERY_GENERIC
	dw WGTCemeteryPool
ENDR
	db -1

; sWildGenericFloor: bits 0-2 his floor ordinal; the cave keeps its cell's block
; Y in bits 3-7 (its 20x20 blocks do not fit the Forest's packed cell).
DEF WGT_FLOOR_MASK EQU %111

; ------------------------------------------------------------
; The roll: every Forest preload, from OptionalForestAssignEncounter, after
; ForestDeepLobbyDecide (which wrote this Forest's control word) and before the
; stage event's sprites are staged (a clash with the villain's sprite is
; resolved where the row is read, WGTRow). His floor is uniform over the
; Forest's floors (A2); the cell becomes pending.
; Clobbers everything; leaves SRAM open on bank 0, as that caller expects.
; ------------------------------------------------------------
ForestGenericRoll::
	; His defeat flag is run-scoped like the stage pair's: a new Forest finds him
	; unbeaten. Reset here, not in the preload ($3F has no room for it).
	xor a
	ld [wWildGenericBeaten], a
	ld hl, WGTForestArea
	call WGTRollRow
.store                                  ; tests force a here: row + 1, 0 = none
	ld b, a
	call FGTOpenSRAM
	call WGTForestDeep
	ld a, 0
	jr nc, .floor
	ld c, 2
	push bc
	call Rangerandom
	pop bc
.floor                                  ; tests force a here: 0 floor 1, 1 floor 2
	ld [sWildGenericFloor], a
	ld a, b
	ld [sWildGenericRow], a
	ld a, FGT_CELL_PENDING
	ld [sWildGenericCell], a
	ret

; hl -> an area row. Out: a = a pool index + 1, or 0 for none (at
; GENERIC_TRAINER_ODDS). Clobbers bc/de/hl.
WGTRollRow:
IF GENERIC_TRAINER_ODDS < 256
	call Random
	cp GENERIC_TRAINER_ODDS
	ld a, 0
	ret nc
ENDC
	call WGTPool
	ld c, [hl]
	call Rangerandom
	inc a
	ret

; hl -> an area row. Out: hl -> its pool. Clobbers a.
WGTPool:
	inc hl
	inc hl
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret

; Carry = this Forest is deep (its control word valid; FDReadCtrl's test).
; SRAM bank 0 open. Clobbers a/hl.
WGTForestDeep:
	ld hl, FOREST_DEEP_CTRL + 1
	ld a, [hld]
	cpl
	cp [hl]
	jr nz, .no
	and FOREST_DEEP_MAGIC_MASK
	cp FOREST_DEEP_MAGIC
	jr nz, .no
	scf
	ret
.no
	and a
	ret

; Carry = the floor being loaded or generated is his. A deep floor 2 is floor
; ordinal 1 (BIT_ROGUE_DEEP_FLOOR, set before that floor's load and generation).
; SRAM bank 0 open. Clobbers a/b.
WGTOnHisFloor:
	ld a, [wRogueFlagsBitfield2]
	ASSERT BIT_ROGUE_DEEP_FLOOR == 7
	rlca
	and 1
	ld b, a
	ld a, [sWildGenericFloor]
	and WGT_FLOOR_MASK                  ; the cave keeps its cell's Y above
	cp b
	scf
	ret z
	and a
	ret

; ------------------------------------------------------------
; The cell: PFScanForBall, once the balls and the hideout are chosen and while
; the dead-end candidate list is intact (sProcForestGenScratch[0..count-1],
; packed col | row << 4; the boss cell, the entrance and clearings are already
; left out of it). Only when pending and on his floor's generation, so the other
; floor's generation never moves him. No Random: the start is the balls'
; coordinate sum, so adding him moves no other roll. Rejected: a ball's cell,
; and any cell within one of the hideout's (its own and the eight around it).
; Facing: the dead end's one opening in the maze as generated
; (wOverworldMap + PF_BASE), so his one-tile sight covers the way in.
; SRAM bank 0 open (kept open). Clobbers everything.
; ------------------------------------------------------------
ForestGenericPick::
	ld a, [sWildGenericCell]
	cp FGT_CELL_PENDING
	ret nz
	call WGTOnHisFloor
	ret nc
	ld a, [wBuffer + wPFCandCount]
	and a
	jr z, .none
	ld e, a                             ; e = candidates
	ld hl, wBuffer + wPFAcceptedXY
	ld b, 8
	xor a
.sum
	add [hl]
	inc hl
	dec b
	jr nz, .sum
.mod
	cp e
	jr c, .start
	sub e
	jr .mod
.start
	ld c, a                             ; c = the candidate index
	ld d, e                             ; d = tries left
.try
	ld b, 0
	ld hl, sProcForestGenScratch
	add hl, bc
	ld a, [hl]
	call FGTCellBlock                   ; -> wPFCurX/Y
	call FGTCellOk
	jr c, .found
	inc c
	ld a, c
	cp e
	jr c, .noWrap
	ld c, 0
.noWrap
	dec d
	jr nz, .try
.none
	ld a, FGT_CELL_NONE
	ld [sWildGenericCell], a
	ret
.found
	ld a, [hl]
	ld [sWildGenericCell], a
	call FGTFacing                      ; a = 0 down, 1 up, 2 left, 3 right
	swap a
	ld b, a
	ld a, [sWildGenericRow]
	and $0f
	or b
	ld [sWildGenericRow], a
	ret

; a = a packed cell. Out: wBuffer + wPFCurX/Y = its block. Keeps bc/de/hl.
FGTCellBlock:
	push af
	and $0f
	add a
	inc a
	ld [wBuffer + wPFCurX], a           ; block X = 2 * col + 1
	pop af
	swap a
	and $0f
	add a
	inc a
	ld [wBuffer + wPFCurY], a
	ret

; Carry = wPFCurX/Y may hold him: not a ball's block, and more than one cell
; (two blocks) from the hideout's. On a deep floor 2 only balls 1-2 can stand
; there and there is no stage pair (ForestDeepPatchSprites parks the rest), so
; only those balls count and the hideout does not: measured 2026-11-20 (CGB),
; floor 2 had 5 dead ends, 4 under balls and 1 near floor 1's hideout. Keeps bc/de/hl.
FGTCellOk:
	push hl
	push bc
	ld hl, wBuffer + wPFAcceptedXY
	ld b, 4
	ld a, [wRogueFlagsBitfield2]
	bit BIT_ROGUE_DEEP_FLOOR, a
	jr z, .ball
	ld b, 2
.ball
	ld a, [wBuffer + wPFCurX]
	cp [hl]
	inc hl
	jr nz, .nextBall
	ld a, [wBuffer + wPFCurY]
	cp [hl]
	jr z, .no
.nextBall
	inc hl
	dec b
	jr nz, .ball
	ld a, [wRogueFlagsBitfield2]
	bit BIT_ROGUE_DEEP_FLOOR, a
	jr nz, .yes                         ; floor 2: no stage pair
	ld a, [sStageEventHideoutX]
	cp STAGE_EVENT_NO_HIDEOUT
	jr z, .yes
	ld b, a
	ld a, [wBuffer + wPFCurX]
	sub b
	add 2                               ; -2..2 -> 0..4
	cp 5
	jr nc, .yes
	ld a, [sStageEventHideoutY]
	ld b, a
	ld a, [wBuffer + wPFCurY]
	sub b
	add 2
	cp 5
	jr c, .no
.yes
	pop bc
	pop hl
	scf
	ret
.no
	pop bc
	pop hl
	and a
	ret

; The dead end at wPFCurX/Y: which neighbouring wall block is open (not
; PF_TREE), in the maze being generated. Out: a = 0 down, 1 up, 2 left, 3 right
; (down when none reads open, which a dead end cannot be). Clobbers bc/de/hl.
FGTFacing:
	ld a, [wBuffer + wPFCurY]
	ld l, a
	ld h, 0
	ld bc, PF_STRIDE
	call FGTMultiply                    ; hl = Y * PF_STRIDE
	ld a, [wBuffer + wPFCurX]
	ld c, a
	ld b, 0
	add hl, bc
	ld bc, wOverworldMap + PF_BASE
	add hl, bc                          ; hl -> the dead end's block
	ld de, PF_STRIDE
	push hl
	add hl, de
	ld a, [hl]                          ; south
	pop hl
	cp PF_TREE
	ld a, 0
	ret nz
	push hl
	ld a, l
	sub e
	ld l, a
	jr nc, .north
	dec h
.north
	ld a, [hl]
	pop hl
	cp PF_TREE
	ld a, 1
	ret nz
	dec hl
	ld a, [hl]                          ; west
	inc hl
	cp PF_TREE
	ld a, 2
	ret nz
	inc hl
	ld a, [hl]                          ; east
	cp PF_TREE
	ld a, 3
	ret nz
	xor a
	ret

; hl = l * bc (l small). Clobbers a/de.
FGTMultiply:
	ld a, l
	ld hl, 0
	and a
	ret z
.loop
	add hl, bc
	dec a
	jr nz, .loop
	ret

; ------------------------------------------------------------
; The picture: ForestDeepPatchSprites, every Forest load before InitMapSprites.
; His sprite on his floor when he was rolled and has (or, on that floor's first
; entry before generation, may yet get) a cell; else 0. Clobbers everything.
; ------------------------------------------------------------
ForestGenericPatch::
	call FGTOpenSRAM
	ld b, 0
	call WGTOnHisFloor
	ld b, 0                             ; WGTOnHisFloor used b; keeps the carry
	jr nc, .close
	ld hl, WGTForestArea
	call WGTRow
	ld b, 0                             ; WGTRow used b; keeps the carry
	jr nc, .close
	ld a, [sWildGenericCell]
	cp FGT_CELL_NONE
	jr z, .close
	inc hl
	ld b, [hl]                          ; his sprite
.close
	call FGTCloseSRAM
	ld a, b
	ld [wSprite{02d:FOREST_GENERIC}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ret

; ------------------------------------------------------------
; The cell, facing and class: ForestDeepAfterFinalize, every Forest load after
; PFinalizeForest (which ran the pick on his floor's first entry). Another
; floor, no trainer or no cell: picture 0, parked off the map. A battle's
; return keeps his position and facing (the engine kept them).
; Clobbers everything; SRAM closed.
; ------------------------------------------------------------
ForestGenericPlace::
	call FGTOpenSRAM
	call WGTOnHisFloor
	jr nc, .closePark
	ld hl, WGTForestArea
	call WGTRow                         ; carry, hl -> his class record
	jr nc, .closePark
	ld a, [sWildGenericCell]
	cp FGT_CELL_NONE
	jr nc, .closePark                   ; none, or never picked
	ld b, a                             ; b = his cell
	ld c, [hl]                          ; c = his class
	ld a, [sWildGenericRow]
	swap a
	and 3
	ld d, a                             ; d = his facing
	call FGTCloseSRAM
	ld hl, wMapSpriteExtraData + (FOREST_GENERIC - 1) * 2
	ld a, c
	ld [hli], a
	ld [hl], 1                          ; the roster ignores the team number
	ld a, [wStatusFlags4]
	bit BIT_BATTLE_OVER_OR_BLACKOUT, a
	ret nz
	ld a, b
	and $0f
	add a
	inc a                               ; block X
	add a
	add 4                               ; block * 2 + 4, as the balls and the pair
	ld [wSprite{02d:FOREST_GENERIC}StateData2MapX], a
	ld a, b
	swap a
	and $0f
	add a
	inc a
	add a
	add 4
	ld [wSprite{02d:FOREST_GENERIC}StateData2MapY], a
	ld a, d
	add a
	ld c, a
	ld b, 0
	ld hl, .facings
	add hl, bc
	ld a, [hli]
	ld [wSprite{02d:FOREST_GENERIC}StateData1FacingDirection], a
	; Movement byte 2 too: UpdateNPCSprite re-reads it from wMapSpriteData
	; every tick, so the facing byte alone snaps back (as the Cemetery pair).
	ld a, [hl]
	ld [wMapSpriteData + (FOREST_GENERIC - 1) * 2], a
	ret
.closePark
	call FGTCloseSRAM
	xor a
	ld [wSprite{02d:FOREST_GENERIC}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld [wSprite{02d:FOREST_GENERIC}StateData2MapY], a
	ld [wSprite{02d:FOREST_GENERIC}StateData2MapX], a
	ret

.facings
	db SPRITE_FACING_DOWN,  DOWN
	db SPRITE_FACING_UP,    UP
	db SPRITE_FACING_LEFT,  LEFT
	db SPRITE_FACING_RIGHT, RIGHT

; hl -> an area row. Out: carry = a trainer this area; hl -> his WGTClasses
; record. A pool entry whose sprite is the stage event's (slot 6 or 7) moves to
; the next, so he never wears the villain's picture (the Psychic is
; SPRITE_YOUNGSTER). SRAM bank 0 open. Clobbers a/bc/de/hl.
WGTRow:
	call WGTPool
	ld d, h
	ld e, l                             ; de -> the pool
	ld a, [sWildGenericRow]
	and $0f
	jr z, .none
	dec a
	cp [hl]
	jr nc, .none
	ld b, a                             ; b = the pool index
	ld c, [hl]                          ; c = tries left
.try
	ld h, d
	ld l, e
	ld a, b
	inc a
	add l
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	ld l, [hl]                          ; the class index
	ld h, 0
	add hl, hl
	add hl, hl
	add hl, hl
	ASSERT WGT_CLASS_SIZE == 8
	push bc
	ld bc, WGTClasses
	add hl, bc
	pop bc
	inc hl                              ; -> its sprite
	ld a, [sStageEventSprite6]
	cp [hl]
	jr z, .clash
	ld a, [sStageEventSprite7]
	cp [hl]
	jr z, .clash
	dec hl
	scf
	ret
.clash
	inc b
	ld a, [de]
	cp b
	jr nz, .next
	ld b, 0
.next
	dec c
	jr nz, .try
.none
	and a
	ret

FGTOpenSRAM:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a
	ret

FGTCloseSRAM:
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; ============================================================
; The cave (GENERIC_TRAINER_ALL_AREAS_SPEC.md, Phase 2). Object CAVE_GENERIC.
;   preload   CaveGenericRoll        OptionalCaveAssignEncounter ($26)
;   each load CaveGenericPatch       CaveDeepPatchSprites ($15), the picture
;             CaveGenericPlace       CaveDeepAfterFinalize ($26), after the deep
;                                    decision: the cell on his floor's first load,
;                                    then cell, facing and class
; The cave decides deep or not at its FIRST LOAD, after the preload, so his floor
; is rolled at the preload and counts only on a deep cave (else floor 1): the
; first load's picture is patched before that decision and the placement after
; it, which parks him if the decision moved him off this floor.
; ============================================================

; The preload, before the cave's optional encounter. Leaves SRAM open on bank 0,
; as the caller expects. Clobbers everything.
CaveGenericRoll::
	; Floor 2's first generation re-runs the cave's preload: the same cave, so
	; his roll and flag stay. Measured 2026-11-20: the floor bit is set at that
	; call and clear at a real preload (without this, floor 2 re-rolled him).
	ld a, [wRogueFlagsBitfield2]
	bit BIT_ROGUE_DEEP_FLOOR, a
	jp nz, FGTOpenSRAM
	xor a
	ld [wWildGenericBeaten], a          ; a new cave finds him unbeaten
	ld hl, WGTCaveArea
	call WGTRollRow
.store                                  ; tests force a here: row + 1, 0 = none
	ld b, a
	ld c, 2
	push bc
	call Rangerandom
	pop bc
.floor                                  ; tests force a here: 0 floor 1, 1 floor 2
	ld c, a
	call FGTOpenSRAM
	ld a, c
	ld [sWildGenericFloor], a
	ld a, b
	ld [sWildGenericRow], a
	ld a, FGT_CELL_PENDING
	ld [sWildGenericCell], a
	ret

; Carry = this cave is deep (CaveDeepPostCtrl's test of CAVE_DEEP_CTRL). SRAM
; open; leaves it on bank 0. Clobbers a/b.
WGTCaveDeep:
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld a, [CAVE_DEEP_CTRL + 1]
	cpl
	ld b, a
	ld a, [CAVE_DEEP_CTRL]
	cp b
	jr nz, .no
	and CAVE_DEEP_MAGIC_MASK
	cp CAVE_DEEP_MAGIC
	jr nz, .no
	xor a
	ld [rRAMB], a
	scf
	ret
.no
	xor a                               ; carry clear
	ld [rRAMB], a
	ret

; Carry = the cave floor being loaded is his: his rolled floor on a deep cave,
; floor 1 otherwise. SRAM bank 0 open. Clobbers a/bc.
WGTCaveOnHisFloor:
	call WGTCaveDeep
	ld c, 0
	jr nc, .haveFloor
	ld a, [sWildGenericFloor]
	and WGT_FLOOR_MASK
	ld c, a
.haveFloor
	ld a, [wRogueFlagsBitfield2]
	ASSERT BIT_ROGUE_DEEP_FLOOR == 7
	rlca
	and 1
	cp c
	scf
	ret z
	and a
	ret

; The picture: CaveDeepPatchSprites, every cave load before InitMapSprites. His
; sprite on his floor when he was rolled and has (or may yet get) a cell; else 0.
; Clobbers everything.
CaveGenericPatch::
	call FGTOpenSRAM
	call WGTCaveOnHisFloor
	ld b, 0
	jr nc, .close
	ld hl, WGTCaveArea
	call WGTRow
	ld b, 0                             ; WGTRow used b; keeps the carry
	jr nc, .close
	ld a, [sWildGenericCell]
	cp FGT_CELL_NONE
	jr z, .close
	inc hl
	ld b, [hl]                          ; his sprite
.close
	call FGTCloseSRAM
	ld a, b
	ld [wSprite{02d:CAVE_GENERIC}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ret

; The cell, facing and class: CaveDeepAfterFinalize, every cave load after
; PCFinalizeCave and the deep decision. Another floor, no trainer or no cell:
; picture 0, parked off the map. A battle's return keeps his position and facing.
; Clobbers everything; SRAM closed.
CaveGenericPlace::
	call FGTOpenSRAM
	call WGTCaveOnHisFloor
	jr nc, .closePark
	ld hl, WGTCaveArea
	call WGTRow                         ; carry, hl -> his class record
	jr nc, .closePark
	push hl
	ld a, [sWildGenericCell]
	cp FGT_CELL_PENDING
	jr nz, .picked
	farcall WGTCavePick                 ; his floor's first load: from this floor
.picked
	pop hl
	ld a, [sWildGenericCell]
	cp FGT_CELL_NONE
	jr nc, .closePark                   ; none
	ld b, a                             ; b = X | quadrant << 5
	ld a, [sWildGenericFloor]
	rrca
	rrca
	rrca
	and $1f
	ld e, a                             ; e = block Y
	ld c, [hl]                          ; c = his class
	ld a, [sWildGenericRow]
	swap a
	and 3
	ld d, a                             ; d = his facing
	call FGTCloseSRAM
	ld hl, wMapSpriteExtraData + (CAVE_GENERIC - 1) * 2
	ld a, c
	ld [hli], a
	ld [hl], 1                          ; the roster ignores the team number
	ld a, [wStatusFlags4]
	bit BIT_BATTLE_OVER_OR_BLACKOUT, a
	ret nz
	ld a, b
	swap a
	rrca
	and 3
	ld c, a                             ; c = the quadrant: bit 0 right, bit 1 bottom
	ld a, e
	add a
	add 4                               ; block * 2 + 4, as the balls and the pair
	bit 1, c
	jr z, .top
	inc a
.top
	ld [wSprite{02d:CAVE_GENERIC}StateData2MapY], a
	ld a, b
	and $1f
	add a
	add 4
	bit 0, c
	jr z, .left
	inc a
.left
	ld [wSprite{02d:CAVE_GENERIC}StateData2MapX], a
	ld a, d
	add a
	ld c, a
	ld b, 0
	ld hl, ForestGenericPlace.facings
	add hl, bc
	ld a, [hli]
	ld [wSprite{02d:CAVE_GENERIC}StateData1FacingDirection], a
	ld a, [hl]                          ; movement byte 2 too (UpdateNPCSprite re-reads it)
	ld [wMapSpriteData + (CAVE_GENERIC - 1) * 2], a
	ret
.closePark
	call FGTCloseSRAM
	xor a
	ld [wSprite{02d:CAVE_GENERIC}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld [wSprite{02d:CAVE_GENERIC}StateData2MapY], a
	ld [wSprite{02d:CAVE_GENERIC}StateData2MapX], a
	ret

; ============================================================
; The Facility (GENERIC_TRAINER_ALL_AREAS_SPEC.md, Phase 3). Object
; FACILITY_GENERIC (14).
;   preload   FacilityGenericRoll    PFacPreload ($2F), after FacilityDeepLobbyDecide
;   generate  PFacGenericPick        PFacFinalize ($2F), his floor's generation
;   each load FacilityGenericPatch   FacilityDeepPatchSprites ($15), the picture
;             FacilityGenericPlace   FacilityDeepAfterFinalize ($15): cell, class
; The Facility decides deep or not at its preload, so the roll reads it directly
; (as the Forest's) and WGTOnHisFloor serves. Cell as the cave's: X in
; sWildGenericCell, Y in sWildGenericFloor's bits 3-7, the top-left step.
; ============================================================

; The preload, after the deep decision. Leaves SRAM closed, as the caller.
; Clobbers everything.
FacilityGenericRoll::
	; The same Facility's floor 2 generation must keep him (measured on the cave,
	; which re-runs its preload there; cheap to rule out here too).
	ld a, [wRogueFlagsBitfield2]
	bit BIT_ROGUE_DEEP_FLOOR, a
	ret nz
	xor a
	ld [wWildGenericBeaten], a          ; a new Facility finds him unbeaten
	ld hl, WGTFacilityArea
	call WGTRollRow
.store                                  ; tests force a here: row + 1, 0 = none
	ld b, a
	call FGTOpenSRAM
	ld hl, FACILITY_DEEP_CTRL + 1       ; FDFReadCtrl's test: carry = deep
	ld a, [hld]
	cpl
	cp [hl]
	jr nz, .one
	and DEEP_MAGIC_MASK
	cp FACILITY_DEEP_MAGIC
	jr nz, .one
	ld c, 2
	push bc
	call Rangerandom
	pop bc
	jr .floor
.one
	xor a
.floor                                  ; tests force a here: 0 floor 1, 1 floor 2
	ld [sWildGenericFloor], a
	ld a, b
	ld [sWildGenericRow], a
	ld a, FGT_CELL_PENDING
	ld [sWildGenericCell], a
	jp FGTCloseSRAM

; The picture: FacilityDeepPatchSprites, every Facility load before
; InitMapSprites. Clobbers everything.
FacilityGenericPatch::
	call FGTOpenSRAM
	call WGTOnHisFloor
	ld b, 0
	jr nc, .close
	ld hl, WGTFacilityArea
	call WGTRow
	ld b, 0                             ; WGTRow used b; keeps the carry
	jr nc, .close
	ld a, [sWildGenericCell]
	cp FGT_CELL_NONE
	jr z, .close
	inc hl
	ld b, [hl]                          ; his sprite
.close
	call FGTCloseSRAM
	ld a, b
	ld [wSprite{02d:FACILITY_GENERIC}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ret

; The cell and class: FacilityDeepAfterFinalize, every Facility load after
; PFacFinalize (which picked his cell on his floor's first generation). Another
; floor, no trainer or no cell: picture 0, parked. A battle's return keeps his
; position. Clobbers everything; SRAM closed.
FacilityGenericPlace::
	call FGTOpenSRAM
	call WGTOnHisFloor
	jr nc, .closePark
	ld hl, WGTFacilityArea
	call WGTRow
	jr nc, .closePark
	ld a, [sWildGenericCell]
	cp FGT_CELL_NONE
	jr nc, .closePark                   ; none, or never picked
	ld b, a                             ; b = block X
	ld a, [sWildGenericFloor]
	rrca
	rrca
	rrca
	and $1f
	ld e, a                             ; e = block Y
	ld c, [hl]                          ; c = his class
	call FGTCloseSRAM
	ld hl, wMapSpriteExtraData + (FACILITY_GENERIC - 1) * 2
	ld a, c
	ld [hli], a
	ld [hl], 1                          ; the roster ignores the team number
	ld a, [wStatusFlags4]
	bit BIT_BATTLE_OVER_OR_BLACKOUT, a
	ret nz
	ld a, e
	add a
	add 4                               ; block * 2 + 4, as the balls and the pair
	ld [wSprite{02d:FACILITY_GENERIC}StateData2MapY], a
	ld a, b
	and $1f
	add a
	add 4
	ld [wSprite{02d:FACILITY_GENERIC}StateData2MapX], a
	ld a, SPRITE_FACING_DOWN
	ld [wSprite{02d:FACILITY_GENERIC}StateData1FacingDirection], a
	ld a, DOWN
	ld [wMapSpriteData + (FACILITY_GENERIC - 1) * 2], a
	ret
.closePark
	call FGTCloseSRAM
	xor a
	ld [wSprite{02d:FACILITY_GENERIC}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld [wSprite{02d:FACILITY_GENERIC}StateData2MapY], a
	ld [wSprite{02d:FACILITY_GENERIC}StateData2MapX], a
	ret

; ============================================================
; The Cemetery (GENERIC_TRAINER_ALL_AREAS_SPEC.md, Phase 3). Object
; CEMETERY_GENERIC (6) on all four floor maps. The resurrection NPC's pattern:
;   preload   CemGenericRoll    CemDeepGenerateMaps ($28), after the deep decision
;                               and the resurrector's roll; d = deep or not
;   each load CemGenericPatch   CemDeepPatchSprite ($28), the picture
;             CemGenericPlace   CemDeepFinalizeMap ($28), after the resurrector
; Both loads pass d = the map index, e = the floor ordinal (CDOrdinal: 0-5 over
; 1, 2, 3, 2b, 3b, 4; an ordinary Cemetery's maps read 0, 1, 2, 5). His floor is
; an ordinal, uniform over the Cemetery's floors (CemResurrectorRoll's rule). His
; cell is not saved: the floors' blocks are, so every load's scan finds it again.
; ============================================================

; In: d = nonzero on a deep Cemetery. Clobbers everything; SRAM closed.
CemGenericRoll::
	xor a
	ld [wWildGenericBeaten], a          ; a new Cemetery finds him unbeaten
	push de
	ld hl, WGTCemeteryArea
	call WGTRollRow
	pop de
.store                                  ; tests force a here: row + 1, 0 = none
	ld b, a
	ld a, d
	and a
	ld c, CEM_DEEP_NUM_ORDINALS
	jr nz, .roll
	ld c, 4                             ; ordinary: ordinals 0, 1, 2, 5
.roll
	push bc
	call Rangerandom
	pop bc
	ld d, a
	ld a, c
	cp 4
	ld a, d
	jr nz, .floor
	cp 3
	jr nz, .floor
	ld a, 5                             ; map 4 is ordinal 5
.floor                                  ; tests force a here: the ordinal
	ld c, a
	call FGTOpenSRAM
	ld a, c
	ld [sWildGenericFloor], a
	ld a, b
	ld [sWildGenericRow], a
	ld a, FGT_CELL_PENDING
	ld [sWildGenericCell], a
	jp FGTCloseSRAM

; e = this floor's ordinal. Carry = his floor. SRAM bank 0 open. Clobbers a.
WGTCemOnHisFloor:
	ld a, [sWildGenericFloor]
	and WGT_FLOOR_MASK
	cp e
	scf
	ret z
	and a
	ret

; The picture, before InitMapSprites. In: d/e from CDOrdinal. Clobbers everything.
CemGenericPatch::
	call FGTOpenSRAM
	call WGTCemOnHisFloor
	ld b, 0
	jr nc, .close
	ld hl, WGTCemeteryArea
	call WGTRow
	ld b, 0                             ; WGTRow used b; keeps the carry
	jr nc, .close
	inc hl
	ld b, [hl]                          ; his sprite
.close
	call FGTCloseSRAM
	ld a, b
	ld [wSprite{02d:CEMETERY_GENERIC}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ret

; The cell and class, after PCemFinalizeMap and the resurrector's placement. In:
; d/e from CDOrdinal. On his floor, the first cell from CEM_GEN_SCAN_START that
; the hideout rule accepts (PCemStageHideoutCellOk: a floor block, not the ball's,
; not a stair, not floor 4's boss steps, never sealing a gap), that the
; resurrector's crowd test passes (CRCrowded: not within one block of the
; Channeler, the hideout or floor 1's arrival) and that is not within one block
; of the resurrector himself. Elsewhere, or with no cell, parked.
; Clobbers everything; SRAM closed.
CemGenericPlace::
	call FGTOpenSRAM
	call WGTCemOnHisFloor
	jp nc, .closePark
	push de
	ld hl, WGTCemeteryArea
	call WGTRow
	pop de
	jp nc, .closePark
	ld a, [hl]
	ld [wMapSpriteExtraData + (CEMETERY_GENERIC - 1) * 2], a
	ld a, 1                             ; the roster ignores the team number
	ld [wMapSpriteExtraData + (CEMETERY_GENERIC - 1) * 2 + 1], a
	ld a, [wStatusFlags4]
	bit BIT_BATTLE_OVER_OR_BLACKOUT, a
	jp nz, FGTCloseSRAM                 ; a battle's return keeps his position
	ld a, d
	ld [wBuffer + wCemMapIndex], a
	ld c, CEM_GEN_SCAN_START
	ld b, CEMAP_SIZE
.scan
	ld a, c
	ld d, 0
.div
	cp CEMAP_WIDTH
	jr c, .divDone
	sub CEMAP_WIDTH
	inc d
	jr .div
.divDone
	ld [wBuffer + wCemTryX], a
	ld a, d
	ld [wBuffer + wCemTryY], a
	push bc
	farcall PCemStageHideoutCellOk      ; Z = usable; Bankswitch's return keeps flags
	jr nz, .rejected
	farcall CRCrowded                   ; carry = crowded
	jr c, .rejected
	call WGTCemNearResurrector
	jr nc, .found
.rejected
	pop bc
	inc c
	ld a, c
	cp CEMAP_SIZE
	jr c, .noWrap
	ld c, 0
.noWrap
	dec b
	jr nz, .scan
.closePark
	call FGTCloseSRAM
	xor a
	ld [wSprite{02d:CEMETERY_GENERIC}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld [wSprite{02d:CEMETERY_GENERIC}StateData2MapY], a
	ld [wSprite{02d:CEMETERY_GENERIC}StateData2MapX], a
	ret
.found
	pop bc
	call FGTCloseSRAM
	ld a, [wBuffer + wCemTryY]
	add a
	add 4                               ; block * 2 + 4, as the ball and the pair
	ld [wSprite{02d:CEMETERY_GENERIC}StateData2MapY], a
	ld a, [wBuffer + wCemTryX]
	add a
	add 4
	ld [wSprite{02d:CEMETERY_GENERIC}StateData2MapX], a
	ld a, SPRITE_FACING_DOWN
	ld [wSprite{02d:CEMETERY_GENERIC}StateData1FacingDirection], a
	ld a, DOWN
	ld [wMapSpriteData + (CEMETERY_GENERIC - 1) * 2], a
	ret

; Carry = wCemTryX/Y is within one block of the resurrector, when he stands on
; this floor (a picture). Clobbers a/hl.
WGTCemNearResurrector:
	ld a, [wSprite{02d:CEMETERY_RESURRECTOR}StateData1 + SPRITESTATEDATA1_PICTUREID]
	and a
	ret z                               ; carry clear
	ld a, [wSprite{02d:CEMETERY_RESURRECTOR}StateData2MapX]
	sub 4
	srl a
	ld hl, wBuffer + wCemTryX
	sub [hl]
	inc a                               ; -1..1 -> 0..2
	cp 3
	ret nc
	ld a, [wSprite{02d:CEMETERY_RESURRECTOR}StateData2MapY]
	sub 4
	srl a
	ld hl, wBuffer + wCemTryY
	sub [hl]
	inc a
	cp 3
	ret                                 ; carry = within one block

; ------------------------------------------------------------
; His lines (D4): each class speaks the trio of a vanilla trainer of that class
; whom Red Rogue cut, or who stood on a map Red Rogue does not have
; (GENERIC_TRAINER_TRIAL_SPEC.md, "D4 candidates, corrected";
; GENERIC_TRAINER_ALL_AREAS_SPEC.md, "D4 candidates for the new classes"). The
; header's three texts are text_far stubs to these entries; each is a return-hl
; text_asm (bc is the live text cursor, kept), so the stream - the end-battle
; "<CLASS>: " prefix included - stays as it is. The class comes from the
; object he battles as (wMapSpriteExtraData, written at placement after WGTRow's
; clash shift), so his lines follow the class.
; ------------------------------------------------------------
ForestGenericIntroText::
	text_asm
	xor a
	jr FGTLine

ForestGenericDefeatText::
	text_asm
	ld a, 1
	jr FGTLine

ForestGenericAfterText::
	text_asm
	ld a, 2
	; fall through

; a = 0 intro, 1 defeat, 2 after. Out: hl = the line. Keeps bc.
FGTLine:
	push bc
	ld e, a
	; His slot: this map's area row; the Forest's when the map carries none.
	ldh a, [hCurMap]
	ld b, a
	ld hl, WGTAreas
.area
	ld a, [hli]
	cp -1
	ld a, FOREST_GENERIC
	jr z, .haveSlot
	dec hl
	ld a, [hli]
	cp b
	ld a, [hli]                         ; this row's slot
	inc hl
	inc hl
	jr nz, .area
.haveSlot
	dec a
	add a
	ld c, a
	ld b, 0
	ld hl, wMapSpriteExtraData
	add hl, bc
	ld a, [hl]                          ; his class
	ld hl, WGTClasses
	ld b, NUM_WGT_CLASSES
	ld c, WGT_CLASS_SIZE
.find
	cp [hl]
	jr z, .found
	push af
	ld a, l
	add c
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	pop af
	dec b
	jr nz, .find
	ld hl, WGTClasses                   ; unknown class: the first class's lines
.found
	inc hl
	inc hl                              ; -> intro, defeat, after
	ld a, e
	add a
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
.done                                     ; hl = the line (tests hook here)
	pop bc
	ret

; Every class's lines live in "Wild Generic Trainer Lines" ($2B, room): these
; stubs reach them (a nested text_far maps that bank and returns here).
MACRO wgt_far_lines ; label stem
FGT\1Intro:
	text_far _FGT\1Intro
	text_end
FGT\1Defeat:
	text_far _FGT\1Defeat
	text_end
FGT\1After:
	text_far _FGT\1After
	text_end
ENDM
	wgt_far_lines Youngster
	wgt_far_lines BugCatcher
	wgt_far_lines Lass
	wgt_far_lines Hiker
	wgt_far_lines JrM
	wgt_far_lines JrF
	wgt_far_lines SuperNerd
	wgt_far_lines Pokemaniac
	wgt_far_lines Blackbelt
	wgt_far_lines CooltrainerM
	wgt_far_lines Channeler
	wgt_far_lines Gentleman
	wgt_far_lines Scientist
	wgt_far_lines Rocket
	wgt_far_lines Burglar
	wgt_far_lines Engineer
	wgt_far_lines Juggler


; Vanilla Red's text, verbatim (tmp/shinpokered-reference/text/maps/), picked in
; GENERIC_TRAINER_ALL_AREAS_SPEC.md from trainers on maps Red Rogue does not
; have. Extracted by script, not retyped.
SECTION "Wild Generic Trainer Lines", ROMX, BANK[$2B] ; 1,056 B; $2B had 1,992 free (2026-11-20)

; The Forest's six (2026-11-19, D4), moved from $1A 2026-11-20 for room.
_FGTYoungsterIntro:: ; Route 25 Youngster 7
	text "I knew I had to"
	line "fight you!"
	done
_FGTYoungsterDefeat::
	text "I knew"
	line "I'd lose too!"
	prompt
_FGTYoungsterAfter::
	text "If your #MON"
	line "gets confused or"
	cont "falls asleep,"
	cont "switch it!"
	done

_FGTBugCatcherIntro:: ; Route 6 Bug Catcher 11
	text "I've never seen"
	line "you around!"
	cont "Are you good?"
	done
_FGTBugCatcherDefeat::
	text "You"
	line "are too good!"
	prompt
_FGTBugCatcherAfter::
	text "Are my #MON"
	line "weak? Or, am I"
	cont "just bad?"
	done

_FGTLassIntro:: ; Route 3 Lass 2
	text "That look you"
	line "gave me, it's so"
	cont "intriguing!"
	done
_FGTLassDefeat::
	text "Be nice!"
	prompt
_FGTLassAfter::
	text "Avoid fights by"
	line "not letting"
	cont "people see you!"
	done

_FGTHikerIntro:: ; Route 9 Hiker 6
	text "Hahaha!"
	line "Aren't you a"
	cont "little toughie!"
	done
_FGTHikerDefeat::
	text "What's"
	line "that?"
	prompt
_FGTHikerAfter::
	text "Hahaha! Kids"
	line "should be tough!"
	done

_FGTJrMIntro:: ; Route 6 Jr. Trainer M 5
	text "Huh? You want"
	line "to talk to me?"
	done
_FGTJrMDefeat::
	text "I"
	line "didn't start it!"
	prompt
_FGTJrMAfter::
	text "I should carry"
	line "more #MON with"
	cont "me for safety."
	done

_FGTJrFIntro:: ; Route 13 Jr. Trainer F 11
	text "I'm told I'm good"
	line "for a kid!"
	done
_FGTJrFDefeat::
	text "Ohh!"
	line "I lost!"
	prompt
_FGTJrFAfter::
	text "I want to become"
	line "a good trainer."
	cont "I'll train hard."
	done


; route8 trainer 2, _Route8BattleText3
_FGTSuperNerdIntro::
	text "You need strategy"
	line "to win at this!"
	done
; route8 trainer 2, _Route8EndBattleText3
_FGTSuperNerdDefeat::
	text "It's"
	line "not logical!"
	prompt
; route8 trainer 2, _Route8AfterBattleText3
_FGTSuperNerdAfter::
	text "Go with GRIMER"
	line "first...and..."
	cont "...and...then..."
	done

; rocktunnel2 trainer 7, _RockTunnel2BattleText9
_FGTPokemaniacIntro::
	text "I draw #MON"
	line "when I'm home."
	done
; rocktunnel2 trainer 7, _RockTunnel2EndBattleText9
_FGTPokemaniacDefeat::
	text "Whew!"
	line "I'm exhausted!"
	prompt
; rocktunnel2 trainer 7, _RockTunnel2AfterBattleText9
_FGTPokemaniacAfter::
	text "I'm an artist,"
	line "not a fighter."
	done

; fightingdojo trainer 2, _FightingDojoBattleText3
_FGTBlackbeltIntro::
	text "Nothing tough"
	line "frightens me!"

	para "I break boulders"
	line "for training!"
	done
; fightingdojo trainer 2, _FightingDojoEndBattleText3
_FGTBlackbeltDefeat::
	text "Yow!"
	line "Stubbed fingers!"
	prompt
; fightingdojo trainer 2, _FightingDojoAfterBattleText3
_FGTBlackbeltAfter::
	text "The only thing"
	line "that frightens us"
	cont "is psychic power!"
	done

; victoryroad3 trainer 0, _VictoryRoad3BattleText2
_FGTCooltrainerMIntro::
	text "I heard rumors of"
	line "a child prodigy!"
	done
; victoryroad3 trainer 0, _VictoryRoad3EndBattleText2
_FGTCooltrainerMDefeat::
	text "The"
	line "rumors were true!"
	prompt
; victoryroad3 trainer 0, _VictoryRoad3AfterBattleText2
_FGTCooltrainerMAfter::
	text "You beat GIOVANNI"
	line "of TEAM ROCKET?"
	done

; pokemontower5 trainer 1, _PokemonTower5BattleText2
_FGTChannelerIntro::
	text "You...shall..."
	line "join...us..."
	done
; pokemontower5 trainer 1, _PokemonTower5EndBattleText2
_FGTChannelerDefeat::
	text "What"
	line "a nightmare!"
	prompt
; pokemontower5 trainer 1, _PokemonTower5AfterBattleText2
_FGTChannelerAfter::
	text "I was possessed!"
	done

; ssanne9 trainer 0, _SSAnne9BattleText1
_FGTGentlemanIntro::
	text "Competing against"
	line "the young keeps"
	cont "me youthful."
	done
; ssanne9 trainer 0, _SSAnne9EndBattleText1
_FGTGentlemanDefeat::
	text "Good"
	line "fight! Ah, I feel"
	cont "young again!"
	prompt
; ssanne9 trainer 0, _SSAnne9AfterBattleText1
_FGTGentlemanAfter::
	text "15 years ago, I"
	line "would have won!"
	done

; mansion4 trainer 1, _Mansion4BattleText2
_FGTScientistIntro::
	text "This place is"
	line "ideal for a lab."
	done
; mansion4 trainer 1, _Mansion4EndBattleText2
_FGTScientistDefeat::
	text "What"
	line "was that for?"
	prompt
; mansion4 trainer 1, _Mansion4AfterBattleText2
_FGTScientistAfter::
	text "I like it here!"
	line "It's conducive to"
	cont "my studies!"
	done

; silphco9 trainer 0, _SilphCo9BattleText1
_FGTRocketIntro::
	text "Your #MON seem"
	line "to adore you, kid!"
	done
; silphco9 trainer 0, _SilphCo9EndBattleText1
_FGTRocketDefeat::
	text "Ghaaah!"
	prompt
; silphco9 trainer 0, _SilphCo9AfterBattleText1
_FGTRocketAfter::
	text "If I had started"
	line "as a trainer at"
	cont "your age..."
	done

; mansion4 trainer 0, _Mansion4BattleText1
_FGTBurglarIntro::
	text "Uh-oh. Where am"
	line "I now?"
	done
; mansion4 trainer 0, _Mansion4EndBattleText1
_FGTBurglarDefeat::
	text "Awooh!"
	prompt
; mansion4 trainer 0, _Mansion4AfterBattleText1
_FGTBurglarAfter::
	text "You can find stuff"
	line "lying around."
	done

; route11 trainer 8, _Route11BattleText9
_FGTEngineerIntro::
	text "Watch out for"
	line "live wires!"
	done
; route11 trainer 8, _Route11EndBattleText9
_FGTEngineerDefeat::
	text "Whoa!"
	line "You spark plug!"
	prompt
; route11 trainer 8, _Route11AfterBattleText9
_FGTEngineerAfter::
	text "Well, better get"
	line "back to work."
	done

; fuchsiagym trainer 2, _FuchsiaGymBattleText3
_FGTJugglerIntro::
	text "Let's see you"
	line "beat my special"
	cont "techniques!"
	done
; fuchsiagym trainer 2, _FuchsiaGymEndBattleText3
_FGTJugglerDefeat::
	text "You"
	line "had me fooled!"
	prompt
; fuchsiagym trainer 2, _FuchsiaGymAfterBattleText3
_FGTJugglerAfter::
	text "I like poison and"
	line "sleep techniques,"
	cont "as they linger"
	cont "after battle!"
	done


; The cave's cell pick, in $29: $1A ran out of room with the Cemetery's code
; (2026-11-20). Farcalled by CaveGenericPlace; SRAM bank 0 open, as there.
SECTION "Wild Generic Trainer Cave Pick", ROMX, BANK[$29]

; His cave cell: the hideout's second candidate (sStageEventHideoutAltX/Y,
; PCStageHideoutCapture), one of the generator's carved edge targets, so a dead
; end that is reachable by construction and blocks no way. None when the hideout
; took it (its first candidate was the exit), when it is the exit's block, or a
; ball's. He stands on the block's first walkable quadrant, facing the first open
; neighbour (down, up, left, right). Writes sWildGenericCell (X | quadrant << 5),
; the block Y into sWildGenericFloor's bits 3-7, the facing into sWildGenericRow's
; bits 4-5. SRAM bank 0 open. Clobbers everything.
WGTCavePick::
	ld a, [sStageEventHideoutAltX]
	ld d, a
	ld a, [sStageEventHideoutAltY]
	ld e, a
	call WGTCaveCellOk
	jr c, .found
	; No stage event this cave: the hideout's own dead end stands empty (the
	; pair's pictures are 0, so they do not exist), the second choice.
	; Measured 2026-11-20: a ball took the second candidate in 2 of 9 caves.
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	jp nz, .none
	ld a, [sStageEventHideoutX]
	ld d, a
	ld a, [sStageEventHideoutY]
	ld e, a
	call WGTCaveCellOk.notHideout
	jp nc, .none
.found
	call WGTCaveBlockMask
	ld c, 0
.quadrant
	rrca
	jr c, .haveQuadrant
	inc c
	jr .quadrant
.haveQuadrant
	ld b, 0                             ; b = the facing
	inc e
	call WGTCaveBlockMask               ; below
	dec e
	and a
	jr nz, .haveFacing
	inc b
	dec e
	call WGTCaveBlockMask               ; above
	inc e
	and a
	jr nz, .haveFacing
	inc b
	dec d
	call WGTCaveBlockMask               ; left
	inc d
	and a
	jr nz, .haveFacing
	inc b
	inc d
	call WGTCaveBlockMask               ; right
	dec d
	and a
	jr nz, .haveFacing
	ld b, 0
.haveFacing
	ld a, c
	swap a
	add a                               ; quadrant << 5
	or d
	ld [sWildGenericCell], a
	ld a, e
	add a
	add a
	add a                               ; Y << 3
	ld c, a
	ld a, [sWildGenericFloor]
	and WGT_FLOOR_MASK
	or c
	ld [sWildGenericFloor], a
	ld a, b
	swap a
	ld b, a
	ld a, [sWildGenericRow]
	and $0f
	or b
	ld [sWildGenericRow], a
	ret
.none
	ld a, FGT_CELL_NONE
	ld [sWildGenericCell], a
	ret

; d/e = a candidate block. Carry = he may stand there: in the grid, not the
; hideout's (from .notHideout: skipped), not the exit's, not a ball's (slots
; 2-5), and walkable somewhere. SRAM bank 0 open. Keeps de; clobbers a/bc/hl.
WGTCaveCellOk:
	ld a, d
	cp CAVESUB_SIZE
	jr nc, .no                          ; unset ($ff)
	ld a, e
	cp CAVESUB_SIZE
	jr nc, .no
	ld a, [sStageEventHideoutX]
	cp d
	jr nz, .notHideout
	ld a, [sStageEventHideoutY]
	cp e
	jr z, .no
.notHideout
	ld a, [wWarpEntries + 4]            ; the exit (warp 1): tile Y, X
	srl a
	cp e
	jr nz, .notExit
	ld a, [wWarpEntries + 5]
	srl a
	cp d
	jr z, .no
.notExit
	ld hl, wSprite02StateData2MapY      ; the balls, slots 2-5
	ld b, 4
.ball
	ld a, [hli]
	sub 4
	srl a
	cp e
	jr nz, .nextBall
	ld a, [hl]
	sub 4
	srl a
	cp d
	jr z, .no
.nextBall
	ld a, l
	add SPRITESTATEDATA2_LENGTH - 1     ; the next slot's MapY
	ld l, a
	dec b
	jr nz, .ball
	call WGTCaveBlockMask
	and a
	ret z                               ; and a: carry clear
	scf
	ret
.no
	and a
	ret

; d/e = a cave block (out of the 20x20 grid reads as solid). Out: a = its
; walkable-quadrant mask (CavernQuadWalkMasks, $3F, read with FarCopyData into
; wBuffer + 1: wBuffer is free after PCFinalizeCave; FarCopyData itself uses
; wBuffer + 0). Keeps bc/de.
WGTCaveBlockMask:
	ld a, d
	cp CAVESUB_SIZE
	jr nc, .solid
	ld a, e
	cp CAVESUB_SIZE
	jr nc, .solid
	push bc
	push de
	ld hl, wOverworldMap + CAVESUB_BASE
	ld b, 0
	ld c, d
	add hl, bc
	ld c, CAVESUB_STRIDE
	ld a, e
	and a
	jr z, .haveBlock
.row
	add hl, bc
	dec a
	jr nz, .row
.haveBlock
	ld a, [hl]                          ; the block id
	cp 128                              ; NUM_CAVERN_QUAD_MASKS (cavern_quad_masks.asm)
	jr nc, .solidPop
	ld c, a
	ld b, 0
	ld hl, CavernQuadWalkMasks
	add hl, bc
	ld de, wBuffer + 1
	ld bc, 1
	ld a, BANK(CavernQuadWalkMasks)
	call FarCopyData
	ld a, [wBuffer + 1]
	pop de
	pop bc
	ret
.solidPop
	pop de
	pop bc
.solid
	xor a
	ret
