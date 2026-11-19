; The deep floors' shared core (PROCEDURAL_DEEP_FLOOR_PLAN.md, Facility SPEC D0).
;
; A deep floor is its area's map loaded again with the area's SRAM state
; exchanged for a shadow copy kept in another area's idle buffer. What is the
; same in every area lives here, driven by one descriptor per area: the control
; word, the floor bit, the off-floor ball, the exchange of the live state with
; the shadow, and saving and restoring what a floor-2 generation would rewrite
; for the area as a whole. Each area keeps its own decision, seam, first
; descent, post-pass and sprite patch (cave_deep_floor*.asm, forest_deep_floor.asm).
;
; CALLING: every entry is farcalled with d = the area id (DEEP_AREA_*) and, where
; stated, an argument in e. Bankswitch passes d/e in and h/l/d/e and the carry
; flag back; a/b/c do not survive it. Every entry leaves SRAM closed.
;
; 600 B with its descriptors and lists. $34, beside the Forest's module: moving
; the Forest's and the cave's generic code here left $34 with 730 B free
; (2026-11-19), so the core fits with room for the Facility's descriptor, and
; $14 (622 B) stays whole for the Facility's own module. Nothing here calls
; another ROMX bank.
SECTION "Deep Floor Core", ROMX, BANK[$34]

	ASSERT BANK(sProcCavePalette) == 0
	ASSERT sStageEventHideoutFloor + 1 - sProcCavePalette == DEEP_SRAM_TAIL
	ASSERT CAVE_DEEP_SRAM_TAIL == DEEP_SRAM_TAIL
	ASSERT FOREST_DEEP_SRAM_TAIL == DEEP_SRAM_TAIL
	ASSERT CAVE_DEEP_MAGIC_MASK == DEEP_MAGIC_MASK
	ASSERT FOREST_DEEP_MAGIC_MASK == DEEP_MAGIC_MASK
	ASSERT BIT_CAVE_DEEP_LIVE_2 == BIT_DEEP_LIVE_2
	ASSERT BIT_FOREST_DEEP_LIVE_2 == BIT_DEEP_LIVE_2

; ------------------------------------------------------------
; The descriptor. A group is a list of WRAM addresses (in this bank), how many,
; and where in the save area their bytes go. Group A is always restored, group
; B only when asked (the cave's wild budget: never; the Forest's rest-house
; part: when the house is on floor 1). The SRAM tail follows them in the save.
; A span is a run of up to 255 bytes: its two banks (low nibble the live
; copy's, high nibble the shadow's), its length, the shadow, the live copy.
; ------------------------------------------------------------
RSRESET
DEF DEEP_CTRL       RW 1
DEF DEEP_CTRL_BANK  RB 1
DEF DEEP_MAGIC      RB 1
DEF DEEP_SAVE_BANK  RB 1
DEF DEEP_GROUP_A    RB 5
DEF DEEP_GROUP_B    RB 5
DEF DEEP_TAIL_SAVE  RW 1
DEF DEEP_NUM_SPANS  RB 1
DEF DEEP_SPANS      RB 0

MACRO deep_group ; list, count, save address
	dw \1
	db \2
	dw \3
ENDM

MACRO deep_span ; banks, length, shadow, live
	db \1, \2
	dw \3, \4
ENDM

DeepAreaTable:
	dw DeepCaveArea
	dw DeepForestArea
	dw DeepFacilityArea
	ASSERT (@ - DeepAreaTable) / 2 == NUM_DEEP_AREAS

; The cave: live in bank 0, the shadow and the control word in the Facility's
; idle bank-1 section (constants/cave_ladder_site_constants.asm).
DeepCaveArea:
	dw CAVE_DEEP_CTRL
	db BANK(sProcFacilityGenScratch), CAVE_DEEP_MAGIC
	db BANK(sProcFacilityGenScratch)
	deep_group DeepCaveSavedWram, CAVE_DEEP_SAVED_BUDGET, CAVE_DEEP_SAVE
	deep_group DeepCaveSavedWram + 2 * CAVE_DEEP_SAVED_BUDGET, 1, \
		CAVE_DEEP_SAVE + CAVE_DEEP_SAVED_BUDGET
	dw CAVE_DEEP_SAVE + CAVE_DEEP_NUM_SAVED_WRAM
	db 4
