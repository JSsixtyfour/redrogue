; The Forest's optional deep floor (PROCEDURAL_DEEP_FLOOR_PLAN.md, Forest SPEC
; F1, F3, F4). Same design as the cave's (custom_functions/cave_deep_floor.asm):
; floor 2 is PROCEDURAL_FOREST loaded again, with the Forest's SRAM state
; exchanged for a shadow copy, here kept in the cave's idle bank-0 buffer
; (constants/forest_deep_constants.asm). The generator never learns about floors.
;
; WHERE EACH PIECE OF FLOOR STATE LIVES (as the cave):
;   - The 400 B map and the 102 B block sProcForestExitI..sProcForestGenScratch
;     + 80: SRAM bank 0, live at their own addresses, the other floor's in the
;     shadow. The control word says which floor the live copy holds; every
;     Forest load reconciles it with the saved floor bit.
;   - Which floor the player is on: wRogueFlagsBitfield2 bit 7, saved WRAM.
;   - Toggles: saved WRAM. Floor 2 hides the floor-1 objects it does not use by
;     picture (F5), so their bits keep floor 1's state; ball 1's off-floor copy is
;     wStatusFlags2 bit 6, swapped on a real flip only. Shared with the cave:
;     only one wild area is live per lobby, and each one's preload clears both.
;
; TOPOLOGY, the grotto's: the floors meet opening to opening. Floor 1's
; grotto-style opening (on wall N, W or E; carved on a deep Forest whether or not
; an encounter is assigned, FGWantsOpening) and floor 2's (on the facing wall,
; S, E or W, FGCarveOpening) are both warps FG_WARP / the second warp of this
; map; the seam swaps the floors and FGResolveArrival places the player on the
; live floor's opening. Floor 2's own exit is closed. So that the arrival can be
; placed, the first descent generates floor 2 in the seam, before the map loads.

; 844 B. $34 holds battle-effect code with room to spare (1,545 B free after
; this section, 2026-11-18); $14/$15, the cave's banks, have under 650 B each.
; Every entry is farcalled; nothing here calls another bank directly.
SECTION "Forest Deep Floor", ROMX, BANK[$34]

DEF FD_PF_SIZE EQU 20                   ; PF_SIZE: the 20x20 maze; wOverworldMap adds a 3-block border
	ASSERT FD_PF_SIZE * FD_PF_SIZE == FOREST_DEEP_MAP_SIZE

	ASSERT BANK(sProcCaveStagingBuffer) == 0
	ASSERT BANK(sProcForestStagingBuffer) == 0
	ASSERT BANK(sProcForestExitI) == 0
	ASSERT BANK(sProcCavePalette) == 0
	ASSERT SIZEOF("Procedural Forest Staging") == FOREST_DEEP_MAP_SIZE
	; The state block runs from sProcForestExitI through the generation scratch,
	; which ends where the palettes begin.
	ASSERT sProcCavePalette - sProcForestExitI == FOREST_DEEP_STATE_SIZE
	ASSERT sProcForestGenScratch - sProcForestExitI == FOREST_DEEP_BLOCK_SIZE
	ASSERT sStageEventHideoutY < sProcCavePalette + FOREST_DEEP_SRAM_TAIL
	ASSERT FOREST_DEEP_MAP_SIZE + FOREST_DEEP_STATE_SIZE + 2 \
		+ FOREST_DEEP_NUM_SAVED_WRAM + FOREST_DEEP_SRAM_TAIL + 1 <= 600

; ------------------------------------------------------------
; F1. The decision: the end of OptionalForestAssignEncounter, i.e. every Forest
; preload (lobby and door dice), right after the grotto's encounter is rolled.
; A new Forest starts on floor 1 with floor 2's ball shown; deep or not, and
; which floor keeps the rest house, are rolled here because floor 1's own
; generation must already know the house's floor. Confirmed after floor 1
; generates (ForestDeepAfterFinalize). Leaves SRAM open on bank 0, as the
; caller (PFPreloadForest) expects. Clobbers everything.
; ------------------------------------------------------------
ForestDeepLobbyDecide::
	ld hl, wRogueFlagsBitfield2
	res BIT_ROGUE_DEEP_FLOOR, [hl]
	ld hl, wStatusFlags2
	res BIT_DEEP_OFF_BALL, [hl]
	call Random
	ld d, a                             ; the deep roll
	call Random
	ld e, a                             ; the rest house's coin
	ld b, 0
