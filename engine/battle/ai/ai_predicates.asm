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

; F22, 2026-09-02: carry SET if the move currently loaded in the wEnemyMove*
; block would KO the player, which makes any SECONDARY-EFFECT RIDER it carries
; worth exactly nothing. A paralysis, burn, freeze, poison, confusion, flinch or
; stat-drop chance against a target that is about to faint buys the AI precisely
; zero, and AI_SMART was paying full price for all of them.
;
; ONLY the rider handlers call this. Several other AI_SMART handlers encourage a
; move that is ALSO lethal for reasons that remain perfectly valid on a kill, and
; they must not be gated on this: AISmart_HyperBeam (Hyper Beam does not recharge
; when it KOs - the plan's own "always fire Hyper Beam when it kills" rule) and
; AISmart_DrainHP (the drain still heals you). The distinction is not "is the
; move lethal" but "is the thing being paid for still worth anything once the
; target is gone".
;
; Uses the SAME reliable determination AI_DAMAGE uses: the guaranteed damage
; (minimum roll, minimum hit count, after Substitute) must reach HP and the move
; must have at least 90% hit chance. A crit-weighted expectation is not a KO bound, and an unreliable
; possible kill can still benefit from its rider when the target survives.
;
; Status moves (0 power) return "not lethal" without paying for an estimate. In
; practice unreachable - every *_SIDE_EFFECT is attached to a damaging move - but
; it is four bytes and it keeps the routine honest if one ever is not.
;
; COST: one AIEstimateDamage farcall per riding move per decision, on top of the
; one AI_DAMAGE already pays for the same move. Accepted rather than cached:
; AI_SMART runs BEFORE AI_DAMAGE in bit order, so there is no populated estimate
; to reuse here, and threading one through would need either new wBuffer state
; (there is none spare - wBuffer is an exact 30-byte fit, see AI_BUF_PHYSICAL)
; or a layer reordering, both far larger changes than this is worth.
; Clobbers af, bc, de, hl.
AISmartRiderIsWasted::
	ld a, [wEnemyMovePower]
	and a
	jr z, .notLethal
	farcall AIEstimateDamage
	call AIAdjustEnemyDamageForReliableDelivery
	jp AIMoveIsReliableKO
.notLethal
	and a ; clear carry
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

; Carry SET if the estimate reaches the player's HP and the move's effective hit
; chance is at least 90%. This is the shared contract for callers that need a
; RELIABLE KO rather than a merely possible one.
; INPUT: wAIDamageEstimate as left by AIAdjustEnemyDamageForReliableDelivery
; (minimum damage roll, minimum hit count, after Substitute) and the loaded
; wEnemyMove* block. Feeding it the POSSIBLE delivery (max roll, 5 hits) is the
; 2026-09-29 review's F2/F4 bug: a Spike Cannon needing 3+ hits scored as a
; sure kill. Clobbers af, bc, de, hl.
AIMoveIsReliableKO::
	call AIMoveWouldKO
	ret nc
	call AIGetMoveHitChance
	cp 90 percent
	ccf
	ret

; Checkpoint D: carry SET if the enemy's SELECTED move satisfies the
; reliable-KO contract above. This is the narrow winning-action veto used by
; voluntary switching: do not give up a high-confidence finish merely because
; the player could also KO us.
;
; NO TURN-ORDER TEST, deliberately (2026-09-29 review F1). The only caller is
; AIShouldSwitch, reached only from TrainerAI, which the battle loop calls at
; the ENEMY'S ACTION POINT (core.asm .enemyMovesFirst / after ExecutePlayerMove
; on .playerMovesFirst). If the player moved first they have already acted this
; turn; if we move first we are about to. Either way the selected move lands
; before the player's next action, whatever the speeds. The old
; AIEnemyActsFirstWith requirement made a slower mon that had survived the hit
; switch out of a won exchange (measured: probe_ai_review_phase0 F1). Do not
; call this from move selection, where turn order has NOT been decided yet.
;
; "Reliable" is AIMoveIsReliableKO's meaning, after Substitute delivery. Forced-
; action states cannot use a newly selected finisher, and paralysis (25% full
; paralysis) cannot meet the 90% bar, so neither qualifies. Disable is checked
; by slot exactly as SelectEnemyMove does. The live wEnemyMove block is
; restored on every exit.
; Clobbers af, bc, de, hl.
AIEnemyHasReliableFirstKO::
	ld a, [wEnemyMonStatus]
	and (1 << FRZ) | (1 << PAR) | SLP_MASK
	jr nz, .noKO
	ld a, [wEnemyBattleStatus1]
	and (1 << STORING_ENERGY) | (1 << THRASHING_ABOUT) | (1 << FLINCHED) | (1 << CHARGING_UP) | (1 << USING_TRAPPING_MOVE) | (1 << CONFUSED)
	jr nz, .noKO
	ld a, [wEnemyBattleStatus2]
	and (1 << NEEDS_TO_RECHARGE) | (1 << USING_RAGE)
	jr nz, .noKO

