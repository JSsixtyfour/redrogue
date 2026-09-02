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
;
; GRADED LADDER, AI_OVERHAUL_PLAN.md follow-up F15, 2026-09-02: previously a
; single flat AI_NUDGE covered both an OHKO attempt and an ordinary powerful-
; but-unreliable move, with no distinction - and OHKO moves reached it only by
; accident (AIEstimateDamage deliberately reports ZERO for OHKO_EFFECT, so
; raw=0 trivially satisfies "raw >= reliable*2" against a reliable estimate
; that is also 0). User's own ranking, weakest to strongest desperation play:
; Metronome < unreliable-power/high-crit < OHKO < sleep (sleep is AI_THREAT's
; rank 3, not this layer's concern). OHKO_EFFECT is now detected explicitly by
; effect id, not by the accidental 0/0 collision, and scored a tier above the
; generic case. Metronome (METRONOME_EFFECT, 0 base power - untouched by
; AI_DAMAGE, and F2 already made AI_TYPES skip it rather than value it) is
; handled separately below the main loop: it only ever gets nudged when
; AIAnyScoreBelowBaseline says every move is STILL sitting at or above
; baseline, i.e. genuinely nothing better was found this turn - a true last
; resort, not a competitor to a real preference some earlier layer applied.

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
	ld a, [wEnemyMoveEffect]
	cp OHKO_EFFECT
	jr z, .ohko
	cp METRONOME_EFFECT
	jr z, .metronome
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
.ohko
; OHKO moves reach here explicitly now, not via the accidental raw=reliable=0
; collision the old single-tier code relied on (AIEstimateDamage deliberately
; zeroes OHKO_EFFECT - see that routine's header, core.asm). Legality (the
; slower-auto-misses rule) is already AIRedundant_OHKO's job; this is purely
; "a bigger nudge than the generic risky case", per the user's ranking.
	ld a, AI_STRONG
	jr .apply
.metronome
; A true last resort: only nudge Metronome when NOTHING else has already
; scored better than baseline this turn, so it never competes with a real
; preference (a status move, a damage tier, an OHKO attempt) some earlier
; layer already found. Fires below AI_NUDGE-equivalent strength deliberately -
; see AIAnyScoreBelowBaseline's own header for why "fires rarely" substitutes
; for "fires weakly" here.
	call AIAnyScoreBelowBaseline
	jr c, .noChange
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

; Carry set if ANY of the four current move scores is already below baseline
; (AI_SCORE_BASE) - i.e. some earlier layer already found a real reason to
; prefer a DIFFERENT move this turn. F15, 2026-09-02: gates Metronome above,
; so it is nudged only as a genuine last resort rather than a competitor to
; whatever a real preference already picked. wBuffer+0..3 is exactly the
; live score array at this point in the layer dispatch (AI_BUF_SCORES,
; ai_constants.asm) - AI_RISKY runs last (bit 8), so every earlier layer's
; adjustment is already reflected here, including this same pass's own
; encouragements on slots already visited this loop.
; Clobbers af, b, hl.
AIAnyScoreBelowBaseline:
	ld hl, wBuffer
	ld b, NUM_MOVES
.loop
	ld a, [hli]
	cp AI_SCORE_BASE
	jr c, .yes
	dec b
	jr nz, .loop
	and a
	ret
.yes
	scf
	ret
