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
	call AIEstimateEnemyDamage ; -> wAIDamageEstimate (one-hit max, STAB and type
	                         ; already applied). Clobbers a/bc/hl, all pushed.
; Save the one-hit estimate. Possible KO uses the move's maximum owner-delivered
; damage after Substitute; ranking below uses its expected hit-count delivery.
	ld a, [wAIDamageEstimate]
	push af
	ld a, [wAIDamageEstimate + 1]
	push af
	call AIAdjustEnemyDamageForPossibleDelivery
	ld b, 0
	call AIDamageReachesFraction
; Preserve the possible-KO flags while restoring the one-hit estimate, and keep
; a copy of that estimate for .kill (it used to re-run AIEstimateDamage there).
	push af
	pop de
	pop af
	ld [wAIDamageEstimate + 1], a
	ld c, a
	pop af
	ld [wAIDamageEstimate], a
	ld b, a
	push bc ; STACK: [one-hit max, loop state...]
	push de ; STACK: [possible-KO flags, one-hit max, loop state...]
; Everything past this point ranks moves. Hit-count expectation is applied
; before crit and accuracy weighting; it never masquerades as a possible KO.
	ld a, [wPlayerBattleStatus2]
	bit HAS_SUBSTITUTE_UP, a
	jr nz, .rankIntoSubstitute
	call AIAdjustEnemyDamageForExpectedDelivery
	call AIScaleDamageForCrit
	call AICapEnemyDamageAtOwnerHP
	jr .rankedByDelivery
; Behind a Substitute, a single hit that breaks it delivers 0 to the owner, so
; ranking on owner damage alone left every attack tied at the baseline and the
; AI with no reason to pick the one that breaks the shield (2026-09-29 review
; F3). Rank on the EXPECTED shield progress - over the move's real hit-count
; outcomes, each capped at Substitute HP + 1 (the +1 so a hit that BREAKS it
; outranks one that only leaves a zero-HP shield, the engine equality rule) -
; plus the expected damage that still reaches the owner. Crit weighting and the
; owner-HP cap apply to the owner part only: shield progress is already capped
; and a crit cannot push it past the shield (Codex follow-up R3, 2026-09-29:
; multi-hit moves used to be credited one hit, and a 10-HP shield let Tackle
; rank 12). This is ranking only: the possible-KO test above is unchanged.
.rankIntoSubstitute
	ld a, [wAIDamageEstimate]
	ld d, a
	ld a, [wAIDamageEstimate + 1]
	ld e, a ; de = one-hit maximum
	push de
	call AIAdjustEnemyDamageForExpectedDelivery ; owner part
	call AIScaleDamageForCrit
	call AICapEnemyDamageAtOwnerHP
	pop de
	call AIExpectedShieldProgress ; bc = expected shield part
	ld a, [wAIDamageEstimate + 1]
	add c
	ld [wAIDamageEstimate + 1], a
	ld a, [wAIDamageEstimate]
	adc b
	ld [wAIDamageEstimate], a
.rankedByDelivery
	call AIScaleDamageByAccuracy
	call .trackBest
	pop af
	pop bc ; bc = one-hit max; pop keeps the possible-KO carry
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
; "why use Fire Blast when Flamethrower already kills" rule. "Cannot miss the
; kill" also needs the GUARANTEED damage to reach: the possible-KO test above
; used the max roll and max hit count, so a Spike Cannon needing 3+ hits or a
; hit needing a high roll only earns the unreliable bonus (2026-09-29 review
; F2/F4). The reliable value starts from the same one-hit maximum, which the
; ranking above overwrote, so it comes back from bc (2026-09-30: this used to
; re-run AIEstimateDamage, a whole damage formula per killing move, for an
; identical result). The loop's hl/de/bc are on the stack.
;
; Two-turn moves (CHARGE_EFFECT: Solar Beam, Razor Wind, Skull Bash, Sky Attack,
; Dig; FLY_EFFECT: Fly) deal nothing THIS turn, so they never earn a kill tier
; or set wAIReliableKOFound. They can still finish next turn, but the player can
; switch, heal or hit first, so they take the unreliable-kill tier (2026-10-08,
; found in the #55 benchmark trace: a killing Solar Beam scored AI_KILL_FIRST,
; -10, against which AISmart_Charge's AI_STRONG penalty was noise). Same rule as
; the TrainerAI KO check in ai_predicates.asm. The simulator still credits full
; damage for ranking, as F14 decided. wEnemyMoveEffect is still this slot's:
; nothing between the loop's ReadMove and here reloads the move block.
	ld a, [wEnemyMoveEffect]
	cp CHARGE_EFFECT
	jr z, .unreliableKill
	cp FLY_EFFECT
	jr z, .unreliableKill
	ld a, b
	ld [wAIDamageEstimate], a
	ld a, c
	ld [wAIDamageEstimate + 1], a
	call AIAdjustEnemyDamageForReliableDelivery
	call AIMoveIsReliableKO
	jr nc, .unreliableKill
; Tell AI_PLAN a reliable kill is on the board, so no plan steers past it
; (FOLLOWUPS #55: a plan directive stacked with AI_SMART's opinion of the same
; status move tied a kill). `ld` sets no flags.
	ld a, 1
	ld [wAIReliableKOFound], a
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

; INPUT: de = the enemy move's one-hit maximum. OUTPUT: bc = the expected damage
; the player's Substitute absorbs from it: f(n) = min(n * one hit, Sub HP + 1)
; averaged over the real hit-count outcomes - 1 hit, 2 (ATTACK_TWICE / Twineedle),
; or 2-5 at 3/8, 3/8, 1/8, 1/8 (TwoToFiveAttacksEffect; Witch multistrike is
; player-only). Clobbers af, de, hl.
AIExpectedShieldProgress:
	ld a, [wPlayerSubstituteHP]
	ld l, a
	ld h, 0
	inc hl ; hl = cap, Sub HP + 1
	ld a, [wEnemyMoveEffect]
	cp ATTACK_TWICE_EFFECT
	jr z, .twoHits
	cp TWINEEDLE_EFFECT
	jr z, .twoHits
	cp TWO_TO_FIVE_ATTACKS_EFFECT
	jr z, .variable
	cp EFFECT_1E
	jr z, .variable
	ld a, 1
	jr .shieldAfterHits
.twoHits
	ld a, 2
	jr .shieldAfterHits
.variable
	ld a, 2
	call .shieldAfterHits
	push bc
	push bc
	push bc ; 3 x f(2)
	ld a, 3
	call .shieldAfterHits
	push bc
	push bc
	push bc ; 3 x f(3)
	ld a, 4
	call .shieldAfterHits
	push bc ; f(4)
	ld a, 5
	call .shieldAfterHits ; bc = f(5); the cap in hl is no longer needed
	ld h, b
	ld l, c
	rept 7
		pop bc
		add hl, bc
	endr
	rept 3
		srl h
		rr l
	endr ; / 8
	ld b, h
	ld c, l
	ret
; a = hits, de = one hit, hl = cap -> bc = min(hits * de, cap). Preserves de, hl.
.shieldAfterHits
	ld bc, 0
.addHit
	push af
	ld a, c
	add e
	ld c, a
	ld a, b
	adc d
	ld b, a
	ld a, c
	sub l
	ld a, b
	sbc h
	jr c, .belowCap
	pop af
	ld b, h
	ld c, l
	ret
.belowCap
	pop af
	dec a
	jr nz, .addHit
	ret
