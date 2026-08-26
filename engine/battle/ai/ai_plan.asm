; AI_PLAN layer (AI_OVERHAUL_PLAN.md Phase 5): adaptive multi-turn strategy
; plans. This file is the BANK $0E half - deliberately only the parts the
; dispatcher's same-bank `jp hl` and ReadMove force to live here. The plan
; table, every fitness and execute routine, and the effect->class table all
; live in bank $2C (engine/battle/ai/ai_plans.asm), because bank $0E had 472
; bytes free across all three ROMs when this phase started and a seventeen-plan
; table with two routines per plan would not have fitted in any of them. See
; ai_score_helpers.asm's header for the rule that decides which half is which,
; and ROM_BIBLE.md's Phase 5 entry for the measured split.
;
; WHAT MAKES THE SPLIT POSSIBLE: plan selection and plan execution happen ONCE
; PER TURN, not once per move, so the single farcall to bank $2C costs nothing
; measurable. Only the classification loop (which needs ReadMove and therefore
; the Moves table) and the score-application loop (which needs AIEncourage's
; plain-call hl contract) have to be here.
;
; CROSS-BANK CONTRACT with AIPlanSelectAndExecute, and the reason the directive
; is shaped the way it is: across a farcall only de, hl and the flags survive
; in both directions. The directive therefore travels home as de = the class
; mask to encourage and l = the magnitude, with h reserved.

