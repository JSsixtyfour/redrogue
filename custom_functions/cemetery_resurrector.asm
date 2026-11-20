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
CRCrowded:
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

; His text_asm (scripts/ProceduralCemetery1.asm, PCemResurrectorText).
; PLACEHOLDER until the talk flow lands (spec "Talk"): one line.
CemResurrectorTalk::
	ld hl, .placeholder
	jp PrintText
.placeholder
	text "..."
	done