; SelectEnemyMove has already committed this turn's action before TrainerAI
; considers a switch or item. Evaluate that action only: another finisher in
; the moveset is irrelevant if it was not selected.
	ld a, [wEnemySelectedMove]
	cp CANNOT_MOVE
	jr z, .noKO
	and a
	jr z, .noKO
	ld a, [wEnemyMoveListIndex]
	inc a
	ld c, a
	ld a, [wEnemyDisabledMove]
	swap a
	and $f
	cp c
	jr z, .noKO

	ld hl, wEnemyMoveNum
	ld de, wBuffer + AI_BUF_MOVESAVE
	ld bc, MOVE_LENGTH
	call CopyData
	ld a, [wEnemySelectedMove]
	call ReadMove
; Charge-turn actions do not deliver their estimated damage this turn.
	ld a, [wEnemyMoveEffect]
	cp CHARGE_EFFECT
	jr z, .restoreNoKO
	cp FLY_EFFECT
	jr z, .restoreNoKO
	farcall AIEstimateDamage
	call AIAdjustEnemyDamageForReliableDelivery
	call AIMoveIsReliableKO
	jr nc, .restoreNoKO
	call .restoreMove
	scf
	ret
.restoreNoKO
	call .restoreMove
.noKO
	and a
	ret
.restoreMove
	ld hl, wBuffer + AI_BUF_MOVESAVE
	ld de, wEnemyMoveNum
	ld bc, MOVE_LENGTH
	jp CopyData
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

; Far target for AIPlanClassMoveLands in bank $2C; returns its boolean in e.
; Input de = class mask. Output e = 1 if any matching move can legally land, else 0.
AIPlanClassMoveLandsFar::
	ld hl, wBuffer + AI_BUF_PLANCLASS
	ld b, 0
.next
	ld a, [hli]
	and e
	jr nz, .foundLowByte
	ld a, [hli]
	and d
	jr nz, .candidate
	jr .advance
.foundLowByte
	inc hl
.candidate
	push hl
	push bc
	push de
	ld hl, wEnemyMonMoves
	ld c, b
	ld b, 0
	add hl, bc
	ld e, [hl]
	farcall AIReadMoveFromE
	call .loadedMoveLands
	pop de
	pop bc
	pop hl
	jr c, .lands
.advance
	inc b
	ld a, b
	cp NUM_MOVES
	jr c, .next
	ld e, 0
	ret
.lands
	ld e, 1
	ret

.loadedMoveLands
	ld a, [wEnemyMoveEffect]
	cp SLEEP_EFFECT
	jr z, .sleep
	cp POISON_EFFECT
	jr z, .poison
	cp PARALYZE_EFFECT
	jr z, .paralyze
	ld a, [wPlayerMoveType]
	push af
	ld a, [wEnemyMonType1]
	push af
	ld a, [wEnemyMonType2]
	push af
	ld a, [wEnemyMoveType]
	ld [wPlayerMoveType], a
	ld a, [wBattleMonType1]
	ld [wEnemyMonType1], a
	ld a, [wBattleMonType2]
	ld [wEnemyMonType2], a
	farcall PreviewTypeMatchup
	ld d, e
	pop af
	ld [wEnemyMonType2], a
	pop af
	ld [wEnemyMonType1], a
	pop af
	ld [wPlayerMoveType], a
	ld a, d
	and a
	ret z
	scf
	ret
