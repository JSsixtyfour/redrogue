; The Facility's optional deep floor (PROCEDURAL_DEEP_FLOOR_PLAN.md, Facility
; SPEC X1-X5). Same design as the cave's and the Forest's, on the shared core
; (deep_floor_core.asm, DeepFacilityArea): floor 2 is PROCEDURAL_FACILITY loaded
; again, with the Facility's bank-1 state exchanged for a shadow copy in two
; idle bank-0 buffers (constants/facility_deep_constants.asm). The generator
; never learns about floors.
;
; TOPOLOGY: a deep Facility has floor 2 instead of its subroom. Each floor's
; subroom pad (PFAC_SUBROOM_PAD, its generation scratch byte 7) is armed at its
; OWN warp; no ordinary pad pair ever targets the subroom pad's site, so that
; warp means "the other floor". The seam swaps the floors and points the
; arrival at the new live floor's subroom pad, which the unchanged
; PFacResolveArrival lands. Floor 2's exits are closed.
;
; $14 (622 B free before this, 2026-11-19). Every entry is farcalled.
SECTION "Facility Deep Floor", ROMX, BANK[$14]

	ASSERT BANK(sProcFacilityStagingBuffer) == 1
	ASSERT BANK(sProcForestStagingBuffer) == 0
	ASSERT (FACILITY_FIRST_PAD_WARP + NUM_FACILITY_PAD_SITES) * 4 < 256
	ASSERT NUM_FACILITY_PAD_SITES < FACILITY_PAD_NONE
	ASSERT FACILITY_DEEP_SAVE + FACILITY_DEEP_NUM_SAVED_WRAM + DEEP_SRAM_TAIL \
		<= sProcForestStagingBuffer + FOREST_DEEP_MAP_SIZE
	DEF FACILITY_DEEP_SUBROOM_PAD EQUS "(sProcFacilityGenScratch + 7)" ; PFAC_SUBROOM_PAD

; ------------------------------------------------------------
; X1. The decision: PFacPreload, right after OptionalFacilityAssignEncounter
; (every Facility preload: lobby and door dice). A new Facility starts on floor
; 1 with floor 2's balls shown. Deep or not, and whether floor 2 keeps a second
; ball; a subroom encounter moves to floor 2. Clobbers everything; SRAM closed.
; ------------------------------------------------------------
FacilityDeepLobbyDecide::
	ld hl, wRogueFlagsBitfield2
	res BIT_ROGUE_DEEP_FLOOR, [hl]
	ld hl, wOptionalEncounterState
	res BIT_OPTIONAL_ON_FLOOR_2, [hl]
	ld hl, wStatusFlags2
	res BIT_DEEP_OFF_BALL, [hl]
	res BIT_DEEP_OFF_BALL_2, [hl]
	call Random
	ld d, a                             ; the deep roll
	call Random
	ld e, a                             ; bit 3: floor 2's second ball
	ld b, 0
IF FACILITY_DEEP_ENABLED
IF DEF(_DEBUG)
	ld a, [wStatusFlags6]
	bit BIT_DEBUG2_MODE, a
	jr nz, .deep                        ; Debug 2: every Facility is deep
ENDC
	ld a, d
	cp FACILITY_DEEP_ODDS
	jr nc, .decided
.deep
	inc b
ENDC
.decided
	; b = 1 deep, 0 ordinary. The PyBoy harness forces 0 here unless a test
	; asks for a deep Facility (harness.py, allow_deep_facility_floor).
	xor a
	dec b
	jr nz, .write                       ; ordinary: the control word 0/$FF
	ld a, e
	and 1 << BIT_FACILITY_DEEP_BALLS_2
	or FACILITY_DEEP_MAGIC
	ld b, a
	; Floor 2 replaces the subroom: an encounter rolled for it stands on floor 2.
	ld a, [wOptionalEncounterMap]
	cp PROCEDURAL_FACILITY_SUBROOM
	jr nz, .haveCtrl
	ld a, PROCEDURAL_FACILITY
	ld [wOptionalEncounterMap], a
	set BIT_FACILITY_DEEP_ENC_2, b
	ld hl, wOptionalEncounterState
	set BIT_OPTIONAL_ON_FLOOR_2, [hl]
