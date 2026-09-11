; RogueBuildParty - the party spec resolver (Phase 2 of
; GYM_LEADER_EXPANSION_PLAN.md).
;
; Builds an enemy party from a declarative record instead of from an authored
; `db level, species, ...` list or GetRandRoster's rarity-class roll. Reached
; from ReadTrainer, which keeps both older paths as the fallback: this routine
; reports "no spec for this trainer" by returning carry clear, and the caller
; carries on exactly as before. That is what lets Phase 3 convert nineteen
; characters one round at a time.
;
; BANK CONTRACT. Every table this file walks with a plain [hli] is INCLUDEd into
; the same "Trainer Parties" section - see the block comment at that INCLUDE in
; main.asm - and the ASSERTs at the bottom of this file fail the build if any of
; them drifts out of the bank. The cross-bank helpers it needs are reached by
; farcall, and every one of those was checked against the rule that Bankswitch
; destroys a, b, c, h and l on BOTH legs of a farcall and spares only d, e and
; the flags (see the `project_farcall_bc_clobber_bug_class` note): the helpers
; used here either take their input from WRAM or pass it in de.

; ===========================================================================
; RogueBuildParty
;
; INPUT:  wTrainerClass, wTrainerNo. The enemy party count and terminator have
;         already been reset by ReadTrainer.
; OUTPUT: carry SET   - a spec existed and the enemy party is built
;         carry CLEAR - no spec; the caller must use the authored path
; CLOBBERS: everything. The caller holds no live registers across this call.
; ===========================================================================
RogueBuildParty::
	call PartyGenFindSpec
	ret nc
	ld a, l
	ld [wPartyGenSpecPtr], a
	ld a, h
	ld [wPartyGenSpecPtr + 1], a

	call PartyGenAssignSources

	xor a
	ld [wPartyGenSlot], a
.slotLoop
	call PartyGenSpecHeader
	ld a, [hl]                     ; n_mons
	ld b, a
	ld a, [wPartyGenSlot]
	cp b
	jr nc, .done                   ; slot index reached n_mons
	call PartyGenBuildSlot
	ld a, [wPartyGenSlot]
	inc a
	ld [wPartyGenSlot], a
	cp PARTY_LENGTH
	jr c, .slotLoop                ; hard stop at PARTY_LENGTH even if n_mons lies
.done
	scf
	ret

; ===========================================================================
; PartyGenFindSpec
;
; OUTPUT: carry SET -> hl = the spec record for (wTrainerClass, wTrainerNo)
;         carry CLEAR -> no spec
;
; Three separate ways to say "no spec", all of which mean "use the authored
; path": the class has no spec list at all, wTrainerNo is outside the list, or
; the list entry is a `dw 0` hole. The hole is what lets one class mix authored
; and generated teams across its wTrainerNo range.
; ===========================================================================
PartyGenFindSpec:
	ld a, [wTrainerNo]
	and a
	jr z, .noSpec                  ; wTrainerNo is 1-based; 0 is never a spec
	ld a, [wTrainerClass]
	and a
	jr z, .noSpec
	dec a
	add a                          ; * 2; class ids stop well below $80, no carry
	ld c, a
	ld b, 0
	ld hl, PartySpecPointers
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld a, h
	or l
	jr z, .noSpec                  ; class has no spec list

	ld a, [hli]                    ; entry count
	ld b, a
	ld a, [wTrainerNo]
	cp b
	jr z, .inRange
	jr nc, .noSpec                 ; wTrainerNo past the end of the list
.inRange
	dec a                          ; 1-based wTrainerNo -> 0-based index
	add a                          ; * 2
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld a, h
	or l
	jr z, .noSpec                  ; `dw 0` hole
	scf
	ret
.noSpec
	xor a                          ; also clears carry
	ret

; hl = the current spec record. Re-read rather than cached; see wPartyGenSpecPtr.
PartyGenSpecHeader:
	ld a, [wPartyGenSpecPtr]
	ld l, a
	ld a, [wPartyGenSpecPtr + 1]
	ld h, a
	ret

; hl = this spec's MovesetMixTable row.
PartyGenMixRow:
	call PartyGenSpecHeader
	ld bc, 4
	add hl, bc
	ld a, [hl]                     ; mix id
	ld hl, MovesetMixTable
	ld bc, MIX_ENTRY_SIZE
	jp AddNTimes

; ===========================================================================
; PartyGenAssignSources
;
; Fills wPartyGenSlotSource with one MSRC_* per slot, once, before any mon is
; built. Three claims in priority order:
;
;   1. A slot override naming a source (BIT_POVR_SOURCE) or literal moves
;      (BIT_POVR_MOVES) claims its slot outright. An override that pins only a
;      species does NOT claim the slot's source - it still takes a quota, which
;      is what makes "this exact species, but roll its moveset" expressible.
;   2. BIT_PSPEC_ACE_LAST claims the last slot for the strongest source the mix
;      names, and spends that source's quota. "Strongest" is the highest MSRC_*
;      with a nonzero quota, which works because the MSRC_* order in
;      party_spec_constants.asm is ascending in power by construction.
;   3. The remaining quotas are shuffled across the slots still unassigned.
;
; Anything left over is MSRC_LEARNSET, which is free: AddPartyMon's
; `predef WriteMonMoves` already produces exactly that.
; ===========================================================================
PartyGenAssignSources:
; Mark every slot unassigned. $FF, not MSRC_LEARNSET, so the quota shuffle can
; tell "nobody claimed this" from "deliberately vanilla".
	ld hl, wPartyGenSlotSource
	ld b, PARTY_LENGTH
	ld a, $FF
.clearLoop
	ld [hli], a
	dec b
	jr nz, .clearLoop
	ld a, $FF
	ld [wPartyGenAceSource], a     ; $FF = the ace rule did not claim a source

; --- claim 1: slot overrides that name a source or literal moves ---
	call PartyGenSpecHeader
	ld bc, PARTY_SPEC_HEADER_SIZE
	add hl, bc
.overrideLoop
	ld a, [hl]
	cp PARTY_SPEC_OVERRIDES_END
	jr z, .overridesDone
	ld b, a                        ; b = slot index
	inc hl
	ld a, [hli]                    ; a = flags, hl -> first field
	ld c, a
	push hl
	push bc
	bit BIT_POVR_MOVES, c
	jr z, .noLiteralMoves
	ld a, MSRC_EXPLICIT            ; literal moves imply the explicit source
	jr .claimSlot
.noLiteralMoves
	bit BIT_POVR_SOURCE, c
	jr z, .noSourceClaim
; Read the MSRC_* byte out of the override. b is the field index wanted and is
; preserved by PartyGenFieldPtr, so it has to be loaded after b's slot-index use
; above is saved on the stack.
	ld b, BIT_POVR_SOURCE
	call PartyGenFieldPtr
	jr nc, .noSourceClaim
	ld a, [hl]
	jr .claimSlot
.noSourceClaim
	pop bc
	pop hl
	jr .skipOverride
.claimSlot
	ld d, a                        ; d = source to store
	pop bc                         ; b = slot index
	ld a, b
	cp PARTY_LENGTH
	jr nc, .claimOutOfRange        ; ignore a malformed slot index rather than
	ld hl, wPartyGenSlotSource     ; scribbling past the array
	ld c, a
	ld b, 0
	add hl, bc
	ld [hl], d
.claimOutOfRange
	pop hl
.skipOverride
; hl -> this override's first field byte; skip the fields to reach the next
; override. The flag byte is re-read from hl - 1.
	dec hl
	ld a, [hl]
	inc hl
	call PartyGenSkipFields
	jr .overrideLoop
.overridesDone

; --- claim 2: the ace ---
	call PartyGenSpecHeader
	ld bc, 5
	add hl, bc
	bit BIT_PSPEC_ACE_LAST, [hl]
	jr z, .quotas
	call PartyGenSpecHeader
	ld a, [hl]                     ; n_mons
	and a
	jr z, .quotas
	dec a                          ; last slot index
	cp PARTY_LENGTH
	jr nc, .quotas
	ld c, a
	ld b, 0
	ld hl, wPartyGenSlotSource
	add hl, bc
	ld a, [hl]
	inc a                          ; was it $FF?
	jr nz, .quotas                 ; an override already claimed the ace slot
; Walk the quota columns from the strongest end and take the first nonzero.
	push hl                        ; the ace's slot-source byte
	call PartyGenMixRow
	ld bc, NUM_MSRC_QUOTAS - 1
	add hl, bc                     ; hl -> the last quota column
	ld b, NUM_MSRC_QUOTAS - 1      ; b = the MSRC_* that column stands for
.aceScan
	ld a, [hl]
	and a
	jr nz, .aceFound
	ld a, b
	and a
	jr z, .aceNone                 ; the mix names no source at all
	dec b
	dec hl
	jr .aceScan
