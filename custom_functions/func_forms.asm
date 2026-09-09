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