.haveCtrl
	ld a, b
.write
	push af
	call FDFOpenSRAM
	pop af
	call FDFWriteCtrl
	jp FDFCloseSRAM

; ------------------------------------------------------------
; X2. The arrival seam: first thing in FGResolveArrival's Facility branch,
; before PFacResolveArrival (every real warp into PROCEDURAL_FACILITY, before
; the map loads). On a deep Facility, a same-map warp to the live floor's own
; subroom pad is a trip to the other floor; the first descent generates floor
; 2 here. Then the arrival is the new floor's subroom pad. Clobbers everything;
; SRAM closed.
; ------------------------------------------------------------
FacilityDeepSeam::
	ld a, [wWarpedFromWhichMap]
	cp PROCEDURAL_FACILITY
	ret nz
	call FDFOpenSRAM
	call FDFReadCtrl
	jp nc, FDFCloseSRAM                 ; not deep
	ld b, a
	call FDFLiveSubroomPad
	ld c, a
	call FDFCloseSRAM
	ld a, c
	cp NUM_FACILITY_PAD_SITES
	ret nc                              ; no subroom pad: no way between floors
	ld a, [wDestinationWarpID]
	sub FACILITY_FIRST_PAD_WARP
	cp c
	ret nz                              ; an ordinary pad, or the entrance
	call FDFFloorBit
	and a
	jr nz, .up
	bit BIT_FACILITY_DEEP_MADE, b
	jr nz, .down
	call FacilityDeepFirstDescent
	jr .arrive
.down
	ld a, 1
	call FacilityDeepFlipTo
	jr .arrive
.up
	xor a
	call FacilityDeepFlipTo
.arrive
	call FDFOpenSRAM
	call FDFLiveSubroomPad              ; always a site here: checked at both ends
	ld c, a
	call FDFCloseSRAM                   ; clobbers a
	ld a, c
	add FACILITY_FIRST_PAD_WARP
	ld [wDestinationWarpID], a
	ret

; ------------------------------------------------------------
; X3. The first descent, from the seam, LCD off:
;   1. flip (floor 1 to the shadow), then save what floor 2's generation will
;      rewrite for the Facility as a whole;
;   2. a fresh floor-2 state: floor 1's 21 B of fields as the base (boss
;      species and sprite, palette, sign, entry battle count; the ball fields are
;      regenerated), unbaked, nothing collected, objects unshown, empty scratch;
;   3. generate it now (PFacFinalize's first-visit path, into a void
;      wOverworldMap as LoadTileBlockMap would leave it), so its subroom pad
;      exists for the arrival; the load's own PFacFinalize then blits it;
;   4. put back the externals; clear the follower's picture (the restage's
;      InitMapSprites spawned it at the departure: the Forest's 2026-11-18 bug);
;   5. floor 2 needs its own subroom pad to come back up: with one, its exit
;      doorways are walled and floor 2 is made; without one (no valid pad block
;      at all) the Facility is ordinary after all and the player stays on floor 1.
; Clobbers everything; SRAM closed.
; ------------------------------------------------------------
FacilityDeepFirstDescent:
	ld a, 1
	call FacilityDeepFlipTo
	ld d, DEEP_AREA_FACILITY
	farcall DeepSaveExternals
	call FDFOpenSRAM
	ld hl, FACILITY_DEEP_SHADOW_STATE   ; floor 1's fields, bank 0
	ld de, sProcFacilityExitI           ; the live copy's, bank 1
	ld c, FACILITY_DEEP_BLOCK_SIZE