IF FOREST_DEEP_ENABLED
IF DEF(_DEBUG)
	ld a, [wStatusFlags6]
	bit BIT_DEBUG2_MODE, a
	jr nz, .deep                        ; Debug 2: every Forest is deep
ENDC
	ld a, d
	cp FOREST_DEEP_ODDS
	jr nc, .decided
.deep
	inc b
ENDC
.decided
	; b = 1 deep, 0 ordinary. The PyBoy harness forces 0 here unless a test
	; asks for a deep Forest (harness.py, allow_deep_forest_floor).
	xor a
	dec b
	jr nz, .write                       ; ordinary: the control word 0/$FF
	ld a, e
	and 1 << BIT_FOREST_DEEP_HOUSE_2
	or FOREST_DEEP_MAGIC
	ld b, a
	; Floor 2 replaces the grotto: an encounter rolled for it stands on floor 2.
	ld a, [wOptionalEncounterMap]
	cp PROCEDURAL_FOREST_GROTTO
	jr nz, .haveCtrl
	ld a, PROCEDURAL_FOREST
	ld [wOptionalEncounterMap], a
.haveCtrl
	ld a, b
.write
	push af
	call FDOpenSRAM
	pop af
	jp FDWriteCtrl                      ; SRAM stays open on bank 0

; ------------------------------------------------------------
; F3. The arrival seam: first thing in FGResolveArrival's Forest branch (every
; real warp into PROCEDURAL_FOREST, before parity and before the map loads). On
; a deep Forest, a same-map warp to FG_WARP / the second warp is a trip through
; the openings: from floor 1 down, from floor 2 up (its opening, or its exit when
; it has none). Nothing else reaches the seam with this source map. The first
; descent generates floor 2 here. Clobbers everything; leaves SRAM closed.
; ------------------------------------------------------------
ForestDeepSeam::
	ld a, [wWarpedFromWhichMap]
	cp PROCEDURAL_FOREST
	ret nz
	ld a, [wDestinationWarpID]
	cp FG_WARP
	jr z, .opening
	cp FOREST_GROTTO_SECOND_WARP
	ret nz
.opening
	call FDOpenSRAM
	call FDReadCtrl
	push af
	call FDCloseSRAM
	pop af
	ret nc                              ; not a deep Forest
	ld b, a                             ; the control byte
	call FDFloorBit
	and a
	jr nz, .up
	bit BIT_FOREST_DEEP_MADE, b
	ld a, 1
	jp nz, ForestDeepFlipTo
	jr ForestDeepFirstDescent
.up
	xor a
	jp ForestDeepFlipTo

; ------------------------------------------------------------
; The first descent, from the seam, LCD off:
;   1. the wall floor 2's opening must face: N -> S, W -> E, E -> W;
;   2. flip (floor 1 to the shadow), then save what floor 2's generation will
;      rewrite for the Forest as a whole (after the flip, so the restore cannot
;      undo its ball exchange: the residents' toggle bytes hold ball bits too);
;   3. a fresh floor-2 state: floor 1's block as the base (boss species and
;      sprite, sign variant: the patch paths read them), unbaked, nothing
;      collected, no house, no river, an exit edge away from that wall;
;   4. generate it now (PFinalizeForest's first-visit path, into an all-tree
;      wOverworldMap as LoadTileBlockMap would leave it), so its opening exists
;      when FGResolveArrival places the player; the load's own PFinalizeForest
;      then just blits the baked map;
;   5. put back what the generation rewrote, remove the house the coin gave
;      floor 1, and close floor 2's exit when it has its opening.
; Clobbers everything; leaves SRAM closed.
; ------------------------------------------------------------
ForestDeepFirstDescent:
	farcall FGDeepFindOpening           ; d = floor 1's opening wall (the post-pass
	ld a, d                             ; demotes a deep Forest without one)
	and a
	ld a, 3                             ; north faces south
	jr z, .haveWall
	ld a, d
	xor 3                               ; west 1 <-> east 2
