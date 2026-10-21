; Saturating score adjustment (AI_OVERHAUL_PLAN.md). Scores are unsigned
; bytes with no natural floor or ceiling. With several layers stacking, an
; unclamped adjustment can wrap a byte around, or walk a score into
; AI_SCORE_DISABLED and silently forbid a legal move. Every scoring layer
; adjusts scores through these.
;
; INPUT: hl = pointer to the score byte, a = magnitude
; Clobbers a, bc. Preserves de, hl.
;
; INCLUDEd into "Battle Engine 7" (bank $0E), the SAME bank as trainer_ai.asm
; and every AILayer* routine, rather than living alongside the rest of
; ai_core.asm (a separate floating bank). This is deliberate, not
; incidental: AIEnemyTrainerChooseMoves' layer dispatch reaches every layer
; with a plain same-bank `jp hl` (see ai_core.asm's header comment), so every
; layer already has to live in this bank - and these two routines are called
; far more often, and by far more callers, than anything else in ai_core.asm
; (tier resolution runs once per battle; a score adjustment can run several
; times per move per layer). Keeping them in-bank makes every call site a
; plain `call`, with no bank-switch overhead and no cross-bank
; register-passing constraints to get wrong.
;
; BUGFIX HISTORY (Phase 2a bring-up, see AI_OVERHAUL_PLAN.md and
; AILayerRedundant in ai_redundant.asm for the full account): these
; originally lived in ai_core.asm and took the pointer in de instead of hl,
; reached via farcall, because that is where AIResolveTier/AIGetLayerWord
; already lived. Three compounding bugs came from that one placement choice:
; the farcall macro consumes hl as its own jump-target register, so a
; pointer argument cannot travel in hl across it; Bankswitch's own first
; instruction (`ldh a, [hLoadedROMBank]`) clobbers a before the callee ever
; runs, so a magnitude cannot travel in a either; and `call Bankswitch`'s
; return path clobbers bc unconditionally as its own bank-restore
; bookkeeping. Getting a 16-bit pointer AND an 8-bit magnitude past all of
; that needed a stack peek (`ld hl, sp+N`) that added real complexity for no
; benefit, once the actual constraint (every caller is already same-bank)
; was accounted for. Moving these back to bank $0E removes the farcall
; entirely, and with it every one of those failure modes.

; Make a move more attractive (scores are "lower is better").
AIEncourage::
	push bc
	ld b, a
	ld a, [hl]
	cp AI_SCORE_DISABLED
	jr z, .store ; legality is not a preference
	sub b
	jr c, .floor      ; underflowed past zero
	cp AI_SCORE_MIN
	jr nc, .store
.floor
	ld a, AI_SCORE_MIN
.store
	ld [hl], a
	pop bc
	ret

; Make a move less attractive.
AIDiscourage::
	push bc
	ld b, a
	ld a, [hl]
	cp AI_SCORE_DISABLED
	jr z, .store
	add b
	jr c, .ceiling    ; overflowed past 255
	cp AI_SCORE_MAX + 1
	jr c, .store
.ceiling
	ld a, AI_SCORE_MAX
.store
	ld [hl], a
	pop bc
	ret

; Handler lookup in an ai_dispatch table (macros/ai_dispatch.asm). INPUT: a = a
; move effect, hl = <Name>Index, de = <Name>Handlers. OUTPUT: carry and hl = the
; handler when the effect has one; carry clear otherwise, including an effect id
; past NUM_MOVE_EFFECTS. Constant time: it replaced an IsInArray walk that cost
; 22-34k cycles a T3 decision (Phase 6, 2026-10-21).
; Clobbers af, hl.
AIDispatchLookup::
	cp NUM_MOVE_EFFECTS + 1
	ret nc
	add l
	ld l, a
	jr nc, .indexed
	inc h
.indexed
	ld a, [hl]
	and a ; no handler: z, carry clear
	ret z
	dec a
	add a ; at most 127 handlers per table (ai_dispatch_end asserts it)
	add e
	ld l, a
	ld a, d
	adc 0
	ld h, a
	ld a, [hli]
	ld h, [hl]
	ld l, a
	scf
	ret
