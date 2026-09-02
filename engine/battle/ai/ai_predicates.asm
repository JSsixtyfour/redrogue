; Shared AI predicates (AI_OVERHAUL_PLAN.md Phase 2b): the HP-tier vocabulary
; that most AI_SMART heuristics are expressed in, plus the repeated-move
; tracking those heuristics read.
;
; INCLUDEd into "Battle Engine 7" (bank $0E), the same bank as trainer_ai.asm
; and every AILayer* routine. This is mandatory, not stylistic: the layer
; dispatch reaches layers with a plain same-bank `jp hl`, so everything a layer
; calls in a hot path must be co-located. See ai_score_helpers.asm's header and
; ROM_BIBLE.md's 2026-08-25 entry for the full reasoning and the bugs that
; came from getting this wrong in Phase 2a.
;
; WHY THESE EXIST: pokecrystal expresses roughly thirty AI_SMART handlers in
; about six lines each, and the reason it can is that "am I below half HP" is
; one call rather than an open-coded 16-bit compare every time. Porting the
; handlers without porting this vocabulary first would mean thirty
; opportunities to get a 16-bit comparison subtly wrong.
;
; All six are integer-only: they compare (currentHP << n) against maxHP rather
; than dividing maxHP, so there is no division, no rounding, and no dependence
; on hDivisor/hQuotient (which other battle code uses and which the existing
; AICheckIfHPBelowFraction does clobber).

; Core comparison. Not called directly by heuristics; use the named wrappers.
; INPUT:  hl = pointer to current HP (big-endian dw)
;         de = pointer to max HP (big-endian dw)
;         b  = number of times to double current HP before comparing (0/1/2)
; OUTPUT: carry SET if (currentHP << b) < maxHP
; Clobbers af, bc, de, hl.
AIHPShiftCompare:
	ld a, [hli]
	ld c, [hl]
	ld h, a
	ld l, c ; hl = current HP
	inc b   ; so the loop below handles a shift count of 0 correctly
.shiftLoop
	dec b
	jr z, .compare
	add hl, hl
	jr nc, .shiftLoop
; Overflowed 16 bits. Max HP is capped at 999 by the stat system, so a value
; that has already exceeded 65535 is unambiguously greater - report "not less"
; without touching memory further.
	and a
	ret
.compare
	ld a, [de]
	inc de
	ld b, a
	ld a, [de]
	ld c, a ; bc = max HP
	ld a, l
	sub c
	ld a, h
	sbc b   ; carry set iff hl < bc
	ret