.sleep
	call AIPrimarySleepIsBlocked
	jr .statusResult
.poison
	call AIPrimaryPoisonIsBlocked
	jr .statusResult
.paralyze
	call AIPrimaryParalyzeIsBlocked
.statusResult
	jr c, .doesNotLand
	scf
	ret
.doesNotLand
	and a
	ret
; --- Primary status legality (Checkpoint B R7) -----------------------------
; The Bridge check below asks "is the ENEMY attacking the player?" by reading
; hWhoseTurn, and returns "allowed" when it is 0. The AI plans with whatever
; hWhoseTurn the last executed move left, measured 0 for 30 of 35 calls in a
; FIGHT 2 battle, so an immune player looked sleepable. Force the enemy side
; for the check only, then restore it.
; In: e = BRIDGE_STATUS_CHECK_*. Out: carry = blocked. Clobbers af, bc, de, hl.
AIBridgePlayerTargetBlocksStatus:
	ldh a, [hWhoseTurn]
	push af
	ld a, 1
	ldh [hWhoseTurn], a
	farcall BridgePlayerTargetBlocksStatus ; carry = blocked; flags survive Bankswitch
	pop bc                      ; b = saved hWhoseTurn; pop bc leaves F intact
	ld a, b
	ldh [hWhoseTurn], a         ; ldh leaves carry intact
	ret

; Carry SET when the enemy's primary status move cannot affect the player.
; These are shared by redundancy scoring and strategy-plan fitness. They mirror
; the real effect gates, including Bridge-selected immunities.
AIPrimarySleepIsBlocked::
	ld a, [wPlayerBattleStatus2]
	bit HAS_SUBSTITUTE_UP, a
	jr nz, .blocked
	ld a, [wBattleMonStatus]
	and a
	jr nz, .blocked
	ld e, BRIDGE_STATUS_CHECK_OTHER
	jp AIBridgePlayerTargetBlocksStatus
.blocked
	scf
	ret

AIPrimaryPoisonIsBlocked::
	ld a, [wPlayerBattleStatus2]
	bit HAS_SUBSTITUTE_UP, a
	jr nz, .blocked
	ld a, [wBattleMonStatus]
	and a
	jr nz, .blocked
	ld a, [wBattleMonType1]
	cp POISON
	jr z, .blocked
	ld a, [wBattleMonType2]
	cp POISON
	jr z, .blocked
	ld e, BRIDGE_STATUS_CHECK_POISON
	jp AIBridgePlayerTargetBlocksStatus
.blocked
	scf
	ret

AIPrimaryParalyzeIsBlocked::
	ld a, [wPlayerBattleStatus2]
	bit HAS_SUBSTITUTE_UP, a
	jr nz, .blocked
	ld a, [wBattleMonStatus]
	and a
	jr nz, .blocked
	ld a, [wEnemyMoveType]
	cp ELECTRIC
	jr nz, .bridge
	ld a, [wBattleMonType1]
	cp GROUND
	jr z, .blocked
	ld a, [wBattleMonType2]
	cp GROUND
	jr z, .blocked
.bridge
	ld e, BRIDGE_STATUS_CHECK_PARALYSIS
	jp AIBridgePlayerTargetBlocksStatus
.blocked
	scf
	ret
; --- Multi-hit / Substitute delivery (Checkpoint B R4/R6) ------------------

; Adjusts the one-hit maximum in wAIDamageEstimate to damage delivered to the
; Pokemon after the target's current Substitute and the move's hit-count
; contract. Possible entry points use the maximum count; expected entry points
; use the engine's actual count distribution, expressed in eighths; the
; reliable entry point uses the MINIMUM damage roll and MINIMUM hit count, i.e.
; the damage the move is guaranteed to deliver when it hits.
AIAdjustEnemyDamageForReliableDelivery::
	call AIScaleEstimateToMinimumRoll
	ld a, 4
	jr AIAdjustDamageForDelivery
AIAdjustEnemyDamageForPossibleDelivery::
	xor a
	jr AIAdjustDamageForDelivery
AIAdjustPlayerDamageForPossibleDelivery::
	ld a, 1
	jr AIAdjustDamageForDelivery
AIAdjustEnemyDamageForExpectedDelivery::
	ld a, 2
	jr AIAdjustDamageForDelivery
