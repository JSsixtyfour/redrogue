; AI_THREAT layer (AI_OVERHAUL_PLAN.md Phase 3 Step 2): rank 2 of the priority
; cascade, "do not die for free". T3 only.
;
; INCLUDEd into "Battle Engine 7" (bank $0E) alongside every other AILayer*.
; The player-side damage simulation it depends on lives in bank $0F for the
; register-contract reason documented on AIEstimateDamage; this layer reaches it
; with one farcall per PLAYER move, not once per enemy move.
;
; WHAT IT DOES, AND WHY THIS ORDERING:
; the layer is silent unless the simulator says the player can KO the enemy's
; active mon this turn. Once that is true:
;
;   1. Taking the enemy's OWN kill is already handled - AI_DAMAGE (bit 5) runs
;      BEFORE this layer (bit 6) and has already applied AI_KILL to any lethal
;      move. Rank 1 outranks rank 2 by construction, so this layer deliberately
;      does NOT re-score ordinary kills; doing so would double-count.
;   2. A PRIORITY kill is the exception, and is the whole reason this layer
;      cares about Quick Attack: if raw speed says the enemy loses the race but
;      Quick Attack still kills, that converts a loss into a win, and no
;      speed-blind layer can see it. Encouraged on top of AI_DAMAGE's AI_KILL.
;   3. Investment moves are discouraged hard - a boost, screen or Substitute
;      pays off NEXT turn, and there may not be one.
;   4. A heal that still leaves the enemy dead is discouraged just as hard. This
;      is the ONLY healing case this layer touches; see the note below.
;   5. A disabling status is encouraged only if the enemy ACTS FIRST with it,
;      because only then does it resolve before the player's lethal move.
;   6. If the enemy acts second, the turn is lost on a max roll - so an OHKO
;      attempt gets a nudge, variance being the only line that still wins.
;
; "ACTS FIRST" IS NOT "IS FASTER". Gen 1 hardcodes Quick Attack (moves first)
; and Counter (moves last) in MainInBattleLoop, so raw Speed is only the
; fallback. Every branch below that depends on move order therefore asks
; AIEnemyActsFirstWith, which is per-move, rather than the cached raw-speed
; answer - the cached value is used ONLY to decide whether Quick Attack's
; priority is buying anything.
;
; HEALING - NARROWED, after a correction. An earlier revision of this layer left
; healing alone entirely, reasoning that a mon about to be KO'd is usually at low
; HP, which is exactly when AISmart_Heal correctly encourages a heal. That is
; still true, and blanket suppression would still be wrong. But it missed the
; case the plan actually meant: a heal that does NOT outrun the incoming damage
; leaves the enemy dead anyway, having spent its last turn doing nothing. That
; case is precisely computable - Recover and Softboiled restore half of max HP,
; Rest restores all of it (engine/battle/move_effects/heal.asm) - so it is
; suppressed here and nothing else about healing is touched.

AILayerThreat:
	call AIPlayerWouldKO
	ret nc ; the player cannot kill us this turn - this layer has no opinion

; Cache the RAW SPEED answer once. Used only as the gate on Quick Attack's
; priority being worth anything; per-move order comes from AIEnemyActsFirstWith.
	call AIEnemyIsFaster
	ld a, 0
	jr nc, .storeSpeed
	inc a
.storeSpeed
	ld [wBuffer + AI_BUF_THREATFAST], a

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
	call ReadMove

	call AIIsInvestmentMove
	jr c, .discourageHeavy

; Quick Attack: only interesting when raw speed says we would otherwise lose the
; race. If we are already faster, priority buys nothing and its 40 base power is
; simply a weak move, so leave it to AI_DAMAGE.
	ld a, [wEnemyMoveNum]
	cp QUICK_ATTACK
	jr nz, .checkHeal
	ld a, [wBuffer + AI_BUF_THREATFAST]
	and a
	jr nz, .checkHeal ; already faster - nothing to rescue
	call AIEstimateEnemyDamage ; AI_DAMAGE's estimate belongs to whichever move
	                           ; it scored last; the cache makes this free
	call AIAdjustEnemyDamageForPossibleDelivery
	call AIMoveWouldKO
	jr nc, .noChange
	ld a, AI_STRONG
	scf
	jr .apply

