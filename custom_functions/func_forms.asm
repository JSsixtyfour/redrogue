; Species Groups Phase 2R - form override lookup.
;
; MUST live in BANK(BaseStats). GetMonHeader has already switched to that bank
; when it calls this, so the call is a plain in-bank `call` with no bankswitch
; and no farcall register laundering. home/pokemon.asm carries a link-time
; ASSERT tying the two banks together, so a future relocation of either one is a
; build error rather than a silent cross-bank read of garbage - this project has
; hit that exact class of bug seven times (see the cross-bank-call memory).
;
; Keeping the whole lookup here rather than in HOME costs ROM0 exactly THREE
; bytes (the `call`), which matters: HOME has 113 bytes free.

; ---------------------------------------------------------------------------
; ApplyFormOverride
;
; Patches wMonHeader with a form's own base-stats row, if the pending form
; context applies to the species GetMonHeader just loaded.
;
; INPUT:
;   wCurSpecies           = species whose row was just copied into wMonHeader
;   wFormContextSpecies   = species the pending context applies to, 0 = none
;   wFormContextForm      = form index 1..NUM_FORM_SLOTS, 0 = base species
; OUTPUT:
;   wMonHForm             = the form actually applied (0 if none)
;   wMonHeader            = patched when a form applied, untouched otherwise
; CLOBBERS: af, bc, de, hl
;   Safe at the only call site: GetMonHeader pushes bc/de/hl on entry and pops
;   them after this returns, and reloads `a` from wCurSpecies on the next line.
;
; CONSUMES THE CONTEXT unconditionally - see the wram.asm comment on
; wFormContextSpecies for why zeroing on read is load-bearing rather than tidy.
; The consume happens BEFORE the species compare on purpose: a context that
; turns out not to match must still be cleared, or it would survive to ambush a
; later lookup of the species it does match.
;
; CONTRACT FOR CALLERS: set the context immediately before EACH GetMonHeader
; call. A caller that sets it once and calls twice gets the form only the first
; time. func_fusion.asm calls GetMonHeader repeatedly but writes its own species
; each time, so it is unaffected.
; ---------------------------------------------------------------------------
ApplyFormOverride::
	ld a, [wFormContextSpecies]
	and a
	jr nz, .haveContext