FOR n, 3
	deep_span $10, 200, CAVE_DEEP_SHADOW_MAP + n * 200, sProcCaveStagingBuffer + n * 200
ENDR
	deep_span $10, CAVE_DEEP_STATE_SIZE, CAVE_DEEP_SHADOW_STATE, sProcCaveStagingEntranceY
	ASSERT CAVE_DEEP_SAVED_BUDGET == CAVE_DEEP_NUM_SAVED_WRAM - 1
	ASSERT BANK(sProcCaveStagingBuffer) == 0 && BANK(sProcCaveStagingEntranceY) == 0
	ASSERT BANK(sProcFacilityStagingBuffer) == 1 && BANK(sProcFacilityGenScratch) == 1

; The Forest: everything in bank 0, the shadow and the control word in the
; cave's idle buffer (constants/forest_deep_constants.asm).
DeepForestArea:
	dw FOREST_DEEP_CTRL
	db 0, FOREST_DEEP_MAGIC
	db 0
	deep_group DeepForestSavedWram, FOREST_DEEP_NUM_ALWAYS, FOREST_DEEP_SAVE
	deep_group DeepForestSavedWram + 2 * FOREST_DEEP_NUM_ALWAYS, \
		FOREST_DEEP_NUM_SAVED_WRAM - FOREST_DEEP_NUM_ALWAYS, FOREST_DEEP_SAVE + FOREST_DEEP_NUM_ALWAYS
	dw FOREST_DEEP_SAVE + FOREST_DEEP_NUM_SAVED_WRAM
	db 3
FOR n, 2
	deep_span $00, 200, FOREST_DEEP_SHADOW_MAP + n * 200, sProcForestStagingBuffer + n * 200
ENDR
	deep_span $00, FOREST_DEEP_STATE_SIZE, FOREST_DEEP_SHADOW_STATE, sProcForestExitI
	ASSERT FOREST_DEEP_MAP_SIZE == 2 * 200
	ASSERT BANK(sProcForestStagingBuffer) == 0 && BANK(sProcForestExitI) == 0
	ASSERT BANK(sProcCaveStagingBuffer) == 0

; The Facility: live in bank 1, the shadow in two idle bank-0 buffers (the
; cave's map buffer, the Forest's state block), the control word and the save in
; the Forest's map (constants/facility_deep_constants.asm). No group B.
DeepFacilityArea:
	dw FACILITY_DEEP_CTRL
	db 0, FACILITY_DEEP_MAGIC
	db 0
	deep_group DeepFacilitySavedWram, FACILITY_DEEP_NUM_SAVED_WRAM, FACILITY_DEEP_SAVE
	deep_group DeepFacilitySavedWram, 0, FACILITY_DEEP_SAVE + FACILITY_DEEP_NUM_SAVED_WRAM
	dw FACILITY_DEEP_SAVE + FACILITY_DEEP_NUM_SAVED_WRAM
	db 4
FOR n, 3
	deep_span $01, 200, FACILITY_DEEP_SHADOW_MAP + n * 200, sProcFacilityStagingBuffer + n * 200
ENDR
	deep_span $01, FACILITY_DEEP_STATE_SIZE, FACILITY_DEEP_SHADOW_STATE, sProcFacilityExitI
	ASSERT FACILITY_DEEP_MAP_SIZE == 3 * 200
	ASSERT sProcFacilityExitI - sProcFacilityStagingBuffer >= FACILITY_DEEP_MAP_SIZE
	ASSERT sProcFacilityGenScratch + 81 - sProcFacilityExitI == FACILITY_DEEP_STATE_SIZE
	ASSERT sProcCavePalette - sProcForestExitI == FACILITY_DEEP_STATE_SIZE ; the Forest's block fits it exactly
	ASSERT BANK(sProcFacilityExitI) == 1 && BANK(sProcCaveStagingBuffer) == 0

; What floor 2's fresh PFacFinalize rewrites for the Facility as a whole
; (measured, probe_facility_deep_finalize_diff.py): the wild budget it refills,
; the lobby's door choice, the stage event its restage may disarm. Not
; wRogueItem..+6: PFacFinalize copies the live floor's ball items there on every load.
DeepFacilitySavedWram:
	dw wProcFacilityWildBudget
	dw wRogueDoorSelection
	dw wStageEvent
	ASSERT (@ - DeepFacilitySavedWram) / 2 == FACILITY_DEEP_NUM_SAVED_WRAM