.checkHeal
	ld a, [wEnemyMoveEffect]
	cp HEAL_EFFECT
	jr nz, .checkStatus
	call AIHealWouldStillDie
	jr nc, .noChange ; the heal genuinely saves us - leave AISmart_Heal's
	                 ; encouragement alone
	jr .discourageHeavy

.checkStatus
	call AIIsDisablingStatus
	jr nc, .checkGamble
	call AIEnemyActsFirstWith
	jr nc, .noChange ; we act second: the status never resolves, so it is no out
	ld a, AI_STRONG
	scf
	jr .apply

.checkGamble
	ld a, [wEnemyMoveEffect]
	cp OHKO_EFFECT
	jr nz, .noChange
	call AIEnemyActsFirstWith
	jr c, .noChange ; acting first, an ordinary attack beats a 30% gamble
	ld a, AI_NUDGE
	scf
	jr .apply

.discourageHeavy
	ld a, AI_HEAVY
	and a ; carry CLEAR = discourage (and a always clears carry)
	jr .apply

.noChange
	xor a ; also clears carry; .apply's zero test sends it straight on

.apply
; a = magnitude (0 for "leave alone"), carry = direction. The three pops below
; touch neither a nor the flags (POP rr for BC/DE/HL preserves both - only
; POP AF does not), so both survive the unwind. Branch on CARRY FIRST: any
; `and`/`or`/`cp` used to test a for zero would clear it. Getting that order
; wrong was the original bug in ai_smart.asm's dispatcher.
	pop bc
	pop de
	pop hl
	jr c, .encourage
	and a
	jr z, .nextMove
	call AIDiscourage
	jr .nextMove
.encourage
	and a
	jr z, .nextMove
	call AIEncourage
	jr .nextMove

; ---------------------------------------------------------------------------
; Carry SET if ANY move the AI believes the player has would KO the enemy's
; active mon this turn. Short-circuits on the first lethal move found.
;
; Reads the player's moveset through AIGetPlayerMoveN, the accessor seam, NOT
; through wBattleMonMoves directly - this is the single most important consumer
; of that seam, because "which moves does the opponent have" is exactly the
; information Phase 7's fair-play tiers withhold. When that lands, a fair-play
; trainer will reason here only about moves it has actually been shown, with no
; edit to this routine.
;
; It borrows the live wPlayerMove* block, because GetDamageVarsForPlayerAttack
; reads the move's power and type from there and nowhere else. The real contents
; are stashed in wBuffer for the duration and put back on every exit path.
; GetCurrentMove does reload that block from wPlayerSelectedMove before the move
; actually executes, so this is belt-and-braces - but proving non-destructiveness
; is cheaper than proving nothing else reads it in between.
; Clobbers af, bc, de, hl (only af on a cache hit).
;
; ONE-DECISION CACHE (2026-09-29, AI review option 3): every input - both
; sides' HP, stats, stages, Substitute, and the believed player moveset - is
; fixed for the length of one decision, yet a T3 move selection asked this up to
; three times (THREAT, RISKY, plan checks) at ~20-30k cycles each (measured).
; wAIPlayerKOCache is cleared at the start of AIEnemyTrainerChooseMoves. At
; TrainerAI it is kept on an enemy-first turn, and on a player-first turn
; re-derived from wAIPlayerKOMaxDamage when nothing but our HP has changed
; (AIRevalidateDecisionCaches), else cleared. A caller outside those two
; decisions must clear it first (AIClearDecisionCaches).
AIPlayerWouldKO::
	ld a, [wAIPlayerKOCache]
	and a
	jr z, .compute
	dec a ; AI_KO_CACHE_NO -> 0, AI_KO_CACHE_YES -> 1
	rra ; carry = cached answer
	ret
