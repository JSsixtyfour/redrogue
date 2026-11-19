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
	ld d, DEEP_AREA_CAVE
	farcall DeepSaveExternals       ; deep_floor_core.asm
	call CaveDeepBeginDoubleSpeed
	push af
	farcall PCPreloadCave
	pop af
	call CaveDeepEndDoubleSpeed
	ld de, DEEP_AREA_CAVE << 8 | 0   ; group A: all but the wild budget
	farcall DeepRestoreExternals
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

; What PCPreloadCave writes for the whole cave rather than for one floor is
; saved and restored by the shared core (DeepCaveSavedWram, deep_floor_core.asm).

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
	ld a, d                             ; the deep roll's bit 0: a second ball
	and 1 << BIT_CAVE_DEEP_BALLS_2
	ld [CAVE_DEEP_FLAGS], a
	ld a, b
	call CaveDeepWriteCtrl
.done
	call FGCloseSRAM
	farjp CaveDeepPostPass              ; the per-floor half ($15)

; ------------------------------------------------------------
; The flip and its parts (Phase 1).
; ------------------------------------------------------------

; The flip, the reconcile and the exchange are the shared core's
; (deep_floor_core.asm, DeepCaveArea). These keep their names and contracts.

; In: a = the floor being arrived on (0 = floor 1, 1 = floor 2), for a real warp
; between the floors (the arrival seam). Clobbers everything.
CaveDeepFlipTo::
	ld e, a
	ld d, DEEP_AREA_CAVE
	farjp DeepFlipTo

; Every PROCEDURAL_CAVE_1 load, before anything reads the cave's SRAM
; (ProcBossPatchStageSprite's first step). Clobbers everything.
CaveDeepReconcile::
	ld d, DEEP_AREA_CAVE
	farjp DeepReconcile

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
	res BIT_DEEP_OFF_BALL_2, [hl]
	call FGOpenParentSRAM
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld a, CAVE_DEEP_UNDECIDED
	call CaveDeepWriteCtrl
	jp FGCloseSRAM