; --- Enemy side (the AI's own mon) ---

; Carry set if the enemy is at full HP.
; Current HP can never exceed max, so "not less than max" is exactly "at max".
AIEnemyHPAtMax::
	ld hl, wEnemyMonHP
	ld de, wEnemyMonMaxHP
	ld b, 0
	call AIHPShiftCompare
	ccf
	ret

; Carry set if the enemy is strictly below half HP.
AIEnemyHPBelowHalf::
	ld hl, wEnemyMonHP
	ld de, wEnemyMonMaxHP
	ld b, 1
	jp AIHPShiftCompare

; Carry set if the enemy is strictly below a quarter HP.
AIEnemyHPBelowQuarter::
	ld hl, wEnemyMonHP
	ld de, wEnemyMonMaxHP
	ld b, 2
	jp AIHPShiftCompare

; --- Player side (the AI's target) ---
; These read wBattleMon* directly rather than going through the ai_core.asm
; accessor seam, because HP is not part of the information model the seam
; hides: Phase 7 limits what the AI knows about the player's MOVES and
; status/type, not their visible HP bar, which is on screen either way.

; Carry set if the player is at full HP.
AIPlayerHPAtMax::
	ld hl, wBattleMonHP
	ld de, wBattleMonMaxHP
	ld b, 0
	call AIHPShiftCompare
	ccf
	ret

; Carry set if the player is strictly below half HP.
AIPlayerHPBelowHalf::
	ld hl, wBattleMonHP
	ld de, wBattleMonMaxHP
	ld b, 1
	jp AIHPShiftCompare

; Carry set if the player is strictly below a quarter HP.
AIPlayerHPBelowQuarter::
	ld hl, wBattleMonHP
	ld de, wBattleMonMaxHP
	ld b, 2
	jp AIHPShiftCompare

; F14, 2026-09-02: carry set if the player already has damage-over-time
; running (poisoned or badly poisoned via Toxic - both set PSN on
; wBattleMonStatus; burned; or Leech Seeded). Shared by AISmart_Trapping
; (ai_smart.asm, plain call - same bank) and AIFit_WrapLock/AIFit_AgilityWrap
; (ai_plans.asm, bank $2C, reached by farcall - same shape as
; AIEnemyHPBelowHalf/AIPlayerWouldKO already used from those two routines).
; Sleep/freeze/paralysis are deliberately excluded: they stop the target
; acting, which is already the point of a trap, but they are not damage
; sources on their own, so they do not raise a trap's value the way an
; uninterruptible drain does.
; Clobbers af.
AIPlayerHasChipDamage::
	ld a, [wBattleMonStatus]
	and (1 << PSN) | (1 << BRN)
	jr nz, .yes
	ld a, [wPlayerBattleStatus1]
	bit SEEDED, a
	jr z, .no
.yes
	scf
	ret
.no
	and a
	ret

; F14, 2026-09-02: carry set if the player is currently losing turns or HP
; regardless of what we do this turn - poisoned/badly poisoned, burned,
; asleep, frozen, or wrap-locked by OUR OWN trapping move. Broader than
; AIPlayerHasChipDamage above (which only covers the three damage-per-turn
; statuses, for the trap-value question): this one also covers the two
; turn-denial statuses (sleep, freeze) and our own trap, since those make a
; slow move "free" in the same way a damage-per-turn status does - the player
; is not getting anywhere regardless. Used to decide whether a two-turn move's
; lost tempo, or an evasion boost's lost turn, is actually costing anything.
; Clobbers af.
AIPlayerIsStalled::
	ld a, [wBattleMonStatus]
	and (1 << PSN) | (1 << BRN) | (1 << FRZ) | SLP_MASK
	jr nz, .yes
	ld a, [wPlayerBattleStatus1]
	bit USING_TRAPPING_MOVE, a
	jr z, .no
.yes
	scf
	ret
.no
	and a
	ret

; --- Damage / KO predicates (Phase 3) --------------------------------------
; These read wAIDamageEstimate, which is populated by AIEstimateDamage
; (engine/battle/core.asm, bank $0F - see that routine's header for why it
; cannot live in this bank). A caller must `farcall AIEstimateDamage` for the
; move it wants to ask about BEFORE calling anything here; these routines do
; not run the simulator themselves, so that one farcall per move is not paid
; again per predicate.

; Carry SET if (wAIDamageEstimate << b) >= the defender's current HP. The shift
; turns one comparison into the whole damage-tier vocabulary, the same trick
; AIHPShiftCompare above uses for HP bands, and for the same reason: no
; division, no rounding, no hDivisor/hQuotient dependency.
;   b = 0 -> this move kills outright
;   b = 1 -> it takes at least half the remaining HP
;   b = 2 -> at least a quarter
;
; Note the estimate is a MAXIMUM roll (AIEstimateDamage skips RandomizeDamage),
; so b=0 answers "can this move kill", not "does it on average". That is the
; intended reading for the priority cascade's rank 1: taking a kill that is
; merely possible is correct play, even when a low roll would fall short.
;
; INPUT: b = shift count, hl = pointer to the defender's current HP (2 bytes,
;        high byte first). Whichever side is DEFENDING is the caller's choice,
;        which is what lets the enemy-attacks-player and player-attacks-enemy
;        directions share one comparison.
; Clobbers af, bc, de, hl.
AIDamageReachesHP::
	ld a, [wAIDamageEstimate]
	ld d, a
	ld a, [wAIDamageEstimate + 1]
	ld e, a ; de = estimated damage
	inc b   ; so a shift count of 0 falls straight through to .compare
.shiftLoop
	dec b
	jr z, .compare
	sla e
	rl d
	jr nc, .shiftLoop
; Overflowed 16 bits. Max HP is capped at 999 by the stat system, so a value
; this large unambiguously reaches it - report "reaches" without reading further.
	scf
	ret
.compare
	ld a, [hli]
	ld b, a
	ld c, [hl] ; bc = defender's current HP
	ld a, e
	sub c
	ld a, d
	sbc b   ; carry set iff de < bc, i.e. the hit falls short
	ccf     ; flip, so carry set means "reaches or exceeds"
	ret

; Carry SET if (estimate << b) >= the PLAYER's current HP. Used by AI_DAMAGE to
; score the enemy's own moves. INPUT: b = shift count.
AIDamageReachesFraction::
	ld hl, wBattleMonHP
	jp AIDamageReachesHP

; Carry SET if the currently-estimated enemy move would KO the player outright.
AIMoveWouldKO::
	ld b, 0
	jr AIDamageReachesFraction

; Carry SET if the currently-estimated PLAYER move reaches the enemy HP total
; currently staged in wBuffer + AI_BUF_EFFHP. The mirror of AIMoveWouldKO, used
; by AI_THREAT to answer "am I about to die".
;
; Deliberately reads the STAGED total rather than wEnemyMonHP directly. Callers
; set it: AIPlayerWouldKO stages the live current HP, and AIHealWouldStillDie
; stages the POST-heal total, which is what lets "would healing actually save
; me" reuse this whole scan instead of needing a separate max-damage value.
; Reading wEnemyMonHP here instead was a real bug - it made AIHealWouldStillDie
; silently answer the question AIPlayerWouldKO had already answered, so a heal
; that fully restored HP was still reported as futile.
AIDamageWouldKOEnemy::
	ld b, 0
	ld hl, wBuffer + AI_BUF_EFFHP
	jp AIDamageReachesHP

; --- Repeated-move / anti-spam tracking -----------------------------------
; Maintains wAILastMovePower, wAILastMoveNum and wAISameMoveCount, which Phase 1
; allocated but nothing wrote. Called once per AI decision, from the top of
; AIEnemyTrainerChooseMoves, BEFORE any ReadMove call in the scoring layers.
;
; That ordering is the whole trick and is why this needs no core.asm edit:
;   - wEnemyMovePower still holds the power of the move the enemy executed LAST
;     turn, because ReadMove (which overwrites the wEnemyMove* block) has not
;     run yet this cycle. This is ShinRed's technique, verbatim.
;   - wEnemySelectedMove likewise still holds LAST turn's selection, because
;     SelectEnemyMove only writes it at its `.done` label, after this routine
;     has already returned (verified: engine/battle/core.asm, `.done` /
;     `ld [wEnemySelectedMove], a` sits below the AI call site).
;
; Consumed by AI_SMART: wAILastMovePower drives anti-spam (do not follow a
; 0-power move with another 0-power move), and wAISameMoveCount drives
; repeated-move fatigue (ExtremeYellow's idea: discourage a move only after it
; has already been used several times in a row, so ordinary sensible repetition
; is not punished).
;
; Clobbers af, hl.
AITrackLastMove::
	ld a, [wEnemyMovePower]
	ld [wAILastMovePower], a

	ld a, [wEnemySelectedMove]
	ld hl, wAILastMoveNum
	cp [hl]
	jr nz, .differentMove
; Same move as last turn: bump the streak, saturating so it cannot wrap around
; to zero during a very long stall and silently cancel the fatigue penalty.
	ld a, [wAISameMoveCount]
	cp $ff
	jr z, .done
	inc a
	ld [wAISameMoveCount], a
	ret
.differentMove
	ld [hl], a ; remember the new move
	xor a
	ld [wAISameMoveCount], a
.done
	ret

; --- Speed comparison (Phase 3 Step 2) -------------------------------------
; Carry SET if the enemy's Speed is strictly greater than the player's, i.e.
; the enemy acts first this turn.
;
; This is the hinge of the whole "I am about to die" decision. If the enemy is
; FASTER, a disabling status can still land and prevent the KO outright, so
; spending the turn on it is correct. If the enemy is SLOWER, the player's
; lethal move resolves first and nothing the enemy picks can stop it - at which
; point variance is the only line that wins, because the estimate is a MAXIMUM
; roll and a low roll may leave the enemy alive.
;
; Deliberately ignores paralysis' quarter-speed penalty and Speed stat stages:
; wEnemyMonSpeed / wBattleMonSpeed are the live in-battle values, which already
; have both folded in.
; Clobbers af, bc, de.
AIEnemyIsFaster::
	ld a, [wEnemyMonSpeed]
	ld b, a
	ld a, [wEnemyMonSpeed + 1]
	ld c, a ; bc = enemy speed
	ld a, [wBattleMonSpeed]
	ld d, a
	ld a, [wBattleMonSpeed + 1]
	ld e, a ; de = player speed
	ld a, e
	sub c
	ld a, d
	sbc b   ; carry set iff de < bc, i.e. player is slower
	ret

; Carry SET if the enemy acts FIRST this turn using the move currently loaded in
; the wEnemyMove* block.
;
; Gen 1 has no priority field. The engine hardcodes two move ids in
; MainInBattleLoop (engine/battle/core.asm, the block around .noLinkBattle):
; QUICK_ATTACK moves its user first, COUNTER moves its user LAST, and everything
; else falls through to a Speed comparison. So AIEnemyIsFaster on its own is an
; incomplete answer to "who acts first" - which is a correctness bug, not just a
; missing refinement: a slower mon holding Quick Attack really does act first,
; and AI_THREAT reasoned as though it did not.
;
; DELIBERATELY does not read wPlayerSelectedMove, even though the player has
; already locked their move in by the time the AI runs. Knowing THIS turn's
; choice is a far stronger form of cheating than the roster-level omniscience
; the plan permits, and it would make mirror-priority situations unbeatable.
; The AI assumes the player is not also using Quick Attack - the same assumption
; a human opponent makes.
; Clobbers af, bc, de, hl.
AIEnemyActsFirstWith::
	ld a, [wEnemyMoveNum]
	cp QUICK_ATTACK
	jr z, .actsFirst
	cp COUNTER
	jr z, .actsLast
	jp AIEnemyIsFaster
.actsFirst
	scf
	ret
.actsLast
	and a ; a holds COUNTER here, so this only clears carry
	ret

; --- Accuracy (Phase 3 Step 3) ---------------------------------------------

; OUTPUT: a = the enemy's currently-loaded move's true hit chance, 0-255.
;
; Wraps the engine's own CalcHitChance rather than reading wEnemyMoveAccuracy
; raw, and that distinction is the whole point: CalcHitChance already scales a
; move's base accuracy by the ATTACKER's accuracy stages and the TARGET's
; evasion stages. So a target who has been boosting evasion correctly devalues
; ordinary moves here - and correctly makes Swift, which bypasses the accuracy
; check entirely, look better against exactly that target.
;
; CalcHitChance writes its scaled result BACK into wEnemyMoveAccuracy in place,
; so the original byte is saved and restored around the call.
;
; Reached by farcall despite living in another bank, which is safe here for the
; precise reason AIEstimateDamage could NOT be split: CalcHitChance takes no
; register arguments at all. It selects its inputs from hWhoseTurn and returns
; through WRAM, so there is no register contract for Bankswitch to destroy.
;
; KNOWN GAP: SF_NEVER_MISS / SF_ALWAYS_HIT are not consulted, so a special-form
; attacker's accuracy is under-reported. They cannot be read across a farcall
; (GetAttackerSpecialFormCaps returns in a, which Bankswitch destroys), so they
; are tracked together with the SF_ALWAYS_CRIT gap in the plan.
; Clobbers bc, de, hl.
AIGetMoveHitChance::
	ld a, [wEnemyMoveEffect]
	cp SWIFT_EFFECT
	jr z, .neverMisses ; Swift returns before MoveHitTest's accuracy roll
	ld a, [wEnemyMoveAccuracy]
	push af
	ldh a, [hWhoseTurn]
	push af
	ld a, $1
	ldh [hWhoseTurn], a ; CalcHitChance picks its move block and stat mods off this
	farcall CalcHitChance
	ld a, [wEnemyMoveAccuracy]
	ld b, a ; the scaled chance, captured before the byte is put back
	pop af
	ldh [hWhoseTurn], a
	pop af
	ld [wEnemyMoveAccuracy], a
	ld a, b
	ret
.neverMisses
	ld a, $ff
	ret

; Scales wAIDamageEstimate down by the loaded move's hit chance, turning the
; max-roll figure into an EXPECTED damage figure.
;
; This one routine is what makes accuracy pervade every damage decision:
; Thunderbolt (95 power, 100%) beats Thunder (120 power, 70%) on expected
; damage with neither special-cased, and the same arithmetic settles
; Flamethrower vs Fire Blast. It is strictly stronger than the classic
; "power x accuracy" heuristic, because the number being scaled already has
; STAB, dual-type effectiveness, live stats and screens folded into it.
;
; Callers that need to ask "CAN this move kill" must do so BEFORE calling this:
; that is a question about possibility, not expectation, and scaling first would
; hide a real but unreliable kill.
; Clobbers af, bc, de, hl.
AIScaleDamageByAccuracy::
	call AIGetMoveHitChance
	ld b, a
	xor a
	ldh [hMultiplicand], a
	ld a, [wAIDamageEstimate]
	ldh [hMultiplicand + 1], a
	ld a, [wAIDamageEstimate + 1]
	ldh [hMultiplicand + 2], a
	ld a, b
	ldh [hMultiplier], a
	call Multiply
; hProduct is big-endian and OVERLAPS hMultiplicand through the union in
; ram/hram.asm, so dividing the 32-bit product by 256 is simply dropping its
; last byte: the 16-bit answer is hProduct+1 (high) and hProduct+2 (low).
; Damage caps at 999 and the chance at 255, so hProduct+0 is always zero here.
	ldh a, [hProduct + 1]
	ld [wAIDamageEstimate], a
	ldh a, [hProduct + 2]
	ld [wAIDamageEstimate + 1], a
	ret

; Scales wAIDamageEstimate by the move's EXPECTED critical-hit contribution:
;
;     expected = estimate + estimate * critThreshold / 256
;
; User request, 2026-09-01, and it answers the Slash-vs-Strength question
; directly rather than special-casing guaranteed crits. Worked example, Persian
; (base speed 115), verified against the real CalcCritRate arithmetic:
;
;   Slash    high-crit, threshold = baseSpeed * 4 -> capped 255 -> x1.996
;            70 base power behaves like ~140
;   Strength normal,    threshold = baseSpeed / 2 ->        57 -> x1.22
;            80 base power behaves like ~98
;
; So Slash correctly outranks the nominally stronger move, with no move-specific
; rule. The engine's crit math sanity-checks against Smogon too: Tauros (base
; speed 110) gives 55/256 = 21.5%, the published figure.
;
; WHY THE TIER TESTS ARE ALLOWED TO SEE THIS, even though a 21% crit chance is
; not a 21% larger hit: AIEstimateDamage already reports the MAXIMUM damage roll
; on purpose, so every consumer in this AI is written against an optimistic
; bound, not an average. Crit expectation is the same kind of optimism applied
; consistently, and at the extreme - a guaranteed crit - it is exact rather than
; optimistic. Introducing a second, separate "raw" value for the kill test would
; buy accuracy the rest of the simulator does not have.
;
; KNOWN LIMITATION, deliberately not fixed here: Gen 1 crits ignore stat stages
; and screens, so a real crit into a Reflect or Amnesia wall is worth MORE than
; 2x this estimate, and a crit from a mon that has boosted its own Attack is
; worth LESS. Getting that exact needs a second estimate pass with stages
; neutralised, which is its own piece of work (AI_OVERHAUL_PLAN.md follow-ups).
;
; SIDE EFFECT MANAGED, NOT IGNORED: CalcCritRate writes wCurSpecies and calls
; GetMonHeader. wCurSpecies is the byte that is also wCurPartySpecies and
; wCurItem (see project_wcuritem_species_alias), so it is saved and restored
; here. wMonHeader itself is left clobbered, which is safe because
; CriticalHitTest does exactly the same thing to it moments later during the
; move that follows.
;
; Reached by farcall despite CalcCritRate living in bank $0F: it takes no
; register arguments (it selects everything from hWhoseTurn and the move block),
; and it returns in e plus the Z and C flags, all of which survive a farcall
; return - the same reasoning AIGetMoveHitChance's header sets out.
; Clobbers af, bc, de, hl.
AIScaleDamageForCrit::
	ld a, [wCurSpecies]
	push af
	ldh a, [hWhoseTurn]
	push af
	ld a, $1
	ldh [hWhoseTurn], a ; CalcCritRate picks the attacker off this
	farcall CalcCritRate ; -> e = threshold, Z = move has no power,
	                     ;    C = special form guarantees the crit