.compute
	ld a, [wEnemyMonHP]
	ld [wBuffer + AI_BUF_EFFHP], a
	ld a, [wEnemyMonHP + 1]
	ld [wBuffer + AI_BUF_EFFHP + 1], a
	call _AIScanPlayerMovesForKO ; de = largest delivery seen (Super Fang excluded)
	ld a, AI_KO_CACHE_NO
	jr nc, .store
	set AI_KO_MAX_PARTIAL_BIT, d ; stopped at the KO: later slots unscanned
	ld a, AI_KO_CACHE_YES
.store
	ld [wAIPlayerKOCache], a
	ld b, a
	set AI_KO_MAX_VALID_BIT, d
	ld hl, wAIPlayerKOMaxDamage
	ld [hl], d
	inc hl
	ld [hl], e ; for AIRevalidateDecisionCaches (ai_predicates.asm)
	ld a, b
	dec a
	rra ; carry = the answer just computed
	ret

; Carry SET if the player's best move STILL kills the enemy after the heal move
; currently loaded in the wEnemyMove* block resolves - i.e. the heal is a wasted
; turn. Same scan as AIPlayerWouldKO, run against the post-heal HP total.
;
; Heal amounts are engine facts, not guesses: Rest restores the full max HP,
; while Recover and Softboiled restore half of it (the `srl b / rr c` in
; HealEffect_). Anything that overflows or exceeds max HP clamps to max HP.
; Clobbers af, bc, de, hl.
AIHealWouldStillDie::
	ld a, [wEnemyMonMaxHP]
	ld h, a
	ld a, [wEnemyMonMaxHP + 1]
	ld l, a ; hl = max HP, preserved across everything below
	ld a, [wEnemyMoveNum]
	cp REST
	jr z, .storeMax ; Rest goes to full, so post-heal HP is simply max HP
	ld d, h
	ld e, l
	srl d
	rr e ; de = maxHP / 2, the Recover/Softboiled amount
	ld a, [wEnemyMonHP]
	ld b, a
	ld a, [wEnemyMonHP + 1]
	ld c, a ; bc = current HP
	ld a, e
	add c
	ld e, a
	ld a, d
	adc b
	ld d, a ; de = current + heal
	jr c, .storeMax ; overflowed 16 bits, so certainly at or past max
	ld a, l
	sub e
	ld a, h
	sbc d
	jr c, .storeMax ; max HP < de, so the heal caps out
	ld a, d
	ld [wBuffer + AI_BUF_EFFHP], a
	ld a, e
	ld [wBuffer + AI_BUF_EFFHP + 1], a
	jp _AIScanPlayerMovesForKO
.storeMax
	ld a, h
	ld [wBuffer + AI_BUF_EFFHP], a
	ld a, l
	ld [wBuffer + AI_BUF_EFFHP + 1], a
	jp _AIScanPlayerMovesForKO

; Checkpoint D item-payoff gate. INPUT: a = fixed item heal amount, or 0 for
; Full Restore's full-HP heal. Carry SET when a T2/T3 trainer would still be
; KO'd after that heal; T0/T1 preserve vanilla item behavior and return clear.
; Uses the same visible-moveset and maximum-damage contract as AIHealWouldStillDie.
; Clobbers af, bc, de, hl.
AIItemHealWouldStillDie::
	ld b, a
	ld a, [wAITier]
	and a
	jr z, .worthwhile
	dec a
	cp AI_TIER_SKILLED
	jr c, .worthwhile
	ld a, [wEnemyMonMaxHP]
	ld h, a
	ld a, [wEnemyMonMaxHP + 1]
	ld l, a ; hl = max HP
	ld a, b
	and a
	jr z, .storeMax
	ld d, 0
	ld e, a
	ld a, [wEnemyMonHP]
	ld b, a
	ld a, [wEnemyMonHP + 1]
	ld c, a
	ld a, e
	add c
	ld e, a
	ld a, d
	adc b
	ld d, a
	jr c, .storeMax
	ld a, l
	sub e
	ld a, h
	sbc d
	jr c, .storeMax
	ld a, d
	ld [wBuffer + AI_BUF_EFFHP], a
	ld a, e
	ld [wBuffer + AI_BUF_EFFHP + 1], a
	jp _AIScanPlayerMovesForKO
