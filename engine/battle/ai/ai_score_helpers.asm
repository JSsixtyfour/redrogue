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