; Capture the answer BEFORE the pops below: `pop af` restores flags and would
; destroy both results. `ld b, e` is safe here because LD r,r touches no flags.
	ld b, e
	jr z, .noPower ; CalcCritRate returned before computing a threshold
	jr nc, .gotRate
	ld b, $ff ; SF_ALWAYS_CRIT. Distinct from a threshold that merely happens to
	          ; cap at $ff, per CalcCritRate's own header, but worth the same
	          ; here: both mean "this crits".
	jr .gotRate
.noPower
	ld b, 0
.gotRate
	pop af
	ldh [hWhoseTurn], a
	pop af
	ld [wCurSpecies], a

	ld a, b
	and a
	ret z ; no crit chance at all: leave the estimate exactly as it was

; bonus = estimate * threshold / 256, the same shape AIScaleDamageByAccuracy
; uses above - hProduct overlaps hMultiplicand through the union in ram/hram.asm,
; so dividing by 256 is just dropping the last byte.
	xor a
	ldh [hMultiplicand], a
	ld a, [wAIDamageEstimate]
	ldh [hMultiplicand + 1], a
	ld a, [wAIDamageEstimate + 1]
	ldh [hMultiplicand + 2], a
	ld a, b
	ldh [hMultiplier], a
	call Multiply
	ldh a, [hProduct + 1]
	ld b, a
	ldh a, [hProduct + 2]
	ld c, a ; bc = the crit bonus

	ld a, [wAIDamageEstimate + 1]
	add c
	ld e, a
	ld a, [wAIDamageEstimate]
	adc b
	ld d, a
	jr nc, .noOverflow
	ld de, $ffff ; saturate rather than wrap. Unreachable with the 999 damage
	             ; cap, but a wrapped estimate would read as "this move does
	             ; almost nothing", which is the worst possible failure here.