.base
	xor a
	ld [rRAMB], a
	ld b, [hl]
	inc hl
	inc a
	ld [rRAMB], a
	ld a, b
	ld [de], a
	inc de
	dec c
	jr nz, .base
	ASSERT sProcFacilityGenScratch == sProcFacilityExitI + FACILITY_DEEP_BLOCK_SIZE
	ld h, d                             ; bank 1, hl = sProcFacilityGenScratch
	ld l, e
	ld c, FACILITY_DEEP_STATE_SIZE - FACILITY_DEEP_BLOCK_SIZE
	xor a
.scratch
	ld [hli], a
	dec c
	jr nz, .scratch
	ld [sProcFacilityBaked], a
	ld [sProcFacilityItemGot], a
	call FDFCloseSRAM
	ld hl, wOverworldMap
	ld bc, (FACILITY_DEEP_SIZE + 6) * (FACILITY_DEEP_SIZE + 6)
	ld a, FACILITY_DEEP_WALL
	call FillMemory
	call FDFBeginDoubleSpeed
	push af
	farcall PFacFinalize
	pop af
	call FDFEndDoubleSpeed
	ld de, DEEP_AREA_FACILITY << 8 | 0
	farcall DeepRestoreExternals
	xor a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID], a
	call FDFOpenSRAM
	call FDFLiveSubroomPad
	cp NUM_FACILITY_PAD_SITES
	jr nc, .noWayUp
	call FDFCloseExit
	call FDFReadCtrl
	or 1 << BIT_FACILITY_DEEP_MADE
	call FDFWriteCtrl
	jp FDFCloseSRAM
.noWayUp
	call FDFCloseSRAM
	xor a
	call FacilityDeepFlipTo             ; floor 1 back live; floor 2 is dropped
	call FDFOpenSRAM
	call FDFDemote
	jp FDFCloseSRAM

; ------------------------------------------------------------
; Helpers.
; ------------------------------------------------------------

; In: a = the floor being arrived on (0 = floor 1, 1 = floor 2). The shared
; core's flip (DeepFacilityArea). Clobbers everything.
FacilityDeepFlipTo:
	ld e, a
	ld d, DEEP_AREA_FACILITY
	farjp DeepFlipTo

; SRAM open. The Facility after all is ordinary: the control word 0/$FF, and an
; encounter the decision moved to floor 2 goes back to the subroom. Clobbers a/hl.
FDFDemote:
	call FDFReadCtrl
	bit BIT_FACILITY_DEEP_ENC_2, a
	jr z, .ordinary
	ld a, PROCEDURAL_FACILITY_SUBROOM
	ld [wOptionalEncounterMap], a
	ld hl, wOptionalEncounterState
	res BIT_OPTIONAL_ON_FLOOR_2, [hl]
.ordinary
	xor a
	jr FDFWriteCtrl

; SRAM open. Floor 2's exit doorways on the baked map's outer ring become wall,
; so the map the load blits has no way out but its subroom pad. Clobbers a/bc/de/hl.
FDFCloseExit:
	ld a, BANK(sProcFacilityStagingBuffer)
	ld [rRAMB], a
	ld hl, sProcFacilityStagingBuffer + FACILITY_DEEP_BASE
	ld b, FACILITY_DEEP_SIZE
.north
	ld a, [hl]
	cp FACILITY_DEEP_EXIT_N
	jr nz, .notNorth
	ld [hl], FACILITY_DEEP_WALL
.notNorth
	inc hl
	dec b
	jr nz, .north
	ld hl, sProcFacilityStagingBuffer + FACILITY_DEEP_BASE
	ld b, FACILITY_DEEP_SIZE
.row
	ld a, [hl]
	cp FACILITY_DEEP_EXIT_W
	jr nz, .notWest
	ld [hl], FACILITY_DEEP_WALL
.notWest
	push hl
	ld de, FACILITY_DEEP_SIZE - 1
	add hl, de
	ld a, [hl]
	cp FACILITY_DEEP_EXIT_E
	jr nz, .notEast
	ld [hl], FACILITY_DEEP_WALL
.notEast
	pop hl
	ld de, FACILITY_DEEP_STRIDE
	add hl, de
	dec b
	jr nz, .row
	ret