.storeMax
	ld a, h
	ld [wBuffer + AI_BUF_EFFHP], a
	ld a, l
	ld [wBuffer + AI_BUF_EFFHP + 1], a
	jp _AIScanPlayerMovesForKO
.worthwhile
	and a
	ret

; B4 switch-in survival (AI_BACKLOG, 2026-09-29). Farcall target from
; AIReplacementIsBetter ($2C), NO register inputs: the reserve is the slot in
; wBuffer + AI_BUF_BESTPARTYSLOT that the ranking just chose. OUTPUT: e = 1 if
; it would survive every believed player move at its current HP, e = 0 if one
; would KO it. Stages the reserve's HP, types, Defense and Special into
; wEnemyMon, with our Substitute and screens OFF (they do not follow a switch),
; runs the UNCACHED scan (wAIPlayerKOCache must keep describing the active mon),
; then restores every borrowed byte. Clobbers af, bc, d, hl.
AIBestReserveSurvivesThreat::
	xor a
; a = 0: test against the reserve's HP; a = 1: against HALF of it (B5,
; AIBestReserveKeepsHalf). Carried on the stack under the five saved words and
; read back with `ld hl, sp + 11` - keep that offset in step with the pushes.
_AIBestReserveThreatScan:
	push af
	ld hl, wEnemyMonHP
	ld a, [hli]
	ld d, a
	ld e, [hl]
	push de
	ld a, [wEnemyMonType1]
	ld d, a
	ld a, [wEnemyMonType2]
	ld e, a
	push de
	ld hl, wEnemyMonDefense
	ld a, [hli]
	ld d, a
	ld e, [hl]
	push de
	ld hl, wEnemyMonSpecial
	ld a, [hli]
	ld d, a
	ld e, [hl]
	push de
	ld a, [wEnemyBattleStatus2]
	ld d, a
	ld a, [wEnemyBattleStatus3]
	ld e, a
	push de

	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	ld hl, wEnemyMon1
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes ; hl = the reserve's party struct
	push hl
	inc hl ; HP
	ld a, [hli]
	ld [wEnemyMonHP], a
	ld [wBuffer + AI_BUF_EFFHP], a
	ld a, [hli]
	ld [wEnemyMonHP + 1], a
	ld [wBuffer + AI_BUF_EFFHP + 1], a
	inc hl ; BoxLevel
	inc hl ; Status
	ld a, [hli]
	ld [wEnemyMonType1], a
	ld a, [hl]
	ld [wEnemyMonType2], a
	pop hl
	push hl
	ld bc, wEnemyMon1Defense - wEnemyMon1
	add hl, bc
	ld a, [hli]
	ld [wEnemyMonDefense], a
	ld a, [hl]
	ld [wEnemyMonDefense + 1], a
	pop hl
	ld bc, wEnemyMon1Special - wEnemyMon1
	add hl, bc
	ld a, [hli]
	ld [wEnemyMonSpecial], a
	ld a, [hl]
	ld [wEnemyMonSpecial + 1], a
	ld hl, wEnemyBattleStatus2
	res HAS_SUBSTITUTE_UP, [hl]
	ld hl, wEnemyBattleStatus3
	res HAS_REFLECT_UP, [hl]
	res HAS_LIGHT_SCREEN_UP, [hl]
	ld hl, sp + 11 ; the entry flag's a, above the five saved words
	ld a, [hl]
	and a
	jr z, .fullHP
	ld hl, wBuffer + AI_BUF_EFFHP
	srl [hl]
	inc hl
	rr [hl] ; the scan's bar is now half the reserve's HP
