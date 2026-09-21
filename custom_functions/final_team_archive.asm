; Versioned rolling archive used by the final AI sequence.
;
; Public routines are farcall-safe and publish success in
; wActionResultOrTookBattleTurn (0 = failure, 1 = success). They never leave
; SRAM enabled and always restore bank 0 before returning.

DEF FINAL_TEAM_ARCHIVE_MAGIC_0 EQU 'R'
DEF FINAL_TEAM_ARCHIVE_MAGIC_1 EQU 'R'
DEF FINAL_TEAM_ARCHIVE_VERSION_VALUE EQU 1
DEF FINAL_TEAM_ARCHIVE_EMPTY_INDEX EQU $ff
DEF FINAL_TEAM_ARCHIVE_CAPACITY EQU 4
DEF FINAL_TEAM_PARTY_SIZE EQU 404
DEF FINAL_TEAM_RECORD_SIZE EQU FINAL_TEAM_PARTY_SIZE + 2
DEF FINAL_TEAM_ARCHIVE_HEADER_SIZE EQU 11

FinalTeamArchiveInit::
	call FinalTeamArchiveOpen
	call .InitOpen
	jp FinalTeamArchiveClose

.InitOpen
	ld hl, sFinalTeamArchiveMagic
	ld a, FINAL_TEAM_ARCHIVE_MAGIC_0
	ld [hli], a
	ld a, FINAL_TEAM_ARCHIVE_MAGIC_1
	ld [hli], a
	ld a, FINAL_TEAM_ARCHIVE_VERSION_VALUE
	ld [hli], a
	xor a
	ld [hli], a ; count
	ld [hli], a ; next index
	dec a
	ld [hli], a ; latest index
	ld b, FINAL_TEAM_ARCHIVE_CAPACITY
.clearChecksums
	ld [hli], a
	dec b
	jr nz, .clearChecksums
	call FinalTeamArchiveWriteHeaderChecksum
	ret

; Save the current party in the next rolling slot. A party containing more
; than one fusion, or a fusion without its released secondary identity, is
; rejected rather than archived ambiguously.
FinalTeamArchiveCapture::
	xor a
	ld [wActionResultOrTookBattleTurn], a
	call FinalTeamArchiveValidateFusion
	ret nc
	; Preserve the two sidecar bytes across the copy using the stack.
	ld a, [wFusionSecondarySpecies]
	ld d, a
	ld a, [wFusionSecondaryForm]
	ld e, a
	push de
	call FinalTeamArchiveOpen
	call FinalTeamArchiveValidateHeader
	jr c, .headerReady
	call FinalTeamArchiveInit.InitOpen
.headerReady
	ld a, [sFinalTeamArchiveNextIndex]
	and FINAL_TEAM_ARCHIVE_CAPACITY - 1
	ld d, a
	; Mark this slot invalid before replacing it.
	ld e, a
	ld hl, sFinalTeamArchiveRecordChecksums
	ld b, 0
	ld c, e
	add hl, bc
	ld [hl], $ff
	ld a, d
	call FinalTeamArchiveRecordAddress
	push hl
	ld d, h
	ld e, l
	ld hl, wPartyDataStart
	ld bc, FINAL_TEAM_PARTY_SIZE
	call CopyData
	pop hl
	ld bc, FINAL_TEAM_PARTY_SIZE
	add hl, bc
	pop de
	ld a, d
	ld [hli], a
	ld a, e
	ld [hl], a
	; Calculate and publish the completed record checksum.
	ld a, [sFinalTeamArchiveNextIndex]
	and FINAL_TEAM_ARCHIVE_CAPACITY - 1
	ld d, a
	call FinalTeamArchiveRecordAddress
	ld bc, FINAL_TEAM_RECORD_SIZE
	push de
	call FinalTeamArchiveChecksum
	pop de
	push af
	ld hl, sFinalTeamArchiveRecordChecksums
	ld b, 0
	ld c, d
	add hl, bc
	pop af
	ld [hl], a
	ld a, d
	ld [sFinalTeamArchiveLatestIndex], a
	inc a
	and FINAL_TEAM_ARCHIVE_CAPACITY - 1
	ld [sFinalTeamArchiveNextIndex], a
	ld a, [sFinalTeamArchiveCount]
	cp FINAL_TEAM_ARCHIVE_CAPACITY
	jr nc, .countDone
	inc a
	ld [sFinalTeamArchiveCount], a
.countDone
	call FinalTeamArchiveWriteHeaderChecksum
	call FinalTeamArchiveClose
	ld a, 1
	ld [wActionResultOrTookBattleTurn], a
	ret

; Restore the newest checksum-valid archived party and fully heal it.
FinalTeamArchiveRestoreLatest::
	xor a
	ld [wActionResultOrTookBattleTurn], a
	call FinalTeamArchiveOpen
	call FinalTeamArchiveValidateHeader
	jr nc, .fail
	ld a, [sFinalTeamArchiveCount]
	and a
	jr z, .fail
	ld b, a
	ld a, [sFinalTeamArchiveLatestIndex]
	and FINAL_TEAM_ARCHIVE_CAPACITY - 1
	ld d, a
