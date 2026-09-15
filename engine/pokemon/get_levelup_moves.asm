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
; The level-up half is form-aware too, via GetEvosMovesEntry below. Both halves
; therefore describe the same mon. (Before that existed, this comment recorded
; the opposite: level-up moves came from the base species while the four base
; moves came from the form.)
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
	ld a, [wCurSpecies]
	call GetEvosMovesEntry         ; form's record if this mon has one
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

; ---------------------------------------------------------------------------
; GetEvosMovesEntry
;
; The single resolver every LEVEL-UP LEARNSET read goes through. Returns the
; form's own record when the mon has a form, and the species' record otherwise.
;
; INPUT:  a  = internal species index (1-based; NOT a dex number)
; OUTPUT: hl = the evos/moves record to walk
; CLOBBERS: af, bc.  PRESERVES de.
;
; WHERE THE FORM COMES FROM. Not from a new variable and not from the caller:
; from wMonHForm/wMonHFormSpecies, the pair ApplyFormOverride maintains to
; describe the header currently sitting in wMonHeader. That pair is already the
; source of truth for the two form-aware move features that work today - the
; four starting moves (wMonHMoves) and TM/HM legality (wMonHLearnset) - so
; routing the level-up learnset through it makes all three describe the same
; mon instead of two of them describing the form and one the base species.
;
; The wMonHFormSpecies compare is what makes this safe rather than a guess.
; ApplyFormOverride resets BOTH bytes together on every path it can take
; (.noForm, .haveContext, .found), so the pair can never claim a form for the
; wrong species. A caller that never loaded a header, or loaded one for some
; other mon, therefore gets form 0 and the plain species record - exactly the
; behaviour that existed before this routine did. There is no failure mode here
; that is worse than the old one.
;
; CONTRACT FOR CALLERS: load this mon's header, with its form context published,
; before asking for its learnset. Most sites already do because they need the
; header anyway; see the audit in the Phase 1 plan for the three that did not.
; ---------------------------------------------------------------------------
GetEvosMovesEntry::
	ld b, a                        ; b = species, live on both exits
	ld hl, wMonHFormSpecies
	cp [hl]
	jr nz, .baseSpecies            ; header describes someone else
	ld a, [wMonHForm]
	and a
	jr z, .baseSpecies             ; header describes this species, but no form
	ld c, a                        ; c = form index 1..NUM_FORM_SLOTS
	ld hl, FormEvosMovesPointers
.formLoop
	ld a, [hli]                    ; entry's base species
	and a
	jr z, .baseSpecies             ; end of table: no override authored for it,
	                               ; which is not an error - a form with no entry
	                               ; simply keeps its base species' learnset
	cp b
	jr nz, .nextEntry
	ld a, [hli]                    ; entry's form index
	cp c
	jr nz, .nextEntryPointer
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret
.nextEntry
	inc hl                         ; past the form byte
.nextEntryPointer
	inc hl                         ; past the 2-byte record pointer
	inc hl
	jr .formLoop

.baseSpecies
; Indexed with bc added TWICE rather than `add a` + carry fixup. Species indexes
; run past $80, so doubling in `a` overflows; adding the undoubled offset twice
; cannot.
	ld a, b
	dec a
	ld c, a
	ld b, 0
	ld hl, EvosMovesPointerTable
	add hl, bc
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret

; ---------------------------------------------------------------------------
; LearndexLoadRecordFar  (Form Learnsets Phase 3)
;
; The Learndex's form-aware record loader. Runs IN bank $31, so the record is
; a plain in-bank read and CopyData suffices; the caller over in bank $2C
; reaches it by farcall. Reads wCurSpecies, resolves through GetEvosMovesEntry
; so a form gets its own learnset, and leaves the copy in wMoveBuffer.
; CLOBBERS: af, bc, de, hl - de is the CopyData destination pointer, same as
; the old LearndexLoadRecord. Both call sites already push/pop de around this
; call (a documented past crash fixed it), so that is not this routine's
; problem to solve.
; ---------------------------------------------------------------------------
LearndexLoadRecordFar::
	ld a, [wCurSpecies]
	call GetEvosMovesEntry
	ld de, wMoveBuffer
	ld bc, LEARNDEX_RECORD_SIZE
	jp CopyData

ASSERT BANK(GetLevelUpMovesFar) == BANK(EvosMovesPointerTable), \
       "GetLevelUpMovesFar does plain in-bank reads of EvosMovesPointerTable \
and the learnset blocks it points at; it must stay in that bank"

ASSERT BANK(GetEvosMovesEntry) == BANK(EvosMovesPointerTable), \
       "GetEvosMovesEntry dereferences bare `dw` pointers out of both \
EvosMovesPointerTable and FormEvosMovesPointers with plain [hli] reads; all \
three must share one bank"

ASSERT BANK(FormEvosMovesPointers) == BANK(EvosMovesPointerTable), \
       "FormEvosMovesPointers' records are reached by bare `dw`, so the table, \
its records and EvosMovesPointerTable must all share one bank"

ASSERT BANK(LearndexLoadRecordFar) == BANK(EvosMovesPointerTable), \
       "LearndexLoadRecordFar reads GetEvosMovesEntry's returned record with a \
plain CopyData (not FarCopyData), which only works if it executes in the same \
bank as the record it is copying"