; The layer proper. Reached by the dispatcher's `jp hl` with a return address
; already pushed, exactly like every other AILayer* routine.
AILayerPlan:
; Trainer classes with a forced personality are skipped outright. AIRunPersonality
; runs AFTER the whole layer loop and owns that trainer's move choice by design
; (Gambler's Paradise is the only one today), so letting a plan also steer the
; same scores would have two systems pulling in different directions with the
; personality silently winning because it runs last. The plan document calls
; this "trainer-class personality forces a plan and skips selection"; skipping
; the layer IS that, expressed in six bytes instead of a plan-table entry.
	ld a, [wTrainerClass]
	cp GAMBLER
	ret z

	call AIClassifyMoveset ; fills wBuffer + AI_BUF_PLANCLASS .. +7

	farcall AIPlanSelectAndExecute ; de = class mask to encourage, l = magnitude

	ld a, l
	and a
	ret z ; the active plan wants nothing steered this turn

; Clamp before applying. AI_PLAN_MAX_MAGNITUDE is an invariant (see
; ai_constants.asm): a plan must never out-encourage AI_KILL, or a mon
; mid-setup would walk past a guaranteed win to keep boosting. Enforced here,
; at the single choke point every directive passes through, rather than trusting
; seventeen separate execute routines to each remember it.
	cp AI_PLAN_MAX_MAGNITUDE + 1
	jr c, .magnitudeOK
	ld a, AI_PLAN_MAX_MAGNITUDE
.magnitudeOK
	ld [wBuffer + AI_BUF_PLANMAG], a

	ld b, e
	ld c, d ; bc = the directive mask (b = low byte, c = high byte)

	ld hl, wBuffer + AI_BUF_SCORES
	ld de, wBuffer + AI_BUF_PLANCLASS

; The loop terminates on the mask cursor reaching the end of the class array
; rather than on a counter, because every register is already spoken for: hl is
; the score pointer AIEncourage requires, de is the cursor, and bc is the
; directive mask. Comparing e alone is only valid while both ends of the array
; share a page, which the assert below makes a build error rather than a
; silent wrap.
	assert HIGH(wBuffer + AI_BUF_PLANCLASS) == HIGH(wBuffer + AI_BUF_PLANCLASS + NUM_MOVES * 2), \
		"AILayerPlan's apply loop compares only the low byte of its cursor"
.nextSlot
	ld a, [de]
	and b
	jr nz, .steer ; this slot carries one of the classes the plan wants
	inc de
	ld a, [de]
	dec de ; 16-bit inc/dec set no flags, so the `and` below still reads clean
	and c
	jr z, .skipSlot
.steer
	ld a, [wBuffer + AI_BUF_PLANMAG]
	call AIEncourage ; preserves bc, de and hl - it clobbers only a
.skipSlot
	inc de
	inc de
	inc hl
	ld a, e
	cp LOW(wBuffer + AI_BUF_PLANCLASS + NUM_MOVES * 2)
	jr nz, .nextSlot
	ret

; ---------------------------------------------------------------------------
; Fills wBuffer + AI_BUF_PLANCLASS .. +7 with one 16-bit class mask per move
; slot, little-endian, zero for an empty slot.
;
; RECOMPUTED EVERY TURN rather than cached at send-out. That is a deliberate
; choice and it is what lets Phase 5 add zero WRAM: the only plan state that
; has to survive a turn is wAIPlan/wAIPlanStep, which Phase 1 already allocated.
; It also cannot go stale - a Transform, a Mimic or a Disable changes what the
; mon's moves ARE, and a cached mask would keep steering toward a move that is
; no longer there. Four ReadMove calls per turn is the same order of cost as one
; AI_DAMAGE pass.
;
; Leaves the wEnemyMove* block holding the LAST move scanned, exactly as every
; other layer's ReadMove loop does. Nothing downstream depends on it: AI_RISKY
; (bit 8, the only scoring layer after this one) re-reads per move, and
; AITrackLastMove already ran before the first layer.
; Clobbers af, bc, de, hl.
AIClassifyMoveset:
	ld hl, wBuffer + AI_BUF_PLANCLASS
	ld de, wEnemyMonMoves
	ld b, NUM_MOVES
.nextMove
	ld a, [de]
	inc de
	and a
	jr z, .emptySlot
	push bc
	push de
	push hl
	call ReadMove ; a = move id on entry
	ld a, [wEnemyMoveEffect]
	ld e, a
	farcall AIPlanLookupEffect ; e = effect in, de = static class mask out
; AICLASS_DAMAGE is the one class not derived from the effect byte, because
; "does this move deal damage" is a property of its POWER and several effects
; (Body Slam's paralysis rider, Hyper Beam, Explosion) appear on both damaging
; and non-damaging moves in principle.
	ld a, [wEnemyMovePower]
	and a
	jr z, .noPower
	assert AICLASS_DAMAGE == 1 << 15, \
		"AIClassifyMoveset sets AICLASS_DAMAGE as bit 7 of the mask's high byte"
	set 7, d
.noPower
	pop hl
	ld a, e
	ld [hli], a
	ld a, d
	ld [hli], a
	pop de
	pop bc
	dec b
	jr nz, .nextMove
	ret
.emptySlot
	xor a
	ld [hli], a
	ld [hli], a
	dec b
	jr nz, .nextMove
	ret

; ---------------------------------------------------------------------------
; Carry SET if the enemy's Substitute would SURVIVE the player's best move.
;
; This is the predicate the plan document singles out as the one no reference AI
; implements. Yume and ShinRed both check only "HP <= 1/4, so the move would
; fail", which prevents an ILLEGAL Substitute and does nothing about a USELESS
; one - a sub that dies to the first hit costs a quarter of the user's HP to
; block a single secondary effect. Every Substitute plan gates on this, which is
; also why those plans are T2+ only: without Phase 3's damage simulator the
; question cannot be answered honestly.
;
; Implemented as a reuse of _AIScanPlayerMovesForKO (ai_threat.asm) rather than
; a new scan. That routine compares every believed player move against whatever
; HP total sits in wBuffer + AI_BUF_EFFHP, which is exactly the seam needed
; here: substitute the SUB's HP for the mon's and "would this kill me" becomes
; "would this break my sub", with no new damage-estimation code at all. The
; same seam is what AIHealWouldStillDie already uses for the post-heal total.
;
; The sub's HP is maxHP/4, taken from SubstituteEffect_'s own `srl a / rr b`
; twice (engine/battle/move_effects/substitute.asm) rather than from Gen 1
; documentation, which disagrees with several forks about the +1.
; Clobbers af, bc, de, hl.
AISubWouldSurvive::
	ld a, [wEnemyMonMaxHP]
	ld d, a
	ld a, [wEnemyMonMaxHP + 1]
	ld e, a
	srl d
	rr e
	srl d
	rr e ; de = maxHP / 4 = the Substitute's HP
	ld a, d
	ld [wBuffer + AI_BUF_EFFHP], a
	ld a, e
	ld [wBuffer + AI_BUF_EFFHP + 1], a
	call _AIScanPlayerMovesForKO ; carry SET = some move reaches that total,
	                             ; i.e. the sub BREAKS
	ccf
	ret

; ---------------------------------------------------------------------------
; ReadMove takes its move id in a, and a cannot survive a farcall - Bankswitch's
; very first instruction is `ldh a, [hLoadedROMBank]`. This trampoline is the
; entire reason the plan engine's move-inspection helpers (AIPlanFindClassMove,
; AIPlanClassMoveLands) can live out of bank in $2C: they pass the id in e,
; which does survive, and get the wEnemyMove* block filled exactly as an
; in-bank caller would.
;
; Four bytes here versus roughly fifty for a whole in-bank scan-and-inspect
; helper, in a bank with 472 free - which is why the split landed at this
; boundary rather than one routine further out.
AIReadMoveFromE::
	ld a, e
	jp ReadMove