.find
	push bc
	call FinalTeamArchiveRecordIsValid
	pop bc
	jr c, .found
	ld a, d
	dec a
	and FINAL_TEAM_ARCHIVE_CAPACITY - 1
	ld d, a
	dec b
	jr nz, .find
.fail
	call FinalTeamArchiveClose
	ret
.found
	ld a, d
	call FinalTeamArchiveRecordAddress
	ld de, wPartyDataStart
	ld bc, FINAL_TEAM_PARTY_SIZE
	call CopyData
	; hl advanced by CopyData to the sidecar.
	ld a, [hli]
	ld [wFusionSecondarySpecies], a
	ld a, [hl]
	ld [wFusionSecondaryForm], a
	call FinalTeamArchiveClose
	predef HealParty
	ld a, 1
	ld [wActionResultOrTookBattleTurn], a
	ret

; Select uniformly from all checksum-valid records and load it into the enemy
; party block. Full-health normalization is performed after SRAM is closed.
FinalTeamArchiveLoadRandomEnemy::
	xor a
	ld [wActionResultOrTookBattleTurn], a
	ld [wFinalAISecondarySpecies], a
	ld [wFinalAISecondaryForm], a
	call FinalTeamArchiveOpen
	call FinalTeamArchiveValidateHeader
	jr nc, .fail
	; Build a valid-record mask in e and count in c.
	ld d, 0
	ld e, 0
	ld c, 0
.scan
	push bc
	call FinalTeamArchiveRecordIsValid
	pop bc
	jr nc, .next
	ld a, 1
	ld b, d
	inc b
.shift
	dec b
	jr z, .shiftDone
	add a, a
	jr .shift
.shiftDone
	or e
	ld e, a
	inc c
.next
	inc d
	ld a, d
	cp FINAL_TEAM_ARCHIVE_CAPACITY
	jr c, .scan
	ld a, c
	and a
	jr z, .fail
	call Rangerandom
	; Choose the a-th set bit.
	ld c, a
	ld d, 0
.choose
	bit 0, e
	jr z, .advance
	ld a, c
	and a
	jr z, .selected
	dec c
.advance
	srl e
	inc d
	jr .choose
.selected
	ld a, d
	call FinalTeamArchiveRecordAddress
	ld de, wEnemyPartyCount
	ld bc, FINAL_TEAM_PARTY_SIZE
	call CopyData
	ld a, [hli]
	ld [wFinalAISecondarySpecies], a
	ld a, [hl]
	ld [wFinalAISecondaryForm], a
	call FinalTeamArchiveClose
	call FinalTeamArchiveHealEnemy
	ld a, 1
	ld [wActionResultOrTookBattleTurn], a
	ret
.fail
	call FinalTeamArchiveClose
	ret

; Carry set iff the current party has a representable fusion sidecar.
FinalTeamArchiveValidateFusion:
	ld a, [wPartyCount]
	and a
	ret z
	ld b, a
	ld c, 0
	ld hl, wPartyMon1CatchRate
.loop
	bit BIT_FUSION, [hl]
	jr z, .notFusion
	inc c
.notFusion
	ld de, PARTYMON_STRUCT_LENGTH
	add hl, de
	dec b
	jr nz, .loop
	ld a, c
	and a
	jr z, .plain
	cp 1
	ret nz
	ld a, [wFusionSecondarySpecies]
	and a
	ret z
	ld a, [wFusionSecondaryForm]
	cp 4
	ret nc
	scf
	ret
.plain
	; Ignore stale globals when no party struct carries the fusion bit.
	xor a
	ld [wFusionSecondarySpecies], a
	ld [wFusionSecondaryForm], a
	scf
	ret

FinalTeamArchiveOpen:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ASSERT BANK(sFinalTeamArchive) == BMODE_ADVANCED
	ld [rRAMB], a
	ret

FinalTeamArchiveClose:
	xor a
	ld [rRAMB], a
	ld a, BMODE_SIMPLE
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; Carry set iff magic/version/ranges/header checksum are valid.
FinalTeamArchiveValidateHeader:
	ld a, [sFinalTeamArchiveMagic]
	cp FINAL_TEAM_ARCHIVE_MAGIC_0
	jr nz, .invalid
	ld a, [sFinalTeamArchiveMagic + 1]
	cp FINAL_TEAM_ARCHIVE_MAGIC_1
	jr nz, .invalid
	ld a, [sFinalTeamArchiveVersion]
	cp FINAL_TEAM_ARCHIVE_VERSION_VALUE
	jr nz, .invalid
	ld a, [sFinalTeamArchiveCount]
	cp FINAL_TEAM_ARCHIVE_CAPACITY + 1
	jr nc, .invalid
	ld a, [sFinalTeamArchiveNextIndex]
	cp FINAL_TEAM_ARCHIVE_CAPACITY
	jr nc, .invalid
	ld a, [sFinalTeamArchiveCount]
	and a
	jr z, .empty
	ld a, [sFinalTeamArchiveLatestIndex]
	cp FINAL_TEAM_ARCHIVE_CAPACITY
	jr nc, .invalid
	jr .checksum
