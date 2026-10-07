; Ironman mode (wOptions3 BIT_IRONMAN, OPTION screen row IRONMAN).
;
; Any party mon that faints is released. Revives are not usable in battle, so
; "HP == 0 once a battle is over" is exactly "fainted during it", and the
; release happens after the battle rather than mid-battle, where compacting the
; party would break every party-index-keyed battle variable. Out-of-battle
; faints (poison) are released right after the damage step.
;
; A blackout never reaches here: it ends the run and RogueResetRunState wipes
; the party anyway. Both release entry points still refuse to empty the party
; (all members at 0 HP), because that is the blackout path's job, and the
; losable Oak's Lab rival fight must keep its starter.
;
; Every routine here is a farcall-only leaf; pinned to $3C in main.asm.

; Battle path: prints IronmanReleasedText for each mon before releasing it.
; Called from EndOfBattle only when the battle was not lost.
IronmanReleaseFaintedMons::
	ld b, 1
	jr IronmanReleaseCommon

; Poison path: silent, because the "fainted!" box (_PokemonFaintedText) has
; already carried the Ironman line for each mon.
IronmanReleaseFaintedMonsSilent::
	ld b, 0
	; fall through

; b = 1 to print a release message per mon, 0 for silent.
IronmanReleaseCommon:
	ld a, [wOptions3]
	bit BIT_IRONMAN, a
	ret z
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret z
	ld a, [wPartyCount]
	and a
	ret z
	ld c, a
; Guard: never release down to an empty party.
	ld hl, wPartyMon1HP
	ld de, PARTYMON_STRUCT_LENGTH
.aliveLoop
	ld a, [hli]
	or [hl]
	dec hl
	jr nz, .someoneAlive
	add hl, de
	dec c
	jr nz, .aliveLoop
	ret
.someoneAlive
; Walk the party from the LAST slot down, so RemovePokemon's compaction only
; ever shifts slots this loop has already visited.
	ld a, [wPartyCount]
	ld c, a ; c = slot + 1
.loop
	dec c
	push bc
	ld a, c
	ld hl, wPartyMon1HP
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	pop bc
	ld a, [hli]
	or [hl]
	jr nz, .next
	push bc
	ld a, b
	and a
	jr z, .release
	ld a, c
	ld hl, wPartyMonNicks
	call GetPartyMonName ; -> wNameBuffer
	ld hl, IronmanReleasedText
	call PrintText
	pop bc
	push bc
.release
	call FallenLogRecord ; c = slot
	pop bc
	push bc
	ld a, c
	ldh [hWhichPokemon], a
	xor a
	ld [wRemoveMonFromBox], a
	call RemovePokemon ; also updates the bridge owner map
	pop bc
.next
	ld a, c
	and a
	jr nz, .loop
	ret

; wCanEvolveFlags has one bit per party slot (bit N = slot N), set on level-up.
; In Ironman, clear the bit of every mon at 0 HP before EvolutionAfterBattle
; runs, so a mon that leveled up and then fainted does not evolve on its way
; out. Ironman OFF returns before touching anything: vanilla behaviour, where
; a fainted mon still evolves, is unchanged.
IronmanClearFaintedEvolveFlags::
	ld a, [wOptions3]
	bit BIT_IRONMAN, a
	ret z
	ld a, [wPartyCount]
	and a
	ret z
	ld c, a
	ld b, 1 ; this slot's bit
	ld hl, wPartyMon1HP
	ld de, PARTYMON_STRUCT_LENGTH
.loop
	ld a, [hli]
	or [hl]
	dec hl
	jr nz, .alive
	ld a, b
	cpl
	push hl
	ld hl, wCanEvolveFlags
	and [hl]
	ld [hl], a
	pop hl
.alive
	add hl, de
	sla b
	dec c
	jr nz, .loop
	ret

; ============================================================================
; Fallen log. sFallenLog (SRAM bank 2) holds wFallenCount valid entries, each
; FALLEN_ENTRY_SIZE bytes: the party struct, then the OT name, then the
; nickname, copied just before RemovePokemon. Capture only; nothing reads it
; yet. Once FALLEN_LOG_CAPACITY is reached, further releases are not logged.
; ============================================================================
	ASSERT FALLEN_ENTRY_SIZE == PARTYMON_STRUCT_LENGTH + NAME_LENGTH + NAME_LENGTH

; In: c = party slot. Clobbers everything.
FallenLogRecord:
	ld a, [wFallenCount]
	cp FALLEN_LOG_CAPACITY
	ret nc
	ld hl, sFallenLog
	push bc
	ld bc, FALLEN_ENTRY_SIZE
	call AddNTimes
	pop bc
	ld d, h
	ld e, l ; de = this entry
	call FallenLogOpen
	ld a, c
	push bc
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	call CopyData ; de advances past the struct
	pop bc
	ld a, c
	push bc
	ld hl, wPartyMonOT
	ld bc, NAME_LENGTH
	call AddNTimes
	call CopyData
	pop bc
	ld a, c
	ld hl, wPartyMonNicks
	ld bc, NAME_LENGTH
	call AddNTimes
	call CopyData
	call FallenLogClose
	ld hl, wFallenCount
	inc [hl]
	ret

; Zero every entry. Called at every run end (RogueResetRunState) and at new
; game (IronmanNewGameSRAMInit). wFallenCount itself lives in the region both
; of those already blanket-clear.
FallenLogClear::
	call FallenLogOpen
	ld hl, sFallenLog
	ld bc, sFallenLogEnd - sFallenLog
	xor a
	call FillMemory
	; fall through

; SRAM bank 2 selected on open; always leave bank 0 and SRAM disabled on
; close, the ambient state other SRAM users rely on
; (project_sram_new_field_needs_explicit_clear).
FallenLogClose:
	xor a
	ld [rRAMB], a
	ld [rBMODE], a
	ld [rRAMG], a ; RAMG_SRAM_DISABLE
	ret

FallenLogOpen:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sFallenLog)
	ld [rRAMB], a
	ret

; New game's single SRAM-init farcall (InitPlayerData, bank $03, ~10 B free):
; the final-team archive, the reward offer DVs, then the fallen log.
IronmanNewGameSRAMInit::
	farcall FinalTeamArchiveInit
	call RogueOfferDVsClear ; same bank ($3C), reward_offer_info.asm
	jr FallenLogClear

; TODO(user): placeholder wording. wNameBuffer holds the mon's nickname.
IronmanReleasedText:
	text_ram wNameBuffer
	text " is"
	line "gone for good..."
	prompt
