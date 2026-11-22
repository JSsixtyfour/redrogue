; The Cemetery's resurrection NPC (CEMETERY_RESURRECTION_NPC_SPEC.md, Phase 7b).
; In Ironman he brings back a Pokemon from the fallen log; otherwise he revives
; a fainted one. This file holds the fallen log's writer (moved here from
; ironman.asm: $3C has no room for the Bridge stamp) and its reader, the
; restore.
;
; THE BRIDGE STAMP (spec D8). A log entry is the whole party struct, whose
; MON_BOX_LEVEL duplicates MON_LEVEL. The restore rewrites both levels (D9), so
; that byte is free in the log: FallenLogRecord writes FALLEN_STAMP | effect
; there, effect 0 when the mon owned no selected Bridge effect. Every level is
; below FALLEN_STAMP, so an entry logged before the stamp existed reads as "no
; effect", with no save migration.
;
; $28, beside the Cemetery's deep floors. Every entry is farcalled.
SECTION "Cemetery Resurrector", ROMX, BANK[$28]

	ASSERT FALLEN_ENTRY_SIZE == PARTYMON_STRUCT_LENGTH + NAME_LENGTH + NAME_LENGTH
	ASSERT MAX_LEVEL < FALLEN_STAMP
	ASSERT NUM_BRIDGE_SELECTED_EFFECTS <= $0F
	ASSERT wPartyMonNicks == wPartyMonOT + PARTY_LENGTH * NAME_LENGTH
	ASSERT wBoxMonNicks == wBoxMonOT + MONS_PER_BOX * NAME_LENGTH
	ASSERT MONS_PER_BOX == 20

; ------------------------------------------------------------
; The fallen log's writer: IronmanReleaseCommon ($3C), just before RemovePokemon.
; In: hWhichPokemon = the party slot being released. Once FALLEN_LOG_CAPACITY
; is reached, further releases are not logged. Clobbers everything; SRAM closed.
; ------------------------------------------------------------
FallenLogRecord::
	ld a, [wFallenCount]
	cp FALLEN_LOG_CAPACITY
	ret nc
	call CRLogEntry                     ; hl = the new entry
	push hl
	ld d, h
	ld e, l
	call CRLogOpen
	ldh a, [hWhichPokemon]
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	call CopyData                       ; de advances past the struct
	ldh a, [hWhichPokemon]
	ld hl, wPartyMonOT
	ld bc, NAME_LENGTH
	call AddNTimes
	call CopyData
	ldh a, [hWhichPokemon]
	ld hl, wPartyMonNicks
	ld bc, NAME_LENGTH
	call AddNTimes
	call CopyData
	; The stamp: its selected Bridge effect, if its owner (slot + 1) has one.
	pop hl
	ld bc, MON_BOX_LEVEL
	add hl, bc
	ldh a, [hWhichPokemon]
	inc a
	ld c, a                             ; c = its owner
	ld e, 0                             ; e = its effect, none yet
	ld b, BRIDGE_SELECTED_RECORD_COUNT
	push hl
	ld hl, wBridgeSelectedEffects
.find
	ld a, [hli]
	cp c
	jr nz, .next
	ld e, [hl]
.next
	inc hl
	dec b
	jr nz, .find
	pop hl
	ld a, e
	or FALLEN_STAMP
	ld [hl], a
	call CRLogClose
	ld hl, wFallenCount
	inc [hl]
	ret

; ------------------------------------------------------------
; CemResurrectRestore: brings fallen entry a back, at max(its level, the
; reward level) (D9), with full HP, no status and full PP (PP Ups kept). No
; evolution, no new moves. To the party, or the current box when the party is
; full (D7). Its Bridge effect comes back when a record is free (D8). The entry
; then leaves the log.
;
; In:  a = the entry index (< wFallenCount).
; Out: carry set = the party and the box are both full; nothing changed.
;      carry clear = restored; a = RESURRECT_TO_BOX if it went to the box,
;      plus RESURRECT_EFFECT_LOST if its Bridge effect found no free record.
; Clobbers everything; SRAM closed.
; ------------------------------------------------------------
CemResurrectRestore::
	ld c, a                             ; c = the entry
	ld b, 0                             ; b = the result flags
	ld a, [wPartyCount]
	cp PARTY_LENGTH
	jr c, .room
	ld a, [wBoxCount]
	cp MONS_PER_BOX
	ccf
	ret c                               ; nowhere to put it
	ld b, RESURRECT_TO_BOX