.noOverflow
	ld a, d
	ld [wAIDamageEstimate], a
	ld a, e
	ld [wAIDamageEstimate + 1], a
	ret

; --- Switching support (Phase 4) -------------------------------------------

; Carry SET if the enemy's active mon has at least one move that is
; super-effective against the player.
;
; Deliberately uses AIGetTypeEffectiveness - the same single-type check AI_TYPES
; already scores with - rather than the dual-type PreviewTypeMatchup. The point
; is to answer "does the scoring layer think I have a good move here", and using
; a DIFFERENT notion of effectiveness than the layer that actually picks the
; move would let the switch decision and the move decision disagree about the
; same board. See AI_OVERHAUL_PLAN.md follow-up F7 for why $10, not 10, is this
; engine's neutral sentinel; every caller compares against it, so this does too.
;
; Lives in bank $0E because it calls ReadMove, whose Moves table is in this
; bank. Farcalled from the switching engine in bank $2C, returning its answer in
; CARRY - which survives a farcall return (see ai_switching.asm's header).
;
; CLOBBERS the wEnemyMove* block via ReadMove. Safe at the point this is called
; from (TrainerAI, before move execution reloads it through GetCurrentMove), and
; no worse than what every scoring layer already does to that block.
; Clobbers af, bc, de, hl.
AIHasSuperEffectiveMove::
	ld hl, wEnemyMonMoves
	ld b, NUM_MOVES
.loop
	ld a, [hli]
	and a
	jr z, .no ; move list is packed, so an empty slot ends it
	push hl
	push bc
	call ReadMove
	callfar AIGetTypeEffectiveness
	ld a, [wTypeEffectiveness]
	pop bc
	pop hl
	cp $10
	jr z, .next ; exactly neutral
	jr c, .next ; below neutral - resisted or immune
	scf
	ret
.next
	dec b
	jr nz, .loop
.no
	and a
	ret
