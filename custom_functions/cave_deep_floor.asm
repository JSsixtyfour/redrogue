; The cave's optional deep floor (FOLLOWUPS #73, PROCEDURAL_DEEP_FLOOR_PLAN.md).
;
; Floor 2 is PROCEDURAL_CAVE_1 loaded again, with the cave's SRAM state
; exchanged for a shadow copy kept in the Facility's bank-1 section (idle during
; a cave stage: plan Phase 0's canary). The generator never learns about floors.
;
; WHERE EACH PIECE OF FLOOR STATE LIVES, and why:
;   - The map buffer, its CAVESUB_* tail and the 23 B state block: SRAM, live in
;     bank 0, the other floor's in the bank-1 shadow. SRAM is not reverted by a
;     reset, so it can be AHEAD of the save; the control word says which floor
;     the live buffer holds, and every cave load reconciles it with the save.
;   - Which floor the player is on: wRogueFlagsBitfield2 bit 7, saved WRAM.
;   - Toggles: saved WRAM, never in SRAM. Floor 2 removes the floor-1 objects it
;     does not use by picture (PICTUREID 0, the "slot does not exist" rule), so
;     their bits keep floor 1's state. The one bit both floors use is ball 1's;
;     the off-floor's copy is wStatusFlags2 bit 6, swapped on a real flip only.
;     A reset therefore returns every toggle to the save point together with the
;     bag, and reconcile has to fix SRAM alone. (Keeping the off-floor toggles
;     in the SRAM shadow instead was the plan's first idea; it duplicates a ball:
;     take floor 2's, climb, save, descend, reset.)
;
; THE CONTROL WORD (CAVE_DEEP_CTRL, byte and complement): UNDECIDED from the
; lobby preload, then decided on the first floor-1 load: 0 (ordinary) or
; CAVE_DEEP_MAGIC with the LIVE_2 / MADE / SETTLED bits and floor 2's resident.

SECTION "Cave Deep Floor", ROMX, BANK[$26]

	ASSERT BANK(sProcCaveStagingBuffer) == 0
	ASSERT BANK(sProcCaveStagingEntranceY) == 0
	ASSERT BANK(sProcCavePalette) == 0
	ASSERT BANK(sProcFacilityStagingBuffer) == 1
	ASSERT BANK(sProcFacilityGenScratch) == 1
	ASSERT sProcCaveBaked + 1 - sProcCaveStagingEntranceY == CAVE_DEEP_STATE_SIZE
	ASSERT sProcFacilityGenScratch - sProcFacilityStagingBuffer >= 600
	ASSERT sStageEventHideoutFloor + 1 - sProcCavePalette == CAVE_DEEP_SRAM_TAIL
	ASSERT wOptionalEncounterBattle == wOptionalEncounterSpecies + 6

; ------------------------------------------------------------
; The arrival seam: first thing in CaveResolveArrival (every real warp into
; PROCEDURAL_CAVE_1, before parity and before the map loads). A same-map warp
; on a deep cave is a trip between the floors:
;   floor 1, cave warp 0 or 1 (ladders A/B, CaveDeepAfterFinalize) -> floor 2
;   floor 2, cave warp 2 or 3 (its entrance / exit ladders)        -> floor 1
; Any other arrival (the lobby, a battle return, Continue: those never reach
; the seam with this source map) changes nothing. The first descent generates
; floor 2. Clobbers everything; leaves SRAM closed.
; ------------------------------------------------------------
CaveDeepSeam::
	ld a, [wWarpedFromWhichMap]
	cp PROCEDURAL_CAVE_1
	ret nz
	call FGOpenParentSRAM
	call CaveDeepReadCtrl
	push af
	call FGCloseSRAM
	pop af
	ret nc                              ; not a deep cave
	ld b, a                             ; the control byte
	call CaveDeepFloorBit
	ld c, a
	ld a, [wDestinationWarpID]
	bit 0, c
	jr nz, .onFloor2
	cp 2
	ret nc                              ; not one of the ways down
	bit BIT_CAVE_DEEP_MADE, b
	ld a, 1
	jp nz, CaveDeepFlipTo
	call CaveDeepFlipTo                 ; floor 1 to the shadow; the live is stale
	jp CaveDeepGenerateFloor2
.onFloor2
	sub 2
	cp 2
	ret nc                              ; not one of the ways up
	xor a
	jp CaveDeepFlipTo

; ------------------------------------------------------------
; The first descent, from the seam, LCD off, floor 1 already in the shadow:
; build floor 2 in the live buffer with the ordinary preload (its finalize runs
; on the fresh path, as sProcCaveBaked is now 0), keeping everything that
; preload would re-roll for the cave as a whole. Then roll floor 2's resident
; here, not later: its picture has to be known before InitMapSprites.
; Clobbers everything; leaves SRAM closed.
; ------------------------------------------------------------
CaveDeepGenerateFloor2:
	call CaveDeepSaveExternals
	call CaveDeepBeginDoubleSpeed
	push af
	farcall PCPreloadCave
	pop af
	call CaveDeepEndDoubleSpeed
	call CaveDeepRestoreExternals
	call Random                         ; the B1F resident's odds (CaveSubroomPlaceLadders)
	ld b, CAVE_DEEP_GAMBLER << CAVE_DEEP_RESIDENT_SHIFT
	cp CAVESUB_GAMBLER_ODDS
	jr c, .resident
	ld b, CAVE_DEEP_SUPER_NERD << CAVE_DEEP_RESIDENT_SHIFT
	cp CAVESUB_GAMBLER_ODDS + CAVESUB_NERD_ODDS
	jr c, .resident
	ld b, CAVE_DEEP_MANIAC << CAVE_DEEP_RESIDENT_SHIFT
.resident
	call FGOpenParentSRAM
	call CaveDeepReadCtrl               ; a = control, bank 1 selected
	and ~CAVE_DEEP_RESIDENT_MASK & $ff
	or b
	or 1 << BIT_CAVE_DEEP_MADE
	call CaveDeepWriteCtrl
	jp FGCloseSRAM

; What PCPreloadCave writes for the whole cave rather than for one floor (plan
; Phase 0, item 6, and the ResetEvents at the end of PCRollBoss): floor 1's boss,
; the optional encounter, eight events, the wild budget (last: S4 puts it back
; after the fresh finalize), then CAVE_DEEP_SRAM_TAIL bytes of bank 0 from
; sProcCavePalette (the palette, the stage-event hideout and NPC sprites).
CaveDeepSavedWram:
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
	ASSERT (@ - CaveDeepSavedWram) / 2 == CAVE_DEEP_NUM_SAVED_WRAM

CaveDeepSaveExternals:
	call FGOpenParentSRAM
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld hl, CaveDeepSavedWram
	ld de, CAVE_DEEP_SAVE
	ld c, CAVE_DEEP_NUM_SAVED_WRAM
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
	xor a                               ; bank 0 before taking a bank-0 address
	ld [rRAMB], a
	ld hl, sProcCavePalette             ; de = right after the WRAM bytes
	ld c, CAVE_DEEP_SRAM_TAIL
.sram
	xor a
	ld [rRAMB], a
	ld b, [hl]
	inc a
	ld [rRAMB], a
	ld a, b
	ld [de], a
	inc hl
	inc de
	dec c
	jr nz, .sram
	jp FGCloseSRAM

; Puts back all but the wild budget. Clobbers everything; leaves SRAM closed.
CaveDeepRestoreExternals:
	call FGOpenParentSRAM
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld hl, CaveDeepSavedWram
	ld de, CAVE_DEEP_SAVE
	ld c, CAVE_DEEP_NUM_SAVED_WRAM - 1
	ASSERT CAVE_DEEP_SAVED_BUDGET == CAVE_DEEP_NUM_SAVED_WRAM - 1
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
	inc de                              ; past the budget
	xor a                               ; bank 0 before taking a bank-0 address
	ld [rRAMB], a
	ld hl, sProcCavePalette
	ld c, CAVE_DEEP_SRAM_TAIL
.sram
	ld a, 1
	ld [rRAMB], a
	ld a, [de]
	ld b, a
	xor a
	ld [rRAMB], a
	ld a, b
	ld [hli], a
	inc de
	dec c
	jr nz, .sram
	jp FGCloseSRAM

; ProcGenerationBegin/EndDoubleSpeed ($3C) are local to their section, and a
; farcall would lose their a result, so the pair is repeated here.
; Out: a = $ff (nothing to undo) or 0 (switched a CGB to double speed).
CaveDeepBeginDoubleSpeed:
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

CaveDeepEndDoubleSpeed:
	inc a
	ret z
	predef SingleCPUSpeed
	ret

; ------------------------------------------------------------
; ProcStageLoadDispatch, every PROCEDURAL_CAVE_1 load, right after
; PCFinalizeCave. Phase 2 S1: the first load after the lobby decides whether
; this cave is deep. (S4's per-floor post-pass follows here.)
; Clobbers everything; leaves SRAM closed.
; ------------------------------------------------------------
CaveDeepAfterFinalize::
	call FGOpenParentSRAM
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld hl, CAVE_DEEP_CTRL
	ld a, [hli]
	cp CAVE_DEEP_UNDECIDED
	jr nz, .done
	ld a, [hl]
	cp CAVE_DEEP_UNDECIDED ^ $ff
	jr nz, .done
	call FGCloseSRAM
	call Random                         ; before SRAM opens again: rolled every cave
	ld d, a
	call FGOpenParentSRAM               ; bank 0
	ld b, 0                             ; an ordinary cave
IF !CAVE_DEEP_ENABLED
	jr .decide                          ; not switched on yet (see the constant)
ENDC
	ld a, [CAVESUB_LADDER_A]
	cp CAVESUB_DYN_LADDER_1
	jr nz, .decide
	ld a, [CAVESUB_LADDER_B]
	cp CAVESUB_DYN_LADDER_2
	jr nz, .decide                      ; two real ladders, or no floor 2
IF DEF(_DEBUG)
	ld a, [wStatusFlags6]
	bit BIT_DEBUG2_MODE, a
	jr nz, .deep                        ; Debug 2: every cave that can be is
ENDC
	ld a, d
	cp CAVE_DEEP_ODDS
	jr nc, .decide
.deep
	ld b, CAVE_DEEP_MAGIC
	; Floor 2 is the B1F now: an encounter assigned to the premade one (the
	; cold cave's Onix or Snorlax) stands on floor 2 instead.
	ld a, [wOptionalEncounterMap]
	cp PROCEDURAL_CAVE_SUBROOM
	jr nz, .decide
	ld a, PROCEDURAL_CAVE_1
	ld [wOptionalEncounterMap], a
.decide
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld a, b
	call CaveDeepWriteCtrl
.done
	call FGCloseSRAM
	farjp CaveDeepPostPass              ; the per-floor half ($15)

; ------------------------------------------------------------
; The flip and its parts (Phase 1).
; ------------------------------------------------------------

; In: a = the floor being arrived on (0 = floor 1, 1 = floor 2), for a real warp
; between the floors (the arrival seam). Records the floor, swaps ball 1's
; toggle with its off-floor copy, then makes the live buffer that floor's.
; No-op on a cave that is not deep or when already on that floor.
; Clobbers everything.
CaveDeepFlipTo::
	ld c, a
	push bc
	call FGOpenParentSRAM
	call CaveDeepReadCtrl
	push af
	call FGCloseSRAM
	pop af
	pop bc
	ret nc                              ; not a deep cave
	call CaveDeepFloorBit
	cp c
	ret z
	ld hl, wRogueFlagsBitfield2
	ld a, [hl]
	xor 1 << BIT_ROGUE_DEEP_FLOOR
	ld [hl], a
	; Ball 1: exchange this floor's toggle bit with the off-floor copy, i.e.
	; flip both when they differ.
	DEF CAVE_DEEP_BALL_MASK EQU 1 << (TOGGLE_WILD_AREA_POKEBALL_1 % 8)
	ld a, [wToggleableObjectFlags + TOGGLE_WILD_AREA_POKEBALL_1 / 8]
	and CAVE_DEEP_BALL_MASK
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
	xor CAVE_DEEP_BALL_MASK
	ld [hl], a
	ld hl, wStatusFlags2
	ld a, [hl]
	xor 1 << BIT_DEEP_OFF_BALL
	ld [hl], a
.live
	; fall through: the live buffer follows the new floor bit

; Every PROCEDURAL_CAVE_1 load, before anything reads the cave's SRAM
; (ProcBossPatchStageSprite's first step), and the end of every flip. A deep
; cave whose live buffer holds the other floor than the saved floor bit says
; (a reset without saving) is exchanged back. Never touches WRAM: WRAM is the
; save, and the save is right. Clobbers everything.
CaveDeepReconcile::
	call FGOpenParentSRAM
	call CaveDeepReadCtrl
	push af
	call FGCloseSRAM
	pop af
	ret nc                              ; not a deep cave
	and 1 << BIT_CAVE_DEEP_LIVE_2
	ASSERT BIT_CAVE_DEEP_LIVE_2 == 0
	ld c, a                             ; the floor the live buffer holds
	call CaveDeepFloorBit
	cp c
	ret z
	; fall through

; Exchanges the live cave (SRAM bank 0) with the shadow floor (bank 1): the
; 600 B map buffer with its CAVESUB_* tail, the 23 B state block, and the
; control word's LIVE bit. About 50,000 cycles (under a frame); runs only
; inside a map load. Touches no WRAM. Leaves SRAM closed. Clobbers everything.
CaveDeepExchange:
	call FGOpenParentSRAM
	ld hl, sProcCaveStagingBuffer
	ld de, CAVE_DEEP_SHADOW_MAP
	ld b, 3
.chunk
	push bc
	ld c, 200
	call CaveDeepSwapSpan
	pop bc
	dec b
	jr nz, .chunk
	ld hl, sProcCaveStagingEntranceY
	ld de, CAVE_DEEP_SHADOW_STATE
	ld c, CAVE_DEEP_STATE_SIZE
	call CaveDeepSwapSpan
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld a, [CAVE_DEEP_CTRL]
	xor 1 << BIT_CAVE_DEEP_LIVE_2
	call CaveDeepWriteCtrl
	jp FGCloseSRAM

; hl = a bank-0 address, de = a bank-1 address, c = the byte count (1-255).
; SRAM open in advanced mode. Out: hl/de past the span, bank 0 selected.
; Clobbers a/b/c.
CaveDeepSwapSpan:
.loop
	xor a
	ld [rRAMB], a
	ld b, [hl]                          ; live
	inc a                               ; the shadow's bank, 1
	ld [rRAMB], a
	ld a, [de]                          ; shadow
	push af
	ld a, b
	ld [de], a                          ; shadow <- live
	xor a
	ld [rRAMB], a
	pop af
	ld [hli], a                         ; live <- shadow
	inc de
	dec c
	jr nz, .loop
	ret

; Out: carry = the control word is valid (a deep cave), a = the control byte,
; hl = CAVE_DEEP_CTRL. SRAM open (advanced mode); leaves bank 1 selected.
CaveDeepReadCtrl:
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld hl, CAVE_DEEP_CTRL + 1
	ld a, [hld]
	cpl
	cp [hl]
	jr nz, .invalid
	and CAVE_DEEP_MAGIC_MASK
	cp CAVE_DEEP_MAGIC
	jr nz, .invalid
	ld a, [hl]
	scf
	ret
.invalid
	and a
	ret

; a = the new control byte; writes it and its complement. SRAM open, bank 1
; selected. Clobbers a/hl.
CaveDeepWriteCtrl:
	ld hl, CAVE_DEEP_CTRL
	ld [hli], a
	cpl
	ld [hl], a
	ret

; Out: a = 1 when the player is on floor 2, else 0. Clobbers nothing else.
CaveDeepFloorBit:
	ld a, [wRogueFlagsBitfield2]
	ASSERT BIT_ROGUE_DEEP_FLOOR == 7
	rlca
	and 1
	ret

; ProcPreloadAssignedWildArea, right after a cave's PCPreloadCave (the lobby and
; the door dice both preload through it): a new cave starts on floor 1 with
; floor 2's ball shown, and undecided. Never after a Facility preload: its
; generation scratch holds room records.
CaveDeepLobbyReset::
	ld hl, wRogueFlagsBitfield2
	res BIT_ROGUE_DEEP_FLOOR, [hl]
	ld hl, wStatusFlags2
	res BIT_DEEP_OFF_BALL, [hl]
	call FGOpenParentSRAM
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld a, CAVE_DEEP_UNDECIDED
	call CaveDeepWriteCtrl
	jp FGCloseSRAM
