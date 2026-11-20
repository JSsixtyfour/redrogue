; The Cemetery's two extra floors (PROCEDURAL_DEEP_FLOOR_PLAN.md, Cemetery SPEC
; C0-C6). Later in a run (round 5 on) the chain is 1, 2, 3, 2b, 3b, 4: the same
; stairs, the same four maps, with maps 2 and 3 each hosting an "a" and a "b"
; state. A "b" state is made by the Cemetery's own lazy generation: the
; exchange puts the "a" floor's state in a shadow (the cave's idle buffer,
; constants/cemetery_deep_constants.asm) with its ready bit clear, and the
; unchanged PCemFinalizeMap generates the fresh floor. Nothing in $05 changes.
;
; STATE: the shadow and the control word in SRAM, and one saved WRAM bit,
; wRogueFlagsBitfield2's BIT_ROGUE_DEEP_FLOOR, which in a Cemetery means "the
; player is on a b leg" (2b or 3b). The seam sets the bit on every stair; the
; reconcile makes the live maps follow it on every load, Continue included, so
; a reset without saving repairs itself (the bit is the save).
;
; ROUTING: two stairs are retargeted. 3a's east stair leads to map 2's east
; stair (2b), and 2b's east stair leads to map 3's east stair (3a). Every
; other stair keeps its target, and the seam reads which leg it lands on from
; the source map, the source warp and the source leg.
;
; $28 (2,174 B free, 2026-11-19). Every entry is farcalled.
SECTION "Cemetery Deep Floor", ROMX, BANK[$28]

	ASSERT BANK(sProcCaveStagingBuffer) == 0
	ASSERT BANK(sProcCemeteryMaps) == 0
	ASSERT BANK(sStageEventHideoutFloor) == 0
	ASSERT BIT_ROGUE_DEEP_FLOOR == 7
	ASSERT 1 << BIT_CEM_DEEP_LIVE_2B == 1 && 1 << BIT_CEM_DEEP_LIVE_3B == 2
	ASSERT 1 << BIT_CEM_SHADOW_READY_2 == 1 && 1 << BIT_CEM_SHADOW_READY_3 == 2
	ASSERT 1 << BIT_CEM_SHADOW_GOT_2 == 4 && 1 << BIT_CEM_SHADOW_GOT_3 == 8

; ------------------------------------------------------------
; The two stage-hook entries ($3C has no room for more calls, so its existing
; ones lead here). The preload: PCemGenerateMaps, then the decision. Every
; Cemetery load: the reconcile, PCemFinalizeMap, then the retargets.
; ------------------------------------------------------------
CemDeepGenerateMaps::
	farcall PCemGenerateMaps
	call CemDeepLobbyDecide
	jp CemResurrectorRoll               ; after the decision: his roll reads it

CemDeepFinalizeMap::
	call CemDeepReconcile
	farcall PCemFinalizeMap
	call CemResurrectorPlace            ; after the Channeler's placement
	jp CemDeepAfterFinalize

; ------------------------------------------------------------
; C1. The decision: ProcPreloadAssignedWildArea's .cemetery, after
; PCemGenerateMaps. A new Cemetery starts on floor 1, on no b leg. Deep from
; round 5: both b floors ungenerated, their balls untaken, the Channeler and the
; hideout re-rolled over the six floors. Clobbers everything; SRAM closed.
; ------------------------------------------------------------
CemDeepLobbyDecide::
	ld hl, wRogueFlagsBitfield2
	res BIT_ROGUE_DEEP_FLOOR, [hl]
	ld hl, wOptionalEncounterState
	res BIT_OPTIONAL_ON_FLOOR_2, [hl]
	ld b, 0
	call GetRunProgress                 ; the wild budget's own measure of the run
	cp CEM_DEEP_MIN_PROGRESS
	jr c, .decided
	inc b