.empty
	ld a, [sFinalTeamArchiveLatestIndex]
	cp FINAL_TEAM_ARCHIVE_EMPTY_INDEX
	jr nz, .invalid
.checksum
	ld hl, sFinalTeamArchiveMagic
	ld bc, FINAL_TEAM_ARCHIVE_HEADER_SIZE - 1
	call FinalTeamArchiveChecksum
	ld hl, sFinalTeamArchiveHeaderChecksum
	cp [hl]
	jr nz, .invalid
	scf
	ret
.invalid
	and a ; explicitly clear carry for every invalid-header path
	ret

FinalTeamArchiveWriteHeaderChecksum:
	ld hl, sFinalTeamArchiveMagic
	ld bc, FINAL_TEAM_ARCHIVE_HEADER_SIZE - 1
	call FinalTeamArchiveChecksum
	ld [sFinalTeamArchiveHeaderChecksum], a
	ret

; d = record index. Carry set iff its checksum matches.
FinalTeamArchiveRecordIsValid:
	push de
	ld a, d
	call FinalTeamArchiveRecordAddress
	ld bc, FINAL_TEAM_RECORD_SIZE
	call FinalTeamArchiveChecksum
	pop de
	push af
	ld hl, sFinalTeamArchiveRecordChecksums
	ld b, 0
	ld c, d
	add hl, bc
	ld a, [hl]
	ld e, a
	pop af
	cp e
	jr nz, .invalid
	scf
	ret
.invalid
	and a ; checksum inequality must never leak cp's carry as "valid"
	ret

; a = record index, returns hl = record address.
FinalTeamArchiveRecordAddress:
	ld hl, sFinalTeamArchiveRecords
	ld bc, FINAL_TEAM_RECORD_SIZE
	jp AddNTimes

; Complemented additive checksum over bc bytes at hl.
FinalTeamArchiveChecksum:
	xor a
.loop
	add [hl]
	inc hl
	dec bc
	ld d, a
	ld a, b
	or c
	ld a, d
	jr nz, .loop
	cpl
	ret

; Enemy equivalent of HealParty. The copied party structs already contain
; calculated stats and PP-Up bits, so only volatile HP/status/PP need reset.
FinalTeamArchiveHealEnemy:
	ld a, ENEMY_PARTY_DATA
	ld [wMonDataLocation], a
	xor a
	ldh [hWhichPokemon], a
.mon
	ldh a, [hWhichPokemon]
	ld b, a
	ld a, [wEnemyPartyCount]
	cp b
	jr z, .done
	ld hl, wEnemyMon1
	ld bc, PARTYMON_STRUCT_LENGTH
	ldh a, [hWhichPokemon]
	call AddNTimes
	push hl
	ld bc, MON_STATUS
	add hl, bc
	xor a
	ld [hl], a
	pop hl
	push hl
	ld bc, MON_MAXHP
	add hl, bc
	ld a, [hli]
	ld d, a
	ld a, [hl]
	ld e, a
	pop hl
	ld bc, MON_HP
	add hl, bc
	ld [hl], d
	inc hl
	ld [hl], e
	xor a
	ldh [hCurrentMenuItem], a
.move
	; Empty move slots have zero PP and must not be passed to GetMaxPP.
	ld hl, wEnemyMon1
	ld bc, PARTYMON_STRUCT_LENGTH
	ldh a, [hWhichPokemon]
	call AddNTimes
	ld bc, MON_MOVES
	add hl, bc
	ldh a, [hCurrentMenuItem]
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	and a
	jr z, .zeroPP
	callfar GetMaxPP
	ld a, [wMaxPP]
	jr .writePP
.zeroPP
	xor a
.writePP
	ld d, a
	ld hl, wEnemyMon1
	ld bc, PARTYMON_STRUCT_LENGTH
	ldh a, [hWhichPokemon]
	call AddNTimes
	ld bc, MON_PP
	add hl, bc
	ldh a, [hCurrentMenuItem]
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	and PP_UP_MASK
	or d
	ld [hl], a
	ld hl, hCurrentMenuItem
	inc [hl]
	ld a, [hl]
	cp NUM_MOVES
	jr c, .move
	ld hl, hWhichPokemon
	inc [hl]
	jp .mon
.done
	xor a
	ld [wMonDataLocation], a
	ldh [hWhichPokemon], a
	ldh [hCurrentMenuItem], a
	ret