.room
	push bc                             ; held for the whole routine
	farcall GetRewardMonLevel           ; -> wCurEnemyLevel; clobbers freely

	; The struct, into wLoadedMon: the work copy for both destinations.
	pop bc
	push bc
	ld a, c
	call CRLogEntry
	ld de, wLoadedMon
	ld bc, PARTYMON_STRUCT_LENGTH
	call CRLogOpen
	call CopyData
	call CRLogClose

	; Its Bridge effect, registered to the owner it is about to have, so the
	; stats below see a ray the way they would for a mon that never left.
	pop bc
	push bc
	call CRDestinationOwner             ; a = the owner
	ld d, a
	ld a, [wLoadedMon + MON_BOX_LEVEL]
	sub FALLEN_STAMP
	jr c, .effectDone                   ; logged before the stamp: none
	jr z, .effectDone                   ; stamped: none
	ld e, a                             ; e = the effect
	push de
	farcall BridgeSelectedRegistryHasRoom ; carry, hl = a free record
	pop de
	jr nc, .effectLost
	ld [hl], d
	inc hl
	ld [hl], e
	jr .effectDone
.effectLost
	pop bc
	set BIT_RESURRECT_EFFECT_LOST, b
	push bc
.effectDone

	; Level (D9), with the form's header: its growth rate and base stats.
	call CRLoadHeader
	ld a, [wCurEnemyLevel]              ; the reward level
	ld hl, wLoadedMon + MON_LEVEL
	cp [hl]
	jr c, .levelReady                   ; its own is higher
	jr z, .levelReady
	ld [hl], a
	ld d, a
	callfar CalcExperience              ; the start of that level
	ld hl, wLoadedMon + MON_EXP
	ldh a, [hExperience]
	ld [hli], a
	ldh a, [hExperience + 1]
	ld [hli], a
	ldh a, [hExperience + 2]
	ld [hl], a
.levelReady
	ld a, [wLoadedMon + MON_LEVEL]
	ld [wLoadedMon + MON_BOX_LEVEL], a  ; replaces the stamp
	ld [wCurEnemyLevel], a              ; CalcStats' level

	; Stats, as the box-to-party withdrawal computes them.
	ld de, wLoadedMon + MON_STATS
	ld hl, wLoadedMon + MON_HP_EXP - 1
	ld b, 1                             ; with stat exp
	push bc
	push hl
	farcall PrepareFusionAndBridgeRayCalcStats ; keeps de
	pop hl
	pop bc
	call CalcStats

	; Full HP, no status, full PP.
	ld hl, wLoadedMon + MON_MAXHP
	ld de, wLoadedMon + MON_HP
	ld a, [hli]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a
	xor a
	ld [wLoadedMon + MON_STATUS], a
	call CRRefillPP

	; The commit. [sp] = the entry's OT, then the flags and the entry.
	pop bc
	push bc
	ld a, c
	call CRLogEntry
	ld de, PARTYMON_STRUCT_LENGTH
	add hl, de
	pop bc
	push bc
	push hl
	bit BIT_RESURRECT_TO_BOX, b
	ld hl, wPartyCount
	jr z, .append
	ld hl, wBoxCount
.append
	ld a, [hl]
	inc [hl]
	ld e, a                             ; e = its slot
	ld d, 0
	inc hl
	add hl, de
	ld a, [wLoadedMon + MON_SPECIES]
	ld [hli], a
	ld [hl], $ff
	ld a, e
	bit BIT_RESURRECT_TO_BOX, b
	jr nz, .toBox
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call CRCopyLoadedMon
	ld hl, wPartyMonOT
	ld bc, PARTY_LENGTH * NAME_LENGTH
	jr .names
.toBox
	ld hl, wBoxMons
	ld bc, BOXMON_STRUCT_LENGTH         ; the box struct is the party struct's head
	call CRCopyLoadedMon
	ld hl, wBoxMonOT
	ld bc, MONS_PER_BOX * NAME_LENGTH
.names
	; hl = the OT array, bc = its distance to the nickname array, e = the slot,
	; [sp] = the entry's OT (its nickname follows it).
	ld a, e
	push bc
	ld bc, NAME_LENGTH
	call AddNTimes
	pop bc
	ld d, h
	ld e, l                             ; de = its OT
	add hl, bc
	ld b, h
	ld c, l                             ; bc = its nickname
	pop hl                              ; hl = the entry's OT
	push bc
	call CRLogOpen
	ld bc, NAME_LENGTH
	call CopyData                       ; hl -> the entry's nickname
	pop de
	ld bc, NAME_LENGTH
	call CopyData
	call CRLogClose

	pop bc
	push bc
	ld a, c
	call CRLogDelete
	pop bc
	ld a, b
	and a                               ; carry clear: restored
	ret

; a = its slot, hl = the array, bc = the struct length. Copies that much of
; wLoadedMon there. Keeps e.
CRCopyLoadedMon:
	call AddNTimes
	push de
	ld d, h
	ld e, l
	ld hl, wLoadedMon
	call CopyData
	pop de
	ret