.aceFound
; The quota this source spends on the ace is charged in WRAM, NOT by
; decrementing the table. `ld [hl], a` here would write into MovesetMixTable,
; which sits at $4Exx in a ROMX bank - and a write to $4000-$5FFF on MBC3 is the
; RAM-bank / RTC select register. It does not store anything; it silently
; repoints SRAM, and the damage shows up later somewhere else entirely.
	ld a, b
	ld [wPartyGenAceSource], a
	pop hl
	ld [hl], a
	jr .quotas
.aceNone
	pop hl

; --- claim 3: shuffle the remaining quotas across unassigned slots ---
; For each source, for each unit of its quota, pick a random still-unassigned
; slot. Bounded: the outer walk is NUM_MSRC_QUOTAS x PARTY_LENGTH, and a quota
; unit that finds no free slot is simply dropped (the mix overflowed the team).
.quotas
	ld d, 0                        ; d = source id
.quotaSourceLoop
	call PartyGenMixRow
	ld c, d
	ld b, 0
	add hl, bc
	ld e, [hl]                     ; e = this source's quota
; Charge the ace's unit against this register copy. See .aceFound for why it
; cannot be charged against the table itself.
	ld a, [wPartyGenAceSource]
	cp d
	jr nz, .quotaUnitLoop
	ld a, e
	and a
	jr z, .quotaUnitLoop
	dec e
.quotaUnitLoop
	ld a, e
	and a
	jr z, .quotaNextSource
	push de
	call PartyGenPickFreeSlot      ; hl -> a free slot byte, carry set if any
	pop de
	jr nc, .quotaNextSource        ; team is full; drop the rest of this quota
	ld [hl], d
	dec e
	jr .quotaUnitLoop
.quotaNextSource
	inc d
	ld a, d
	cp NUM_MSRC_QUOTAS
	jr c, .quotaSourceLoop

; --- anything still unclaimed is vanilla ---
	ld hl, wPartyGenSlotSource
	ld b, PARTY_LENGTH
.defaultLoop
	ld a, [hl]
	inc a
	jr nz, .defaultNext
	ld [hl], MSRC_LEARNSET
.defaultNext
	inc hl
	dec b
	jr nz, .defaultLoop
	ret

; ===========================================================================
; PartyGenPickFreeSlot
;
; OUTPUT: carry SET -> hl points at an unassigned ($FF) byte of
;         wPartyGenSlotSource, chosen uniformly among those within n_mons
;         carry CLEAR -> no slot is free
;
; Count then select, the same two-pass shape _PickNextGym uses for badge bits,
; so the choice is uniform without needing a retry loop.
; ===========================================================================
PartyGenPickFreeSlot:
	call PartyGenSpecHeader
	ld a, [hl]                     ; n_mons
	cp PARTY_LENGTH + 1
	jr c, .gotLimit
	ld a, PARTY_LENGTH
.gotLimit
	ld e, a                        ; e = slots in play
	and a
	jr z, .none

	ld hl, wPartyGenSlotSource
	ld b, e
	ld c, 0                        ; c = free slots found
.countLoop
	ld a, [hli]
	inc a
	jr nz, .countNext
	inc c
.countNext
	dec b
	jr nz, .countLoop

	ld a, c
	and a
	jr z, .none
	call Rangerandom               ; a = 0 .. c-1, HOME, preserves bc/de
	ld c, a

; Bounded by the array length. Rangerandom's result is in range for the count
; measured above, so the bound is unreachable today - but an unbounded scan for
; a $FF byte would, if that ever stopped holding, walk out of the 6-byte array
; and hand the caller a pointer into the rest of the union for `ld [hl], d` to
; write through. A wild WRAM write is not the failure mode to leave latent in a
; routine this small.
	ld hl, wPartyGenSlotSource
	ld b, PARTY_LENGTH
.selectLoop
	ld a, [hl]
	inc a
	jr nz, .selectNext
	ld a, c
	and a
	jr z, .found
	dec c
.selectNext
	inc hl
	dec b
	jr nz, .selectLoop
	xor a                          ; ran out of array: report no free slot
	ret
.found
	scf
	ret
.none
	xor a
	ret

; ===========================================================================
; PartyGenFieldPtr
;
; Locates one optional field inside a slot override.
;
; INPUT:  hl = the override's first field byte
;         c  = the override's flag byte
;         b  = the BIT_POVR_* index wanted
; OUTPUT: carry SET -> hl = that field's first byte
;         carry CLEAR -> the field is absent
; CLOBBERS: af, c, de, hl. PRESERVES b.
;
; Fields are stored in bit order, so the offset of field b is the sum of the
; widths of the present fields below it. PartySpecOverrideFieldWidths supplies
; the widths, which is why adding a field costs one const and one table row and
; nothing else.
;
; The width is added to l with an explicit carry into h rather than through
; `add hl, bc`, because bc is holding the target index and the shifting flag
; byte - de is needed to index the width table itself.
; ===========================================================================
PartyGenFieldPtr:
	ld e, 0                        ; e = bit cursor
.loop
	ld a, e
	cp b
	jr z, .atTarget
	srl c                          ; test bit `e` of the original flags
	jr nc, .next
	push hl
	ld hl, PartySpecOverrideFieldWidths
	ld d, 0
	add hl, de
	ld a, [hl]
	pop hl
	add a, l
	ld l, a
	jr nc, .next
	inc h
.next
	inc e
	jr .loop
.atTarget
	srl c
	ret nc                         ; field absent
	scf
	ret

; ===========================================================================
; PartyGenSkipFields
;
; INPUT:  a = an override's flag byte, hl = its first field byte
; OUTPUT: hl = the byte after the last field, i.e. the next override
; CLOBBERS: af, bc, de, hl
; ===========================================================================
PartyGenSkipFields:
	ld c, a
	ld e, 0
.loop
	ld a, e
	cp NUM_POVR_FIELDS
	ret nc
	srl c
	jr nc, .next
	push hl
	ld hl, PartySpecOverrideFieldWidths
	ld d, 0
	add hl, de
	ld a, [hl]
	pop hl
	add a, l
	ld l, a
	jr nc, .next
	inc h
.next
	inc e
	jr .loop

; ===========================================================================
; PartyGenBuildSlot
;
; Builds the one mon for slot [wPartyGenSlot]: resolve species and form,
; resolve level, evolve if it came from the pool, create it, then apply its
; assigned moveset source.
; ===========================================================================
PartyGenBuildSlot:
; --- level, before the species roll: ScaleTrainer_evolution needs it ---
	call PartyGenResolveLevel

; --- species and form ---
	call PartyGenResolveSpecies    ; sets wCurPartySpecies, carry set if pinned
	push af                        ; remember whether it was pinned

; A pinned species is NOT evolved. Evolving it would defeat the pin, which is
; the whole point of BIT_POVR_SPECIES - an author writing PIDGEOT at level 17
; means Pidgeot, not "whatever Pidgeot evolves into by then".
	jr c, .noEvolve
	ld a, [wCurPartySpecies]
	ld d, a
	farcall ScaleTrainer_evolution ; d = species in; publishes the promoted one
.noEvolve

; --- form ---
; wCurPartySpecies is FINAL here, after any evolution step, which matters
; because a form record is keyed to the species that carries the sprite: rolling
; before the evolve would ask for (EXEGGCUTE, 1), which does not exist, instead
; of (EXEGGUTOR, 1), which does.
	pop af
	call PartyGenResolveForm

; --- create it ---
; wSpawnForm is written immediately before AddPartyMon and nothing between them
; creates a mon, which is the "write wSpawnForm only just before a creation"
; rule holding by construction. AddPartyMon folds the form into this mon's own
; MON_CATCH_RATE bits 5-6 and clears wSpawnForm again.
	ld a, ENEMY_PARTY_DATA
	ld [wMonDataLocation], a
	call AddPartyMon

; --- moveset ---
	jp PartyGenApplyMoveset

; ===========================================================================
; PartyGenResolveLevel
;
; wCurEnemyLevel = an override's absolute level, else base_level + slot * step
; with a signed step, clamped to 1..MAX_LEVEL. Then the existing witch and
; difficulty modifiers run, exactly as the authored path does.
; ===========================================================================
PartyGenResolveLevel:
	ld a, [wPartyGenSlot]
	ld b, a
	call PartyGenFindOverrideForSlot
	jr nc, .fromSpec
	ld b, BIT_POVR_LEVEL
	call PartyGenFieldPtr
	jr nc, .fromSpec
	ld a, [hl]
	jr .gotLevel
.fromSpec
	call PartyGenSpecHeader
	inc hl
	ld a, [hli]                    ; base level
	ld d, a
	ld a, [hl]                     ; level step, signed
	ld e, a
	ld a, [wPartyGenSlot]
	ld b, a
	ld a, d
.stepLoop
	ld d, a
	ld a, b
	and a
	jr z, .stepDone
	ld a, d
	add e                          ; a signed step just wraps, which is correct
	dec b
	jr .stepLoop
