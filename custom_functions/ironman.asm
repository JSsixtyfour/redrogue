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

; TODO(user): placeholder wording. wNameBuffer holds the mon's nickname.
IronmanReleasedText:
	text_ram wNameBuffer
	text " is"
	line "gone for good..."
	prompt