; ---- No context pending. Is this a RELOAD of the header we already hold? ----
; Measured 2026-09-09: several routines reload wMonHeader from the species it
; already describes, WITHOUT publishing a context, purely to refresh it -
; PrintMonType (engine/battle/print_type.asm:6, reached from the status screen
; BEFORE the sprite is drawn) and five sites in status_view.asm/status_screen.asm
; that re-derive wCurSpecies from wMonHIndex. Every one of them would silently
; strip a form: the status screen applied Alolan Meowth's row, then PrintMonType
; overwrote it with vanilla Meowth's, and the sprite drew from the vanilla
; pointers. The form context was provably correct at this routine's entry; it had
; simply already been consumed.
;
; Fixing that HERE rather than at each call site kills all six at once and, more
; importantly, is immune to the seventh nobody has found yet.
;
; The test is exact, not a heuristic: GetMonHeader writes wMonHIndex AFTER this
; routine returns, so wMonHIndex still names the species the CURRENT wMonHeader
; was built for. wCurSpecies == wMonHIndex therefore means "same species, loaded
; again", which is precisely a refresh - and the form it carried is still in
; wMonHForm.
;
; This cannot mis-fire on two same-species mons in a row (an Alolan Meowth in
; slot 4 and a vanilla one in slot 5): every real per-mon load goes through
; LoadMonData_, which ALWAYS publishes a context - form 0 included - so those
; take the .haveContext path and never reach this code.
; ⚠ Compare against wMonHFormSpecies, NEVER wMonHIndex. wMonHIndex is
; wMonHeader + 0 - literally the same byte - and GetMonHeader's base-stats
; CopyData has already overwritten it with the ROM row's BASE_DEX_NO by the time
; this routine runs; the species index is written back only AFTER we return. An
; earlier version of this guard used wMonHIndex and compared $33 (Dugtrio's dex)
; against $76 (its species index), so it never once fired. See wram.asm.
	ld a, [wCurSpecies]
	ld hl, wMonHFormSpecies
	cp [hl]
	jr nz, .noForm               ; different species: a genuine fresh load
	ld a, [wMonHForm]
	and a
	jr z, .noForm                ; the held header had no form either
	ld c, a                      ; re-apply the same form
	ld a, [wCurSpecies]
	ld b, a
	jr .lookup

.noForm
	xor a
	ld [wMonHForm], a
	ld [wMonHFormSpecies], a
	ret

.haveContext
	ld b, a                      ; b = context species
	xor a
	ld [wFormContextSpecies], a  ; consume, unconditionally
	ld [wMonHForm], a            ; and default this header to "no form"
	ld [wMonHFormSpecies], a     ; keep the pair consistent - .found resets both

	ld a, [wCurSpecies]
	cp b
	ret nz                       ; context was for a different species

	ld a, [wFormContextForm]
	and a
	ret z                        ; form 0 is the base species: nothing to patch
	ld c, a                      ; c = wanted form index

.lookup
	ld hl, FormOverrides
.loop
	ld a, [hl]                   ; record's base species
	and a
	jr z, .noForm                ; end of table, no match. Routed through .noForm
	                             ; rather than a bare `ret` so the re-apply path
	                             ; above cannot leave wMonHForm claiming a form
	                             ; that was never actually copied in.
	cp b
	jr nz, .next
	inc hl
	ld a, [hl]                   ; record's form index
	dec hl
	cp c
	jr z, .found
.next
	ld de, FORM_REC_SIZE
	add hl, de
	jr .loop

.found
	ld a, c
	ld [wMonHForm], a
	ld a, b
	ld [wMonHFormSpecies], a     ; remember WHICH species this form belongs to,
	                             ; so a later refresh can recognise itself
	ld de, FORM_REC_DATA         ; skip the 2-byte key
	add hl, de
	ld de, wMonHeader
	ld bc, BASE_DATA_SIZE
	jp CopyData                  ; HOME, always mapped; its ret returns to GetMonHeader

; ---------------------------------------------------------------------------
; GetFormNameSource
;
; Redirects GetMonName's source row to a form's own name when a form context is
; pending for the species being named. Without it a form clone prints its BASE
; species' name, because MonsterNames is indexed by species alone.
;
; Lives here, and is plain-called from HOME, for the same reason as
; ApplyFormOverride: GetMonName has already switched to BANK(MonsterNames), and
; layout.link pins "Monster Names" and "Species Forms" to the SAME bank as
; "Base Stats". home/names.asm asserts that.
;
; INPUT:  hl = the MonsterNames row GetMonName computed (the default)
;         wFormContextSpecies / wFormContextForm
; OUTPUT: hl = the form's 10-character name, or unchanged if no form applies
; CLOBBERS: af, bc, de  (hl is the return value)
;   Safe: GetMonName loads de and bc for the copy AFTER this returns.
;
; Consumes the context, exactly like ApplyFormOverride. That is workable here
; only because species names are BAKED into a nickname buffer at three creation
; sites rather than read live, so each of those three publishes its own context
; immediately before calling. A display path that wants BOTH a form-correct
; header and a form-correct name must publish twice - once per call.
; ---------------------------------------------------------------------------
GetFormNameSource::
	ld a, [wFormContextSpecies]
	and a
	ret z                        ; no context pending - the common case

	ld b, a
	xor a
	ld [wFormContextSpecies], a  ; consume, unconditionally

	ld a, [wNamedObjectIndex]
	cp b
	ret nz                       ; context was for a different species

	ld a, [wFormContextForm]
	and a
	ret z                        ; form 0 is the base species: keep the default row
	ld c, a

	push hl                      ; keep the default MonsterNames row
	ld hl, FormOverrides
.nameLoop
	ld a, [hl]
	and a
	jr z, .nameNotFound
	cp b
	jr nz, .nameNext
	inc hl
	ld a, [hl]
	dec hl
	cp c
	jr z, .nameFound
.nameNext
	ld de, FORM_REC_SIZE
	add hl, de
	jr .nameLoop

.nameNotFound
	pop hl                       ; fall back to the base species' name
	ret

.nameFound
	ld de, FORM_REC_NAME
	add hl, de                   ; hl = the form's name field
	pop de                       ; discard the saved default row
	ret

; ---------------------------------------------------------------------------
; RogueRollFormForSpecies
;
; Decides whether a freshly-rolled species spawns as one of its regional forms.
; This is the ONLY thing that makes the 48 records in data/pokemon/forms/
; reachable from ordinary play - everything before increment 8 could only be
; reached by setting wSpawnForm by hand from a debugger.
;
; INPUT:  e = species. Must be the FINAL species, after any evolution step:
;         RogueSelectFromTier rolls a base form and then promotes it with
;         EvolveMonByLevel, and it is the promoted species that has to own a
;         form record. Rolling before the evolve would ask for (EXEGGCUTE, 1),
;         which does not exist, instead of (EXEGGUTOR, 1), which does.
; OUTPUT: e = form index; 0 = ordinary base species, 1..NUM_FORM_SLOTS = a form
; CLOBBERS: af, bc, hl  (d PRESERVED - callers park the species there)
;
; Farcall-safe by construction. Bankswitch destroys a/b/c/h/l on BOTH legs of a
; farcall and only d/e/flags survive, so the species arrives and the answer
; leaves in e - the same contract RogueClassifySpeciesFar uses, and for the same
; reason. Do NOT "simplify" this to return in a or c.
;
; Random and Rangerandom are both HOME (home/random.asm), so they are plain
; calls from this bank and Random's internal farcall restores bank $30 on the
; way back.
; ---------------------------------------------------------------------------
RogueRollFormForSpecies::
	ld b, e                      ; b = species; e is the return slot from here on
	call Random                  ; preserves bc/de/hl
	cp FORM_SPAWN_ODDS
	jr nc, .noForm               ; the common case - an ordinary base-species spawn

; Count this species' records first, then walk again to fetch the chosen one.
; Two passes rather than one pass into a scratch buffer: the table is 52 records
; of ROM that cannot change between the passes, only 1 spawn in 8 gets this far,
; and it needs no WRAM at all. Reservoir sampling would be one pass but costs a
; Random call PER match, which is strictly worse here.
	ld c, 0                      ; c = matching records found
	ld hl, FormOverrides
	ld de, FORM_REC_SIZE         ; d is dead from here - see the CLOBBERS note
.countLoop
	ld a, [hl]
	and a
	jr z, .counted               ; terminator
; The terminator test above runs BEFORE the compare, which is what makes a
; species of 0 safe: it can never "match" the terminator byte and walk off the
; end of the table.
	cp b
	jr nz, .countNext
; A tier-placed form is NOT a candidate here. Its rarity is pinned to a specific
; tier (FormTierTable), and reaching it from its base species' tier as well is
; exactly the thing that table exists to prevent - Scream Tail would still fall
; out of a pokeball-tier Jigglypuff.
	inc hl
	ld a, [hl]                   ; this record's form index
	dec hl
	call IsFormTierPlaced        ; preserves bc/de/hl
	jr c, .countNext
	inc c
.countNext
	add hl, de
	jr .countLoop
.counted
	ld a, c
	and a
	jr z, .noForm                ; this species has no forms - most of them
	call Rangerandom             ; a = 0 .. matches-1, unbiased; preserves bc/de
	ld c, a                      ; c = which match to take, counted down below

	ld hl, FormOverrides
.pickLoop
	ld a, [hl]
	cp b
	jr nz, .pickNext
	inc hl                       ; same tier-placed exclusion as the count pass -
	ld a, [hl]                   ; the two walks MUST agree or the ordinal picked
	dec hl                       ; from the count would select the wrong record
	call IsFormTierPlaced
	jr c, .pickNext
	ld a, c
	and a
	jr z, .found
	dec c
.pickNext
	add hl, de
	jr .pickLoop
.found
	inc hl
	ld e, [hl]                   ; the record's OWN form index, not its ordinal -
	                             ; so a species with records for forms 1 and 3 but
	                             ; not 2 still returns a valid index
	ret

.noForm
	ld e, 0
	ret

; ---------------------------------------------------------------------------
; IsFormTierPlaced
;
; Is this (species, form) listed in FormTierTable - i.e. is its rarity pinned to
; a specific tier rather than inherited from its base species?
;
; INPUT:  b = species, a = form index
; OUTPUT: carry SET if the pair is tier-placed
; CLOBBERS: af   (bc, de, hl PRESERVED - both callers are mid-walk over
;           FormOverrides with a live cursor in hl and a stride in de)
;
; Walks FormTierPairs..FormTierPairsEnd as one flat pair array. The five per-tier
; lists are contiguous by declaration order, so this sees every entry regardless
; of which tier it sits under, and a tier added later is covered automatically.
; ---------------------------------------------------------------------------
IsFormTierPlaced:
	push bc
	push hl
	ld c, a                      ; c = wanted form
	ld a, (FormTierPairsEnd - FormTierPairs) / 2
	and a
	jr z, .notFound              ; no overrides exist at all - the usual case
	ld hl, FormTierPairs
.loop
	push af                      ; a = pairs remaining
	ld a, [hli]                  ; species
	cp b
	jr nz, .next
	ld a, [hl]                   ; form
	cp c
	jr z, .foundPop
.next
	inc hl
	pop af
	dec a
	jr nz, .loop
.notFound
	pop hl
	pop bc
	and a                        ; clear carry
	ret
.foundPop
	pop af
	pop hl
	pop bc
	scf
	ret

; ---------------------------------------------------------------------------
; RogueRollFormForTier
;
; Gives tier-placed forms first refusal on a pick at this tier. A hit REPLACES
; the species the tier's own list would have rolled - that is the whole point:
; Scream Tail's base species is only ever rolled at pokeball tier, so a form that
; was merely blocked at low tiers would be unreachable instead of rare.
;
; INPUT:  e = tier id (RARITY_TIER_*)
; OUTPUT: d = species, e = form index. d = 0 means "no tier-placed form, roll a
;         species normally" - the overwhelmingly common answer.
; CLOBBERS: af, bc, hl
;
; Consumes NO randomness when the tier has an empty list, so tiers with no
; overrides roll byte-identically to before this existed. That is deliberate:
; this project has had smoke tests shift on RNG consumption alone.
; ---------------------------------------------------------------------------
RogueRollFormForTier::
	ld a, e
	cp NUM_RARITY_TIERS
	jr nc, .none                 ; defensive - an out-of-range tier picks nothing
	ld l, a
	ld h, 0
	add hl, hl                   ; tier * 2
	ld c, a
	ld b, 0
	add hl, bc                   ; tier * 3 = tier * FORM_TIER_ENTRY_SIZE
	ASSERT FORM_TIER_ENTRY_SIZE == 3, "RogueRollFormForTier hardcodes a 3-byte stride"
	ld bc, FormTierTable
	add hl, bc
	ld a, [hli]                  ; pair count for this tier
	and a
	jr z, .none                  ; empty tier - return before touching Random
	ld c, a
	ld a, [hli]
	ld h, [hl]
	ld l, a                      ; hl = this tier's pair list
	push hl
	push bc
	call Random
	pop bc
	pop hl
	cp FORM_TIER_ODDS
	jr nc, .none
	call Rangerandom             ; a = 0 .. count-1; preserves hl
	add a                        ; pairs are 2 bytes
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld d, a                      ; species
	ld e, [hl]                   ; form
	ret

.none
	ld d, 0
	ld e, 0
	ret