; b = the result flags. Out: a = the owner the restored mon will have; the
; destination in wMonDataLocation and hWhichPokemon, which is how
; PrepareFusionAndBridgeRayCalcStats identifies wLoadedMon. Clobbers a/de.
CRDestinationOwner:
	bit BIT_RESURRECT_TO_BOX, b
	jr nz, .box
	ASSERT PLAYER_PARTY_DATA == 0
	xor a
	ld [wMonDataLocation], a
	ld a, [wPartyCount]
	ldh [hWhichPokemon], a
	inc a                               ; a party owner is slot + 1
	ret
.box
	ld a, BOX_DATA
	ld [wMonDataLocation], a
	ld a, [wBoxCount]
	ldh [hWhichPokemon], a
	ld e, a
	ld a, [wCurrentBoxNum]
	and BOX_NUM_MASK
	ld d, a
	add a
	add a
	add d                               ; 5 * box
	add a
	add a                               ; 20 * box
	add e
	add BRIDGE_SELECTED_OWNER_BOX_BASE  ; BridgeSelectedOwnerFromCurrentBoxSlot's
	ret

; wLoadedMon's header, with its form (PublishFormContext). Clobbers a.
CRLoadHeader:
	ld a, [wLoadedMon + MON_SPECIES]
	ld [wCurSpecies], a
	ld [wCurPartySpecies], a
	push hl
	ld hl, wLoadedMon
	call PublishFormContext
	pop hl
	jp GetMonHeader

; Every move's PP to its maximum, keeping the PP Up bits: the move's base PP
; plus, per PP Up, a fifth of it capped at 7 (AddBonusPP's rule). Clobbers
; everything.
CRRefillPP:
	ld hl, wLoadedMon + MON_MOVES
	ld de, wNormalMaxPPList - 1
	predef LoadMovePPs                  ; base PP, 0 for an empty slot
	ld hl, wLoadedMon + MON_PP
	ld de, wNormalMaxPPList
	ld c, NUM_MOVES
.move
	push bc
	push de
	ld a, [de]
	ld b, a                             ; b = the PP so far
	ld e, 0                             ; e = a fifth of it
.fifth
	cp 5
	jr c, .fifthDone
	sub 5
	inc e
	jr .fifth
.fifthDone
	ld a, e
	cp 8
	jr c, .bonus
	ld a, 7
.bonus
	ld e, a                             ; e = the PP per PP Up
	ld a, [hl]
	and PP_UP_MASK
	ld c, a                             ; c = the PP Up bits, kept
	rlca
	rlca
	ld d, a                             ; d = PP Ups used, 0-3
	inc d
.ups
	dec d
	jr z, .write
	ld a, b
	add e
	ld b, a
	jr .ups
.write
	ld a, b
	or c
	ld [hli], a
	pop de
	inc de
	pop bc
	dec c
	jr nz, .move
	ret

; Removes entry a: the later entries move down one and the freed last entry is
; zeroed (the log's tail is kept clean). Decrements wFallenCount. Clobbers
; everything; SRAM closed.
CRLogDelete:
	ld c, a
	ld hl, wFallenCount
	dec [hl]
	ld a, [hl]
	sub c
	ld b, a                             ; b = entries after it
	push bc
	ld a, c
	call CRLogEntry
	pop bc
	ld d, h
	ld e, l                             ; de = the hole
	push de
	ld de, FALLEN_ENTRY_SIZE
	add hl, de                          ; hl = the entry after it
	pop de
	call CRLogOpen
	ld a, b
	and a
	jr z, .tail                         ; it was the last
	push hl
	ld hl, 0
	push de
	ld de, FALLEN_ENTRY_SIZE
.length
	add hl, de
	dec a
	jr nz, .length
	pop de
	ld b, h
	ld c, l
	pop hl
	call CopyData                       ; de ends on the old last entry
.tail
	ld h, d
	ld l, e
	ld bc, FALLEN_ENTRY_SIZE
	xor a
	call FillMemory
	jr CRLogClose

; a = an entry index. Out: hl = its address in sFallenLog. Clobbers bc.
CRLogEntry:
	ld hl, sFallenLog
	ld bc, FALLEN_ENTRY_SIZE
	jp AddNTimes

; SRAM bank 2 selected on open; always bank 0 and SRAM disabled on close, the
; ambient state other SRAM users rely on (as FallenLogClose).
CRLogOpen:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sFallenLog)
	ld [rRAMB], a
	ret

CRLogClose:
	xor a
	ld [rRAMB], a
	ld [rBMODE], a
	ld [rRAMG], a                       ; RAMG_SRAM_DISABLE
	ret

; ============================================================================
; Presence and placement (D2, D5). He is object CEMETERY_RESURRECTOR on all four
; floor maps, with no toggle: on his floor he gets his picture and a cell; on
; every other floor, picture 0 and an off-grid park (0, 0), as the stage pair
; is parked and the Forest's optional slot is hidden. His floor is an ordinal
; in CDOrdinal's numbering, so the same compare serves a deep Cemetery (0-5,
; the Channeler's projection) and an ordinary one (floors 1-4 read 0, 1, 2, 5:
; the floor bit is always clear there).
; ============================================================================

