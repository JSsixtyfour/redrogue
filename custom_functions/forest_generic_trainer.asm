; The Forest's generic route trainer (GENERIC_TRAINER_TRIAL_SPEC.md, D3: its own
; object slot, independent of the stage event). Object FOREST_GENERIC of
; ProceduralForest, no toggle (the Forest has none): picture 0 and parked when
; absent, as the optional slot 8.
;
; LIFECYCLE, each piece riding an existing Forest hook (the generator's bank
; $3F has 10 B free and the deep floor's $34 53 B):
;   preload   ForestGenericRoll      OptionalForestAssignEncounter ($26)
;   generate  ForestGenericPick      PFScanForBall, after the hideout ($3F)
;   each load ForestGenericPatch     ForestDeepPatchSprites ($34), the picture
;             ForestGenericPlace     ForestDeepAfterFinalize ($34): cell,
;                                    facing, class
; State: sForestGenericRow and sForestGenericCell (ram/sram.asm), SRAM bank 0.
;
; Every entry is farcalled. INCLUDEd after the Forest generator, whose
; PF_* and wPF* constants it uses.
SECTION "Forest Generic Trainer", ROMX, BANK[$1A]

	ASSERT BANK(sForestGenericRow) == 0
	ASSERT BANK(sProcForestGenScratch) == 0
	ASSERT BANK(sProcForestBaked) == 0
	ASSERT FOREST_GENERIC == 9

DEF FGT_CELL_PENDING EQU $ff ; not picked yet (the roll's value)
DEF FGT_CELL_NONE    EQU $fe ; the pick found no dead end

; The classic route classes and their usual route sprites (D1). Camper and
; Picnicker are Gen 2 classes; Gen 1's are the Jr. Trainers. Every row is a
; roster class: ReadTrainer finds no authored team and GetRandRoster rolls one.
GenericTrainerTable:
	db OPP_YOUNGSTER,    SPRITE_YOUNGSTER
	db OPP_BUG_CATCHER,  SPRITE_YOUNGSTER
	db OPP_LASS,         SPRITE_COOLTRAINER_F
	db OPP_HIKER,        SPRITE_HIKER
	db OPP_JR_TRAINER_M, SPRITE_COOLTRAINER_M
	db OPP_JR_TRAINER_F, SPRITE_COOLTRAINER_F
DEF NUM_GENERIC_TRAINERS EQU (@ - GenericTrainerTable) / 2
	ASSERT NUM_GENERIC_TRAINERS < 16

; ------------------------------------------------------------
; The roll: every Forest preload, from OptionalForestAssignEncounter, before
; the stage event's sprites are staged (so a clash with the villain's sprite is
; resolved where the row is read, FGTRow). The cell becomes pending.
; Clobbers everything; leaves SRAM open on bank 0, as that caller expects.
; ------------------------------------------------------------
ForestGenericRoll::
	; His defeat flag is run-scoped like the stage pair's: a new Forest finds him
	; unbeaten. Reset here, not in the preload ($3F has no room for it).
	ResetEvent EVENT_BEAT_FOREST_GENERIC_TRAINER
IF GENERIC_TRAINER_ODDS < 256
	call Random
	cp GENERIC_TRAINER_ODDS
	ld a, 0
	jr nc, .store
ENDC
	ld c, NUM_GENERIC_TRAINERS
	call Rangerandom
	inc a                               ; row + 1
.store
	ld b, a
	call FGTOpenSRAM
	ld a, b
	ld [sForestGenericRow], a
	ld a, FGT_CELL_PENDING
	ld [sForestGenericCell], a
	ret

; ------------------------------------------------------------
; The cell: PFScanForBall, once the balls and the hideout are chosen and while
; the dead-end candidate list is intact (sProcForestGenScratch[0..count-1],
; packed col | row << 4; the boss cell, the entrance and clearings are already
; left out of it). Only when pending, so the deep floor 2's own generation
; never moves floor 1's trainer. No Random: the start is the balls' coordinate
; sum, so adding him moves no other roll. Rejected: a ball's cell, and any cell
; within one of the hideout's (its own and the eight around it). Facing: the
; dead end's one opening in the maze as generated (wOverworldMap + PF_BASE),
; so his one-tile sight covers the way in.
; SRAM bank 0 open (kept open). Clobbers everything.
; ------------------------------------------------------------
ForestGenericPick::
	ld a, [sForestGenericCell]
	cp FGT_CELL_PENDING
	ret nz
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
	ld [sForestGenericCell], a
	ret
.found
	ld a, [hl]
	ld [sForestGenericCell], a
	call FGTFacing                      ; a = 0 down, 1 up, 2 left, 3 right
	swap a
	ld b, a
	ld a, [sForestGenericRow]
	and $0f
	or b
	ld [sForestGenericRow], a
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
; (two blocks) from the hideout's. Keeps bc/de/hl.
FGTCellOk:
	push hl
	push bc
	ld hl, wBuffer + wPFAcceptedXY
	ld b, 4
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
; His sprite on floor 1 when he was rolled and has (or, on a first entry before
; generation, may yet get) a cell; else 0. Clobbers everything.
; ------------------------------------------------------------
ForestGenericPatch::
	ld a, [wRogueFlagsBitfield2]
	bit BIT_ROGUE_DEEP_FLOOR, a
	ld b, 0
	jr nz, .write                       ; floor 2: none
	call FGTOpenSRAM
	call FGTRow
	ld b, 0                             ; FGTRow used b; keeps the carry
	jr nc, .close
	ld a, [sForestGenericCell]
	cp FGT_CELL_NONE
	jr z, .close
	inc hl
	ld b, [hl]                          ; his sprite
.close
	call FGTCloseSRAM
.write
	ld a, b
	ld [wSprite{02d:FOREST_GENERIC}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ret

; ------------------------------------------------------------
; The cell, facing and class: ForestDeepAfterFinalize, every Forest load after
; PFinalizeForest (which ran the pick on a first entry). Floor 2, no trainer or
; no cell: picture 0, parked off the map. A battle's return keeps his position
; and facing (the engine kept them). Clobbers everything; SRAM closed.
; ------------------------------------------------------------
ForestGenericPlace::
	ld a, [wRogueFlagsBitfield2]
	bit BIT_ROGUE_DEEP_FLOOR, a
	jr nz, .park
	call FGTOpenSRAM
	call FGTRow                         ; carry, hl -> his row
	jr nc, .closePark
	ld a, [sForestGenericCell]
	cp FGT_CELL_NONE
	jr nc, .closePark                   ; none, or never picked
	ld b, a                             ; b = his cell
	ld c, [hl]                          ; c = his class
	ld a, [sForestGenericRow]
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
.park
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

; Out: carry = a trainer this Forest; hl -> his GenericTrainerTable row. A
; row whose sprite is the stage event's (slot 6 or 7) moves to the next row,
; so he never wears the villain's picture (the Psychic is SPRITE_YOUNGSTER).
; SRAM bank 0 open. Clobbers a/bc/hl.
FGTRow:
	ld a, [sForestGenericRow]
	and $0f
	jr z, .none
	dec a
	cp NUM_GENERIC_TRAINERS
	jr nc, .none
	ld c, NUM_GENERIC_TRAINERS
.try
	ld b, a
	add a
	ld hl, GenericTrainerTable + 1
	add l
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
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
	ld a, b
	inc a
	cp NUM_GENERIC_TRAINERS
	jr c, .next
	xor a
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