.fullHP

	call _AIScanPlayerMovesForKO ; carry = some believed move KOs the reserve
	ld e, 1
	jr nc, .restore
	dec e
.restore ; e survives every pop below (they load hl and a only)
	pop hl
	ld a, h
	ld [wEnemyBattleStatus2], a
	ld a, l
	ld [wEnemyBattleStatus3], a
	pop hl
	ld a, h
	ld [wEnemyMonSpecial], a
	ld a, l
	ld [wEnemyMonSpecial + 1], a
	pop hl
	ld a, h
	ld [wEnemyMonDefense], a
	ld a, l
	ld [wEnemyMonDefense + 1], a
	pop hl
	ld a, h
	ld [wEnemyMonType1], a
	ld a, l
	ld [wEnemyMonType2], a
	pop hl
	ld a, h
	ld [wEnemyMonHP], a
	ld a, l
	ld [wEnemyMonHP + 1], a
	pop af ; the entry flag; e survives
	ret

; e = 1 if the best-ranked reserve would keep MORE than half its current HP
; through every believed player move, e = 0 if one would take half or more.
; Same staging and contract as AIBestReserveSurvivesThreat. Clobbers af, bc, d, hl.
AIBestReserveKeepsHalf:
	ld a, 1
	jp _AIBestReserveThreatScan

; B5 team preservation (AI_BACKLOG, 2026-09-30). Farcall target from
; AIShouldSwitch ($2C), asked only once the KO-threat trigger has found a
; better reserve that survives (so wBuffer + AI_BUF_BESTPARTYSLOT is it).
; Carry SET = SACRIFICE: stay in and let the active mon fall, because a
; replacement sent in after a faint enters without taking a hit, while one
; switched in now takes the player's attack. Two cases make that the better
; trade:
;   - the active mon is below a quarter HP: little is kept by saving it;
;   - the reserve would lose half or more of its HP to the hit, i.e. the
;     switch spends most of the mon that is meant to answer the threat.
; The reserve test uses the scan's POSSIBLE delivery (max roll, max hits), so
; it leans toward the sacrifice. No register inputs; clobbers af, bc, de, hl.
AISacrificeBeatsSwitch::
	ld hl, wEnemyMonHP
	ld a, [hli]
	ld d, a
	ld e, [hl]
	sla e
	rl d
	sla e
	rl d ; de = HP * 4 (HP <= 999, so no overflow)
	ld hl, wEnemyMonMaxHP + 1
	ld a, e
	sub [hl]
	dec hl
	ld a, d
	sbc [hl] ; carry iff HP * 4 < MaxHP
	ret c ; below a quarter: sacrifice
	call AIBestReserveKeepsHalf
	ld a, e
	cp 1 ; carry iff e = 0: the hit would take half or more
	ret

; Shared scan. Compares every believed player move against whatever HP total
; sits in wBuffer + AI_BUF_EFFHP, which is what lets the "would I survive if I
; healed" question reuse this wholesale instead of needing a max-damage value.
; Also returns de = the largest delivered damage it saw, Super Fang excluded
; (half of OUR current HP, so not HP-independent); with carry set that is only a
; lower bound, since the scan stops at the first KO. Only AIPlayerWouldKO keeps
; it. The running maximum lives on the stack across the loop.
_AIScanPlayerMovesForKO:
	ld hl, wPlayerMoveNum
	ld de, wBuffer + AI_BUF_MOVESAVE
	ld bc, MOVE_LENGTH
	call CopyData
	xor a
	ld [wBuffer + AI_BUF_SCANSLOT], a
	ld h, a
	ld l, a
	push hl ; running maximum