.haveWall
	ld c, a
	call FDOpenSRAM
	ld a, c
	ld [FOREST_DEEP_UP_WALL], a
	call FDCloseSRAM
	ld a, 1
	call ForestDeepFlipTo
	call ForestDeepSaveExternals
	call FDOpenSRAM
	ld hl, FOREST_DEEP_SHADOW_STATE
	ld de, sProcForestExitI
	ld c, FOREST_DEEP_BLOCK_SIZE
.copyBlock
	ld a, [hli]
	ld [de], a
	inc de
	dec c
	jr nz, .copyBlock
	ld h, d                             ; de = sProcForestGenScratch
	ld l, e
	ld c, FOREST_DEEP_STATE_SIZE - FOREST_DEEP_BLOCK_SIZE
	xor a
.zeroScratch
	ld [hli], a
	dec c
	jr nz, .zeroScratch
	ld [sProcForestBaked], a
	ld [sProcForestItemGot], a          ; nothing collected, no house, objects unshown
	ld [sProcForestAlgoForce], a
	dec a
	ld [sProcForestRiverSide], a        ; $FF: no river
	ld c, 3
	call Rangerandom                    ; floor 2's exit edge: N/W/E but not that wall
	ld b, a
	ld a, [FOREST_DEEP_UP_WALL]
	cp b
	ld a, b
	jr nz, .edge
	inc a
	cp 3
	jr c, .edge
	xor a
.edge
	ld [sProcForestExitEdge], a
	call FDReadCtrl
	or 1 << BIT_FOREST_DEEP_MADE
	call FDWriteCtrl
	call FDCloseSRAM
	; 4. generate
	ld hl, wOverworldMap
	ld bc, (FD_PF_SIZE + 6) * (FD_PF_SIZE + 6)
	ld a, FOREST_DEEP_TREE
	call FillMemory
	call FDBeginDoubleSpeed
	push af
	farcall PFinalizeForest
	pop af
	call FDEndDoubleSpeed
	; The generation's PFRestageEventSprites can run InitMapSprites, whose
	; FollowerPrepareMap spawns slot 15 at the departure coordinates before
	; FGResolveArrival places the player; the load's own pass then kept that
	; stale spawn (same picture). Clear the picture again, as LoadMapHeader did,
	; so the load's pass spawns the follower on the arrival.
	xor a
	ld [wSprite15StateData1 + SPRITESTATEDATA1_PICTUREID], a
	; 5. restore, house, exit
	call FDOpenSRAM
	call FDReadCtrl
	ld b, a
	call FDCloseSRAM
	push bc
	call ForestDeepRestoreExternals
	pop bc
	call FDOpenSRAM
	bit BIT_FOREST_DEEP_HOUSE_2, b
	call z, FDRemoveHouse
	call FDCloseSRAM
	farcall FGDeepFindOpening           ; carry = floor 2 has its opening
	ret nc                              ; no: its exit stays the way up
	call FDOpenSRAM
	call FDCloseExit
	call FDReadCtrl
	or 1 << BIT_FOREST_DEEP_OPENING_2
	call FDWriteCtrl
	jp FDCloseSRAM