.decided
	; b = 1 deep, 0 ordinary. The PyBoy harness forces 0 here unless a test
	; asks for a deep Cemetery (harness.py, allow_deep_cemetery_floor).
	call CDOpenSRAM
	ld hl, CEM_DEEP_CTRL
	dec b
	jr z, .deep
	xor a
	ld [hli], a
	cpl
	ld [hl], a
	jp CDCloseSRAM
.deep
	ld a, CEM_DEEP_MAGIC
	ld [hli], a
	cpl
	ld [hli], a
	; The b floors' balls, as the other areas' floor 2 (1 or 2 extra balls): on
	; a coin both keep theirs, otherwise one of the two (another coin) has none.
	; "None" is its ball already collected: the shadow's ItemGot bit, which the
	; exchange hands the floor on its first visit (generation never clears it).
	push hl
	call Random
	pop hl
	ld c, 0                             ; both b floors keep a ball
	rrca
	jr c, .balls
	ld c, 1 << BIT_CEM_SHADOW_GOT_2     ; 2b has none
	rrca
	jr c, .balls
	ld c, 1 << BIT_CEM_SHADOW_GOT_3     ; 3b has none
.balls
	; c = the b floors' starting shadow bits. Tests force it here
	; (test_cemetery_deep_floor.py, force_balls).
	ld a, c
	ld [hli], a                         ; CEM_DEEP_SHADOW_BITS
	ASSERT CEM_DEEP_SHADOW_BITS + 1 == CEM_DEEP_CHAN_ORD
	ld c, CEM_DEEP_NUM_ORDINALS
	call Rangerandom
	ld [hli], a                         ; CEM_DEEP_CHAN_ORD: 0-5
	ASSERT CEM_DEEP_CHAN_ORD + 1 == CEM_DEEP_HIDE_ORD
	ld a, [sStageEventHideoutFloor]
	cp STAGE_EVENT_NO_HIDEOUT
	jr z, .hideout                      ; nothing to hide: stays NO_HIDEOUT
	ld c, CEM_DEEP_NUM_ORDINALS - 1
	call Rangerandom
	inc a                               ; 1-5: never floor 1, as the ordinary roll
.hideout
	ld [hl], a                          ; CEM_DEEP_HIDE_ORD
	; C5 is moot: the Cemetery never rolls an optional encounter (no
	; OptionalCemetery* assigner; wOptionalEncounterMap is never a Cemetery map),
	; so there is nothing to move onto a b leg.
	jp CDCloseSRAM

; ------------------------------------------------------------
; C2. The seam: FGResolveArrival, every warp arrival, hCurMap the destination.
; Sets the floor bit to the leg the player arrives on, from the source map,
; the source warp and the source leg (the bit as it stands). Floor 1 and 4 are
; never a b leg. Not a Cemetery, or not deep: nothing. Clobbers everything.
;   dest 2: b iff the source is map 3 and (leg XOR warp) is 1: 3a's east
;           stair (warp 1, retargeted) or 3b's west stair (warp 0)
;   dest 3: b iff the source is map 4, or 2b's west stair (warp 1); 2b's east
;           stair (warp 0, retargeted) is 3a's
; ------------------------------------------------------------
CemDeepSeam::
	call CDCemeteryMap
	ret nc
	call CDCtrl
	push af
	call CDCloseSRAM
	pop af
	ret nc                              ; not deep
	ld hl, wRogueFlagsBitfield2
	ld b, 0                             ; the new bit
	ldh a, [hCurMap]
	cp PROCEDURAL_CEMETERY_2
	jr z, .dest2
	cp PROCEDURAL_CEMETERY_3
	jr nz, .write                       ; floor 1 or 4
	ld a, [wWarpedFromWhichMap]
	cp PROCEDURAL_CEMETERY_4
	jr z, .legB
	cp PROCEDURAL_CEMETERY_2
	jr nz, .write
	bit BIT_ROGUE_DEEP_FLOOR, [hl]
	jr z, .write                        ; from 2a: 3a
	ld a, [wWarpedFromWhichWarp]
	dec a
	jr z, .legB                         ; 2b's west stair
	jr .write