; CemDeepGenerateMaps, after the deep decision. 60% of Cemeteries (D5) get him,
; on a random floor of the chain (D2). Tests force the result at .store.
; Clobbers everything; SRAM closed.
CemResurrectorRoll:
	call Random
	cp RESURRECT_ODDS
	ld a, CEM_RES_ABSENT
	jr nc, .store
	call CDCtrl                         ; carry = deep
	ld c, CEM_DEEP_NUM_ORDINALS
	jr c, .deep
	ld c, 4
	call Rangerandom
	cp 3
	jr nz, .store
	ld a, 5                             ; map 4 is ordinal 5
	jr .store
.deep
	call Rangerandom
.store
	ld b, a
	call CDOpenSRAM
	ld a, b
	ld [CEM_DEEP_RES_ORD], a
	jp CDCloseSRAM

; Out: carry = he stands on this floor; d = this floor's map index (0-3).
; Clobbers a/e; SRAM closed.
CRIsHere:
	call CDCemeteryMap
	ret nc
	call CDOrdinal                      ; d = the map index, e = the ordinal
	call CDOpenSRAM
	ld a, [CEM_DEEP_RES_ORD]
	push af
	call CDCloseSRAM
	pop af
	cp e
	scf
	ret z
	and a
	ret

; CemDeepPatchSprite, every load before InitMapSprites (the patch-before-
; dispatch order: memory project_facility_sprite_patch_before_generation).
; Clobbers a/de.
CemResurrectorPatchSprite:
	call CRIsHere
	ld a, SPRITE_BALDING_GUY
	jr c, .write
	xor a
