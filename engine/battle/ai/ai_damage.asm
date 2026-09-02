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
; Reset the comparative record. $ff means "no damaging move seen yet", which is
; what makes a moveset of pure status moves exit cleanly at .applyBest.
	xor a
	ld [wBuffer + AI_BUF_BESTDMG], a
	ld [wBuffer + AI_BUF_BESTDMG + 1], a
	ld a, $ff
	ld [wBuffer + AI_BUF_BESTSLOT], a

	ld hl, wBuffer - 1 ; temp move selection array (-1 byte offset)
	ld de, wEnemyMonMoves
	ld b, NUM_MOVES + 1
.nextMove
	dec b
	jp z, .applyBest ; processed all 4 moves. jp, not jr: F16's added scoring
	                 ; paths pushed .applyBest past the 128-byte relative range
	inc hl
; Stash which slot this is, because the AIEstimateDamage farcall below destroys
; every register that could otherwise carry it.
;
; This MUST happen before the move id is loaded into a, not after. Computing it
; between `ld a, [de]` and `call ReadMove` destroys the move id in flight -
; ReadMove takes its argument in a - so every move was read from the wrong table
; offset. Same shape as the struct-pointer-clobbers-a-live-register bug class:
; never insert register work between a value's producer and its consumer.
	ld a, NUM_MOVES
	sub b
	ld [wBuffer + AI_BUF_CURSLOT], a
	ld a, [de]
	and a
	jp z, .applyBest ; no more moves in move set (jp for the same range reason)
	inc de
	push hl ; STACK: [hl=scorePtr]
	push de ; STACK: [de=movelistPtr, hl=scorePtr]
	push bc ; STACK: [bc=loopCounter, de=movelistPtr, hl=scorePtr]
	call ReadMove ; loads this move into the wEnemyMove* block for the simulator
; Fixed-damage moves carry base power 1, or 0 for Night Shade, so a plain power
; test would skip Night Shade as a status move and wave the rest through as
; trivial. The simulator knows their real values, so let them past the guard.
	ld a, [wEnemyMoveEffect]
	cp SPECIAL_DAMAGE_EFFECT
	jr z, .estimate
	cp SUPER_FANG_EFFECT
	jr z, .estimate
	ld a, [wEnemyMovePower]
	and a
	jr z, .noChange ; status move: this layer has no opinion. Skipping the
	                ; farcall here is also most of the layer's cost saved, since
	                ; a moveset is usually part status.
.estimate
	farcall AIEstimateDamage ; -> wAIDamageEstimate (max roll, STAB and dual-type
	                         ; already applied). Clobbers a/bc/hl, all pushed.
; Fold in the move's expected critical-hit contribution before ANY test below
; reads the estimate, so a high-crit move is ranked on what it is really worth.
; This is what makes Slash beat Strength on a fast user; see the routine's
; header for the worked numbers and for why the tier tests are allowed to see it.
	call AIScaleDamageForCrit
; "Can this kill" is asked FIRST and against the RAW max roll, because it is a
; question about possibility rather than expectation: a 70%-accurate move that
; can kill still can kill, and scaling it down first would hide that outright.
	ld b, 0
	call AIDamageReachesFraction
	push af ; the "can this kill" answer, saved across the scaling below
; Everything past this point RANKS moves against one another, which is exactly
; where accuracy belongs. Scaling the estimate by the real hit chance turns it
; into expected damage, so Thunderbolt beats Thunder and Flamethrower beats Fire
; Blast - but note the coarse tiers below cannot express that on their own, so
; the comparative record updated here is what actually delivers it.
	call AIScaleDamageByAccuracy
	call .trackBest
	pop af
	jr c, .kill
	ld b, 1
	call AIDamageReachesFraction
	jr c, .half
	ld b, 2
	call AIDamageReachesFraction
	jr c, .quarter
.noChange
	xor a
	jr .priorityBonus
.kill
; A kill that might miss is worth less than a kill that cannot - this is the
; "why use Fire Blast when Flamethrower already kills" rule, and it is the whole
; reason the KO test above deliberately ran on the unscaled estimate.
	call AIGetMoveHitChance
	cp 90 percent
	jr c, .unreliableKill
