; AI_THREAT's paralysis test (AIIsDisablingStatus): "does the enemy have a real
; hit THIS turn?" Its own SECTION (main.asm, pinned in layout.link): banks $0E and
; $0F are full, and its one caller farcalls it. Reads WRAM only.

; Carry SET if no move the enemy can use this turn is expected to take 40% of the
; player's current HP (tested exactly as 5 * best < 2 * HP). 40% rather than half:
; that much of what is left is already a real hit, worth more than paralysis's
; quarter-chance skip.
;
; "This turn", not AI_BUF_BESTDMG (2026-11-21 AI review, section 1): that record
; ranks a two-turn move at half its hit, which is right for ranking across turns
; but made a threatened Solar Beam user (Solar Beam 49 of 100 HP, its only attack)
; skip Thunder Wave for a move that lands nothing before the player's KO. So:
;   - the hits come from AI_BUF_SLOTDMG, the same expected damage per slot that
;     AI_DAMAGE ranked by, which reads 0 for a two-turn move, a status move and a
;     slot the legality filter drops (disabled, no PP);
;   - Self-Destruct / Explosion also read 0 there (PP conservation, .trackBest),
;     so a live one comes from its one-hit estimate in wAIEnemyEstimateCache,
;     which AI_DAMAGE filled. That is the maximum roll, not the expected one: a
;     blast is rarely near the line, and the extra rounding is ~8%.
;     It counts unless the player has a Substitute: this test runs only under a
;     KO threat (AILayerThreat returns otherwise), and there AIExplosionWorthIt
;     allows the trade at T2/T3 for that reason alone. A Substitute is its earlier
;     veto. A themed gambler skips the veto, but a blast into a Substitute still
;     reaches the owner for 0, so it is no hit either way.
; Slot damage is capped at the player's HP (Substitute progress adds at most its
; HP), and estimates never exceed 999, so 5 * best fits 16 bits.
; Must run inside the AI_THREAT pass that follows AI_DAMAGE: AI_PLAN rebuilds
; +20..+27 as class masks after it. Clobbers af, bc, de, hl.
AIImmediateHitUnder40Pct::
	ld de, 0 ; de = the best hit so far
	ld hl, wBuffer + AI_BUF_SLOTDMG
	ld c, NUM_MOVES
.slotDamage
	ld a, [hli]
	ld b, a
	ld a, [hli]
	push bc
	ld c, a ; bc = this slot's expected hit
	call .max
	pop bc
	dec c
	jr nz, .slotDamage

	ld a, [wPlayerBattleStatus2]
	bit HAS_SUBSTITUTE_UP, a
	jr nz, .compare
	ld c, 0 ; c = slot 0-3
.blast
	ld hl, wEnemyMonMoves
	call .index
	ld a, [hl]
	cp SELFDESTRUCT
	jr z, .live
	cp EXPLOSION
	jr nz, .nextBlast
.live
	ld hl, wEnemyMonPP
	call .index
	ld a, [hl]
	and PP_MASK
	jr z, .nextBlast
	ld a, [wEnemyDisabledMove]
	swap a
	and $f ; the disabled slot 1-4, 0 = none
	dec a
	cp c
	jr z, .nextBlast
	ld hl, wAIEnemyEstimateCache
	call .index
	call .index ; two bytes per slot
	ld a, [hli]
	bit AI_ESTIMATE_VALID_BIT, a
	jr z, .nextBlast ; not estimated: AI_DAMAGE did not score it
	and ~(1 << AI_ESTIMATE_VALID_BIT)
	push bc
	ld b, a
	ld c, [hl]
	call .max
	pop bc
.nextBlast
	inc c
	ld a, c
	cp NUM_MOVES
	jr c, .blast

.compare
	ld h, d
	ld l, e
	add hl, hl
	add hl, hl
	add hl, de ; hl = 5 * best
	ld a, [wBattleMonHP]
	ld b, a
	ld a, [wBattleMonHP + 1]
	ld c, a
	sla c
	rl b ; bc = 2 * HP
	ld a, l
	sub c
	ld a, h
	sbc b ; carry iff 5 * best < 2 * HP
	ret

; de = the larger of de and bc. Clobbers af.
.max
	ld a, e
	sub c
	ld a, d
	sbc b
	ret nc ; de >= bc
	ld d, b
	ld e, c
	ret

; hl += c. Clobbers af.
.index
	ld a, l
	add c
	ld l, a
	ret nc
	inc h
	ret