.stepDone
	ld a, d
.gotLevel
; Clamp. A negative step can walk a late slot below 1, and MAX_LEVEL is the
; ceiling every other level path in the game respects.
	and a
	jr nz, .notZero
	inc a
.notZero
	cp MAX_LEVEL + 1
	jr c, .inRange
	ld a, MAX_LEVEL
.inRange
	ld [wCurEnemyLevel], a
	farcall RogueApplyTrainerLevelModifiers
	ret

; ===========================================================================
; PartyGenResolveSpecies
;
; OUTPUT: wCurPartySpecies set; carry SET if the species was PINNED by an
;         override (so the caller must not evolve it), carry CLEAR if it came
;         from the pool.
; ===========================================================================
PartyGenResolveSpecies:
	ld a, [wPartyGenSlot]
	ld b, a
	call PartyGenFindOverrideForSlot
	jr nc, PartyGenRollFromPool
	ld b, BIT_POVR_SPECIES
	call PartyGenFieldPtr
	jr nc, PartyGenRollFromPool
	ld a, [hl]
	ld [wCurPartySpecies], a
	scf
	ret

; ===========================================================================
; PartyGenRollFromPool
;
; Rolls a species from the spec's pool, honouring the active species groups and
; BIT_PSPEC_NO_DUPES.
;
; A pool is three contiguous runs (Kanto, Johto, Time Warp) with one count each.
; Only the runs whose group bit is active this run are eligible, so a pool
; shrinks to the player's unlock state without a per-entry group byte. The
; eligible runs are not contiguous in general - Johto off with Time Warp on is a
; legal state - so the draw is "roll within the total, then walk the runs
; subtracting", which is three iterations, not a scan.
; ===========================================================================
PartyGenRollFromPool:
	ld c, PARTY_GEN_MAX_RETRIES
.retry
	push bc
	call PartyGenDrawFromPool      ; wCurPartySpecies set, carry set on success
	pop bc
	jr nc, .giveUp
	push bc
	call PartyGenPoolCandidateOk   ; carry set = passes every filter
	pop bc
	jr c, .accept
	dec c
	jr nz, .retry
; Retries exhausted. The LAST draw stands: it is a real member of the pool and
; only failed a preference (a duplicate, a rarity or type filter), so it is a
; strictly better answer than refusing to build the slot. Bounded-then-accept,
; the same shape the moveset sampler uses, and for the same reason: a pool
; smaller than the team size or a filter no pool member satisfies must degrade,
; never spin.
.accept
	xor a                          ; carry clear = came from the pool
	ret
.giveUp
; No eligible entry at all - an empty pool, or every run's group locked. Fall
; back to the pool's first entry, unfiltered, so wCurPartySpecies cannot be left
; holding whatever the previous mon used.
	call PartyGenPoolList
	ld a, [hl]
	ld [wCurPartySpecies], a
	xor a
	ld [wSpawnForm], a
	xor a
	ret

; hl -> this spec's TrainerPoolTable entry (the three counts, then the `dw`).
PartyGenPoolEntry:
	call PartyGenSpecHeader
	ld bc, 3
	add hl, bc
	ld a, [hl]                     ; pool id
	ld hl, TrainerPoolTable
	ld bc, POOL_TABLE_ENTRY_SIZE
	jp AddNTimes

; hl -> entry 0 of this spec's pool species list, i.e. the table entry's `dw`
; DEREFERENCED. Distinct from PartyGenPoolEntry, which points at the counts -
; conflating the two reads a run count as a species id.
PartyGenPoolList:
	call PartyGenPoolEntry
	ld bc, 3
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret

; ===========================================================================
; PartyGenPoolCandidateOk
;
; OUTPUT: carry SET if the freshly drawn wCurPartySpecies passes every filter
;         that applies to this slot.
;
; Four filters, cheapest first:
;   BIT_PSPEC_NO_DUPES     already on the team
;   BIT_PSPEC_ALLOW_UBER RARITY_TIER_UBER species are excluded unless set, so
;                          a pool may list Articuno without a route trainer
;                          being handed one
;   BIT_POVR_RARITY        this slot demands a specific rarity tier
;   BIT_POVR_TYPE          this slot demands a type
;
; The type test reads the species AS DRAWN, before form substitution, because
; the form is not resolved until after the evolution step. That matters for a
; pool entry with a pinned form that changes type (Alolan Ninetales is Ice, not
; Fire): such an entry is filtered on its BASE type. Pin the species on the slot
; instead of filtering by type if that distinction matters.
; ===========================================================================
PartyGenPoolCandidateOk:
; --- duplicates ---
	call PartyGenSpecHeader
	ld bc, 5
	add hl, bc
	bit BIT_PSPEC_NO_DUPES, [hl]
	jr z, .dupesOk
	call PartyGenSpeciesAlreadyUsed
	jr c, .reject
.dupesOk

; --- legendary ---
	call PartyGenSpecHeader
	ld bc, 5
	add hl, bc
	bit BIT_PSPEC_ALLOW_UBER, [hl]
	jr nz, .legendOk
	ld a, [wCurPartySpecies]
	ld e, a
	farcall RogueGetSpeciesTierFar ; e = RARITY_TIER_*, $FF if in no pool
	ld a, e
	cp RARITY_TIER_UBER
	jr z, .reject
.legendOk

; --- per-slot rarity ---
	ld a, [wPartyGenSlot]
	ld b, a
	call PartyGenFindOverrideForSlot
	jr nc, .accept                 ; no override, so no rarity or type demand
	push bc
	push hl
	ld b, BIT_POVR_RARITY
	call PartyGenFieldPtr
	jr nc, .rarityOk
	ld d, [hl]                     ; d = the demanded tier; survives the farcall
	ld a, [wCurPartySpecies]
	ld e, a
	farcall RogueGetSpeciesTierFar
	ld a, e
	cp d
	jr nz, .rejectPopped
.rarityOk
	pop hl
	pop bc

; --- per-slot type ---
	push bc
	push hl
	ld b, BIT_POVR_TYPE
	call PartyGenFieldPtr
	jr nc, .typeOk
	ld d, [hl]                     ; d = the demanded type
	ld a, [wCurPartySpecies]
	ld [wCurSpecies], a
	push de
	call GetMonHeader              ; HOME; publishes wMonHType1/2
	pop de
	ld a, [wMonHType1]
	cp d
	jr z, .typeOk
	ld a, [wMonHType2]
	cp d
	jr nz, .rejectPopped
.typeOk
	pop hl
	pop bc
.accept
	scf
	ret
.rejectPopped
	pop hl
	pop bc
.reject
	xor a
	ret

; ===========================================================================
; PartyGenDrawFromPool
;
; One uniform draw across the eligible runs of the spec's pool.
;
; OUTPUT: carry SET -> wCurPartySpecies = the drawn species and wSpawnForm = the
;                      entry's form SPEC, resolved later by PartyGenResolveForm
;         carry CLEAR -> no eligible entry
;
; The eligible runs are not contiguous in general (Johto off with Time Warp on
; is a legal state), so this is "total the active runs, roll once inside that
; total, then walk the three runs subtracting". The important subtlety: the
; DRAW is charged only against active runs, but the list OFFSET must advance
; past inactive runs too, because their entries still occupy space in the list.
; Conflating the two would silently return the wrong species whenever a middle
; group was disabled - the kind of bug that looks like a bad pool rather than
; bad indexing.
; ===========================================================================
PartyGenDrawFromPool:
	call PartyGenPoolEntry
	ld a, [hli]
	ld b, a                        ; b = Kanto run count
	ld a, [hli]
	ld c, a                        ; c = Johto run count
	ld a, [hli]
	ld d, a                        ; d = Time Warp run count
	ld a, [hli]
	ld e, a
	ld a, [hl]
	ld h, a
	ld l, e                        ; hl = the species list base
	push hl

; The mask has to come back in e: RogueGetActiveGroupMask returns in a, which a
; farcall destroys. See RogueGetActiveGroupMaskFar in engine/pokemon/rarity.asm.
	push bc
	push de
	farcall RogueGetActiveGroupMaskFar
	ld a, e                        ; stash it in a, which survives the pops
	pop de
	pop bc
	ld e, a                        ; e = active group mask

; --- total the ACTIVE runs ---
	xor a
	bit BIT_GROUP_KANTO, e
	jr z, .skipKantoTotal
	add b
.skipKantoTotal
	bit BIT_GROUP_JOHTO, e
	jr z, .skipJohtoTotal
	add c
.skipJohtoTotal
	bit BIT_GROUP_WARP, e
	jr z, .skipWarpTotal
	add d
.skipWarpTotal
	and a
	jr z, .empty

	push bc
	push de
	ld c, a
	call Rangerandom               ; a = 0 .. total-1, HOME
	pop de
	pop bc
	ld h, a                        ; h = the draw, counted down run by run
	ld l, 0                        ; l = list offset accumulated so far