; What floor 2's PFinalizeForest rewrites for the Forest as a whole (Forest
; Phase 0, item 6). The "always" part, then the rest house's lobby offers and
; residents, which come back only when the house is on floor 1 (on floor 2 its
; own generation rolls the house's offers, once). Whole bytes: between the save
; and the restore nothing but floor 2's generation runs.
ForestDeepSavedWram:
	dw wRoguePokemon1, wRoguePokemonForm1, wStageEvent, wProcForestWildBudget
	DEF FOREST_DEEP_NUM_ALWAYS EQU (@ - ForestDeepSavedWram) / 2
FOR n, 17                              ; wroguenpctradegive..wroguenpcclass
	dw wroguenpctradegive + n
ENDR
	ASSERT wroguenpcclass + 1 - wroguenpctradegive == 17
	dw wroguenpctradeform
	dw wCompletedInGameTradeFlags + TRADE_FOR_RANDOM / 8
	dw wEventFlags + EVENT_BOUGHT_POKEMON / 8
	dw wToggleableObjectFlags + TOGGLE_PFRESTHOUSE_RENTAL_OFFICIAL / 8
	dw wToggleableObjectFlags + TOGGLE_PFRESTHOUSE_GAMBLER / 8
	ASSERT TOGGLE_PFRESTHOUSE_GAMBLER - TOGGLE_PFRESTHOUSE_RENTAL_OFFICIAL == 6
	ASSERT (@ - ForestDeepSavedWram) / 2 == FOREST_DEEP_NUM_SAVED_WRAM

; The WRAM list, then FOREST_DEEP_SRAM_TAIL bytes from sProcCavePalette (the
; palettes and the stage-event hideout). Clobbers everything; SRAM closed.
ForestDeepSaveExternals:
	call FDOpenSRAM
	ld hl, ForestDeepSavedWram
	ld de, FOREST_DEEP_SAVE
	ld c, FOREST_DEEP_NUM_SAVED_WRAM
.wram
	ld a, [hli]
	push hl
	ld h, [hl]
	ld l, a
	ld a, [hl]
	ld [de], a
	pop hl
	inc hl
	inc de
	dec c
	jr nz, .wram
	ld hl, sProcCavePalette
	ld c, FOREST_DEEP_SRAM_TAIL
.sram
	ld a, [hli]
	ld [de], a
	inc de
	dec c
	jr nz, .sram
	jp FDCloseSRAM

; In: b = the control byte. Puts back the "always" part and the SRAM tail, and
; the house part when the house is on floor 1. Clobbers everything; SRAM closed.
ForestDeepRestoreExternals:
	push bc
	call FDOpenSRAM
	ld hl, ForestDeepSavedWram
	ld de, FOREST_DEEP_SAVE
	ld c, FOREST_DEEP_NUM_ALWAYS
	call .wram
	pop bc
	bit BIT_FOREST_DEEP_HOUSE_2, b
	ld c, FOREST_DEEP_NUM_SAVED_WRAM - FOREST_DEEP_NUM_ALWAYS
	call z, .wram                       ; the house is on floor 1: its offers stand
	ld hl, FOREST_DEEP_SAVE + FOREST_DEEP_NUM_SAVED_WRAM
	ld de, sProcCavePalette
	ld c, FOREST_DEEP_SRAM_TAIL
.sram
	ld a, [hli]
	ld [de], a
	inc de
	dec c
	jr nz, .sram
	jp FDCloseSRAM
; hl = the list, de = the save area, c = how many. Out: hl/de past them.
.wram
	ld a, [hli]
	push hl
	ld h, [hl]
	ld l, a
	ld a, [de]
	ld [hl], a
	pop hl
	inc hl
	inc de
	dec c
	jr nz, .wram
	ret

; ProcGenerationBegin/EndDoubleSpeed ($3C) are local to their section, and a
; farcall would lose their a result, so the pair is repeated here (as the cave).
; Out: a = $ff (nothing to undo) or 0 (switched a CGB to double speed).
FDBeginDoubleSpeed:
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

FDEndDoubleSpeed:
	inc a
	ret z
	predef SingleCPUSpeed
	ret

; ------------------------------------------------------------
; F4. ProcStageLoadDispatch, every PROCEDURAL_FOREST load, after PFinalizeForest
; and FGArmForestWarp. Clobbers everything; leaves SRAM closed.
;   Floor 1, until floor 2 exists: no opening was carved (or a river took the
;     walls) -> an ordinary Forest after all, the encounter back to the grotto.
;   Floor 1: a house the coin gave to floor 2 is removed (idempotent); its
;     opening leads to floor 2's.
;   Floor 2: its opening leads up to floor 1's, its exit closed; or, when it has
;     no opening, its exit leads up. The boss, balls 2-4 and the stage NPCs are
;     parked off the map (the boss's flank guard reads slot 1's position, so this
;     disables it too); the encounter stands on ball 4's dead end.
; ------------------------------------------------------------
ForestDeepAfterFinalize::
	call FDOpenSRAM
	call FDReadCtrl
	jp nc, FDCloseSRAM                  ; not a deep Forest
	ld b, a
	call FDFloorBit
	and a
	jr nz, .floor2
	bit BIT_FOREST_DEEP_MADE, b
	jr nz, .floor1
	call FDCloseSRAM
	push bc
	farcall FGDeepFindOpening           ; carry = floor 1 has its opening
	pop bc
	push af
	call FDOpenSRAM
	pop af
	jr c, .floor1
	xor a                               ; no way down: ordinary
	call FDWriteCtrl
	ld a, [wOptionalEncounterMap]
	cp PROCEDURAL_FOREST
	jp nz, FDCloseSRAM
	ld a, PROCEDURAL_FOREST_GROTTO
	ld [wOptionalEncounterMap], a
	jp FDCloseSRAM
.floor1
	bit BIT_FOREST_DEEP_HOUSE_2, b
	call nz, FDRemoveHouse
	call FDCloseSRAM
	farjp FGDeepArmOpening              ; over FGArmForestWarp's grotto aim

.floor2
	call .park
	bit BIT_FOREST_DEEP_OPENING_2, b
	jr z, .exitUp
	ld a, $ff                           ; the exit is closed: no warp there
	ld [wWarpEntries + 1 * 4], a
	ld [wWarpEntries + 2 * 4], a
	call FDCloseSRAM
	farjp FGDeepArmOpening
.exitUp
	ld hl, wWarpEntries + 1 * 4 + 2
	ld a, FG_WARP
	ld [hli], a
	ld [hl], PROCEDURAL_FOREST
	ld hl, wWarpEntries + 2 * 4 + 2
	ld a, FOREST_GROTTO_SECOND_WARP
	ld [hli], a
	ld [hl], PROCEDURAL_FOREST
	jp FDCloseSRAM

; SRAM open. Keeps b.
.park
	xor a
FOR n, 1, FOREST_OPTIONAL_MON
	IF n != 2                           ; slot 2 is ball 1, floor 2's ball
		ld [wSprite{02d:n}StateData2MapY], a
		ld [wSprite{02d:n}StateData2MapX], a
	ENDC
ENDR
	ld a, [sProcForestBallXY + 6]       ; ball 4's dead end (sprite coordinates)
	ld [wSprite{02d:FOREST_OPTIONAL_MON}StateData2MapY], a
	ld a, [sProcForestBallXY + 7]
	ld [wSprite{02d:FOREST_OPTIONAL_MON}StateData2MapX], a
	ld a, SPRITE_FACING_DOWN
	ld [wSprite{02d:FOREST_OPTIONAL_MON}StateData1FacingDirection], a
	ld [wSprite{02d:FOREST_OPTIONAL_MON}StateData2OrigFacingDirection], a
	ld a, DOWN
	ld [wMapSpriteData + (FOREST_OPTIONAL_MON - 1) * 2], a
	ret

; The live floor's rest house, if it has one, goes: its two blocks were plain
; trees (PFHouseSiteValid), so they are trees again in the map and the baked
; copy; the site field is cleared, so PFArmHouseDoor disarms the door on every
; later load, and this load's armed door is disarmed here. SRAM open, bank 0.
; Keeps b. Clobbers a/c/de/hl.
FDRemoveHouse:
	ld a, [sProcForestItemGot]
	and FOREST_DEEP_HOUSE_MASK
	ret z
	dec a
	ld e, a                             ; the site index
	ld a, [sProcForestItemGot]
	and ~FOREST_DEEP_HOUSE_MASK & $ff
	ld [sProcForestItemGot], a
	push bc
	ld a, e
	add a
	add a                               ; site * 4 (< 128: sites < 32)
	ld l, a
	ld h, 0
	ld bc, wWarpEntries + FOREST_FIRST_HOUSE_WARP * 4
	add hl, bc
	ld [hl], FOREST_HOUSE_NONE          ; the door's Y: off the map
	ld d, 0
	ld hl, FDHouseSites
	add hl, de
	add hl, de
	ld a, [hli]
	ld b, a                             ; block X
	ld c, [hl]                          ; block Y
	ld hl, wOverworldMap + 81           ; PF_BASE
	ld de, FD_PF_SIZE + 6               ; PF_STRIDE
	call FDBlockAt
	ld a, FOREST_DEEP_TREE
	ld [hli], a
	ld [hl], a
	call FDBakedBlock
	ld a, FOREST_DEEP_TREE
	ld [hli], a
	ld [hl], a
	pop bc
	ret

FDHouseSites:
FOR n, NUM_FOREST_HOUSE_SITES
	db FOREST_HOUSE_SITE_{d:n}_X, FOREST_HOUSE_SITE_{d:n}_Y
ENDR

; The live floor's exit, as PFinalizeForest drew it (sProcForestExitEdge/ExitI:
; N block (2i+1, 0), W (0, 2j+1), E (19, 2j+1) with its floor connector at 18),
; becomes the trees it was carved from, in the baked map (the load blits it).
; SRAM open, bank 0. Clobbers a/bc/de/hl.
FDCloseExit:
	ld a, [sProcForestExitI]
	add a
	inc a
	ld c, a                             ; 2i+1
	ld a, [sProcForestExitEdge]
	and a
	jr nz, .side
	ld b, c                             ; north: (2i+1, 0)
	ld c, 0
	jr .tree