; SRAM open. Out: a = the live floor's subroom pad (a site ordinal, or
; FACILITY_PAD_NONE). Leaves bank 1 selected.
FDFLiveSubroomPad:
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld a, [FACILITY_DEEP_SUBROOM_PAD]
	ret

; SRAM open. Out: carry = the control word is valid (a deep Facility), a = the
; control byte. Leaves bank 0 selected. Clobbers hl.
FDFReadCtrl:
	xor a
	ld [rRAMB], a
	ld hl, FACILITY_DEEP_CTRL + 1
	ld a, [hld]
	cpl
	cp [hl]
	jr nz, .invalid
	and DEEP_MAGIC_MASK
	cp FACILITY_DEEP_MAGIC
	jr nz, .invalid
	ld a, [hl]
	scf
	ret
.invalid
	and a
	ret

; SRAM open. a = the new control byte; writes it and its complement on bank 0.
; Clobbers a/hl.
FDFWriteCtrl:
	push af
	xor a
	ld [rRAMB], a
	pop af
	ld hl, FACILITY_DEEP_CTRL
	ld [hli], a
	cpl
	ld [hl], a
	ret

; Out: a = 1 when the player is on floor 2, else 0. Clobbers nothing else.
FDFFloorBit:
	ld a, [wRogueFlagsBitfield2]
	ASSERT BIT_ROGUE_DEEP_FLOOR == 7
	rlca
	and 1
	ret

; Clobbers a only.
FDFOpenSRAM:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ret

; Clobbers a only; keeps the flags.
FDFCloseSRAM:
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; ProcGenerationBegin/EndDoubleSpeed ($3C) are local to their section, and a
; farcall would lose their a result, so the pair is repeated here (as the cave
; and the Forest). Out: a = $ff (nothing to undo) or 0 (switched a CGB to double speed).
FDFBeginDoubleSpeed:
	ldh a, [hGBC]
	and a
	ld a, $ff
	ret z
	ldh a, [rKEY1]
	bit 7, a
	ld a, $ff
	ret nz
	predef SetCPUSpeed
	xor a
	ret

FDFEndDoubleSpeed:
	inc a
	ret z
	predef SingleCPUSpeed
	ret

; ============================================================
; The load-time half (X4, X5): every Facility load. Farcall/farjp only, in $15
; (542 B free, 2026-11-19), because the whole module (680 B) is larger than
; $14's 622 B. Same split as the cave's cave_deep_floor_post.asm.
; ============================================================
SECTION "Facility Deep Floor 2", ROMX, BANK[$15]