; F16 (2026-09-02): a RELIABLE kill that also ACTS FIRST outranks a bigger
; reliable kill that does not. When two moves both kill, raw damage is the wrong
; tiebreak - turn order is, because the bigger one is worthless if the player
; moves first and wins the exchange.
;
; The magnitude (AI_KILL_FIRST) is DERIVED in ai_constants.asm, not picked -
; see that constant's header for the arithmetic. It has to clear everything a
; competing NON-priority kill can stack up on the same board, which is more than
; just .applyBest's extra nudge: the first attempt at this used AI_KILL +
; AI_STRONG and still LOST the measured case, because the rival Body Slam also
; carried a paralysis rider bonus from AI_SMART.
;
; Concrete case this fixes, measured before and after: a slower mon holding
; Quick Attack and Body Slam against a player in one-shot range scored Body Slam
; 8 (AI_KILL 5 + best-damage nudge 1 + its own rider 2) against Quick Attack's
; 5 - so the AI took Body Slam, moved second, and lost a won game. AI_THREAT has
; a narrower version of this rescue, but it fires only at T3 AND only when
; AIPlayerWouldKO says the player kills us THIS turn, so a slower T2 trainer, or
; a T3 trainer in a close-but-not-lethal race, got nothing at all.
	call AIEnemyActsFirstWith
	ld a, AI_KILL ; `ld a, n` sets no flags, so the carry above still decides
	jr nc, .apply
	ld a, AI_KILL_FIRST ; see the constant's own header for why this size
	jr .apply
.unreliableKill
	ld a, AI_STRONG
	jr .apply
.half
	ld a, AI_STRONG
	jr .priorityBonus
.quarter
	ld a, AI_NUDGE
.priorityBonus
; F16 (2026-09-02): a small, UNCONDITIONAL preference for a priority move at
; otherwise equal value - Quick Attack should beat Pound every time, since at
; identical power and type the guaranteed first strike is free upside. One point
; only: it breaks an exact tie without ever overriding a real damage-tier gap
; (2-5 points), so it can never make a 40-power priority move beat an 85-power
; one that actually hits harder.
;
; Deliberately NOT gated on being slower, unlike AI_THREAT's larger rescue
; bonus. Priority still guarantees the first strike when we are already faster,
; against a Speed drop or the player's own priority move, and at one point the
; cost of being wrong is nil.
;
; Swift deliberately gets NO equivalent nudge: its advantage is bypassing the
; accuracy roll, and AIGetMoveHitChance already reports it at 100% while scaling
; every rival move down by its real hit chance - including against an
; evasion-boosted target, which is precisely when Swift shines. Adding a nudge
; on top would double-count that, and against an equally accurate move of equal
; damage Swift genuinely has no edge to reward.
;
; The kill path above does NOT come through here: its acts-first bump is the
; priority bonus for that case, at the larger magnitude that case needs.
	ld b, a
	ld a, [wEnemyMoveNum]
	cp QUICK_ATTACK
	ld a, b ; LD does not touch flags, so the cp above still decides
	jr nz, .apply
	inc a
.apply
; a holds the magnitude to encourage by, 0 for "leave this move alone".
; The three pops below never touch a (POP rr for BC/DE/HL preserves it and every
; flag - only POP AF does not), so the magnitude survives the unwind, and hl
; comes back as exactly the score pointer AIEncourage wants.
	pop bc
	pop de
	pop hl
	and a
	jp z, .nextMove
	call AIEncourage
	jp .nextMove ; jp, not jr: F16's added scoring paths pushed .nextMove past
	             ; the 128-byte relative range

; Give the single highest-expected-damage move one extra nudge. This is the
; comparative half of the layer: the tiers above say how threatening each move
; is on its own, and this says which one is actually best. Without it, two moves
; in the same tier score identically no matter how far apart their expected
; damage is - which is exactly the Thunderbolt-vs-Thunder case.
.applyBest
	ld a, [wBuffer + AI_BUF_BESTSLOT]
	cp NUM_MOVES
	ret nc ; still $ff: no damaging move in this set
	ld hl, wBuffer
	ld d, 0
	ld e, a
	add hl, de
	ld a, AI_NUDGE
	jp AIEncourage

; Updates the running best-expected-damage record if the move just scaled beats
; it. Called with wAIDamageEstimate already scaled to expected damage.
; Clobbers af, bc, de. Preserves hl and the flags the caller saved on the stack.
.trackBest
	ld a, [wAIDamageEstimate]
	ld d, a
	ld a, [wAIDamageEstimate + 1]
	ld e, a ; de = this move's expected damage
	ld a, [wBuffer + AI_BUF_BESTDMG]
	ld b, a
	ld a, [wBuffer + AI_BUF_BESTDMG + 1]
	ld c, a ; bc = best seen so far
	ld a, c
	sub e
	ld a, b
	sbc d
	ret nc ; best >= this one, so nothing to record
	ld a, d
	ld [wBuffer + AI_BUF_BESTDMG], a
	ld a, e
	ld [wBuffer + AI_BUF_BESTDMG + 1], a
	ld a, [wBuffer + AI_BUF_CURSLOT]
	ld [wBuffer + AI_BUF_BESTSLOT], a
	ret
