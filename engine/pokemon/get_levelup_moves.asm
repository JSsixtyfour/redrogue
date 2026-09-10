; ---------------------------------------------------------------------------
; GetLevelUpMovesFar  (party spec system, Phase 2)
;
; Enumerates every move a mon can know from LEVELLING at or below its current
; level, into RogueBuildParty's candidate buffer.
;
; INPUT:  wCurSpecies     - the species whose learnset to walk
;         wCurEnemyLevel  - the level cap
;         wMonHMoves      - that mon's level-1 moves, form-aware, as already
;                           loaded by GetMonHeader
; OUTPUT: wPartyGenCandidates      - the move ids, deduplicated
;         wPartyGenCandidateCount  - how many
; CLOBBERS: af, bc, de, hl
;
; EVERY input and output is in WRAM, with nothing passed or returned in a
; register. That is deliberate: this routine is reached by farcall from bank
; $39, and Bankswitch destroys a, b, c, h and l on both legs, sparing only d and
; e. A WRAM-only contract cannot be broken by that, and it needs no `*Far`
; shim of its own.
;
; It lives HERE, in the "Evos Moves" section, because it walks
; EvosMovesPointerTable and dereferences the bare `dw` it finds there - both are
; plain in-bank reads, and that table can never be split from its data. The
; ASSERT below fails the build if this file is ever moved out from under it.
;
; The base moves are included because in Gen 1 a mon's level-1 moves live in its
; base-stats row (BASE_MOVES), not in the learnset, so a walk of evos_moves
; alone would miss up to four moves the mon demonstrably knows. Taking them from
; wMonHMoves rather than from BaseStats is what makes the result FORM-AWARE: a
; form record replaces the whole base-stats header, so an Alolan Marowak's
; starting moves are the form's, not Marowak's.
;
; Level-up moves come from the BASE species' learnset even for a form, because
; evos_moves.asm is species-keyed and has no form hook - see the table in
; TRAINER_PARTY_FORMS.md. That asymmetry is intentional and is why the two
; halves are gathered from different places.
; ---------------------------------------------------------------------------
GetLevelUpMovesFar::
	xor a
	ld [wPartyGenCandidateCount], a

; --- the four level-1 moves from the (possibly form-substituted) header ---
	ld hl, wMonHMoves
	ld c, NUM_MOVES
.baseLoop
	ld a, [hli]
	and a
	jr z, .baseNext                ; an empty base slot, not a terminator: keep going
	push hl
	push bc
	call PartyGenAddCandidate
	pop bc
	pop hl
.baseNext
	dec c
	jr nz, .baseLoop

; --- the level-up learnset ---
	ld hl, EvosMovesPointerTable
	ld a, [wCurSpecies]
	dec a
	add a
	ld c, a
	ld b, 0
	jr nc, .noCarry
	inc b                          ; species * 2 passes $FF for indexes >= $80
.noCarry
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
; Skip the evolution records. They are variable width, so they are skipped the
; way the rest of the engine skips them: byte by byte until the 0 terminator.
.skipEvos
	ld a, [hli]
	and a
	jr nz, .skipEvos
.learnLoop
	ld a, [hli]                    ; level of the next learnset entry
	and a
	ret z                          ; end of the learnset
	ld b, a
	ld a, [wCurEnemyLevel]
	cp b
	ret c                          ; entries are level-sorted, so we are done
	ld a, [hli]                    ; the move
	push hl
	call PartyGenAddCandidate
	pop hl
	jr .learnLoop

; ---------------------------------------------------------------------------
; PartyGenAddCandidate
; INPUT:  a = move id
; Appends it to wPartyGenCandidates unless it is already there or the buffer is
; full. CLOBBERS af, bc, hl.
; ---------------------------------------------------------------------------
PartyGenAddCandidate:
	ld b, a
	ld a, [wPartyGenCandidateCount]
	cp PARTY_GEN_MAX_CANDIDATES
	ret nc                         ; full; drop it rather than overrun the union
	ld c, a
	ld hl, wPartyGenCandidates
	and a
	jr z, .append                  ; nothing to compare against yet
.dedupeLoop
	ld a, [hli]
	cp b
	ret z                          ; already a candidate
	dec c
	jr nz, .dedupeLoop
.append
; b still holds the move id, so the offset is added to l by hand rather than
; through `add hl, bc`.
	ld a, [wPartyGenCandidateCount]
	ld hl, wPartyGenCandidates
	add l
	ld l, a
	jr nc, .noOverflow
	inc h
.noOverflow
	ld [hl], b
	ld a, [wPartyGenCandidateCount]
	inc a
	ld [wPartyGenCandidateCount], a
	ret

ASSERT BANK(GetLevelUpMovesFar) == BANK(EvosMovesPointerTable), \
       "GetLevelUpMovesFar does plain in-bank reads of EvosMovesPointerTable \
and the learnset blocks it points at; it must stay in that bank"