.side
	ld b, 0
	cp 1
	jr z, .tree                         ; west: (0, 2j+1)
	ld b, FD_PF_SIZE - 2                ; east: its connector, then the edge
	call .tree
	ld b, FD_PF_SIZE - 1
.tree
	call FDBakedBlock
	ld [hl], FOREST_DEEP_TREE
	ret

; b/c = block X/Y. Out: hl = that block in the compact baked map. Keeps bc.
FDBakedBlock:
	ld hl, sProcForestStagingBuffer
	ld de, FD_PF_SIZE
	; fall through
; hl = row 0's block 0, de = the row stride, b/c = block X/Y. Out: hl = that
; block. Keeps bc.
FDBlockAt:
	ld a, c
	and a
	jr z, .col
.row
	add hl, de
	dec a
	jr nz, .row
.col
	ld e, b
	ld d, 0
	add hl, de
	ret

; ------------------------------------------------------------
; The flip (the cave's, without its banks: everything is bank 0).
; ------------------------------------------------------------

; In: a = the floor being arrived on (0 = floor 1, 1 = floor 2), for a real warp
; between the floors. Records the floor, swaps ball 1's toggle with its
; off-floor copy, then makes the live copy that floor's. No-op on a Forest that
; is not deep or when already on that floor. Clobbers everything.
ForestDeepFlipTo:
	ld c, a
	push bc
	call FDOpenSRAM
	call FDReadCtrl
	push af
	call FDCloseSRAM
	pop af
	pop bc
	ret nc
	call FDFloorBit
	cp c
	ret z
	ld hl, wRogueFlagsBitfield2
	ld a, [hl]
	xor 1 << BIT_ROGUE_DEEP_FLOOR
	ld [hl], a
	DEF FOREST_DEEP_BALL_MASK EQU 1 << (TOGGLE_WILD_AREA_POKEBALL_1 % 8)
	ld a, [wToggleableObjectFlags + TOGGLE_WILD_AREA_POKEBALL_1 / 8]
	and FOREST_DEEP_BALL_MASK
	ld b, a                             ; nz = this floor's ball 1 is hidden
	ld a, [wStatusFlags2]
	and 1 << BIT_DEEP_OFF_BALL
	jr z, .offShown
	ld a, b
	and a
	jr nz, .live                        ; both hidden
	jr .exchangeBall
.offShown
	ld a, b
	and a
	jr z, .live                         ; both shown
.exchangeBall
	ld hl, wToggleableObjectFlags + TOGGLE_WILD_AREA_POKEBALL_1 / 8
	ld a, [hl]
	xor FOREST_DEEP_BALL_MASK
	ld [hl], a
	ld hl, wStatusFlags2
	ld a, [hl]
	xor 1 << BIT_DEEP_OFF_BALL
	ld [hl], a
.live
	; fall through: the live copy follows the new floor bit

; Every PROCEDURAL_FOREST load, before anything reads the Forest's SRAM
; (ProcBossPatchStageSprite's Forest branch), and the end of every flip. A deep
; Forest whose live copy holds the other floor than the saved bit says (a reset
; without saving) is exchanged back. Never touches WRAM. Clobbers everything.
ForestDeepReconcile::
	call FDOpenSRAM
	call FDReadCtrl
	jp nc, FDCloseSRAM
	and 1 << BIT_FOREST_DEEP_LIVE_2
	ASSERT BIT_FOREST_DEEP_LIVE_2 == 0
	ld c, a
	call FDFloorBit
	cp c
	jp z, FDCloseSRAM
	; fall through, SRAM open

; Exchanges the live Forest with the shadow floor: the 400 B map and the 102 B
; state block, then the control word's LIVE bit. About 25,000 cycles. Touches no
; WRAM. Leaves SRAM closed. Clobbers everything.
ForestDeepExchange:
	ld hl, sProcForestStagingBuffer
	ld de, FOREST_DEEP_SHADOW_MAP
	ld c, FOREST_DEEP_MAP_SIZE / 2
	call FDSwapSpan
	ld c, FOREST_DEEP_MAP_SIZE / 2
	call FDSwapSpan
	ASSERT FOREST_DEEP_MAP_SIZE % 2 == 0 && FOREST_DEEP_MAP_SIZE / 2 < 256
	ld hl, sProcForestExitI
	ld c, FOREST_DEEP_STATE_SIZE        ; de = FOREST_DEEP_SHADOW_STATE already
	ASSERT FOREST_DEEP_SHADOW_STATE == FOREST_DEEP_SHADOW_MAP + FOREST_DEEP_MAP_SIZE
	call FDSwapSpan
	call FDReadCtrl                     ; valid: checked by every caller
	xor 1 << BIT_FOREST_DEEP_LIVE_2
	call FDWriteCtrl
	jp FDCloseSRAM

; hl, de = two bank-0 spans, c = the count (1-255). Out: hl/de past them.
; Clobbers a/b/c.
FDSwapSpan:
	ld a, [de]
	ld b, [hl]
	ld [hli], a
	ld a, b
	ld [de], a
	inc de
	dec c
	jr nz, FDSwapSpan
	ret

; ------------------------------------------------------------
; Helpers. FDReadCtrl/FDWriteCtrl expect SRAM open on bank 0.
; ------------------------------------------------------------

; Out: carry = the control word is valid (a deep Forest), a = the control byte,
; hl = FOREST_DEEP_CTRL.
FDReadCtrl:
	ld hl, FOREST_DEEP_CTRL + 1
	ld a, [hld]
	cpl
	cp [hl]
	jr nz, .invalid
	and FOREST_DEEP_MAGIC_MASK
	cp FOREST_DEEP_MAGIC
	jr nz, .invalid
	ld a, [hl]
	scf
	ret
.invalid
	and a
	ret

; a = the new control byte; writes it and its complement. Clobbers a/hl.
FDWriteCtrl:
	ld hl, FOREST_DEEP_CTRL
	ld [hli], a
	cpl
	ld [hl], a
	ret

; Out: a = 1 when the player is on floor 2, else 0.
FDFloorBit:
	ld a, [wRogueFlagsBitfield2]
	ASSERT BIT_ROGUE_DEEP_FLOOR == 7
	rlca
	and 1
	ret

; Clobbers a only.
FDOpenSRAM:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a
	ret

FDCloseSRAM:
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; ------------------------------------------------------------
; ProcBossPatchStageSprite, every PROCEDURAL_FOREST load, after the boss and
; stage-event pictures and before InitMapSprites (the cave's CaveDeepPatchSprites).
; Slot FOREST_OPTIONAL_MON gets the optional encounter's sheet when it stands
; here (floor 2), else 0. On a deep floor 2 the floor-1 objects it does not use
; (the boss, balls 2-4, the stage NPCs) get picture 0, "this slot does not
; exist", so their toggle bits keep floor 1's state. Clobbers everything.
; ------------------------------------------------------------
ForestDeepPatchSprites::
	farcall OptionalEncounterPatchSprite
	ld a, [wRogueFlagsBitfield2]
	bit BIT_ROGUE_DEEP_FLOOR, a
	ret z                               ; floor 1, or an ordinary forest
	xor a
	ld [wSprite01StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld [wSprite03StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld [wSprite04StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld [wSprite05StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld [wSprite06StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld [wSprite07StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ret