; --- Kanto run ---
	bit BIT_GROUP_KANTO, e
	jr z, .kantoInactive
	ld a, b
	cp h
	jr z, .kantoPast               ; count == draw, so the draw is past this run
	jr c, .kantoPast               ; count < draw
	ld a, l                        ; count > draw: the draw lands here
	add h
	jr .found
.kantoPast
	ld a, h
	sub b
	ld h, a
.kantoInactive
	ld a, l
	add b
	ld l, a

; --- Johto run ---
	bit BIT_GROUP_JOHTO, e
	jr z, .johtoInactive
	ld a, c
	cp h
	jr z, .johtoPast
	jr c, .johtoPast
	ld a, l
	add h
	jr .found
.johtoPast
	ld a, h
	sub c
	ld h, a
.johtoInactive
	ld a, l
	add c
	ld l, a

; --- Time Warp run ---
	bit BIT_GROUP_WARP, e
	jr z, .outOfRange
	ld a, d
	cp h
	jr z, .outOfRange
	jr c, .outOfRange
	ld a, l
	add h
	jr .found
.outOfRange
; Unreachable while the total above is exact. Falling back to entry 0 rather
; than to whatever hl happened to hold keeps a future arithmetic slip a wrong
; species instead of a garbage index.
	xor a
.found
	pop hl                         ; hl = the species list base
	add a                          ; entry index * POOL_ENTRY_SIZE
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld [wCurPartySpecies], a
	ld a, [hl]
	ld [wSpawnForm], a             ; the form SPEC, not yet a form index
	scf
	ret
.empty
	pop hl
	xor a
	ret

; ===========================================================================
; PartyGenSpeciesAlreadyUsed
;
; OUTPUT: carry SET if wCurPartySpecies is already on the team, where "on the
;         team" means EITHER already built OR pinned by a slot override that
;         has not been built yet.
;
; The second half is not an extra: without it BIT_PSPEC_NO_DUPES is broken for
; exactly the specs most likely to use it. Slots are built in order, so a spec
; whose ace is pinned to PIDGEOT has an empty party while slots 0 and 1 roll -
; and a pool containing PIDGEOT will happily hand it to slot 0, producing a team
; with two Pidgeot and a NO_DUPES flag that appeared to do nothing. Caught by
; test_no_dupes_flag_is_honoured on its second build.
; ===========================================================================
PartyGenSpeciesAlreadyUsed:
	ld a, [wCurPartySpecies]
	ld c, a                        ; c = the species being tested, throughout

; --- already built ---
	ld a, [wEnemyPartyCount]
	and a
	jr z, .checkPinned
	ld b, a
	ld hl, wEnemyPartySpecies
.builtLoop
	ld a, [hli]
	cp c
	jr z, .yes
	dec b
	jr nz, .builtLoop

; --- pinned by an override, built or not ---
.checkPinned
	call PartyGenSpecHeader
	ld de, PARTY_SPEC_HEADER_SIZE
	add hl, de
.overrideLoop
	ld a, [hl]
	cp PARTY_SPEC_OVERRIDES_END
	jr z, .no
	inc hl
	ld a, [hli]                    ; a = flags, hl -> first field
	ld b, a                        ; b = flags, kept for the skip below
; PartyGenFieldPtr moves hl, so the first-field pointer is stacked to resume the
; walk from it afterwards.
	push hl
	push bc                        ; b = flags, c = the species under test
	ld c, a                        ; c = flags, as PartyGenFieldPtr wants it
	ld b, BIT_POVR_SPECIES
	call PartyGenFieldPtr
	pop bc                         ; restores c = the species under test
	jr nc, .nextOverride
	ld a, [hl]
	cp c
	jr z, .yesPop
.nextOverride
	pop hl                         ; the first-field pointer
	ld a, b                        ; the flags
	push bc
	call PartyGenSkipFields
	pop bc
	jr .overrideLoop
.yesPop
	pop hl
.yes
	scf
	ret
.no
	xor a
	ret