.write
	ld [wSprite{02d:CEMETERY_RESURRECTOR}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ret

; CemDeepFinalizeMap, every load after PCemFinalizeMap (which placed the ball
; and the Channeler). On his floor, the first cell from a fixed start that the
; hideout rule accepts (PCemStageHideoutCellOk: a floor block, not the ball's,
; not a stair, not floor 4's boss steps, never sealing a gap) and that is not
; within one block of the Channeler, the hideout or floor 1's arrival block:
; two solid NPCs side by side can close a gap neither closes alone. The
; floor's blocks are saved, so every load finds the same cell. Elsewhere, or
; with no cell, parked. Clobbers everything; SRAM closed.
CemResurrectorPlace:
	call CRIsHere
	jr nc, .park
	ld a, d
	ld [wBuffer + wCemMapIndex], a
	call CDOpenSRAM
	ld c, CEM_RES_SCAN_START
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
	call CRCrowded                      ; carry = too close to another NPC
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
	call CDCloseSRAM
.park
	xor a
	ld [wSprite{02d:CEMETERY_RESURRECTOR}StateData2MapY], a
	ld [wSprite{02d:CEMETERY_RESURRECTOR}StateData2MapX], a
	ret
.found
	pop bc
	call CDCloseSRAM
	ld a, [wBuffer + wCemTryY]
	add a
	add 4                               ; block * 2 + 4, as the ball and the pair
	ld [wSprite{02d:CEMETERY_RESURRECTOR}StateData2MapY], a
	ld a, [wBuffer + wCemTryX]
	add a
	add 4
	ld [wSprite{02d:CEMETERY_RESURRECTOR}StateData2MapX], a
	ret

; Carry = wCemTryX/Y is within one block of the Channeler (on this floor), the
; stage pair's hideout (on this floor) or, on floor 1, the pair's arrival
; block. SRAM bank 0 open. Clobbers a/bc/hl.
CRCrowded::
	ld hl, wBuffer + wCemMapIndex
	ld a, [sProcCemeteryItemGot]
	and CEM_CHANNELER_FLOOR_MASK
	swap a
	cp [hl]
	jr nz, .hideout
	ASSERT CEMETERY_1_CHANNELER == 4
	ld a, [wSprite04StateData2MapX]
	sub 4
	srl a
	ld b, a
	ld a, [wSprite04StateData2MapY]
	sub 4
	srl a
	ld c, a
	call CRNear
	ret c
.hideout
	ld a, [sStageEventHideoutFloor]
	cp [hl]
	jr nz, .arrival
	ld a, [sStageEventHideoutX]
	ld b, a
	ld a, [sStageEventHideoutY]
	ld c, a
	call CRNear
	ret c
.arrival
	ld a, [hl]
	and a
	ret nz                              ; not floor 1: carry clear
	lb bc, PCEM_ARRIVAL_BLOCK_X, PCEM_ARRIVAL_BLOCK_Y
	; fall through

; b = X, c = Y (blocks). Carry = wCemTryX/Y is within one block of it.
; Clobbers a.
CRNear:
	ld a, [wBuffer + wCemTryX]
	sub b
	inc a                               ; -1..1 -> 0..2
	cp 3
	ret nc
	ld a, [wBuffer + wCemTryY]
	sub c
	inc a
	cp 3
	ret

; ============================================================================
; The talk (spec "Talk"). His text_asm (scripts/ProceduralCemetery1.asm,
; PCemResurrectorText) saves bc and farcalls CemResurrectorTalk, which returns
; to it. Once per Cemetery: bit 7 of sProcCemeteryItemGot, set by a service.
;
; IRONMAN. The list is drawn the way room_pc.asm draws its lists (TextBoxBorder +
; PlaceString + HandleMenuInput), cheapest fee first and the newest fallen first
; among equal fees. Its order lives in a stack frame (no free WRAM: wBuffer is
; YesNoChoice's save area) built once at the top of CRIronman, so every access to
; the frame is made at that routine's own depth, with nothing pushed:
;   +0..9    each entry's fee index (0 Poke, 1 Great, 2 Ultra and above)
;   +10..19  the list rows, as entry indices
;   +20      the cursor (kept across a declined offer)
;   +21      the chosen entry
;   +22      hUILayoutFlags as found (the list sets BIT_DOUBLE_SPACED_MENU)
; ============================================================================
DEF CR_FRAME_TIERS   EQU 0
DEF CR_FRAME_ORDER   EQU FALLEN_LOG_CAPACITY
DEF CR_FRAME_CURSOR  EQU FALLEN_LOG_CAPACITY * 2
DEF CR_FRAME_ENTRY   EQU CR_FRAME_CURSOR + 1
DEF CR_FRAME_UIFLAGS EQU CR_FRAME_ENTRY + 1
DEF CR_FRAME_SIZE    EQU CR_FRAME_UIFLAGS + 1
DEF CR_NICK_OFFSET   EQU PARTYMON_STRUCT_LENGTH + NAME_LENGTH
DEF CR_NAME_COL      EQU 2
DEF CR_PRICE_COL     EQU 12              ; right-aligned: yen sign and digits end on col 18
	ASSERT MON_SPECIES == 0
	ASSERT FALLEN_LOG_CAPACITY <= 10     ; rows 1-10 are the box's whole height
	ASSERT CR_FRAME_SIZE < 128           ; ld hl, sp + n reaches +127

CemResurrectorTalk::
	call CRIsDone
	ld hl, CRAfterText
	jp c, PrintText
	ld a, [wOptions3]
	bit BIT_IRONMAN, a
	jr nz, CRIronman
	farcall CemReviverTalk
	ret

CRIronman:
	ld a, [wFallenCount]
	and a
	ld hl, CRNoSoulsText
	jp z, PrintText
	add sp, -CR_FRAME_SIZE
	ldh a, [hUILayoutFlags]
	ld hl, sp + CR_FRAME_UIFLAGS
	ld [hl], a
	xor a
	ld hl, sp + CR_FRAME_CURSOR
	ld [hl], a

	; Each entry's fee index.
	ld a, [wFallenCount]
	ld b, a
	ld c, 0
.tier
	push bc
	ld a, c
	call CRFeeIndex
	pop bc
	ld hl, sp + CR_FRAME_TIERS
	ld e, c
	ld d, 0
	add hl, de
	ld [hl], a
	inc c
	ld a, c
	cp b
	jr c, .tier

	; The rows: fee index 0, 1, 2 in turn, each newest entry first.
	ld hl, sp + CR_FRAME_ORDER
	ld d, h
	ld e, l                             ; de = the order's write pointer
	ld c, 0                             ; c = the fee index being laid out
.fillTier
	ld a, [wFallenCount]
	ld b, a
.fillEntry
	ld a, b
	and a
	jr z, .nextTier
	dec b
	ld hl, sp + CR_FRAME_TIERS
	ld a, l
	add b
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	ld a, [hl]
	cp c
	jr nz, .fillEntry
	ld a, b
	ld [de], a
	inc de
	jr .fillEntry
.nextTier
	inc c
	ld a, c
	cp 3
	jr c, .fillTier

	ld hl, CRWhichText
	call PrintText
	call SaveScreenTilesToBuffer2
.list
	call LoadScreenTilesFromBuffer2
	ldh a, [hUILayoutFlags]
	set BIT_DOUBLE_SPACED_MENU, a       ; one row per entry (its sense is inverted)
	ldh [hUILayoutFlags], a
	hlcoord 0, 0
	ld a, [wFallenCount]
	ld b, a
	ld c, SCREEN_WIDTH - 2
	call TextBoxBorder
	ld b, 0
.row
	ld hl, sp + CR_FRAME_ORDER
	ld e, b
	ld d, 0
	add hl, de
	ld a, [hl]
	push bc
	call CRPlaceRow
	pop bc
	inc b
	ld a, [wFallenCount]
	cp b
	jr nz, .row

	ld hl, sp + CR_FRAME_CURSOR
	ld a, [hl]
	ldh [hCurrentMenuItem], a
	ld hl, wTopMenuItemY
	ld a, 1
	ld [hli], a                         ; wTopMenuItemY: the first row
	ld [hli], a                         ; wTopMenuItemX: the cursor's column
	inc hl
	ld a, [wFallenCount]
	dec a
	ld [hli], a                         ; wMaxMenuItem
	ld a, PAD_A | PAD_B
	ld [hli], a
	xor a
	ld [hl], a                          ; wLastMenuItem
	ld hl, wListScrollOffset
	ld [hli], a
	ld [hl], a
	ld [wMenuWatchMovingOutOfBounds], a
	call HandleMenuInput
	call PlaceUnfilledArrowMenuCursor
	bit B_PAD_B, a
	jp nz, .leave
	ldh a, [hCurrentMenuItem]
	ld hl, sp + CR_FRAME_CURSOR
	ld [hl], a
	ld e, a
	ld d, 0
	ld hl, sp + CR_FRAME_ORDER
	add hl, de
	ld a, [hl]
	ld hl, sp + CR_FRAME_ENTRY
	ld [hl], a
	call CRPrepareOffer                 ; wNameBuffer, wCurEnemyLevel, wPriceTemp
	ld hl, CRConfirmText
	call PrintText
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	jp nz, .list                        ; declined: back to the list

	call LoadScreenTilesFromBuffer2     ; the list is done; its box goes
	ld hl, wPriceTemp
	ld de, hMoney
	ld bc, 3
	call CopyData
	call HasEnoughMoney
	ld hl, CRNoMoneyText
	jr c, .say
	; The fee waits on the stack: the restore clobbers everything.
	ld a, [wPriceTemp]
	ld b, a
	ld a, [wPriceTemp + 1]
	ld c, a
	ld a, [wPriceTemp + 2]
	ld d, a
	push bc
	push de
	ld hl, sp + 4 + CR_FRAME_ENTRY
	ld a, [hl]
	call CemResurrectRestore            ; carry = nowhere to put it
	jr c, .full
	pop de
	pop bc
	push af                             ; the RESURRECT_* flags
	ld a, b
	ld [wPriceTemp], a
	ld a, c
	ld [wPriceTemp + 1], a
	ld a, d
	ld [wPriceTemp + 2], a
	ld hl, wPriceTemp + 2
	ld de, wPlayerMoney + 2
	ld c, 3
	predef SubBCDPredef
	call CRSetDone
	pop af
	ld e, a                             ; farcall clobbers a; e crosses
	farcall CemResultTexts
	jr .exit
.full
	add sp, 4
	ld hl, CRBoxFullText
.say
	call PrintText
	jr .exit
.leave
	call LoadScreenTilesFromBuffer2
.exit
	ld hl, sp + CR_FRAME_UIFLAGS
	ld a, [hl]
	ldh [hUILayoutFlags], a
	add sp, CR_FRAME_SIZE
	ret

; a = the entry, b = its row. Draws its nickname and its fee. Clobbers everything.
CRPlaceRow:
	push af
	push bc
	call CRLogEntry
	ld bc, CR_NICK_OFFSET
	add hl, bc
	call CRLogOpen
	ld de, wNameBuffer
	ld bc, NAME_LENGTH
	call CopyData
	call CRLogClose
	pop bc
	push bc
	ld c, CR_NAME_COL
	call CRRowCoord
	ld de, wNameBuffer
	call PlaceString
	pop bc
	pop af
	push bc
	call CRFeeIndex
	call CRFeeAddr
	ld d, h
	ld e, l
	pop bc
	ld c, CR_PRICE_COL
	push de
	call CRRowCoord
	pop de
	ld c, 3 | LEADING_ZEROES | MONEY_SIGN ; LEADING_ZEROES = skip them (inverted name)
	jp PrintBCDNumber

; b = a list row, c = a column. Out: hl = that tile of the box. Clobbers a/de.
CRRowCoord:
	hlcoord 0, 1
	ld a, b
	and a
	jr z, .column
	ld de, SCREEN_WIDTH
.down
	add hl, de
	dec a
	jr nz, .down
.column
	ld e, c
	ld d, 0
	add hl, de
	ret

; a = the entry. Out: wNameBuffer = its nickname, wCurEnemyLevel = what it comes
; back at (max(its level, the reward level), D9), wPriceTemp = its fee.
; Clobbers everything.
CRPrepareOffer:
	push af
	farcall GetRewardMonLevel           ; wCurEnemyLevel = the reward level
	pop af
	push af
	call CRLogEntry
	push hl
	ld bc, CR_NICK_OFFSET
	add hl, bc
	call CRLogOpen
	ld de, wNameBuffer
	ld bc, NAME_LENGTH
	call CopyData
	call CRLogClose
	pop hl
	ld bc, MON_LEVEL
	add hl, bc
	call CRLogOpen
	ld a, [hl]
	ld b, a
	call CRLogClose
	ld a, [wCurEnemyLevel]
	cp b
	jr nc, .rewardLevel                 ; the reward level is the higher
	ld a, b
	ld [wCurEnemyLevel], a
.rewardLevel
	pop af
	call CRFeeIndex
	call CRFeeAddr
	ld de, wPriceTemp
	ld bc, 3
	jp CopyData

; a = an entry. Out: a = its fee index: 0 Poke Ball, 1 Great Ball, 2 Ultra Ball
; and above (D1), from its species and form (MON_CATCH_RATE bits 5-6).
; Clobbers bc/de/hl.
CRFeeIndex:
	call CRLogEntry
	call CRLogOpen
	ld a, [hl]                          ; MON_SPECIES
	ld e, a
	ld bc, MON_CATCH_RATE
	add hl, bc
	ld a, [hl]
	and FORM_MASK
	ASSERT FORM_SHIFT == 5
	rlca
	rlca
	rlca                                ; bits 5-6 -> 0-1
	ld d, a                             ; before CRLogClose, which zeroes a
	call CRLogClose
	farcall RogueClassifyIdentityFar    ; e = the legacy class, 1-4
	ld a, e
	dec a
	cp 2
	ret c
	ld a, 2
	ret

; a = a fee index. Out: hl = its three BCD bytes. Clobbers a/bc.
CRFeeAddr:
	ld c, a
	add a
	add c
	ld c, a
	ld b, 0
	ld hl, CRFeeTable
	add hl, bc
	ret

CRFeeTable:
	bcd3 RESURRECT_FEE_POKEBALL
	bcd3 RESURRECT_FEE_GREATBALL
	bcd3 RESURRECT_FEE_ULTRABALL

; Out: carry = he has served this Cemetery already. Clobbers a/b.
CRIsDone:
	call CDOpenSRAM
	ld a, [sProcCemeteryItemGot]
	ld b, a
	call CDCloseSRAM
	ld a, b
	ASSERT BIT_CEM_RESURRECTOR_DONE == 7
	add a                               ; bit 7 into the carry
	ret

CRSetDone:
	call CDOpenSRAM
	ld a, [sProcCemeteryItemGot]
	set BIT_CEM_RESURRECTOR_DONE, a
	ld [sProcCemeteryItemGot], a
	jp CDCloseSRAM

; The lines (text/ProceduralCemetery.asm; placeholder wording).
CRNoSoulsText:
	text_far _CemResNoSoulsText
	text_end
CRWhichText:
	text_far _CemResWhichText
	text_end
CRConfirmText:
	text_far _CemResConfirmText
	text_end
CRBoxFullText:
	text_far _CemResBoxFullText
	text_end
CRAfterText:
	text_far _CemResAfterText
	text_end
CRNoMoneyText:
	text_far _PCPokemonSalesmanNoMoneyText
	text_end

; ============================================================================
; Outside Ironman (D6): a fainted party Pokemon, for a flat fee. Its own section:
; $28 had no room for it beside the list. Entered only by farcall from
; CemResurrectorTalk, and it calls nothing in $28 (a plain call from here would
; land in whatever $28's labels' bank offsets map to in this bank), so the few
; helpers it shares in spirit are its own, CV-prefixed.
; ============================================================================
; $29, not $1A (2026-11-20): $1A holds the wild areas' generic trainer, which
; needed the room. Reached only by farcall (CemReviverTalk, CemResultTexts); its
; own calls are local, HOME or predef, so it moves whole (ROM Bible 2026-11-20).
SECTION "Cemetery Reviver", ROMX, BANK[$29]

CemReviverTalk::
	call CVAnyFainted
	ld hl, CVNoFaintedText
	jp nc, PrintText
	ld hl, CVAskText
	call PrintText
	call SaveScreenTilesToBuffer2
	xor a
	ldh [hUpdateSpritesEnabled], a
	ld [wPartyMenuTypeOrMessageID], a
	ld [wMenuItemToSwap], a
	call DisplayPartyMenu
	push af
	call GBPalWhiteOutWithDelay3
	call RestoreScreenTilesAndReloadTilePatterns
	call LoadGBPal
	pop af
	ret c                               ; cancelled
	ldh a, [hWhichPokemon]
	call CVPartyMonAddr
	ld de, MON_HP
	add hl, de
	ld a, [hli]
	or [hl]
	ld hl, CVNotFaintedText
	jp nz, PrintText
	ldh a, [hWhichPokemon]
	ld hl, wPartyMonNicks
	call GetPartyMonName
	ld hl, CVFee
	ld de, wPriceTemp
	ld bc, 3
	call CopyData
	ld hl, CVConfirmText
	call PrintText
	ldh a, [hWhichPokemon]
	push af
	ld a, MONEY_BOX
	ld [wTextBoxID], a
	call DisplayTextBoxID
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	ld c, a
	pop af
	ldh [hWhichPokemon], a
	ld a, c
	and a
	ret nz                              ; declined
	ld hl, wPriceTemp
	ld de, hMoney
	ld bc, 3
	call CopyData
	call HasEnoughMoney
	ld hl, CVNoMoneyText
	jp c, PrintText
	ld hl, wPriceTemp + 2
	ld de, wPlayerMoney + 2
	ld c, 3
	predef SubBCDPredef
	ldh a, [hWhichPokemon]
	call CVPartyMonAddr
	push hl
	ld de, MON_MAXHP
	add hl, de
	ld a, [hli]
	ld b, a
	ld a, [hl]
	ld c, a                             ; bc = its max HP
	pop hl
	push hl
	ld de, MON_HP
	add hl, de
	ld a, b
	ld [hli], a
	ld [hl], c
	pop hl
	ld de, MON_STATUS
	add hl, de
	xor a
	ld [hl], a
	; Served: bit 7 of sProcCemeteryItemGot (SRAM bank 0, closed again after).
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a
	ld a, [sProcCemeteryItemGot]
	set BIT_CEM_RESURRECTOR_DONE, a
	ld [sProcCemeteryItemGot], a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld hl, CVRevivedText
	jp PrintText

; a = a party slot. Out: hl = its struct. Clobbers a/bc.
CVPartyMonAddr:
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	jp AddNTimes

; Out: carry = some party Pokemon has 0 HP. Clobbers a/b/de/hl.
CVAnyFainted:
	ld a, [wPartyCount]
	ld b, a
	ld hl, wPartyMons + MON_HP
	ld de, PARTYMON_STRUCT_LENGTH - 1
.next
	ld a, [hli]
	or [hl]
	jr z, .found
	add hl, de
	dec b
	jr nz, .next
	and a
	ret
.found
	scf
	ret

CVFee:
	bcd3 RESURRECT_REVIVE_FEE

CVNoFaintedText:
	text_far _CemResNoFaintedText
	text_end
CVAskText:
	text_far _CemResReviveAskText
	text_end
CVNotFaintedText:
	text_far _CemResNotFaintedText
	text_end
CVConfirmText:
	text_far _CemResReviveConfirmText
	text_end
CVRevivedText:
	text_far _CemResRevivedText
	text_end
CVNoMoneyText:
	text_far _PCPokemonSalesmanNoMoneyText
	text_end

; e = the restore's flags: the result lines (farcalled from CRIronman). Clobbers
; everything.
CemResultTexts::
	ld a, e
	push af
	bit BIT_RESURRECT_TO_BOX, a
	ld hl, wPartyMonNicks
	ld a, [wPartyCount]
	jr z, .named
	ld hl, wBoxMonNicks
	ld a, [wBoxCount]
.named
	dec a                               ; it is the last one in
	ld bc, NAME_LENGTH
	call AddNTimes
	ld de, wNameBuffer
	ld bc, NAME_LENGTH
	call CopyData
	ld hl, CVReturnedText
	call PrintText
	pop af
	push af
	bit BIT_RESURRECT_TO_BOX, a
	ld hl, CVToBoxText
	call nz, PrintText
	pop af
	bit BIT_RESURRECT_EFFECT_LOST, a
	ret z
	ld hl, CVEffectLostText
	jp PrintText

CVReturnedText:
	text_far _CemResReturnedText
	text_end
CVToBoxText:
	text_far _CemResToBoxText
	text_end
CVEffectLostText:
	text_far _CemResEffectLostText
	text_end