.dest2
	ld a, [wWarpedFromWhichMap]
	cp PROCEDURAL_CEMETERY_3
	jr nz, .write                       ; from floor 1: 2a
	ld a, [hl]
	rlca                                ; the source leg -> bit 0
	ld c, a
	ld a, [wWarpedFromWhichWarp]
	xor c
	and 1
	jr z, .write
.legB
	inc b
.write
	res BIT_ROGUE_DEEP_FLOOR, [hl]
	dec b
	ret nz
	set BIT_ROGUE_DEEP_FLOOR, [hl]
	ret

; ------------------------------------------------------------
; C2. The reconcile: the stage dispatch's .cemetery, every load (Continue
; included), before PCemFinalizeMap reads the Cemetery's SRAM. Map 2 or 3 whose
; live state is not the leg the floor bit names is exchanged. (This floor's
; projections ran earlier in the same load: CemDeepPatchSprite.) Not deep:
; nothing. Clobbers everything; SRAM closed.
; ------------------------------------------------------------
CemDeepReconcile::
	call CDCtrl
	jr nc, CDCloseSRAM                  ; not deep
	ld c, a                             ; the control byte
	ldh a, [hCurMap]
	ld b, 1 << BIT_CEM_DEEP_LIVE_2B
	cp PROCEDURAL_CEMETERY_2
	jr z, .twoOrThree
	ld b, 1 << BIT_CEM_DEEP_LIVE_3B
	cp PROCEDURAL_CEMETERY_3
	jr nz, .project
.twoOrThree
	ld a, c
	and b
	ld e, 0
	jr z, .liveA
	inc e                               ; e = 1: the live state is the b leg
.liveA
	ld a, [wRogueFlagsBitfield2]
	rlca
	and 1                               ; the leg the player is on
	cp e
	call nz, CDExchange
.project
	; fall through