; What PCPreloadCave writes for the whole cave rather than for one floor (plan
; Phase 0, item 6, and the ResetEvents at the end of PCRollBoss): floor 1's boss,
; the optional encounter, eight events, then the wild budget (group B: never
; restored here, S4 puts it back after the fresh finalize).
DeepCaveSavedWram:
	dw wRoguePokemon1, wRoguePokemonForm1
FOR n, 7
	dw wOptionalEncounterSpecies + n
ENDR
	dw wEventFlags + EVENT_BEAT_PC_BOSS / 8
	dw wEventFlags + EVENT_BEAT_STAGE_EVENT_NPC_1 / 8
	dw wEventFlags + EVENT_BEAT_STAGE_EVENT_NPC_2 / 8
	dw wEventFlags + EVENT_BEAT_FACILITY_STAGE_NPC_1 / 8
	dw wEventFlags + EVENT_BEAT_FACILITY_STAGE_NPC_2 / 8
	dw wEventFlags + EVENT_PC_BOSS_OFFERED / 8
	dw wEventFlags + EVENT_PC_BUDGET_ENDED / 8
	dw wEventFlags + EVENT_PC_CALMED_SHOWN / 8
	dw wProcCaveWildBudget
	ASSERT (@ - DeepCaveSavedWram) / 2 == CAVE_DEEP_NUM_SAVED_WRAM
	ASSERT wOptionalEncounterBattle == wOptionalEncounterSpecies + 6