; ------------------------------------------------------------
; X4. ProcStageLoadDispatch, every PROCEDURAL_FACILITY load, after PFacFinalize
; (in place of its own OptionalEncounterPlaceFacility, which runs first).
;   Floor 1 before floor 2 exists, with no subroom pad: an ordinary Facility.
;   Either floor: its subroom pad leads to its own warp (the seam's marker).
;   Floor 2: its exits disarmed; the floor-1 objects it does not use parked.
; Clobbers everything; SRAM closed.
; ------------------------------------------------------------
FacilityDeepAfterFinalize::
	farcall OptionalEncounterPlaceFacility
	call FDF2OpenSRAM
	call FDF2ReadCtrl
	jp nc, FDF2CloseSRAM                 ; not deep
	ld b, a
	call FDF2LiveSubroomPad
	ld c, a
	cp NUM_FACILITY_PAD_SITES
	jr c, .havePad
	call FDF2FloorBit
	and a
	jp nz, FDF2CloseSRAM                 ; never: floor 2 is made only with a pad
	bit BIT_FACILITY_DEEP_MADE, b
	jp nz, FDF2CloseSRAM
	call FDF2Demote                      ; no way down: ordinary
	jp FDF2CloseSRAM
.havePad
	call FDF2CloseSRAM
	ld a, c
	add FACILITY_FIRST_PAD_WARP
	ld e, a
	add a
	add a
	ld l, a
	ld h, 0
	push de
	ld de, wWarpEntries + 2
	add hl, de
	pop de
	ld a, e
	ld [hli], a                         ; its own warp
	ld [hl], PROCEDURAL_FACILITY
	call FDF2FloorBit
	and a
	ret z
	ld a, $ff                           ; floor 2's exits lead nowhere
	ld [wWarpEntries + 1 * 4], a
	ld [wWarpEntries + 2 * 4], a
	xor a
	ld [wSprite01StateData2MapY], a     ; the boss
	ld [wSprite01StateData2MapX], a
	bit BIT_FACILITY_DEEP_BALLS_2, b
	jr nz, .ball2Stays
	ld [wSprite03StateData2MapY], a
	ld [wSprite03StateData2MapX], a
.ball2Stays
FOR n, 4, FACILITY_SUPER_NERD           ; balls 3-4, the fake balls, the stage NPCs
	ld [wSprite{02d:n}StateData2MapY], a
	ld [wSprite{02d:n}StateData2MapX], a
ENDR
	; fall through: the Super Nerd stands here instead of in the subroom

; Floor 2's resident. The scratch bytes the fallback spot would use hold the pad
; and the room piece here, so his block is not stored. It is found again on
; every load: the first block, scanning forward from a seeded start and wrapping
; round, that passes the pad rule (PFacPadBlockValid: plain floor, and his tile,
; its bottom-right quadrant, strands nothing) and is not the encounter's. The
; seed is floor 2's own ball cells (sProcFacilityBallXY): random per floor 2,
; baked with it, so he stands in the same place on every visit and after
; Continue, and somewhere else on the next deep Facility. (Scanning from the top
; put him in the top four rows on 52 of 60 floors 2, measured 2026-11-19.)
; Toggle bits outlive the floor, so his is written each time (floor 1 hid him;
; the script's show block is skipped on floor 2). No spot: he is hidden.
; Clobbers everything; SRAM closed.
DEF FDF2_SCAN_BLOCKS EQU (FACSUB_FALLBACK_MAX + 1 - FACSUB_FALLBACK_TOP) * FACSUB_FALLBACK_MAX
	ASSERT FACSUB_FALLBACK_MAX + 1 - FACSUB_FALLBACK_TOP == 16 ; the seed's low nibble picks the row
FDF2PlaceResident:
	call FDF2OpenSRAM
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld hl, sProcFacilityBallXY
	ld b, 8
	xor a
.seed
	rlca
	add [hl]
	inc hl
	dec b
	jr nz, .seed
	ld b, a
	and $0f
	add FACSUB_FALLBACK_TOP
	ld e, a                             ; the start row, 3-18
	ld a, b
	swap a
	and $0f
	inc a
	ld d, a                             ; the start column, 1-16
	ld hl, FDF2_SCAN_BLOCKS             ; every block once, then give up
.block
	push hl
	push de
	farcall PFacPadBlockValid           ; carry = it passes; keeps d/e
	pop de                              ; keeps the carry
	pop hl
	jr nc, .next
	ld a, [sProcFacilityGenScratch + FACSUB_SCRATCH_MON_X]
	cp d
	jr nz, .foundC
	ld a, [sProcFacilityGenScratch + FACSUB_SCRATCH_MON_Y]
	cp e
	jr nz, .foundC
.next
	inc d
	ld a, d
	cp FACSUB_FALLBACK_MAX + 1
	jr c, .counted
	ld d, 1
	inc e
	ld a, e
	cp FACSUB_FALLBACK_MAX + 1
	jr c, .counted
	ld e, FACSUB_FALLBACK_TOP           ; round to the top
.counted
	dec hl
	ld a, h
	or l
	jr nz, .block
	and a                               ; none (carry clear)
	jr .found
.foundC
	scf
.found
	push af
	call FDF2CloseSRAM
	pop af
	ld b, FLAG_SET
	jr nc, .toggle
	ld a, e
	add a
	add 4 + 1                           ; the block's bottom-right quadrant
	ld [wSprite{d:FACILITY_SUPER_NERD}StateData2MapY], a
	ld a, d
	add a
	add 4 + 1
	ld [wSprite{d:FACILITY_SUPER_NERD}StateData2MapX], a
	ld b, FLAG_RESET
.toggle
	ld c, TOGGLE_FACILITY_SUPER_NERD
	ld hl, wToggleableObjectFlags
	predef_jump FlagActionPredef

; ------------------------------------------------------------
; X5 hooks, ProcBossPatchStageSprite's Facility branch ($3C).
; ------------------------------------------------------------

; First, in place of its OptionalEncounterPatchSprite: the saved floor's state
; into the live copy before anything reads it, then that patch. Clobbers everything.
FacilityDeepReconcile::
	ld d, DEEP_AREA_FACILITY
	farcall DeepReconcile
	farjp OptionalEncounterPatchSprite

; Last (.npcSlots1011): on floor 2 the floor-1 objects it does not use (the
; boss, balls 3-4 and ball 2 unless kept, the fake balls, the stage NPCs) get
; picture 0, "this slot does not exist", so their toggle bits keep floor 1's
; state. Clobbers everything.
FacilityDeepPatchSprites::
	call FDF2OpenSRAM
	call FDF2ReadCtrl
	ld b, a
	jr nc, .read                        ; ordinary: carry clear
	call FDF2LiveSubroomPad
	cp NUM_FACILITY_PAD_SITES           ; carry = this floor has its pad
.read
	call FDF2CloseSRAM                  ; keeps the carry
	ret nc                              ; ordinary, or a deep floor 1 about to be demoted
	call FDF2FloorBit
	jr nz, .floor2                      ; (a = 0 on floor 1)
	ld [wSprite{d:FACILITY_SUPER_NERD}StateData1 + SPRITESTATEDATA1_PICTUREID], a ; floor 1: he lives on floor 2
	ret
.floor2
	xor a
	ld [wSprite01StateData1 + SPRITESTATEDATA1_PICTUREID], a
	bit BIT_FACILITY_DEEP_BALLS_2, b
	jr nz, .ball2Stays
	ld [wSprite03StateData1 + SPRITESTATEDATA1_PICTUREID], a
.ball2Stays
FOR n, 4, FACILITY_SUPER_NERD
	ld [wSprite{02d:n}StateData1 + SPRITESTATEDATA1_PICTUREID], a
ENDR
	ret


; ------------------------------------------------------------
; This half's copies of the helpers (the other half is in another bank).
; ------------------------------------------------------------

; SRAM open. As FDFDemote.
FDF2Demote:
	call FDF2ReadCtrl
	bit BIT_FACILITY_DEEP_ENC_2, a
	jr z, .ordinary
	ld a, PROCEDURAL_FACILITY_SUBROOM
	ld [wOptionalEncounterMap], a
	ld hl, wOptionalEncounterState
	res BIT_OPTIONAL_ON_FLOOR_2, [hl]
.ordinary
	xor a
	ld [rRAMB], a                       ; bank 0 (FDF2ReadCtrl left it there)
	ld hl, FACILITY_DEEP_CTRL
	ld [hli], a
	cpl
	ld [hl], a
	ret

; As FDFLiveSubroomPad.
FDF2LiveSubroomPad:
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld a, [FACILITY_DEEP_SUBROOM_PAD]
	ret

; As FDFReadCtrl.
FDF2ReadCtrl:
	xor a
	ld [rRAMB], a
	ld hl, FACILITY_DEEP_CTRL + 1
	ld a, [hld]
	cpl
	cp [hl]
	jr nz, .invalid
	and DEEP_MAGIC_MASK
	cp FACILITY_DEEP_MAGIC
	jr nz, .invalid
	ld a, [hl]
	scf
	ret
.invalid
	and a
	ret

FDF2FloorBit:
	ld a, [wRogueFlagsBitfield2]
	rlca
	and 1
	ret

FDF2OpenSRAM:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ret

FDF2CloseSRAM:
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ld [rRAMG], a
	ret