CDCloseSRAM:
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; ------------------------------------------------------------
; C4. The projections: ProcBossPatchStageSprite's Cemetery branch, every load
; (Continue included), whose existing farcall of CemChannelerPatchSprite leads
; here ($3C is full). It must run there and not in the stage dispatch: the
; patch reads his floor (his picture) and the hideout floor (the pair's gate)
; before the dispatch runs, so a projection written later shows the previous
; floor's (measured: his picture on 2a with his ordinal on 2b). The floor bit
; is already this floor's: the seam runs in the warp's setup, before the load.
; Then his picture, as before. Clobbers everything.
; ------------------------------------------------------------
CemDeepPatchSprite::
	call CDCtrl
	call c, CDProject
	call CDCloseSRAM
	call CemResurrectorPatchSprite
	farjp CemChannelerPatchSprite

; Each projection is kept as an ordinal over the six floors and shown to the
; unchanged code as a map index: this floor's own index when the ordinal is
; this floor's, else the index XOR 1 (a different floor in 0-3). The ordinals
; are 0-5: map 1-3's index, 3 and 4 for 2b and 3b, 5 for map 4 (index 3).
; SRAM bank 0 open, a deep Cemetery. Clobbers everything; SRAM left open.
CDProject:
	call CDOrdinal                      ; d = the map index, e = the ordinal
	ld a, [CEM_DEEP_CHAN_ORD]
	cp e
	ld a, d
	jr z, .chanHere
	xor 1
.chanHere
	ld b, a                             ; b = the Channeler's projected floor
	swap a
	ld c, a
	ld a, [sProcCemeteryItemGot]
	and ~CEM_CHANNELER_FLOOR_MASK & $ff
	or c
	ld [sProcCemeteryItemGot], a
	ld a, [CEM_DEEP_HIDE_ORD]
	cp STAGE_EVENT_NO_HIDEOUT
	jr z, .hideoutDone                  ; none armed
	ld c, a
	ld a, [sStageEventHideoutFloor]
	cp STAGE_EVENT_NO_HIDEOUT
	jr nz, .hideoutProject
	ld a, STAGE_EVENT_NO_HIDEOUT        ; disarmed since the lobby: stays so
	ld [CEM_DEEP_HIDE_ORD], a
	jr .hideoutDone
.hideoutProject
	ld a, d
	ld b, a
	ld a, c
	cp e
	ld a, b
	jr z, .hideoutWrite
	xor 1
.hideoutWrite
	ld [sStageEventHideoutFloor], a
.hideoutDone
	; His toggle: shown on this floor only when the projection matches it.
	ld a, d
	ld hl, CDChanToggles
	add l
	ld l, a
	jr nc, .toggleRead
	inc h
.toggleRead
	ld c, [hl]
	ld a, [sProcCemeteryItemGot]
	and CEM_CHANNELER_FLOOR_MASK
	swap a
	cp d
	ld b, FLAG_SET                      ; hidden
	jr nz, .toggleWrite
	ld b, FLAG_RESET                    ; shown
.toggleWrite
	ld hl, wToggleableObjectFlags
	predef FlagActionPredef
	ret

; ------------------------------------------------------------
; C3. The retargets: the stage dispatch's .cemetery, after PCemFinalizeMap has
; loaded wWarpEntries. On 3a its east stair (entry 1) leads to map 2's east
; stair (warp 0), on 2b its east stair (entry 0) to map 3's east stair (warp 1).
; Not deep: nothing. Clobbers everything.
; ------------------------------------------------------------
CemDeepAfterFinalize::
	call CDCtrl
	push af
	call CDCloseSRAM
	pop af
	ret nc
	ld a, [wRogueFlagsBitfield2]
	bit BIT_ROGUE_DEEP_FLOOR, a
	ldh a, [hCurMap]                    ; keeps the flags
	jr nz, .onB
	cp PROCEDURAL_CEMETERY_3
	ret nz
	ld hl, wWarpEntries + 1 * 4 + 2     ; 3a's east stair
	ld [hl], 0                          ; -> warp 0 (the east stair)
	inc hl
	ld [hl], PROCEDURAL_CEMETERY_2      ; of map 2: 2b
	ret
.onB
	cp PROCEDURAL_CEMETERY_2
	ret nz
	ld hl, wWarpEntries + 0 * 4 + 2     ; 2b's east stair
	ld [hl], 1                          ; -> warp 1 (the east stair)
	inc hl
	ld [hl], PROCEDURAL_CEMETERY_3      ; of map 3: 3a
	ret

; ------------------------------------------------------------
; The exchange. b = the map's LIVE mask (1 = map 2, 2 = map 3), SRAM bank 0 open.
; Swaps the map's 90 blocks and its ball X, Y and item with the shadow, its
; ready and ItemGot bits with the shadow's, then flips its LIVE bit. Keeps b.
; Clobbers a/c/de/hl.
; ------------------------------------------------------------
CDExchange:
	ld hl, sProcCemeteryMaps + 1 * CEMAP_SIZE
	ld de, CEM_DEEP_SHADOW_2
	ld c, 1                             ; the map's index
	ld a, b
	dec a
	jr z, .go
	ld hl, sProcCemeteryMaps + 2 * CEMAP_SIZE
	ld de, CEM_DEEP_SHADOW_3
	ld c, 2
.go
	push bc
	ld b, CEMAP_SIZE
	call CDSwap
	pop bc
	push bc
	ld b, 0                             ; bc = the index
	ld hl, sProcCemeteryBallX
	add hl, bc
	call CDSwapOne
	ld hl, sProcCemeteryBallY
	add hl, bc
	call CDSwapOne
	ld hl, sProcCemeteryItem
	add hl, bc
	call CDSwapOne
	pop bc
	ASSERT CEM_DEEP_SHADOW_SIZE == CEMAP_SIZE + 3
	; Ready: live bit = the index (mask b << 1), the shadow's mask is b.
	ld a, b
	add a
	ld e, a
	ld d, b
	ld hl, sProcCemeteryReady
	call CDExchangeBit
	; ItemGot: live bit = the index (mask b << 1), the shadow's mask is b << 2.
	ld a, b
	add a
	ld e, a
	add a
	ld d, a
	ld hl, sProcCemeteryItemGot
	call CDExchangeBit
	ld hl, CEM_DEEP_CTRL
	ld a, [hl]
	xor b
	ld [hli], a
	cpl
	ld [hl], a
	ret

; hl = the live run, de = the shadow, b = the length (1-255). Out: hl/de past
; the run. Clobbers a/b/c.
CDSwap:
	ld a, [de]
	ld c, [hl]
	ld [hli], a
	ld a, c
	ld [de], a
	inc de
	dec b
	jr nz, CDSwap
	ret

; One byte of CDSwap. Keeps bc.
CDSwapOne:
	push bc
	ld b, 1
	call CDSwap
	pop bc
	ret

; hl = a live byte, e = the live bit's mask, d = the shadow bit's mask in
; CEM_DEEP_SHADOW_BITS. Exchanges the two bits when they differ. Keeps b/de.
; Clobbers a/c.
CDExchangeBit:
	ld a, [hl]
	and e
	ld c, a                             ; nz = the live bit is set
	ld a, [CEM_DEEP_SHADOW_BITS]
	and d
	jr z, .shadowClear
	ld a, c
	and a
	ret nz                              ; both set
	jr .flip
.shadowClear
	ld a, c
	and a
	ret z                               ; both clear
.flip
	ld a, [hl]
	xor e
	ld [hl], a
	ld a, [CEM_DEEP_SHADOW_BITS]
	xor d
	ld [CEM_DEEP_SHADOW_BITS], a
	ret

; ------------------------------------------------------------
; Helpers.
; ------------------------------------------------------------

CDChanToggles:
	db TOGGLE_CEMETERY_1_CHANNELER, TOGGLE_CEMETERY_2_CHANNELER
	db TOGGLE_CEMETERY_3_CHANNELER, TOGGLE_CEMETERY_4_CHANNELER

; Out: d = this floor's map index (0-3), e = its ordinal in the chain 1, 2, 3,
; 2b, 3b, 4 (0-5). Needs a deep Cemetery's floor bit. Clobbers a.
CDOrdinal:
	ld de, 0
	ldh a, [hCurMap]
	cp PROCEDURAL_CEMETERY_1
	jr z, .done
	inc d
	cp PROCEDURAL_CEMETERY_2
	jr z, .two
	inc d
	cp PROCEDURAL_CEMETERY_3
	jr z, .three
	inc d
	ld e, 5                             ; map 4
	ret
.two
	ld e, 1
	jr .leg
.three
	ld e, 2
.leg
	ld a, [wRogueFlagsBitfield2]
	bit BIT_ROGUE_DEEP_FLOOR, a
	ret z
	inc e
	inc e                               ; 2b is 3, 3b is 4
	ret
.done
	ret

; Out: carry when hCurMap is a Cemetery floor. Clobbers a.
CDCemeteryMap:
	ldh a, [hCurMap]
	cp PROCEDURAL_CEMETERY_1
	jr z, .yes
	cp PROCEDURAL_CEMETERY_2
	jr z, .yes
	cp PROCEDURAL_CEMETERY_3
	jr z, .yes
	cp PROCEDURAL_CEMETERY_4
	jr z, .yes
	and a
	ret
.yes
	scf
	ret

; Opens SRAM bank 0. Out: carry = a deep Cemetery, a = the control byte, hl =
; the control word. Clobbers nothing else. SRAM left open.
CDCtrl:
	call CDOpenSRAM
	ld hl, CEM_DEEP_CTRL
	ld a, [hli]
	cpl
	cp [hl]
	dec hl                              ; keeps the flags
	jr nz, .invalid
	ld a, [hl]
	and CEM_DEEP_MAGIC_MASK
	cp CEM_DEEP_MAGIC
	jr nz, .invalid
	ld a, [hl]
	scf
	ret
.invalid
	and a
	ret

; Clobbers a only.
CDOpenSRAM:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a
	ret