; What floor 2's PFinalizeForest rewrites for the Forest as a whole (Forest
; Phase 0, item 6). The "always" part, then the rest house's lobby offers and
; residents, which come back only when the house is on floor 1 (on floor 2 its
; own generation rolls the house's offers, once).
DeepForestSavedWram:
	dw wRoguePokemon1, wRoguePokemonForm1, wStageEvent, wProcForestWildBudget
	ASSERT (@ - DeepForestSavedWram) / 2 == FOREST_DEEP_NUM_ALWAYS
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
	ASSERT (@ - DeepForestSavedWram) / 2 == FOREST_DEEP_NUM_SAVED_WRAM

; ------------------------------------------------------------
; The flip. d = the area, e = the floor being arrived on (0 = floor 1,
; 1 = floor 2), for a real warp between the floors. Records the floor, swaps
; ball 1's toggle with its off-floor copy, then makes the live copy that floor's.
; No-op when the area is not deep or the player is already on that floor.
; Clobbers everything.
; ------------------------------------------------------------
DeepFlipTo::
	push de
	call DeepCtrlOpen
	push af
	call DeepCloseSRAM
	pop af
	pop de
	ret nc                              ; not deep
	call DeepFloorBit
	cp e
	ret z
	ld hl, wRogueFlagsBitfield2
	ld a, [hl]
	xor 1 << BIT_ROGUE_DEEP_FLOOR
	ld [hl], a
	; Balls 1 and 2: exchange this floor's toggle bit with its off-floor copy.
	; Ball 2 always, even where floor 2 keeps one ball: there its slot has
	; picture 0, so its bit is floor 2's own and floor 1's comes back intact.
	ld b, 1 << (TOGGLE_WILD_AREA_POKEBALL_1 % 8)
	ld c, 1 << BIT_DEEP_OFF_BALL
	call DeepExchangeBall
	ld b, 1 << (TOGGLE_WILD_AREA_POKEBALL_2 % 8)
	ld c, 1 << BIT_DEEP_OFF_BALL_2
	call DeepExchangeBall
	ASSERT TOGGLE_WILD_AREA_POKEBALL_1 / 8 == TOGGLE_WILD_AREA_POKEBALL_2 / 8
	; fall through: the live copy follows the new floor bit

; d = the area. Every load of the area's map, before anything reads its SRAM,
; and the end of every flip: a deep area whose live copy holds the other floor
; than the saved floor bit says (a reset without saving) is exchanged back.
; Never touches WRAM: WRAM is the save, and the save is right.
; Clobbers everything.
DeepReconcile::
	push de
	call DeepCtrlOpen
	pop de
	jr nc, DeepCloseSRAM                ; not deep
	and 1 << BIT_DEEP_LIVE_2
	ASSERT BIT_DEEP_LIVE_2 == 0
	ld c, a                             ; the floor the live copy holds
	call DeepFloorBit
	cp c
	jr z, DeepCloseSRAM
	; fall through

; d = the area. Exchanges the live state with the shadow, span by span, then
; the control word's LIVE bit. Under a frame on every area. Touches no WRAM.
; Clobbers everything.
DeepExchange:
	push de
	call DeepArea
	ld bc, DEEP_NUM_SPANS
	add hl, bc
	call DeepOpenSRAM
	ld a, [hli]
.span
	push af                             ; spans left
	ld a, [hli]
	ld b, a                             ; the banks
	ld a, [hli]
	ld c, a                             ; the length
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a                             ; de = the shadow
	ld a, [hli]                         ; the live copy's low byte
	push hl                             ; -> its high byte
	ld h, [hl]
	ld l, a
	call DeepSwapSpan
	pop hl
	inc hl                              ; the next span
	pop af
	dec a
	jr nz, .span
	pop de
	call DeepCtrlOpen                   ; valid: every caller checked it
	xor 1 << BIT_DEEP_LIVE_2
	ld [hli], a
	cpl
	ld [hl], a
	; fall through

DeepCloseSRAM:
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; hl = the live span, de = the shadow, c = the length (1-255), b = the banks
; (low nibble the live copy's, high nibble the shadow's). SRAM open in advanced
; mode. Both banks and the count wait on the stack while b and c carry bytes.
; Out: hl/de past the span. Clobbers a/b/c.
DeepSwapSpan:
	push bc
.loop
	pop bc
	push bc
	ld a, b
	and $0f
	ld [rRAMB], a                       ; the live bank
	ld c, [hl]                          ; the live byte
	ld a, b
	swap a
	and $0f
	ld [rRAMB], a                       ; the shadow bank
	ld a, [de]
	ld b, a                             ; the shadow byte
	ld a, c
	ld [de], a                          ; shadow <- live
	ld a, b
	pop bc
	push af
	ld a, b
	and $0f
	ld [rRAMB], a                       ; the live bank
	pop af
	ld [hli], a                         ; live <- shadow
	inc de
	dec c
	push bc
	jr nz, .loop
	pop bc
	ret

; ------------------------------------------------------------
; Externals: what a floor-2 generation would rewrite for the area as a whole.
; ------------------------------------------------------------

; d = the area. Saves both groups and the SRAM tail. Clobbers everything.
DeepSaveExternals::
	call DeepArea
	call DeepOpenSave
	push hl
	ld bc, DEEP_GROUP_A
	call DeepGroupAt
	call DeepSaveList
	pop hl
	push hl
	ld bc, DEEP_GROUP_B
	call DeepGroupAt
	call DeepSaveList
	pop hl
	call DeepTailAt                     ; de = the tail's save, a = the save bank
	swap a                              ; the copy goes bank 0 -> the save's bank
	ld b, a
	ld hl, sProcCavePalette
	ld c, DEEP_SRAM_TAIL
	call DeepCopySpan
	jp DeepCloseSRAM

; d = the area, e = 1 to restore group B too, 0 for group A only. Puts the
; groups back, then the SRAM tail. Clobbers everything.
DeepRestoreExternals::
	push de
	call DeepArea
	call DeepOpenSave
	push hl
	ld bc, DEEP_GROUP_A
	call DeepGroupAt
	call DeepRestoreList
	pop hl
	pop de
	push hl
	bit 0, e
	jr z, .tail
	ld bc, DEEP_GROUP_B
	call DeepGroupAt
	call DeepRestoreList
.tail
	pop hl
	call DeepTailAt                     ; de = the tail's save, a = the save bank
	ld b, a                             ; the copy goes the save's bank -> bank 0
	ld h, d
	ld l, e
	ld de, sProcCavePalette
	ld c, DEEP_SRAM_TAIL
	call DeepCopySpan
	jp DeepCloseSRAM

; hl = a descriptor. Opens SRAM on the save's bank. Keeps hl. Clobbers a/bc.
DeepOpenSave:
	call DeepOpenSRAM
	push hl
	ld bc, DEEP_SAVE_BANK
	add hl, bc
	ld a, [hl]
	pop hl
	ld [rRAMB], a
	ret

; hl = a descriptor, bc = a group's offset. Out: hl = its list, c = how many,
; de = where their bytes go. Clobbers a/b.
DeepGroupAt:
	add hl, bc
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a                             ; de = the list
	ld c, [hl]
	inc hl
	ld a, [hli]
	ld h, [hl]
	ld l, a                             ; hl = the save
	push hl
	ld h, d
	ld l, e
	pop de
	ret

; hl = a descriptor. Out: de = the tail's save address, a = the save's bank.
; Clobbers hl/bc.
DeepTailAt:
	push hl
	ld bc, DEEP_TAIL_SAVE
	add hl, bc
	ld a, [hli]
	ld e, a
	ld d, [hl]
	pop hl
	ld bc, DEEP_SAVE_BANK
	add hl, bc
	ld a, [hl]
	ret

; hl = a list of WRAM addresses, c = how many (0 = none), de = the save, its
; bank selected. Copies each byte into the save. Clobbers a/c/hl/de.
DeepSaveList:
	ld a, c
	and a
	ret z
.loop
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
	jr nz, .loop
	ret

; As DeepSaveList, the other way: each saved byte back to its WRAM address.
DeepRestoreList:
	ld a, c
	and a
	ret z
.loop
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
	jr nz, .loop
	ret

; hl = the source, de = the destination, c = the length (1-255), b = the banks
; (low nibble the source's, high nibble the destination's). SRAM open in
; advanced mode. Clobbers a/c/hl/de.
DeepCopySpan:
	ld a, b
	and $0f
	ld [rRAMB], a
	ld a, [hli]
	push af
	ld a, b
	swap a
	and $0f
	ld [rRAMB], a
	pop af
	ld [de], a
	inc de
	dec c
	jr nz, DeepCopySpan
	ret

; ------------------------------------------------------------
; Helpers.
; ------------------------------------------------------------

; b = a ball's mask in its toggle byte, c = its off-floor bit's mask in
; wStatusFlags2. Flips both when they differ (one floor's ball shown, the
; other's hidden). Keeps d. Clobbers a/e/hl.
DeepExchangeBall:
	ld hl, wToggleableObjectFlags + TOGGLE_WILD_AREA_POKEBALL_1 / 8
	ld a, [hl]
	and b
	jr z, .toggleShown
	ld a, $ff
.toggleShown
	ld e, a                             ; 0 = this floor's ball is shown
	ld a, [wStatusFlags2]
	and c
	jr z, .offShown
	ld a, $ff
.offShown
	xor e
	ret z                               ; both shown, or both hidden
	ld a, [hl]
	xor b
	ld [hl], a
	ld hl, wStatusFlags2
	ld a, [hl]
	xor c
	ld [hl], a
	ret

; d = the area. Out: hl = its descriptor. Clobbers a/bc.
DeepArea:
	ld a, d
	add a
	ld c, a
	ld b, 0
	ld hl, DeepAreaTable
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret

; d = the area. Opens SRAM on the control word's bank. Out: carry = valid (a
; deep area), a = the control byte, hl = the control word. Clobbers bc/e.
DeepCtrlOpen:
	call DeepArea
	ld a, [hli]
	ld c, a
	ld a, [hli]
	ld b, a                             ; bc = the control word
	ld a, [hli]                         ; its bank
	ld e, [hl]                          ; the magic
	push af
	call DeepOpenSRAM
	pop af
	ld [rRAMB], a
	ld h, b
	ld l, c
	ld a, [hli]
	cpl
	cp [hl]
	dec hl                              ; keeps the flags
	jr nz, .invalid
	ld a, [hl]
	and DEEP_MAGIC_MASK
	cp e
	jr nz, .invalid
	ld a, [hl]
	scf
	ret
.invalid
	and a
	ret

; Out: a = 1 when the player is on floor 2, else 0. Clobbers nothing else.
DeepFloorBit:
	ld a, [wRogueFlagsBitfield2]
	ASSERT BIT_ROGUE_DEEP_FLOOR == 7
	rlca
	and 1
	ret

; Clobbers a only.
DeepOpenSRAM:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ret