.nextSlot
	ld a, [wBuffer + AI_BUF_SCANSLOT]
	cp NUM_MOVES
	jr nc, .noKO
	call AIGetPlayerMoveN ; plain same-bank call: this accessor takes its
	                      ; argument in a, which could not survive a farcall
	and a
	jr z, .emptySlot ; unrevealed (Phase 7 fair play) or a real gap - either
	                 ; way, KEEP SCANNING. Before Phase 7 the real moveset was
	                 ; always packed (first zero = end of list, safe to stop),
	                 ; but AIGetPlayerMoveN can now return a sparse revealed set:
	                 ; the player can reveal slot 2 before
	                 ; slot 0. Stopping at the first zero would silently skip
	                 ; every already-revealed move behind an unrevealed one.
	call AIReadMoveIntoPlayerBlock
	farcall AIEstimatePlayerDamage ; -> wAIDamageEstimate
	call AIAdjustPlayerDamageForPossibleDelivery
	ld a, [wPlayerMoveEffect]
	cp SUPER_FANG_EFFECT
	jr z, .maxDone
	pop hl
	ld a, [wAIDamageEstimate + 1]
	sub l
	ld a, [wAIDamageEstimate]
	sbc h ; carry iff this move < the maximum so far
	jr c, .keepMax
	ld a, [wAIDamageEstimate]
	ld h, a
	ld a, [wAIDamageEstimate + 1]
	ld l, a
.keepMax
	push hl
.maxDone
	call AIDamageWouldKOEnemy
	jr c, .yesKO
.emptySlot
	ld hl, wBuffer + AI_BUF_SCANSLOT
	inc [hl]
	jr .nextSlot
.yesKO
	call .restorePlayerMove
	pop de
	scf
	ret
.noKO
	call .restorePlayerMove
	pop de
	and a ; clear carry
	ret
.restorePlayerMove
	ld hl, wBuffer + AI_BUF_MOVESAVE
	ld de, wPlayerMoveNum
	ld bc, MOVE_LENGTH
	jp CopyData

; ReadMove's twin, targeting the PLAYER's move block instead of the enemy's.
; Same shape deliberately; see ReadMove in trainer_ai.asm. INPUT: a = move id.
AIReadMoveIntoPlayerBlock:
	push hl
	push de
	push bc
	ld de, wPlayerMoveNum
	ASSERT BANK(ReadMoveIntoDE) == BANK(@) ; plain jp: must stay co-located
	jp ReadMoveIntoDE    ; pops bc/de/hl and returns for us

; Carry SET if the loaded enemy move is an "investment": it spends this turn to
; be better on a later one. Two contiguous stat-raising bands plus the four
; standalone setup moves.
; Clobbers af.
AIIsInvestmentMove:
	ld a, [wEnemyMoveEffect]
	cp ATTACK_UP1_EFFECT
	jr c, .checkSingles ; below the +1 band
	cp PAY_DAY_EFFECT
	jr c, .yes ; inside ATTACK_UP1..EVASION_UP1
	cp ATTACK_UP2_EFFECT
	jr c, .checkSingles ; between the bands
	cp HEAL_EFFECT
	jr c, .yes ; inside ATTACK_UP2..EVASION_UP2
.checkSingles
	cp FOCUS_ENERGY_EFFECT
	jr z, .yes
	cp LIGHT_SCREEN_EFFECT
	jr z, .yes
	cp REFLECT_EFFECT
	jr z, .yes
	cp SUBSTITUTE_EFFECT
	jr z, .yes
	and a ; clear carry
	ret
.yes
	scf
	ret

; Carry SET if the loaded enemy move's whole point is to stop the target acting.
; Only the guaranteed-application effects qualify: the side-effect versions
; (Body Slam's paralysis, Ice Beam's freeze) are a chance riding on an attack,
; and AI_DAMAGE already scores those on their damage.
; Clobbers af.
AIIsDisablingStatus:
	ld a, [wEnemyMoveEffect]
	cp SLEEP_EFFECT
	jr z, .yes
	cp PARALYZE_EFFECT
	jr z, .yes
	and a
	ret
.yes
	scf
	ret