AIAdjustPlayerDamageForExpectedDelivery::
	ld a, 3

AIAdjustDamageForDelivery:
	ld l, a ; bit 0: player attacks; bit 1: expected rather than possible;
	        ; bit 2: reliable (minimum hit count; possible-path arithmetic)
	bit 0, l
	jr nz, .playerAttacks
	ld a, [wEnemyMoveEffect]
	ld h, a
	ld a, [wPlayerBattleStatus2]
	ld c, $ff
	bit HAS_SUBSTITUTE_UP, a
	jr z, .classify
	ld a, [wPlayerSubstituteHP]
	ld c, a
	jr .classify
.playerAttacks
	ld a, [wPlayerMoveEffect]
	ld h, a
	ld a, [wEnemyBattleStatus2]
	ld c, $ff
	bit HAS_SUBSTITUTE_UP, a
	jr z, .classify
	ld a, [wEnemySubstituteHP]
	ld c, a
.classify
	ld b, 1
	ld a, h
	cp ATTACK_TWICE_EFFECT
	jr z, .fixedTwo
	cp TWINEEDLE_EFFECT
	jr z, .fixedTwo
	cp TWO_TO_FIVE_ATTACKS_EFFECT
	jr z, .variable
	cp EFFECT_1E
	jr z, .variable
	ld h, 0
	jr .countOwnerHits
.fixedTwo
	ld b, 2
	ld h, 1
	jr .countOwnerHits
.variable
	ld b, 5
	ld h, 2
	bit 2, l
	jr z, .notReliableCount
	ld b, 2 ; reliable: 2 hits is the only guaranteed count (3/8 of rolls)
	jr .countOwnerHits
.notReliableCount
	bit 0, l
	jr z, .countOwnerHits
	ld a, [wWitchPrizesEarned + 1]
	and 1 << (PRIZE_MULTISTRIKE - 9)
	jr z, .countOwnerHits
	ld h, 3
.countOwnerHits
	call .remainingOwnerHits
	bit 1, l
	jp z, .possible
; Expected delivery caps EACH hit-count outcome at owner HP, matching the
; execution loop's early-faint termination. c keeps the attacker direction.
	ld a, l
	and 1
	ld c, a
	ld a, h
	cp 2
	jr z, .standardVariable
	cp 3
	jr z, .witchVariable
	ld a, b
	call .cappedOwnerDamage
	jp .storeDE
.standardVariable
	ld hl, 0
	xor a
	call .ownerHitsMinus
	call .addCappedOutcome
	ld a, 1
	call .ownerHitsMinus
	call .addCappedOutcome
	rept 3
		ld a, 2
		call .ownerHitsMinus
		call .addCappedOutcome
	endr
	rept 3
		ld a, 3
		call .ownerHitsMinus
		call .addCappedOutcome
	endr
	jr .storeExpected
.witchVariable
	ld hl, 0
	rept 4
		xor a
		call .ownerHitsMinus
		call .addCappedOutcome
	endr
	rept 4
		ld a, 1
		call .ownerHitsMinus
		call .addCappedOutcome
	endr
.storeExpected
	ld d, h
	ld e, l
	rept 3
		srl d
		rr e
	endr
.storeDE
	ld a, d
	ld [wAIDamageEstimate], a
	ld a, e
	ld [wAIDamageEstimate + 1], a
	ret
.possible
	ld a, b
	call .multiplyEstimateByA
	jp .storeDE
; b starts as the move's maximum hit count. c is $ff for no Substitute or the
; current 8-bit Substitute HP. Returns b = hits that can reach the owner.
; Equality intentionally leaves an active zero-HP shield for the next hit.
.remainingOwnerHits
	ld a, [wAIDamageEstimate]
	ld d, a
	ld a, [wAIDamageEstimate + 1]
	ld e, a
	or d
	jr nz, .hasDamage
	ld b, 0
	ret
.hasDamage
	ld a, c
	inc a
	ret z
.substituteHit
	ld a, d
	and a
	jr nz, .breaksSubstitute
	ld a, c
	sub e
	ld c, a
	dec b
	ret z
	jr nc, .substituteHit
	ret
.breaksSubstitute
	dec b
	ret