; ===========================================================================
; PartyGenResolveForm
;
; INPUT:  carry SET if the species was pinned by an override (in which case the
;         override's own form byte is authoritative), carry CLEAR if it came
;         from the pool (in which case wSpawnForm already holds the pool
;         entry's form SPEC).
; OUTPUT: wSpawnForm holds a literal form index, 0 for none.
;
; POOL_FORM_ROLL defers to RogueRollFormForSpecies, which is the same gated
; roller a procedural roster mon uses, so unlock state is respected. A pinned
; 1..NUM_FORM_SLOTS is passed through UNGATED, deliberately and consistently
; with authored TRAINERPARTY_FORMS teams: TRAINER_PARTY_FORMS.md's rule is that
; authored content shows what you wrote regardless of unlock state, and that a
; form index with no matching record degrades to the base species silently.
; ===========================================================================
PartyGenResolveForm:
	jr nc, .haveSpec
; Pinned species: re-read the override's form byte, which sits directly after
; the species byte in the BIT_POVR_SPECIES field.
	ld a, [wPartyGenSlot]
	ld b, a
	call PartyGenFindOverrideForSlot
	jr nc, .noForm
	ld b, BIT_POVR_SPECIES
	call PartyGenFieldPtr
	jr nc, .noForm
	inc hl
	ld a, [hl]
	ld [wSpawnForm], a
.haveSpec
	ld a, [wSpawnForm]
	cp POOL_FORM_ROLL
	jr z, .roll
	ret                            ; POOL_FORM_BASE (0) or a literal index
.roll
; Gate on the species-group unlocks exactly the way the procedural roster path
; does (custom_functions/func_enc_gen.asm). Flags survive Bankswitch - it only
; does `pop bc` and two `ld`s on the way out - so testing Z after a farcall is
; sound, unlike testing `a`.
	farcall RogueFormsUnlocked
	jr z, .noForm

; ⚠ RogueRollFormForSpecies takes TWO inputs, not one: e = species AND
; d = the active group mask, which its IsFormCandidate check uses as the
; per-form unlock gate. An earlier version of this routine set only e, leaving
; whatever happened to be in d as the mask - which does not crash and does not
; fail to assemble, it just gates forms against garbage. The visible symptom
; would have been regional forms appearing in a fresh Kanto run, which is the
; exact bug TRAINER_PARTY_FORMS.md records from the last time this was got
; wrong ("Alolan Meowth shows up on turn one").
	farcall RogueGetActiveGroupMaskFar ; e = mask
	ld d, e                            ; d = mask, the per-form gate
	ld a, [wCurPartySpecies]
	ld e, a
	farcall RogueRollFormForSpecies ; e = form index, 0 if none (d preserved)
	ld a, e
	ld [wSpawnForm], a
	ret
.noForm
	xor a
	ld [wSpawnForm], a
	ret

; ===========================================================================
; PartyGenFindOverrideForSlot
;
; INPUT:  b = slot index
; OUTPUT: carry SET -> hl = that override's first field byte, c = its flags
;         carry CLEAR -> the slot has no override
; PRESERVES b.
; ===========================================================================
PartyGenFindOverrideForSlot:
	call PartyGenSpecHeader
	ld de, PARTY_SPEC_HEADER_SIZE
	add hl, de
.loop
	ld a, [hl]
	cp PARTY_SPEC_OVERRIDES_END
	jr z, .notFound
	cp b
	jr z, .found
	inc hl
	ld a, [hli]
	push bc
	call PartyGenSkipFields
	pop bc
	jr .loop
.found
	inc hl
	ld a, [hli]
	ld c, a
	scf
	ret
.notFound
	xor a
	ret

; ===========================================================================
; PartyGenApplyMoveset
;
; The mon for this slot has just been created, so it ALREADY carries its
; MSRC_LEARNSET moveset: AddPartyMon runs `predef WriteMonMoves`, which is
; exactly that source. Every other source overwrites those four move bytes and
; their matching PP.
; ===========================================================================
PartyGenApplyMoveset:
	ld a, [wPartyGenSlot]
	ld c, a
	ld b, 0
	ld hl, wPartyGenSlotSource
	add hl, bc
	ld a, [hl]
	ld [wPartyGenSource], a

	cp MSRC_LEARNSET
	ret z                          ; already done, for free, by AddPartyMon
	cp MSRC_TUTOR
	ret z                          ; declared, no table yet: behaves as learnset
	cp MSRC_EXPLICIT
	jp z, PartyGenApplyExplicitMoves
	cp MSRC_SET
	jr nz, PartyGenRollMoveset
	call PartyGenApplySetMoveset
	ret c                          ; a matching curated set was found and written
; MSRC_SET falls back to MSRC_RANDOM when this species has no curated set
; passing this mix's set_tier_mask and this mon's level - not a bug, since the
; corpus tier distribution is skewed enough (HARD 1,204 of 1,816 kept records,
; EASY 114, BAD 26 - see data/trainers/movesets.asm's own header) that a
; narrow tier mask on an uncommon species legitimately yields zero candidates.
	ld a, MSRC_RANDOM
	ld [wPartyGenSource], a
	; fallthrough

; ===========================================================================
; PartyGenRollMoveset
;
; Fills all four move slots from the candidate pool the source names.
; wPartyGenSource selects which pool:
;
;   MSRC_LEARNSET_FULL   level-up segment, UNWEIGHTED (its whole character is
;                        "any of them", not "the good ones")
;   MSRC_RANDOM          level-up segment, rank-weighted
;   MSRC_RANDOM_TM       both segments, rank-weighted, tm_cap on TM-only moves
;   MSRC_RANDOM_TM_ONLY  TM segment only, rank-weighted
; ===========================================================================
PartyGenRollMoveset:
; Reload the header for the mon that was just created, so wMonHMoves and
; wMonHLearnset describe THIS mon, form included, rather than whatever species
; GetMonHeader last saw. Species and form are read back out of the mon's own
; struct rather than from wCurPartySpecies, which AddPartyMon is free to have
; modified on its way through.
	call PartyGenLastMonBase       ; hl -> the mon's party_struct base
	ld a, [hl]                     ; MON_SPECIES
	ld [wCurSpecies], a
	call PublishFormContext        ; HOME; reads MON_CATCH_RATE at hl, keeps hl
	call GetMonHeader

; --- level-up candidates ---
	ld a, [wPartyGenSource]
	cp MSRC_RANDOM_TM_ONLY
	jr z, .noLevelUpSegment
	farcall GetLevelUpMovesFar     ; WRAM in, WRAM out; see that routine's header
	jr .levelUpDone
.noLevelUpSegment
	xor a
	ld [wPartyGenCandidateCount], a
.levelUpDone

; --- TM/HM candidates ---
	ld a, [wPartyGenSource]
	cp MSRC_RANDOM_TM
	jr z, .countTMs
	cp MSRC_RANDOM_TM_ONLY
	jr z, .countTMs
	xor a                          ; MSRC_RANDOM and MSRC_LEARNSET_FULL: none
	ld [wPartyGenTMCount], a
	jr .tmsDone
.countTMs
	call PartyGenCountTMs
.tmsDone
	xor a
	ld [wPartyGenTMUsed], a

; Clear the four move slots. Two reasons: the "is this move already chosen"
; test reads them, so a leftover learnset move would wrongly exclude itself
; from the new pool; and if the pool runs dry the slot must end up NO_MOVE
; rather than holding half a vanilla moveset.
	call PartyGenClearMoves

	ld c, 0                        ; c = move slot being filled
.pickLoop
	push bc
	call PartyGenPickOne           ; a = move id, 0 if nothing selectable
	pop bc
	and a
	jr z, .movesFinal              ; pool exhausted; the rest stay NO_MOVE
	push bc
	call PartyGenWriteMove
	pop bc
	inc c
	ld a, c
	cp NUM_MOVES
	jr c, .pickLoop
.movesFinal:
; The four move slots are final here on every path (pool exhausted early or
; all four filled). require_flags gets its one guaranteed pass now, after
; every write and before this mon counts as done.
	jp PartyGenApplyRequireFlags

; ===========================================================================
; PartyGenApplySetMoveset (MSRC_SET)
;
; The moveset corpus (data/trainers/movesets.asm, generated by
; tools/gen_movesets.py) lives in banks $3A/$3B/$3D, not here in $39, and at
; ~16 KB total it cannot be moved to share this bank the way the smaller
; tables above do. Every read of it goes through FarCopyData2 (HOME, plain
; `call` - HOME is always mapped, so this needs no farcall) rather than a raw
; [hl] walk, which is what a routine executing from ROMX must do to read a
; DIFFERENT ROMX bank's data safely.
;
; TWO FULL PASSES, not rejection sampling - the same reasoning
; RogueRollFormForSpecies documents for its own two-pass walk: a narrow
; set_tier_mask on a lightly-covered species can leave very few or zero
; legal records, and a bounded-retry sampler could report "none" when one
; actually exists. Pass 1 counts how many of this species' records pass the
; filter; pass 2 walks again to find the Nth passing one, N rolled by
; Rangerandom against the pass-1 count. Cost is at most 2x the species'
; record count in 8-byte FarCopyData2 reads (max seen in the corpus: 40, i.e.
; a bounded handful of calls), once per mon, not per party-gen retry.
;
; Reuses wPartyGenCandidates (16 B) + wPartyGenTMCount + wPartyGenTMUsed as
; scratch - none of the three are read again until PartyGenRollMoveset
; re-populates them fresh, which happens only on the fallback path this
; routine's failure leads to. Byte layout, entirely local to this routine:
;   wPartyGenCandidates + 0,1   records array base address (dw)
;   wPartyGenCandidates + 2     record count for this species
;   wPartyGenCandidates + 3     the bank the records array lives in
;   wPartyGenCandidates + 4..11 the record currently being examined (8 B)
;   wPartyGenCandidates + 12    loop index i
;   wPartyGenTMUsed             this mix's set_tier_mask
;   wPartyGenTMCount            pass 1: running match count. pass 2: the
;                               target ordinal, countding down to 0
;
; OUTPUT: carry SET and the mon's 4 moves + PP written, if a record passing
;         this mix's set_tier_mask and this mon's level exists.
;         carry CLEAR otherwise - caller falls back to MSRC_RANDOM.
; ===========================================================================
PartyGenApplySetMoveset:
	call PartyGenLastMonBase       ; hl -> mon struct; MON_SPECIES is byte 0
	ld a, [hl]
	ld c, a
	ld b, 0
	ld hl, MovesetSpeciesIndex
	add hl, bc
	add hl, bc
	add hl, bc
	add hl, bc                     ; hl = &MovesetSpeciesIndex[species] (*4)
	ld a, BANK(MovesetSpeciesIndex)
	ld de, wPartyGenCandidates
	ld bc, 4
	call FarCopyData2               ; wPartyGenCandidates[0..3] = offset,count,bank
	ld a, [wPartyGenCandidates + 2]
	and a
	jp z, .noMatch                  ; this species has no curated sets at all

	call PartyGenMixRow             ; hl -> this spec's mix row
	ld bc, 6
	add hl, bc
	ld a, [hl]                      ; set_tier_mask
	ld [wPartyGenTMUsed], a

; --- pass 1: count how many records pass the filter ---
	xor a
	ld [wPartyGenTMCount], a
	xor a
	ld [wPartyGenCandidates + 12], a ; i = 0
.pass1Loop
	call .loadRecord
	call .recordPasses
	jr nc, .pass1NoMatch
	ld hl, wPartyGenTMCount
	inc [hl]
.pass1NoMatch
	ld hl, wPartyGenCandidates + 12
	inc [hl]
	ld a, [hl]
	ld hl, wPartyGenCandidates + 2
	cp [hl]
	jr c, .pass1Loop

	ld a, [wPartyGenTMCount]
	and a
	jp z, .noMatch                   ; nothing passed the tier/level filter

; --- roll which of the matches (0..matchcount-1) to use, then find it ---
	ld c, a
	call Rangerandom                 ; a = 0..matchcount-1; PRESERVES bc/de
	ld [wPartyGenTMCount], a         ; now the target ordinal, counted down below
	xor a
	ld [wPartyGenCandidates + 12], a ; i = 0 again
.pass2Loop
	call .loadRecord
	call .recordPasses
	jr nc, .pass2Next
	ld a, [wPartyGenTMCount]
	and a
	jr z, .pass2Found
	dec a
	ld [wPartyGenTMCount], a
.pass2Next
	ld hl, wPartyGenCandidates + 12
	inc [hl]
	jr .pass2Loop
; No bound check on i here: pass 1 already proved at least (target+1) records
; among the first `count` pass the SAME filter, so pass 2 finding its target
; before i reaches count is guaranteed, not merely hoped for.
.pass2Found:
	ld c, 0
	ld a, [wPartyGenCandidates + 4]
	call PartyGenWriteMove
	ld c, 1
	ld a, [wPartyGenCandidates + 5]
	call PartyGenWriteMove
	ld c, 2
	ld a, [wPartyGenCandidates + 6]
	call PartyGenWriteMove
	ld c, 3
	ld a, [wPartyGenCandidates + 7]
	call PartyGenWriteMove
	scf
	ret
.noMatch:
	xor a
	ret

; Loads the i-th record (wPartyGenCandidates+12) of the species array
; described by wPartyGenCandidates+0..3 into wPartyGenCandidates+4..11.
; CLOBBERS af, bc, de, hl.
.loadRecord:
	ld a, [wPartyGenCandidates + 12]
	ld c, a
	ld b, 0
	sla c
	rl b
	sla c
	rl b
	sla c
	rl b                            ; bc = i * 8 (MOVESET_RECORD_SIZE)
	ld a, [wPartyGenCandidates]
	ld l, a
	ld a, [wPartyGenCandidates + 1]
	ld h, a
	add hl, bc                      ; hl = records base + i*8
	ld a, [wPartyGenCandidates + 3] ; bank
	ld de, wPartyGenCandidates + 4
	ld bc, 8
	jp FarCopyData2                 ; tail call; FarCopyData2 itself ends in ret

; OUTPUT: carry SET if the record just loaded (wPartyGenCandidates+4..11)
;         passes this mix's set_tier_mask AND this mon's level range.
; CLOBBERS af, hl, d.
.recordPasses:
	ld a, [wPartyGenCandidates + 8] ; tier
	ld hl, wPartyGenTMUsed          ; set_tier_mask
	and [hl]
	jr z, .recordFail
	ld a, [wCurEnemyLevel]
	ld hl, wPartyGenCandidates + 10 ; lvl_min
	cp [hl]
	jr c, .recordFail                ; level < lvl_min
	inc hl                            ; lvl_max
	ld d, a                           ; d = level
	ld a, [hl]
	cp d
	jr c, .recordFail                 ; lvl_max < level
	scf
	ret
.recordFail:
	xor a
	ret

; ===========================================================================
; PartyGenPickOne
;
; OUTPUT: a = the chosen move id, 0 if nothing is selectable
;
; REJECTION SAMPLING, not a weighted sum. Draw a candidate uniformly, then
; accept it with probability weight/64 from MoveRankWeightTable. Chosen over
; "sum the weights, roll inside the total, walk subtracting" because the sum
; over a ~70-candidate pool with weights up to 64 overflows a byte, forcing
; 16-bit accumulation AND a 16-bit modulo, for a distribution that is no better:
; rejection sampling is exactly proportional to weight.
;
; The retry budget bounds it. If every draw is rejected, the last ELIGIBLE draw
; is taken anyway, so the routine always terminates and a slot is never left
; empty because the dice were unkind. That tail is uniform rather than weighted,
; which is a real and deliberate bias: it only bites when the whole candidate
; pool sits in a low-weight rank, and taking a low-ranked move there is the
; correct outcome anyway.
;
; MSRC_LEARNSET_FULL skips the weighting entirely and accepts the first eligible
; draw, which is what distinguishes it from MSRC_RANDOM.
; ===========================================================================
PartyGenPickOne:
	ld b, PARTY_GEN_MAX_DRAWS
.draw
	call PartyGenDrawCandidate     ; e = move id (0 = ineligible), c = weight
	ld a, e
	and a
	jr z, .next
	ld a, [wPartyGenSource]
	cp MSRC_LEARNSET_FULL
	jr z, .accept                  ; unweighted source
	call Random                    ; HOME; preserves bc/de/hl
	and 63
	cp c
	jr c, .accept                  ; roll < weight
.next
	dec b
	jr nz, .draw
; Budget spent. Take the last eligible draw if there was one.
	ld a, e
	and a
	ret z
.accept
	call PartyGenChargeTMOnly      ; spends tm_cap if e is a TM-only move
	ld a, e
	ret

; ===========================================================================
; PartyGenDrawCandidate
;
; One uniform draw over the two candidate segments, with the eligibility filter
; applied.
;
; OUTPUT: e = the drawn move id, or 0 if the draw was ineligible
;         c = its acceptance weight out of 64
; PRESERVES b (PartyGenPickOne's retry counter).
;
; The candidate space is [level-up segment][TM segment]. A draw below
; wPartyGenCandidateCount indexes the buffer; the rest index the set bits of
; wMonHLearnset.
; ===========================================================================
PartyGenDrawCandidate:
	push bc
	ld a, [wPartyGenCandidateCount]
	ld c, a
	ld a, [wPartyGenTMCount]
	add c
	jr z, .none
	ld c, a
	call Rangerandom               ; a = 0 .. total-1; preserves bc/de
	ld hl, wPartyGenCandidateCount
	cp [hl]
	jr c, .levelUpSegment

; --- TM segment ---
	sub [hl]
	call PartyGenTMMoveByIndex     ; a = the move for the a-th set learnset bit
	ld e, a
	and a
	jr z, .ineligible
	call PartyGenIsTMOnly          ; carry set if e is not level-learnable here
	jr nc, .filter
	call PartyGenTMCapReached
	jr c, .ineligible
	jr .filter

; --- level-up segment ---
.levelUpSegment
	ld c, a
	ld b, 0
	ld hl, wPartyGenCandidates
	add hl, bc
	ld a, [hl]
	ld e, a
	and a
	jr z, .ineligible

; --- eligibility ---
.filter
	call PartyGenMoveAlreadyChosen
	jr c, .ineligible
	call PartyGenMoveRank          ; a = MOVE_RANK_* for the move in e
	cp MOVE_RANK_OFFLIST
	jr z, .ineligible              ; Splash, Teleport, Whirlwind, Struggle, ...
	ld c, a                        ; c = rank
	call PartyGenMoveForbidden
	jr c, .ineligible
	ld a, c
	call PartyGenRankWeight        ; a = weight out of 64 for (rank, rank_row)
	and a
	jr z, .ineligible              ; weight 0 means unreachable for this row
; The weight parks in d, not c, so `pop bc` can restore the caller's retry
; counter in b first and c can then be overwritten. d is free here: e carries
; the move id and d is not part of this routine's output.
	ld d, a
	pop bc
	ld c, d
	ret
.ineligible
	ld e, 0
	pop bc
	ld c, 0
	ret
.none
	ld e, 0
	pop bc
	ld c, 0
	ret

; ===========================================================================
; PartyGenMoveRank / PartyGenRankWeight / PartyGenMoveForbidden
; ===========================================================================

; INPUT: e = move id. OUTPUT: a = MOVE_RANK_*. CLOBBERS af, hl. PRESERVES bc/de.
PartyGenMoveRank:
	ld hl, MoveRankByID
	push bc
	ld c, e
	ld b, 0
	add hl, bc
	pop bc
	ld a, [hl]
	ret

; INPUT: a = MOVE_RANK_*. OUTPUT: a = acceptance weight out of 64.
; CLOBBERS af, hl. PRESERVES bc/de.
PartyGenRankWeight:
	push bc
	push de
	ld e, a                        ; e = rank
	call PartyGenMixRow
	ld bc, 7                       ; mix row -> its rank_row byte
	add hl, bc
	ld a, [hl]                     ; a = RANK_ROW_*
	cp NUM_RANK_ROWS
	jr c, .rowInRange
	xor a                          ; a malformed row reads as the easiest one
.rowInRange
	ld hl, MoveRankWeightTable
	ld bc, NUM_MOVE_RANKS
	call AddNTimes                 ; hl -> that row
	ld c, e
	ld b, 0
	add hl, bc
	ld a, [hl]
	pop de
	pop bc
	ret

; INPUT: e = move id. OUTPUT: carry SET if the mix forbids it.
; CLOBBERS af, hl. PRESERVES bc/de.
PartyGenMoveForbidden:
	push bc
	push de
	call PartyGenMoveFlags         ; de = this move's MOVEFLAG_* mask
	call PartyGenMixRow
	ld bc, 11                      ; mix row -> forbid_flags (low byte first)
	add hl, bc
	ld a, [hli]
	and e
	jr nz, .forbidden
	ld a, [hl]
	and d
	jr nz, .forbidden
	pop de
	pop bc
	xor a
	ret
.forbidden
	pop de
	pop bc
	scf
	ret

; INPUT: e = move id. OUTPUT: de = its 16-bit MOVEFLAG_* mask.
; CLOBBERS af, hl. PRESERVES bc.
;
; MoveFlagsByID (data/moves/move_ranks.asm) is generated by
; tools/reorder_move_ranks.py from the CORRECTED move-rankings corpus, with
; every mask bit already translated from the source's MOVEFLAG_* bit
; assignments to this tree's (they differ - see that script's header). bc is
; explicitly saved and restored around the index math below, rather than
; merely "not needed after", because PartyGenMoveForbidden's caller relies on
; this preserving bc across the call.
PartyGenMoveFlags:
	push bc
	ld hl, MoveFlagsByID
	ld c, e
	ld b, 0
	add hl, bc
	add hl, bc                     ; MoveFlagsByID + e*2 (2 bytes per entry)
	pop bc
	ld a, [hli]
	ld e, a
	ld a, [hl]
	ld d, a
	ret

; OUTPUT: bc = the current spec's require_flags mask (0 if none).
; CLOBBERS af, de, hl.
;
; A fresh read via PartyGenMixRow rather than a cached value: this is called
; only a handful of times per mon, so the extra in-bank read costs nothing,
; and it avoids every register-lifetime problem that keeping the mask alive
; across PartyGenLastMonMoves/PartyGenMoveFlags (which between them clobber
; af/bc/de/hl) would otherwise create.
PartyGenRequireFlagsMask:
	call PartyGenMixRow
	ld de, 9                       ; mix row -> require_flags (low byte first)
	add hl, de
	ld a, [hli]
	ld c, a
	ld a, [hl]
	ld b, a
	ret

; INPUT: a = move id (0 = empty slot, never satisfies)
; OUTPUT: carry SET if this move's MOVEFLAG_* mask intersects the current
;         spec's require_flags mask.
; CLOBBERS af, bc, de, hl.
PartyGenMoveHasRequiredFlag:
	and a
	jr z, .no
	push af                         ; stash the move id across the mask fetch,
	                                 ; which clobbers af like everything else here
	call PartyGenRequireFlagsMask   ; bc = require mask
	pop af
	ld e, a
	call PartyGenMoveFlags          ; de = this move's flags; PRESERVES bc
	ld a, e
	and c
	jr nz, .yes
	ld a, d
	and b
	jr nz, .yes
.no:
	xor a
	ret
.yes:
	scf
	ret

; ===========================================================================
; PartyGenApplyRequireFlags
;
; Guarantees at least one of a just-built mon's four moves carries a bit from
; the spec's require_flags mask, WHEN A LEGAL CANDIDATE CARRYING ONE EXISTS.
; Called once at the tail of PartyGenRollMoveset on every exit path (the pool
; can run dry before all four slots fill), after the four move slots are
; already final.
;
; Does nothing when:
;   - the mix's require_flags mask is 0 (no requirement), or
;   - one of the four already-written moves already carries a required bit, or
;   - no candidate in the level-up+TM candidate space carries one. This is the
;     "when a legal candidate exists" clause - it must not loop or fail.
;
; A qualifying candidate replaces an EMPTY (NO_MOVE) slot if one exists -
; nothing sacrificed - else the slot holding the weakest already-chosen move
; (lowest MOVE_RANK_*; ties keep the earliest slot).
;
; Every register gets clobbered by the mix of calls this needs
; (PartyGenLastMonMoves alone clobbers af/bc/hl), so slot indices and other
; loop state that must survive a sub-call are carried on the stack via
; push/pop pairs rather than in a register, throughout.
; ===========================================================================
PartyGenApplyRequireFlags:
	call PartyGenRequireFlagsMask   ; bc = require mask
	ld a, b
	or c
	ret z                            ; no requirement on this spec's mix row

; --- pass 1: does any already-chosen move already satisfy it? ---
	ld c, 0                          ; c = slot index 0..NUM_MOVES-1
.chosenLoop
	ld a, c
	cp NUM_MOVES
	jr nc, .chosenPassFailed
	push bc
	call PartyGenLastMonMoves        ; hl -> MON_MOVES[0]
	pop bc
	push bc
	ld b, 0
	add hl, bc                       ; hl -> MON_MOVES[slot]
	pop bc
	ld a, [hl]
	push bc
	call PartyGenMoveHasRequiredFlag
	pop bc
	jr c, .satisfied                 ; already satisfied - nothing to do
	inc c
	jr .chosenLoop
.satisfied:
	ret
.chosenPassFailed:

; --- pass 2: pick the slot to (maybe) overwrite ---
; An empty slot wins immediately and unconditionally; otherwise the weakest
; already-chosen move's slot.
	ld c, 0                           ; c = slot index
	ld d, $FF                         ; d = best rank seen so far (worse than any real rank)
	ld e, 0                           ; e = best slot index found so far
.rankLoop
	ld a, c
	cp NUM_MOVES
	jr nc, .rankLoopDone
	push bc
	push de
	call PartyGenLastMonMoves
	pop de
	pop bc
	push bc
	ld b, 0
	add hl, bc
	pop bc
	ld a, [hl]
	and a
	jr z, .isEmpty
	push bc
	push de
	ld e, a
	call PartyGenMoveRank             ; a = MOVE_RANK_* for this move; PRESERVES bc/de...
	pop de
	pop bc
	cp d
	jr nc, .rankNext                  ; not weaker than the current best
	ld d, a
	ld e, c
.rankNext:
	inc c
	jr .rankLoop
.isEmpty:
	ld e, c
.rankLoopDone:
; e = the slot to (possibly) overwrite.
	push de                           ; kept alive across the whole candidate scan below

; --- pass 3: scan the candidate space for a move carrying the flag ---
	ld a, [wPartyGenCandidateCount]
	ld b, a                           ; b = level-up candidate count (loop bound)
	ld d, 0                           ; d = index into wPartyGenCandidates
.levelUpLoop
	ld a, d
	cp b
	jr nc, .levelUpDone
	ld c, d
	ld hl, wPartyGenCandidates
	push bc
	ld b, 0
	add hl, bc
	ld a, [hl]
	pop bc
	push bc
	push de
	call .tryCandidate                ; carry + a = move id, if it qualifies
	pop de
	pop bc
	jr c, .writeIt
	inc d
	jr .levelUpLoop
.levelUpDone:

	ld a, [wPartyGenTMCount]
	ld b, a
	ld d, 0
.tmLoop
	ld a, d
	cp b
	jr nc, .noneFound
; PartyGenTMMoveByIndex takes its ordinal in `a` and then uses `d` AS THAT
; COUNTDOWN, so it returns with d clobbered - de must be saved here, not just
; bc. It was not, until 2026-09-10: d is this loop's index, so the first call
; reset it to 0, `inc d` made it 1, the next call reset it to 0 again, and the
; loop never reached b. Measured as 2,962,876 calls without returning.
;
; Nothing could reach it before Phase 3. MIX_ELITE is the only shipping mix row
; with a nonzero require_flags and no spec referenced MIX_ELITE until the round
; 6-8 leader specs landed, so the whole TM leg of this scan was dead code.
	push bc
	push de
	ld a, d
	call PartyGenTMMoveByIndex        ; a = the move for the d-th set TM bit
	pop de
	pop bc
	push bc
	push de
	call .tryCandidate
	pop de
	pop bc
	jr c, .writeIt
	inc d
	jr .tmLoop

.noneFound:
	pop de                             ; discard the target slot; nothing to write
	ret

.writeIt:
; a = the winning candidate's move id (from .tryCandidate). de was pushed
; once, above, holding the target slot in e.
	ld c, a                            ; stash the move id; unaffected by the pop below
	pop de                             ; e = target slot index
	ld a, c                            ; a = move id
	ld c, e                            ; c = slot index - PartyGenWriteMove's input
	jp PartyGenWriteMove               ; writes MON_MOVES[c] = a and its PP, then rets

; INPUT: a = candidate move id (0 = no such candidate, e.g. an unset level-up
;        buffer slot)
; OUTPUT: carry SET and a = move id, if it is a legal, not-yet-chosen
;         candidate carrying a required flag. Carry CLEAR otherwise.
; CLOBBERS af, bc, de, hl.
.tryCandidate:
	and a
	ret z                              ; carry already clear from `and a`
	push af                            ; stash the original candidate move id
	ld e, a
	call PartyGenMoveAlreadyChosen     ; carry set if already one of the 4 moves
	jr c, .tryCandidateReject
	call PartyGenMoveRank              ; e preserved; a = MOVE_RANK_*
	cp MOVE_RANK_OFFLIST
	jr z, .tryCandidateReject
	call PartyGenMoveForbidden         ; e preserved; carry set if the mix forbids it
	jr c, .tryCandidateReject
	ld a, e
	call PartyGenMoveHasRequiredFlag   ; carry set if it satisfies the requirement
	jr nc, .tryCandidateReject
	pop af                             ; a = the original candidate move id
	scf
	ret
.tryCandidateReject:
	pop af
	xor a
	ret

; ===========================================================================
; Candidate-space helpers
; ===========================================================================

; OUTPUT: wPartyGenTMCount = popcount(wMonHLearnset)
; CLOBBERS af, bc, de, hl
PartyGenCountTMs:
	ld hl, wMonHLearnset
	ld d, 0                        ; d = bits found
	ld e, 0                        ; e = bit index
.byteLoop
; Guarded before the read as well as inside the bit loop, so the walk cannot
; read one byte past the flag_array on a NUM_TM_HM that is a multiple of 8.
	ld a, e
	cp NUM_TM_HM
	jr nc, .done
	ld a, [hli]
	ld c, a
	ld b, 8
.bitLoop
	ld a, e
	cp NUM_TM_HM
	jr nc, .done                   ; the last byte is only partly used
	srl c
	jr nc, .bitNext
	inc d
.bitNext
	inc e
	dec b
	jr nz, .bitLoop
	jr .byteLoop
.done
	ld a, d
	ld [wPartyGenTMCount], a
	ret

; INPUT:  a = which SET bit of wMonHLearnset to take (0-based)
; OUTPUT: a = the corresponding move id, 0 if the index runs off the end
; CLOBBERS af, bc, de, hl
;
; ⚠ `d` IN PARTICULAR. This routine copies the input ordinal into d and counts
; it down, so a caller looping over TM indexes must NOT keep its loop counter
; there - and must push de, not just bc, across the call. PartyGenApplyRequireFlags
; did exactly that and span forever; see the note at its .tmLoop.
;
; Bit i of the bitfield means "can learn TMMovesForPartyGen[i]" - the convention
; CanLearnTM establishes in engine/items/tms.asm, where one counter indexes
; both. Bit order inside a byte is LSB-first, matching FlagAction's
; `mask = 1 << (index & 7)`.
PartyGenTMMoveByIndex:
	ld d, a                        ; d = the set-bit ordinal wanted
	ld hl, wMonHLearnset
	ld e, 0                        ; e = absolute bit index
	ld a, [hl]
	ld c, a
	ld b, 8
.loop
	ld a, e
	cp NUM_TM_HM
	jr nc, .offEnd
	srl c
	jr nc, .next
	ld a, d
	and a
	jr z, .found
	dec d
.next
	inc e
	dec b
	jr nz, .loop
	ld a, e
	cp NUM_TM_HM
	jr nc, .offEnd                 ; do not read past the flag_array
	inc hl
	ld a, [hl]
	ld c, a
	ld b, 8
	jr .loop
.found
	ld hl, TMMovesForPartyGen
	push de
	ld c, e
	ld b, 0
	add hl, bc
	pop de
	ld a, [hl]
	ret
.offEnd
	xor a
	ret

; INPUT:  e = move id
; OUTPUT: carry SET if the move is TM-ONLY, i.e. not also in the level-up
;         segment. A move that is both does not spend tm_cap.
; CLOBBERS af, hl. PRESERVES bc/de.
PartyGenIsTMOnly:
	push bc
	ld a, [wPartyGenCandidateCount]
	and a
	jr z, .tmOnly
	ld b, a
	ld hl, wPartyGenCandidates
.loop
	ld a, [hli]
	cp e
	jr z, .alsoLevelUp
	dec b
	jr nz, .loop
.tmOnly
	pop bc
	scf
	ret
.alsoLevelUp
	pop bc
	xor a
	ret

; OUTPUT: carry SET if this slot has already taken its tm_cap of TM-only moves.
; CLOBBERS af, hl. PRESERVES bc/de.
PartyGenTMCapReached:
	push bc
	push de
	call PartyGenMixRow
	ld bc, 8                       ; mix row -> tm_cap
	add hl, bc
	ld a, [hl]
	ld b, a                        ; b = tm_cap; bc is restored by the pop below
	ld a, [wPartyGenTMUsed]
; Compared as `used < cap` and then inverted, rather than as `cap < used`. The
; latter reads naturally and is off by one: used == cap must count as reached,
; and `cp` yields no carry on equality.
	cp b                           ; carry SET iff used < cap, i.e. room left
	ccf                            ; carry SET iff the cap is reached
	pop de
	pop bc
	ret

; Spends one unit of tm_cap if the move in e is TM-only.
; CLOBBERS af, hl. PRESERVES bc/de.
PartyGenChargeTMOnly:
	call PartyGenIsTMOnly
	ret nc
	ld hl, wPartyGenTMUsed
	inc [hl]
	ret

; INPUT:  e = move id
; OUTPUT: carry SET if it is already in one of this mon's four move slots.
; CLOBBERS af, bc, hl. PRESERVES de.
PartyGenMoveAlreadyChosen:
	call PartyGenLastMonMoves
	ld b, NUM_MOVES
.loop
	ld a, [hli]
	and a
	jr z, .next                    ; an empty slot is not a match
	cp e
	jr z, .yes
.next
	dec b
	jr nz, .loop
	xor a
	ret
.yes
	scf
	ret

; ===========================================================================
; Enemy-mon struct helpers
; ===========================================================================

; hl -> the party_struct base of the most recently added enemy mon.
;
; The zero guard is load-bearing, not defensive noise. AddPartyMon returns
; early without adding when the party is already full, so a count of 0 reaching
; here would `dec a` to $FF and AddNTimes would add 255 x PARTYMON_STRUCT_LENGTH
; = 11,220 bytes to wEnemyMon1 - wrapping clean out of WRAM and landing in
; $0000-$1FFF, which is the MBC3 RAM-ENABLE register, not memory. The
; subsequent move/PP writes would toggle SRAM instead of writing anything.
PartyGenLastMonBase:
	ld hl, wEnemyMon1
	ld a, [wEnemyPartyCount]
	and a
	ret z
	dec a
	ld bc, PARTYMON_STRUCT_LENGTH
	jp AddNTimes

; hl -> MON_MOVES of the most recently added enemy mon. Same guard, same reason.
PartyGenLastMonMoves:
	ld hl, wEnemyMon1Moves
	ld a, [wEnemyPartyCount]
	and a
	ret z
	dec a
	ld bc, PARTYMON_STRUCT_LENGTH
	jp AddNTimes

; Zeroes this mon's four move ids and their PP.
PartyGenClearMoves:
	call PartyGenLastMonMoves
	ld b, NUM_MOVES
	xor a
.moveLoop
	ld [hli], a
	dec b
	jr nz, .moveLoop
	call PartyGenLastMonMoves
	ld bc, MON_PP - MON_MOVES
	add hl, bc
	ld b, NUM_MOVES
	xor a
.ppLoop
	ld [hli], a
	dec b
	jr nz, .ppLoop
	ret

; INPUT: a = move id, c = move slot (0..NUM_MOVES-1)
; Writes MON_MOVES[c] and its full PP into the last enemy mon.
; CLOBBERS af, bc, hl. PRESERVES de.
PartyGenWriteMove:
	push de
	ld e, a                        ; e = move id; the only pair a farcall spares
	push bc
	call PartyGenLastMonMoves
	pop bc
	ld b, 0
	add hl, bc
	ld a, e
	ld [hl], a
	and a
	jr z, .noPP                    ; NO_MOVE: GetMoveMaxPPFar would `dec 0`
	push hl
	farcall GetMoveMaxPPFar        ; e = move id in, its max PP out
	pop hl
	ld bc, MON_PP - MON_MOVES
	add hl, bc
	ld a, e
	ld [hl], a
.noPP
	pop de
	ret

; ===========================================================================
; PartyGenApplyExplicitMoves
;
; Copies the four literal move ids out of the slot's BIT_POVR_MOVES field.
; Deliberately bypasses the rank table and the off-list exclusion: an author
; naming a move means that move, even Whirlwind.
; ===========================================================================
PartyGenApplyExplicitMoves:
	ld a, [wPartyGenSlot]
	ld b, a
	call PartyGenFindOverrideForSlot
	ret nc
	ld b, BIT_POVR_MOVES
	call PartyGenFieldPtr
	ret nc
	push hl                        ; hl -> the four literal move ids
	call PartyGenClearMoves
	pop hl
	ld c, 0
.loop
	push bc
	push hl
	ld a, [hl]
	call PartyGenWriteMove
	pop hl
	pop bc
	inc hl
	inc c
	ld a, c
	cp NUM_MOVES
	jr c, .loop
	ret

; ===========================================================================
; Bank contract
;
; Every table above is read with a plain in-bank [hl]. Splitting any of them out
; of this section would not fail to assemble - it would read whatever data
; happened to sit at the same offset in whatever bank was mapped, which is this
; project's most-repeated bug (see the cross-bank-call notes). Fail the link
; instead.
; ===========================================================================
ASSERT BANK(RogueBuildParty) == BANK(PartySpecPointers), \
       "RogueBuildParty walks PartySpecPointers and the spec records in-bank"
ASSERT BANK(RogueBuildParty) == BANK(MovesetMixTable), \
       "RogueBuildParty reads MovesetMixTable in-bank"
ASSERT BANK(RogueBuildParty) == BANK(PartySpecOverrideFieldWidths), \
       "RogueBuildParty reads PartySpecOverrideFieldWidths in-bank"
ASSERT BANK(RogueBuildParty) == BANK(TrainerPoolTable), \
       "RogueBuildParty walks TrainerPoolTable and the species runs in-bank"
ASSERT BANK(RogueBuildParty) == BANK(MoveRankByID), \
       "RogueBuildParty reads MoveRankByID once per candidate draw; a farcall \
per lookup is not viable"
ASSERT BANK(RogueBuildParty) == BANK(MoveFlagsByID), \
       "PartyGenMoveFlags reads MoveFlagsByID in-bank, same reason as MoveRankByID"
ASSERT BANK(RogueBuildParty) == BANK(MoveRankWeightTable), \
       "RogueBuildParty reads MoveRankWeightTable in-bank"
ASSERT BANK(RogueBuildParty) == BANK(TMMovesForPartyGen), \
       "RogueBuildParty reads TMMovesForPartyGen in-bank"
