; AI_DAMAGE layer (AI_OVERHAUL_PLAN.md Phase 3): the first consumer of the
; damage simulator. This is what makes a T2+ trainer take a kill when one is
; available, which is rank 1 of the plan's priority cascade and the single most
; visible difference between this AI and vanilla's.
;
; INCLUDEd into "Battle Engine 7" (bank $0E), same bank as trainer_ai.asm and
; every other AILayer* routine - mandatory, not stylistic. See
; ai_score_helpers.asm's header and ROM_BIBLE.md's 2026-08-25 entries.
;
; The simulator itself (AIEstimateDamage) deliberately lives in bank $0F beside
; the real damage formula, because GetDamageVarsForEnemyAttack hands its results
; to CalculateDamage in b/c/d/e and a farcall between those two would destroy bc.
; So this layer pays exactly ONE farcall per move to cross into it, and then does
; all its reasoning here through the WRAM result (wAIDamageEstimate) and the
; predicates in ai_predicates.asm. Do not farcall the predicates: they are
; in-bank on purpose.
;
; SCORING SHAPE - why damage tiers rather than "find the single best move":
; a max-finding pass would need to cache four 16-bit damage values and then walk
; them again, which costs a second loop and 8 bytes of the (currently unused)
; wBuffer move-cache region. Comparing each move's damage against the player's
; REMAINING HP instead answers the question the cascade actually asks - "does
; this kill / does this take a big bite" - in one pass with no scratch, and it
; degrades correctly as the player gets low: as HP drops, more moves qualify as
; lethal and the AI naturally converges on finishing rather than maximising.
; The refinement of penalising "not your most powerful move" is deliberately
; left to a later step; see the plan's Phase 3 entry.

AILayerDamage:
	ld hl, wBuffer - 1 ; temp move selection array (-1 byte offset)
	ld de, wEnemyMonMoves
	ld b, NUM_MOVES + 1
.nextMove
	dec b
	ret z ; processed all 4 moves
	inc hl
	ld a, [de]
	and a
	ret z ; no more moves in move set
	inc de
	push hl ; STACK: [hl=scorePtr]
	push de ; STACK: [de=movelistPtr, hl=scorePtr]
	push bc ; STACK: [bc=loopCounter, de=movelistPtr, hl=scorePtr]
	call ReadMove ; loads this move into the wEnemyMove* block for the simulator
	ld a, [wEnemyMovePower]
	and a
	jr z, .noChange ; status move: this layer has no opinion. Skipping the
	                ; farcall here is also most of the layer's cost saved, since
	                ; a moveset is usually part status.
	farcall AIEstimateDamage ; -> wAIDamageEstimate (max roll, STAB and dual-type
	                         ; already applied). Clobbers a/bc/hl, all pushed.
	ld b, 0
	call AIDamageReachesFraction
	jr c, .kill
	ld b, 1
	call AIDamageReachesFraction
	jr c, .half
	ld b, 2
	call AIDamageReachesFraction
	jr c, .quarter
.noChange
	xor a
	jr .apply
.kill
	ld a, AI_KILL
	jr .apply
.half
	ld a, AI_STRONG
	jr .apply
.quarter
	ld a, AI_NUDGE
.apply
; a holds the magnitude to encourage by, 0 for "leave this move alone".
; The three pops below never touch a (POP rr for BC/DE/HL preserves it and every
; flag - only POP AF does not), so the magnitude survives the unwind, and hl
; comes back as exactly the score pointer AIEncourage wants.
	pop bc
	pop de
	pop hl
	and a
	jr z, .nextMove
	call AIEncourage
	jr .nextMove