; Returns a = max(b - a, 0). b is the max-count owner hits after Substitute.
.ownerHitsMinus
	ld d, a
	ld a, b
	sub d
	ret nc
	xor a
	ret

.addCappedOutcome
	call .cappedOwnerDamage
	add hl, de
	ret

; Returns de = min(a * one-hit estimate, current owner HP). Preserves bc/hl.
.cappedOwnerDamage
	push bc
	push hl
	ld b, a
	ld a, c
	and a
	ld hl, wBattleMonHP
	jr z, .gotOwnerHP
	ld hl, wEnemyMonHP
.gotOwnerHP
	ld a, [hli]
	ld d, a
	ld e, [hl]
	push de
	ld a, b
	call .multiplyEstimateByA
	pop bc
	ld a, e
	sub c
	ld a, d
	sbc b
	jr c, .belowOwnerHP
	ld d, b
	ld e, c
.belowOwnerHP
	pop hl
	pop bc
	ret

; Returns de = a * one-hit estimate. The supported maximum is 5 * 999.
.multiplyEstimateByA
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
	ldh a, [hProduct + 2]
	ld d, a
	ldh a, [hProduct + 3]
	ld e, a
	ret

; Caps a ranking estimate after crit expectation so early faint still bounds it.
AICapEnemyDamageAtOwnerHP::
	xor a
	ld c, a
	ld a, 1
	call AIAdjustDamageForDelivery.cappedOwnerDamage
	jp AIAdjustDamageForDelivery.storeDE

; Scales the enemy's one-hit maximum in wAIDamageEstimate down to its MINIMUM
; roll: floor(estimate * 217 / 255), exactly RandomizeDamage's smallest
; multiplier (it rejects rolls below 85 percent + 1). Damage 0/1 is left alone,
; as RandomizeDamage skips those. Exact fixed damage (Seismic Toss, Night Shade,
; SonicBoom, Dragon Rage, Super Fang) has no roll; Psywave's minimum is 1.
; Clobbers af, b.
AIScaleEstimateToMinimumRoll:
	ld a, [wEnemyMoveEffect]
	cp SUPER_FANG_EFFECT
	ret z
	cp SPECIAL_DAMAGE_EFFECT
	jr nz, .rolled
	ld a, [wEnemyMoveNum]
	cp PSYWAVE
	ret nz
	xor a
	ld [wAIDamageEstimate], a
	inc a
	ld [wAIDamageEstimate + 1], a
	ret
.rolled
	ld a, [wAIDamageEstimate]
	and a
	jr nz, .scale
	ld a, [wAIDamageEstimate + 1]
	cp 2
	ret c
.scale
	xor a
	ldh [hMultiplicand], a
	ld a, [wAIDamageEstimate]
	ldh [hMultiplicand + 1], a
	ld a, [wAIDamageEstimate + 1]
	ldh [hMultiplicand + 2], a
	ld a, 85 percent + 1
	ldh [hMultiplier], a
	call Multiply
	ld a, 255
	ldh [hDivisor], a
	ld b, 4
	call Divide
	ldh a, [hQuotient + 2]
	ld [wAIDamageEstimate], a
	ldh a, [hQuotient + 3]
	ld [wAIDamageEstimate + 1], a
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
; This value is for move ranking and damage tiers only. It is not an ordinary-hit
; bound or an exact critical-hit bound, so KO predicates must inspect the raw
; estimate before calling this routine.
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
	ld a, [wEnemyMoveEffect]
	cp SPECIAL_DAMAGE_EFFECT
	ret z ; fixed damage bypasses CriticalHitTest in real execution
	cp SUPER_FANG_EFFECT
	ret z
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
; Deliberately uses AIGetTypeEffectiveness - the same enemy-attacks-player check
; AI_TYPES already scores with - rather than PreviewTypeMatchup (player
; attacks). The point is to answer "does the scoring layer think I have a good move here", and using
; a DIFFERENT notion of effectiveness than the layer that actually picks the
; move would let the switch decision and the move decision disagree about the
; same board. Neutral is EFFECTIVE (10) since Shin Red's dual-type fix (it was
; vanilla's $10 before); every caller compares against it, so this does too.
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
	cp EFFECTIVE
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
