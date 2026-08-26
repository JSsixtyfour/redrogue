; AI_RISKY layer (AI_OVERHAUL_PLAN.md Phase 3 Step 3): the ONE place in this
; overhaul that deliberately UNDOES the reliability preference AI_DAMAGE and
; AI_SMART's status-accuracy check spent the rest of Step 3 building. T3 only.
;
; INCLUDEd into "Battle Engine 7" (bank $0E) alongside every other AILayer*.
;
; WHEN IT FIRES: only when AIPlayerWouldKO says the player can kill the active
; enemy mon this turn, AND the enemy has no already-guaranteed win of its own
; (no move that both acts first and would KO the player). That second half
; matters: without it, RISKY's variance-chasing nudges could compete against an
; already-locked-in win instead of staying silent. AI_THREAT already covers the
; narrow "slower and dying, OHKO gamble" case (its own .checkGamble); this layer
; generalises that to every T3 trainer that is simply losing, not just the one
; about to be KO'd outright - see AILayerThreat's header for why the two are
; not meant to duplicate each other (THREAT gates on AIPlayerWouldKO too, but
; only nudges OHKO_EFFECT; RISKY nudges the wider "raw power exceeds reliable
; power" case and HighCriticalMoves).
;
; WHAT IT DOES: for each move, if its RAW (pre-accuracy) estimate is well above
; its accuracy-scaled expected damage - i.e. a powerful, unreliable hit - or the
; move is a high-crit-rate move (HighCriticalMoves, bank $0F, hence the
; farcall), nudge it. This is the literal inverse of AI_DAMAGE's reasoning:
; reliability stopped being the priority the moment a reliable line stopped
; being able to win.

AILayerRisky:
	call AIPlayerWouldKO
	ret nc ; not losing this badly - this layer has no opinion

; Scan our own moveset for an already-guaranteed win: a move that acts first
; AND would KO the player outright. If one exists, AI_DAMAGE (AI_KILL) and
; AI_THREAT's Quick Attack check have already found and scored it - RISKY has
; nothing useful to add and should not risk competing with it.
	ld hl, wEnemyMonMoves
	ld b, NUM_MOVES
.scanGuaranteedWin
	ld a, [hli]
	and a
	jr z, .noGuaranteedWin ; ran out of moves - none guarantee a win
	push hl
	push bc
	call ReadMove ; a = move id, already loaded above; ReadMove itself
	              ; preserves hl/bc, so this alone would not need the pushes -
	              ; they exist for the calls below, which do not preserve them
	ld a, [wEnemyMovePower]
	and a
	jr z, .notGuaranteed ; status move cannot KO
	call AIEnemyActsFirstWith
	jr nc, .notGuaranteed
	farcall AIEstimateDamage ; -> wAIDamageEstimate (raw)
	call AIMoveWouldKO
	jr nc, .notGuaranteed
	pop bc
	pop hl
	ret ; guaranteed win exists elsewhere in the moveset - stay silent
.notGuaranteed
	pop bc
	pop hl
	dec b
	jr nz, .scanGuaranteedWin
.noGuaranteedWin

	ld hl, wBuffer - 1 ; temp move selection array (-1 byte offset)
	ld de, wEnemyMonMoves
	ld b, NUM_MOVES + 1
.nextMove
	dec b
	ret z
	inc hl
	ld a, [de]
	and a
	ret z
	inc de
	push hl
	push de
	push bc
	call ReadMove
	ld a, [wEnemyMovePower]
	and a
	jr z, .noChange ; status move: nothing to gamble with here

	farcall AIEstimateDamage ; -> wAIDamageEstimate (raw)
	ld a, [wAIDamageEstimate]
	ld d, a
	ld a, [wAIDamageEstimate + 1]
	ld e, a ; de = raw estimate
	push de ; AIScaleDamageByAccuracy clobbers de (it calls AIGetMoveHitChance,
	        ; which farcalls CalcHitChance), so the raw estimate must survive
	        ; on the stack across it, not in a register
	call AIScaleDamageByAccuracy ; wAIDamageEstimate is now the RELIABLE figure
	pop de ; de = raw estimate again
	ld a, [wAIDamageEstimate]
	ld b, a
	ld a, [wAIDamageEstimate + 1]
	ld c, a ; bc = reliable (accuracy-scaled) estimate
; "Well above" is raw >= reliable * 2 - a move whose accuracy roughly halves or
; worse its expected value is exactly the powerful/unreliable shape this layer
; exists to nudge. Comparing raw against 2x reliable avoids a division.
	sla c
	rl b ; bc = reliable * 2 (0/1 discarded on overflow is fine: a doubled
	     ; 16-bit value this small never approaches the 999 damage cap)
	ld a, e
	sub c
	ld a, d
	sbc b ; carry set iff raw(de) < reliable*2(bc) - not unreliable enough
	jr nc, .risky
	ld a, [wEnemyMoveNum]
	ld e, a ; AIIsHighCritMove takes its argument in e, not a - a plain call
	        ; would also be wrong here regardless, since the routine lives in
	        ; bank $0F and this file is bank $0E
	farcall AIIsHighCritMove
	jr nc, .noChange
.risky
	ld a, AI_NUDGE
	jr .apply
.noChange
	xor a
.apply
; This layer only ever encourages (or does nothing) - never discourages - so
; there is no direction to signal and no carry-before-and-a ordering to get
; wrong here (contrast AI_SMART's dispatcher, which does both directions).
	pop bc
	pop de
	pop hl
	and a
	jr z, .nextMove
	call AIEncourage
	jr .nextMove
