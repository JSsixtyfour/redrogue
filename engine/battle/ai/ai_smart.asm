; AI_SMART layer (AI_OVERHAUL_PLAN.md Phase 2b): per-move-effect heuristics
; ported from pokecrystal's AI_Smart (the Gen-1-portable subset) and Yume,
; plus two cross-cutting rules (anti-spam, repeated-move fatigue) that are not
; tied to any single effect. Dispatch shape copied from AILayerRedundant
; (ai_redundant.asm) - see that file's header for the register discipline
; this depends on; re-read it before touching this dispatcher.
;
; INCLUDEd into "Battle Engine 7" (bank $0E), same bank as trainer_ai.asm and
; every AILayer* routine - mandatory, not stylistic. See
; ai_score_helpers.asm's header and ROM_BIBLE.md's 2026-08-25 entry.
;
; HANDLER CONTRACT (both directions, unlike ai_redundant's discourage-only
; contract): a handler returns a = 0 (no change) or a nonzero magnitude in a,
; with carry SET meaning encourage and carry CLEAR meaning discourage (carry
; is only meaningful when a != 0). A handler may clobber any register except
; a and the flags on its way out.
;
; WHY CARRY, NOT A SEPARATE FLAG BYTE: `POP rr` for rr in {BC,DE,HL} never
; touches any flag on this CPU - only `POP AF` does. So the dispatcher can
; restore its three saved registers with three plain pops immediately after
; the handler returns, and the handler's carry (and a) survive those pops
; completely untouched. The one thing that WILL clobber carry is any
; subsequent `and`/`or`/`cp` used to test whether a == 0 - so the dispatcher
; branches on carry FIRST (via `jr c`/fallthrough), and only tests a for zero
; once carry has already been consumed. Getting this ordering backwards was
; the first draft of this file's bug: `and a` before reading carry silently
; discards which direction the handler wanted.

AILayerSmart:
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
	call ReadMove ; sets wEnemyMoveEffect/Power/Type/Accuracy/wEnemyMoveNum
	ld a, [wEnemyMoveEffect]
	ld c, a
	ld hl, AISmartEffectTable
	ld de, 3 ; effect id (1) + handler pointer (2)
	call IsInArray
	jr nc, .notFound
	inc hl
	ld a, [hli]
	ld h, [hl]
	ld l, a ; hl = handler address
	call .callHandler ; a = 0 or magnitude; carry = direction (see header)
	pop bc ; restore loopCounter - POP rr never touches a or flags
	pop de ; restore movelistPtr - same
	pop hl ; restore scorePtr - same; also exactly what AIEncourage/
	       ; AIDiscourage want as their pointer argument
	jr c, .encourageBranch
	and a  ; safe to clobber carry now - already branched on it
	jr z, .crossCutting
	call AIDiscourage
	jr .crossCutting
.encourageBranch
	and a
	jr z, .crossCutting ; defensive: a handler that sets carry with a=0 is a
	                     ; no-op, not a crash
	call AIEncourage
.crossCutting
	call AISmartCrossCutting ; hl = scorePtr, untouched since the pops above
	jr .nextMove
.notFound
	pop bc
	pop de
	pop hl
	call AISmartCrossCutting
	jr .nextMove
.callHandler
	jp hl

; --- Cross-cutting rules, applied to every move regardless of whether it had
; a per-effect table entry. INPUT: hl = this move's score-array pointer.
; Every read here uses direct addressing (never `ld hl, wSomething`), so hl is
; never clobbered by THIS routine's own logic and needs no save/restore for
; most of it - it is exactly what the caller needs back afterward. The one
; exception is the status-accuracy block below, which calls AIGetMoveHitChance
; (a routine that DOES clobber hl) and explicitly saves/restores around it.
; Clobbers af, bc, de.
AISmartCrossCutting::
; Anti-spam: two consecutive zero-power turns is how a Gen 1 AI stalls out.
; Exempt HEAL_EFFECT and SUBSTITUTE_EFFECT - repeating those is often correct.
	ld a, [wEnemyMovePower]
	and a
	jr nz, .statusAccuracy ; this move has power; anti-spam does not apply
	ld a, [wAILastMoveNum]
	and a
	jr z, .statusAccuracy ; no move tracked yet (turn 1, or the first decision
	                     ; after a send-out) - NO_MOVE is 0 and no real move is
	                     ; ever numbered 0, so this is not a genuine back-to-back
	                     ; zero-power turn, just an unset tracker. Testing
	                     ; wAILastMoveNum rather than wAILastMovePower is the
	                     ; point: a power of 0 is ambiguous between "last move
	                     ; really was 0 power" and "there was no last move", and
	                     ; conflating them would discourage a turn-1 status move
	                     ; (e.g. a turn-1 sleep, which the plan's priority
	                     ; cascade ranks above ordinary damage) for no reason.
	ld a, [wAILastMovePower]
	and a
	jr nz, .statusAccuracy ; last move had power; no back-to-back zero yet
	ld a, [wEnemyMoveEffect]
	cp HEAL_EFFECT
	jr z, .statusAccuracy
	cp SUBSTITUTE_EFFECT
	jr z, .statusAccuracy
	ld a, AI_STRONG
	call AIDiscourage
.statusAccuracy
; Status-move accuracy: AI_DAMAGE only scales DAMAGING moves by hit chance (via
; AIScaleDamageByAccuracy), so without this, Sing/Hypnosis/Lovely Kiss
; (55/60/75% respectively) all scored identically - accuracy did nothing for
; the whole class of pure-status moves. Only fires on 0-power moves; a
; damaging move's accuracy is already handled in AI_DAMAGE, and applying it
; again here would double-count.
	ld a, [wEnemyMovePower]
	and a
	jr nz, .fatigueCheck
; AIGetMoveHitChance clobbers bc/de/hl. bc is fine to lose - the dispatcher's
; own loop termination relies on the movelist pointer in DE hitting a zero
; byte, not on the loop counter surviving in B (see AILayerSmart's header:
; every handler is already allowed to clobber bc). DE and HL are NOT safe to
; lose: DE is that same movelist pointer, and HL is the caller's score
; pointer. Losing DE here was a real, shipped bug - it let the dispatcher walk
; past the real move list into unrelated WRAM, calling ReadMove and this
; routine repeatedly on garbage "moves" until the loop counter happened to hit
; zero by chance, corrupting scores for slots that were never real moves.
; Found by a scenario whose result touched wBuffer+3 despite only two moves
; existing in the set.
	push de
	push hl
	call AIGetMoveHitChance
	pop hl
	pop de
	cp 75 percent
	jr nc, .fatigueCheck ; reliable enough - no penalty
	cp 60 percent
	jr nc, .accuracyNudge
	ld a, AI_STRONG
	call AIDiscourage
	jr .fatigueCheck
.accuracyNudge
	ld a, AI_NUDGE
	call AIDiscourage
.fatigueCheck
; Repeated-move fatigue: only a genuinely long streak is discouraged, since
; ordinary repetition (spamming a strong STAB move) is usually correct.
	ld a, [wEnemyMoveNum]
	ld b, a
	ld a, [wAILastMoveNum]
	cp b
	ret nz ; this move is not the one that has been repeating
	ld a, [wAISameMoveCount]
	cp 4
	ret c ; streak below the threshold: no penalty yet
	cp 6
	jr nc, .veryStrongFatigue
	cp 5
	jr nc, .strongFatigue
	ld a, AI_NUDGE
	jr .applyFatigue
.strongFatigue
	ld a, AI_STRONG
	jr .applyFatigue
.veryStrongFatigue
	ld a, AI_VERY_STRONG
.applyFatigue
	call AIDiscourage
	ret

; Effect -> handler table, IsInArray's dbw shape, same convention as
; ai_redundant.asm's AIRedundantEffectTable.
AISmartEffectTable:
	dbw SLEEP_EFFECT, AISmart_Sleep
	dbw DREAM_EATER_EFFECT, AISmart_DreamEater
	dbw EXPLODE_EFFECT, AISmart_Explode
	dbw HEAL_EFFECT, AISmart_Heal
	dbw SUBSTITUTE_EFFECT, AISmart_Substitute
	dbw POISON_EFFECT, AISmart_Poison
	dbw HYPER_BEAM_EFFECT, AISmart_HyperBeam
	dbw OHKO_EFFECT, AISmart_OHKO
	dbw SUPER_FANG_EFFECT, AISmart_SuperFang
	dbw DRAIN_HP_EFFECT, AISmart_DrainHP
	dbw PARALYZE_EFFECT, AISmart_Paralyze
	dbw TRAPPING_EFFECT, AISmart_Trapping
	dbw LIGHT_SCREEN_EFFECT, AISmart_Screen
	dbw REFLECT_EFFECT, AISmart_Screen
	dbw HAZE_EFFECT, AISmart_Haze
	dbw CONFUSION_EFFECT, AISmart_Confusion
; F14, 2026-09-02: two-turn moves and evasion, scored blind before this.
	dbw CHARGE_EFFECT, AISmart_Charge
	dbw FLY_EFFECT, AISmart_InvulnerableCharge
	dbw EVASION_UP1_EFFECT, AISmart_Evasion
	dbw EVASION_UP2_EFFECT, AISmart_Evasion
; Phase 3 Step 3: secondary-effect bonuses. AI_REDUNDANT used to discourage
; these moves when the rider specifically could not land (already statused,
; type immunity); that logic moved here as the mirror bonus - see
; AIRedundant_PoisonSide / AIRedundant_BurnFreezeParaSide in ai_redundant.asm
; for the removed half of this and why keeping both double-counted.
	dbw PARALYZE_SIDE_EFFECT1, AISmart_BurnFreezeParaSide
	dbw PARALYZE_SIDE_EFFECT2, AISmart_BurnFreezeParaSide
	dbw BURN_SIDE_EFFECT1, AISmart_BurnFreezeParaSide
	dbw BURN_SIDE_EFFECT2, AISmart_BurnFreezeParaSide
	dbw FREEZE_SIDE_EFFECT1, AISmart_BurnFreezeParaSide
	dbw FREEZE_SIDE_EFFECT2, AISmart_BurnFreezeParaSide
	dbw POISON_SIDE_EFFECT1, AISmart_PoisonSide
	dbw POISON_SIDE_EFFECT2, AISmart_PoisonSide
	dbw CONFUSION_SIDE_EFFECT, AISmart_ConfusionSide
	dbw FLINCH_SIDE_EFFECT1, AISmart_FlinchSide
	dbw FLINCH_SIDE_EFFECT2, AISmart_FlinchSide
	dbw RECOIL_EFFECT, AISmart_RecoilEffect
	dbw ATTACK_DOWN_SIDE_EFFECT, AISmart_StatDownSide
	dbw DEFENSE_DOWN_SIDE_EFFECT, AISmart_StatDownSide
	dbw SPEED_DOWN_SIDE_EFFECT, AISmart_StatDownSide
	dbw SPECIAL_DOWN_SIDE_EFFECT, AISmart_StatDownSide
; SPECIAL_DAMAGE_EFFECT deliberately has NO handler as of Phase 3 Step 3. It
; used to be encouraged whenever the target was above half HP, which was
; backwards reasoning - fixed damage is a constant, so a healthier target makes
; it relatively WORSE, not better. Now that AIEstimateDamage returns these moves'
; real values, AI_DAMAGE ranks them correctly on damage alone and any extra
; nudge here would just double-count.
	db -1

; --- Handlers ---------------------------------------------------------
; Each returns a = 0 (no change), or a = magnitude with carry set (encourage)
; / carry clear (discourage). May clobber anything except a and flags on the
; way out.

; If the enemy also knows a Dream Eater move, landing sleep sets up a big
; follow-up - worth chasing harder. Source: pokecrystal AI_Smart_Sleep.
;
; MUST restore wEnemyMoveNum/Effect/Power/Type/Accuracy before returning: it
; scans OTHER moves in the moveset via ReadMove, which overwrites those globals
; for whatever it last scanned. AISmartCrossCutting reads wEnemyMovePower and
; wEnemyMoveEffect right after this handler returns, so leaving them pointed
; at the wrong move would make anti-spam/fatigue reason about a move that
; isn't the one actually being scored.
AISmart_Sleep:
	ld a, [wEnemyMoveNum] ; the move actually being scored (Sleep)
	push af
	ld hl, wEnemyMonMoves
	ld b, NUM_MOVES
	xor a
	ld d, a ; d = 0/1 found flag
.scan
	ld a, [hli]
	and a
	jr z, .scanDone
	push hl
	push bc
	push de
	call ReadMove
	pop de
	pop bc
	pop hl
	ld a, [wEnemyMoveEffect]
	cp DREAM_EATER_EFFECT
	jr nz, .notFoundThisSlot
	ld d, 1
.notFoundThisSlot
	dec b
	jr nz, .scan
.scanDone
	pop af
	call ReadMove ; restore wEnemyMove* to the Sleep move being scored
	ld a, d
	and a
	jr z, .noDreamEater
	ld a, AI_STRONG
	scf
	ret
.noDreamEater
	xor a
	ret

; Dream Eater only does anything if the target is already asleep - AI_Redundant
; already fully eliminates the awake case, so this only needs to encourage the
; already-legal case. Source: pokecrystal AI_Smart_DreamEater.
AISmart_DreamEater:
	call AIGetTargetStatus
	and SLP_MASK
	ret z ; not asleep - AI_Redundant already made this move's score 79
	ld a, AI_VERY_STRONG
	scf
	ret

; Explosion/Self-Destruct is a trade: bad at full HP (loses the user for
; nothing extra), good when nearly dead anyway (the trade was coming regardless).
; Source: pokecrystal AI_Smart_Selfdestruct, HP bands only (no party-count check
; here - Phase 4's switching engine is a better home for "is this our last mon").
AISmart_Explode:
	call AIEnemyHPAtMax
	jr c, .discourage
	call AIEnemyHPBelowQuarter
	jr c, .encourage
	xor a
	ret
.encourage
	ld a, AI_STRONG
	scf
	ret
.discourage
	ld a, AI_VERY_STRONG
	and a
	ret

; Recover/Softboiled: good when low, wasteful when healthy. AI_Redundant
; already eliminates the at-max-HP case. Source: pokecrystal AI_Smart_Heal.
AISmart_Heal:
	call AIEnemyHPBelowQuarter
	jr c, .encourage
	call AIEnemyHPBelowHalf
	jr c, .noChange ; between quarter and half: no change either way. NOTE:
	                ; the predicate leaves a undefined on this path (its
	                ; internal subtraction, not a clean 0) - always `jr`, not
	                ; `ret`, off a predicate/bit-test result; land on an
	                ; explicit `xor a` before returning. Same rule applies to
	                ; every handler below.
	ld a, AI_STRONG
	and a
	ret
.encourage
	ld a, AI_STRONG
	scf
	ret
.noChange
	xor a
	ret

; Substitute below half HP is a bad trade even though it is still legal
; (AI_Redundant only blocks the illegal <=25% case). Source: pokecrystal.
AISmart_Substitute:
	call AIEnemyHPBelowHalf
	jr nc, .noChange
	ld a, AI_HEAVY
	and a
	ret
.noChange
	xor a
	ret

; Hyper Beam's recharge cost is worth it when healthy, riskier when low (the
; enemy may not survive to use the follow-up turn it owes). Source: pokecrystal
; AI_Smart_HyperBeam.
AISmart_HyperBeam:
	call AIEnemyHPBelowQuarter
	jr c, .discourage
	call AIEnemyHPBelowHalf
	jr c, .noChange ; between quarter and half: no change
	ld a, AI_NUDGE
	scf
	ret
.discourage
	ld a, AI_NUDGE
	and a
	ret
.noChange
	xor a
	ret

; OHKO moves need the user's level to exceed the target's, on top of the speed
; requirement AI_Redundant already checks. Source: pokecrystal AI_Smart_Ohko.
AISmart_OHKO:
	ld a, [wBattleMonLevel]
	ld b, a
	ld a, [wEnemyMonLevel]
	cp b
	jr nc, .noChange ; enemy level >= player level -> OHKO retains its normal
	                 ; chance; AI_Redundant's speed check is the main gate,
	                 ; this only adds the level check on top of it
	ld a, AI_HEAVY
	and a
	ret
.noChange
	xor a
	ret

; Super Fang sets damage to half the target's CURRENT HP (.superFangEffect in
; core.asm), so its absolute damage is LARGEST against a healthy target and it
; can never finish one off.
;
; Phase 3 Step 3 inverted this handler. It previously encouraged Super Fang when
; the target was below a quarter HP, which is exactly backwards - that is where
; the move is weakest. AI_DAMAGE now ranks it on its real simulated damage, so
; all this handler still contributes is the one thing a damage figure cannot
; express: it cannot KO, so once the target is low an ordinary attack both
; out-damages it and can actually end the fight.
AISmart_SuperFang:
	call AIPlayerHPBelowHalf
	jr nc, .noChange
	ld a, AI_STRONG
	and a ; carry CLEAR = discourage (was scf, i.e. encourage)
	ret
.noChange
	xor a
	ret

; Drain moves are more valuable as sustain when the enemy is not already at
; full HP. Source: PureRGB EncourageDrainingMoveIfLowHealth.
AISmart_DrainHP:
	call AIEnemyHPAtMax
	jr c, .noChange
	ld a, AI_NUDGE
	scf
	ret
.noChange
	xor a
	ret

; Thunder Wave on a target that is about to faint anyway wastes a turn that
; could have been a hit - only relevant once AI_Redundant's Ground/already-
; statused eliminations have passed. Source: pokecrystal AI_Smart_Paralyze.
; PARAFUSION, the mirror direction (follow-up F19, 2026-09-02): paralysing an
; already CONFUSED target is worth the same 62.5% lockdown as the reverse
; ordering - see AISmart_Confusion's header for the arithmetic and the
; engine-truth check. This handler only ever sees a legal Thunder Wave:
; AIRedundant_Paralyze has already saturated the move if the target carries ANY
; major status (including paralysis itself) or is Ground-type, and confusion is
; not a major status, so a confused-but-unstatused target arrives here intact.
AISmart_Paralyze:
	ld a, [wPlayerBattleStatus1]
	bit CONFUSED, a
	jr nz, .parafusion
	call AIPlayerHPBelowQuarter
	jr nc, .noChange
	ld a, AI_NUDGE
	and a
	ret
.parafusion
	ld a, AI_STRONG
	scf
	ret
.noChange
	xor a
	ret

; F14, 2026-09-02: Toxic and Poison Powder share POISON_EFFECT and were
; scored identically before this - nothing distinguished Toxic's ramping
; counter (wPlayerToxicCounter, core.asm) from a flat poison. Toxic is worth
; materially more against a target that will be around for many turns (the
; ramp has room to matter) and worth little against one about to die anyway
; (the ramp barely gets started before the fight ends some other way).
;
; Skips outright if the target already has a status: AIRedundant_Poison has
; already saturated this move to AI_REDUNDANT_HEAVY in that case (same-turn
; scoring order: AI_REDUNDANT runs before AI_SMART), and encouraging here
; would fight that saturation instead of agreeing with it.
AISmart_Poison:
	ld a, [wBattleMonStatus]
	and a
	jr nz, .noChange
	call AIPlayerHPBelowQuarter
	jr c, .noChange ; dying anyway - let the damage layers finish it instead
	ld a, [wEnemyMoveNum]
	cp TOXIC
	jr nz, .plainPoison
	call AIPlayerHPBelowHalf
	jr c, .weakerToxic
	ld a, AI_STRONG ; healthy target: the ramp has room to run
	jr .encourage
.weakerToxic
	ld a, AI_NUDGE ; already hurting: still worth it, less ramp left to use
	jr .encourage
.plainPoison
	ld a, AI_NUDGE
.encourage
	scf
	ret
.noChange
	xor a
	ret

; Re-using a trapping move on a target that is already trapped cannot extend
; the lock in this engine - it just wastes the turn. Source: pokecrystal
; AI_Smart_TrapTarget (simplified: no HP/status branch, just the redundancy
; check that AI_Redundant does not currently cover for TRAPPING_EFFECT).
AISmart_Trapping:
	ld a, [wPlayerBattleStatus1]
	bit USING_TRAPPING_MOVE, a
	jr z, .checkChipDamage ; bit tests a bit WITHOUT clearing a's value, but
	                       ; that value is dead here either way - the branch
	                       ; below reloads what it needs
	ld a, AI_NUDGE
	and a ; discourage: already trapped, re-using cannot extend the lock
	ret
.checkChipDamage
; F14, 2026-09-02: user's own correction mid-design - encourage TRAPPING a
; target once it already has damage-over-time running (poisoned/badly
; poisoned/burned/Leech Seeded), never the reverse. Poisoning a target we are
; ALREADY trapping cannot happen anyway: core.asm's move-selection gate
; (~:3473-3475) returns the enemy out of the whole decision while
; USING_TRAPPING_MOVE is set, so no heuristic ever runs mid-lock. What CAN
; happen, and previously had no positive signal at all, is choosing to trap a
; target that is already bleeding HP each turn: locking them in place turns
; that chip into a guaranteed, uninterruptible drain instead of a race the
; player could outrun by switching. Mirrored into AIFit_WrapLock's and
; AIFit_AgilityWrap's own fitness via the same AIPlayerHasChipDamage
; predicate, so the plan layer agrees with this layer about the same board.
	call AIPlayerHasChipDamage
	jr nc, .noChange
	ld a, AI_STRONG
	scf
	ret
.noChange
	xor a
	ret

; F14, 2026-09-02: two-turn moves are not one family. ChargeEffect
; (effects.asm) grants INVULNERABLE only to Dig (disambiguated here by move
; id, since it shares CHARGE_EFFECT with the exposed family below) - it dodges
; the free turn it hands the player. Razor Wind/Solarbeam/Skull Bash/Sky
; Attack charge fully exposed: a turn AND a hit given away.
; AIEstimateDamage currently credits full damage for all of these as if they
; land THIS turn (Phase 3's simulator has no charge-move awareness), which
; over-rates a move that gives the player a free turn to switch or set up.
; This handler is the scoring-side correction; the simulator itself is
; unchanged. User's own framing: small penalty normally (bigger for the
; exposed family - losing a turn AND eating a hit is worse than losing a turn
; while invulnerable), no benefit from stalling for the exposed family (it
; still eats a hit regardless of what the player's status costs them).
AISmart_Charge:
	ld a, [wEnemyMoveNum]
	cp DIG
	jr z, AISmart_InvulnerableCharge ; shared tail with Fly, below
	call AIPlayerIsStalled
	jr c, .noChange ; stalling doesn't help an exposed charge - still eats a hit
	ld a, AI_STRONG
	and a
	ret
.noChange
	xor a
	ret

; Shared by Dig (via AISmart_Charge above) and Fly (its own effect id,
; FLY_EFFECT, not CHARGE_EFFECT - own table entry below): both grant
; INVULNERABLE, so losing the turn is offset by dodging a hit - a smaller
; penalty than the exposed charge family, and worth boosting back when
; stalling (AIPlayerIsStalled) costs nothing extra.
AISmart_InvulnerableCharge:
	call AIPlayerIsStalled
	jr c, .stallBoost
	ld a, AI_NUDGE
	and a
	ret
.stallBoost
	ld a, AI_NUDGE
	scf
	ret

; Double Team / Minimize (EVASION_UP1/2_EFFECT): AI_SETUP already gives these
; a blanket AI_STRONG encouragement on turn 1 of any send-out, with no
; evaluation of whether the boost is worth the turn it costs
; (AIMoveChoiceModification2, trainer_ai.asm - the same layer F9 already had
; to gate for ATTACK_UP*/DEFENSE_DOWN*, though evasion was left alone there
; since it has no physical/special-usefulness question to ask). F14,
; 2026-09-02: evasion only pays off if the fight lasts long enough to
; matter, which is exactly what AIPlayerIsStalled answers. Mildly discourage
; outside a stall context - PARTIALLY offsetting AI_SETUP's blanket
; encouragement rather than fighting it outright, since a mon with nothing
; better to do on turn 1 may still want some setup - and strongly encourage
; when stalling, where the lost turn costs nothing.
AISmart_Evasion:
	call AIPlayerIsStalled
	jr c, .stallBoost
	ld a, AI_NUDGE
	and a
	ret
.stallBoost
	ld a, AI_STRONG
	scf
	ret

; Light Screen / Reflect are a turn-1 investment; using one while already
; damaged wastes the setup turn on a body that may not live to benefit.
; Source: pokecrystal.
AISmart_Screen:
	call AIEnemyHPAtMax
	jr c, .noChange
	ld a, AI_NUDGE
	and a
	ret
.noChange
	xor a
	ret

; Haze is wasted if nothing on either side has actually changed: no player
; stat is boosted, and no enemy stat is lowered. AI_Redundant does not cover
; this (it only fires on effect-specific "already applied" states, and Haze
; has no such single flag - it clears everything at once). Source: Yume
; IsHazeWasted, HP-mod-only subset (this fork's Haze does not touch status,
; see move_effects/haze.asm, so no status check is needed here).
AISmart_Haze:
	ld hl, wPlayerMonAttackMod
	ld b, 6 ; the 6 real stat mods (Attack/Defense/Speed/Special/Accuracy/
	        ; Evasion); NUM_STAT_MODS is 8, but the last 2 are const_skip
	        ; padding ResetStatMods also sweeps that carries no game state
.checkPlayerBoosted
	ld a, [hli]
	cp BASE_STAT_LEVEL
	jr nc, .found ; player stat at/above neutral -> Haze would undo a boost
	dec b
	jr nz, .checkPlayerBoosted
	ld hl, wEnemyMonAttackMod
	ld b, 6
.checkEnemyLowered
	ld a, [hli]
	cp BASE_STAT_LEVEL
	jr c, .found ; enemy stat below neutral -> Haze would restore it
	dec b
	jr nz, .checkEnemyLowered
	ld a, AI_STRONG
	and a
	ret
.found
	xor a
	ret

; Confuse Ray becomes a worse choice than a direct hit as the target gets
; low, since a confused-but-alive target might get to act (self-hit chance is
; not a guaranteed lockout) where a KO ends the exchange outright. Source:
; pokecrystal AI_Smart_Confuse.
; PARAFUSION, follow-up F19 (2026-09-02): confusing an ALREADY PARALYSED target
; is one of the strongest lockdowns in Gen 1 and had no representation here.
; Paralysis is a 25% full-stop, confusion a 50% self-hit on the turns that get
; through, so together the target does nothing 0.25 + 0.75 * 0.50 = 62.5% of
; the time. Verified legal in this engine before writing: paralysis lives in
; wBattleMonStatus (major status) and confusion in wPlayerBattleStatus1
; (volatile), so they are independent, and AIRedundant_ConfusionEffect only
; blocks on the CONFUSED bit - never on a major status - so Confuse Ray into a
; paralysed target reaches this handler normally.
;
; Checked BEFORE the low-HP discourage below on purpose: a paralysed target is
; worth locking down even at moderate HP, and the case where it should NOT be
; (target nearly dead, just kill it) is already handled better elsewhere -
; AI_DAMAGE applies AI_KILL (5) to a lethal move, which outweighs the AI_STRONG
; (2) applied here.
AISmart_Confusion:
	ld a, [wBattleMonStatus]
	and 1 << PAR
	jr nz, .parafusion
	call AIPlayerHPBelowHalf
	jr nc, .noChange
	ld a, AI_NUDGE
	and a
	ret
.parafusion
	ld a, AI_STRONG
	scf
	ret
.noChange
	xor a
	ret


; --- Secondary-effect bonuses (Phase 3 Step 3) -----------------------------
; Give credit for a move's chance to apply a status/stat-drop/flinch on top of
; its damage, which nothing did before this. Verified proc rates (source:
; engine/battle/effects.asm) and the weight table are recorded in
; PHASE_3_STEP3_SPEC.md; magnitudes follow the plan's status thesis (freeze >
; KO, paralysis ~ half a KO), scaled down for these lower, move-specific rates.
;
; Every handler below is gated on "could the rider actually land" and returns
; a plain xor a/ret when it cannot - this is the mirror image of the discourage
; that AIRedundant_PoisonSide / AIRedundant_BurnFreezeParaSide used to apply in
; that situation, moved here so the two are not double-counting the same fact
; from opposite directions (see PHASE_3_STEP3_SPEC.md's magnitude-imbalance
; finding, and this file's header for the "why carry, why xor a" discipline
; every one of these follows).

; Carry SET if a paralyze/burn/freeze rider CANNOT land on the current target:
; a Substitute is up, the target already has a status, or the move's own type
; matches one of the target's types (Gen 1's same-type-cannot-be-statused rule,
; FreezeBurnParalyzeEffect in effects.asm).
; Clobbers af, b.
AISmartParaSideBlocked:
	call AIRedundantTargetHasSubstitute
	jr nz, .blocked
	call AIGetTargetStatus
	and a
	jr nz, .blocked
	ld a, [wEnemyMoveType]
	ld b, a
	call AIGetTargetType1
	cp b
	jr z, .blocked
	call AIGetTargetType2
	cp b
	jr z, .blocked
	and a ; clear carry
	ret
.blocked
	scf
	ret

; Body Slam / Lick (PARALYZE_SIDE_EFFECT2, 30%), Thunderbolt / Thunder
; (PARALYZE_SIDE_EFFECT1, 10%), Ice Beam / Blizzard / Ice Punch
; (FREEZE_SIDE_EFFECT1, 10%), Fire Blast (BURN_SIDE_EFFECT2, 30%), Fire Punch
; (BURN_SIDE_EFFECT1, 10%). FREEZE_SIDE_EFFECT2 is unused by any move in this
; game (English Blizzard uses the _1 rate) but is included for completeness -
; the table entry costs two bytes and nothing currently reaches it.
AISmart_BurnFreezeParaSide:
	call AISmartParaSideBlocked
	jr c, .noChange
	ld a, [wEnemyMoveEffect]
	cp FREEZE_SIDE_EFFECT2
	jr z, .veryStrong
	cp FREEZE_SIDE_EFFECT1
	jr z, .strong
	cp PARALYZE_SIDE_EFFECT2
	jr z, .strong
	ld a, AI_NUDGE
	scf
	ret
.strong
	ld a, AI_STRONG
	scf
	ret
.veryStrong
	ld a, AI_VERY_STRONG
	scf
	ret
.noChange
	xor a
	ret

; Carry SET if a poison rider CANNOT land: a Substitute is up, the target
; already has a status, or the target is Poison-type (PoisonEffect's own
; inline immunity check in effects.asm).
; Clobbers af.
AISmartPoisonSideBlocked:
	call AIRedundantTargetHasSubstitute
	jr nz, .blocked
	call AIGetTargetStatus
	and a
	jr nz, .blocked
	call AIGetTargetType1
	cp POISON
	jr z, .blocked
	call AIGetTargetType2
	cp POISON
	jr z, .blocked
	and a
	ret
.blocked
	scf
	ret

; Smog / Sludge (POISON_SIDE_EFFECT2, 40%), Poison Sting (POISON_SIDE_EFFECT1,
; 20%).
AISmart_PoisonSide:
	call AISmartPoisonSideBlocked
	jr c, .noChange
	ld a, [wEnemyMoveEffect]
	cp POISON_SIDE_EFFECT2
	jr z, .strong
	ld a, AI_NUDGE
	scf
	ret
.strong
	ld a, AI_NUDGE ; 20/40% both land at the same low tier here - see the value
	scf            ; table in PHASE_3_STEP3_SPEC.md, which puts both POISON_SIDE
	ret            ; rates at AI_NUDGE, unlike the paralyze/burn/freeze family
.noChange
	xor a
	ret

; Psybeam / Confusion (CONFUSION_SIDE_EFFECT, 10%). Gated on the CONFUSED bit
; in wPlayerBattleStatus1, NOT wBattleMonStatus - confusion is not one of the
; mutually-exclusive non-volatile statuses, so it needs its own flag and can
; stack with poison/burn/etc, but not with itself.
AISmart_ConfusionSide:
	call AIRedundantTargetHasSubstitute
	jr nz, .noChange
	ld a, [wPlayerBattleStatus1]
	bit CONFUSED, a
	jr nz, .noChange
	ld a, AI_NUDGE
	scf
	ret
.noChange
	xor a
	ret

; Flinch only matters if the enemy acts BEFORE the target's move resolves -
; landing it after the target has already moved does nothing. Rated on top of
; AIEnemyActsFirstWith rather than AIEnemyIsFaster for the same reason
; ai_threat.asm uses it: Quick Attack and Counter override raw Speed.
; PARA-FLINCH, follow-up F20 (2026-09-02). Two changes, both additive to the
; existing acts-first gate:
;
; 1. PROC RATE now sets the base magnitude. FlinchSideEffect (effects.asm:920)
;    rolls 10% for FLINCH_SIDE_EFFECT1 (Bite, Bone Club, Hyper Fang) and 30%
;    otherwise (Stomp, Rolling Kick, Headbutt, Low Kick), and this handler used
;    to give both a flat AI_NUDGE - so Bite scored identically to Headbutt at
;    three times the rate. AISmart_BurnFreezeParaSide directly above already
;    scales by real proc rate; this brings flinch in line with it.
;
; 2. PARALYSED TARGETS earn one extra point, because the two effects compound
;    into a near-lockout: 0.25 (full para) + 0.75 * 0.30 (flinch) = 47.5% of
;    turns the target does nothing at all. This is the Snorlax line - Body Slam
;    to fish for paralysis, then Headbutt - and note the SEQUENCE needs no extra
;    code: Body Slam earns its own rider bonus from AISmart_BurnFreezeParaSide,
;    and once paralysis lands this handler starts preferring the flincher.
;
; The acts-first gate is unchanged and load-bearing: a flinch does nothing at
; all if the target has already moved. It is deliberately a WITHHELD BONUS
; rather than a penalty - the move still deals its damage, and discouraging a
; perfectly good 70-power attack over a dead rider is exactly the mistake Phase
; 3 Step 3 removed from AIRedundant_PoisonSide/AIRedundant_BurnFreezeParaSide.
; Worth knowing: the gate also picks up the speed half of para-flinch for free,
; because AIEnemyIsFaster reads the LIVE wBattleMonSpeed, which
; QuarterSpeedDueToParalysis has already destructively quartered.
AISmart_FlinchSide:
	call AIRedundantTargetHasSubstitute
	jr nz, .noChange
	call AIEnemyActsFirstWith
	jr nc, .noChange
	ld a, [wEnemyMoveEffect]
	cp FLINCH_SIDE_EFFECT1
	ld a, AI_NUDGE ; 10% flinchers. `ld a, n` sets no flags, so the cp above is
	               ; still what the jr below tests
	jr z, .gotBase
	ld a, AI_STRONG ; 30% flinchers
.gotBase
	ld b, a
	ld a, [wBattleMonStatus]
	and 1 << PAR
	ld a, b ; LD does not touch flags, so the and's z result survives this
	jr z, .apply
	inc a ; paralysed target: the two lockouts compound
.apply
	scf
	ret
.noChange
	xor a
	ret

; Growl / Tail Whip / Leer / etc.-style DAMAGING moves with a stat-down rider
; (Rock Slide's Speed drop and similar). Only Substitute-gated - unlike the
; status riders above, a stat drop is not blocked by the target already having
; a non-volatile status, and this engine has no type-immunity rule for it.
AISmart_StatDownSide:
	call AIRedundantTargetHasSubstitute
	jr nz, .noChange
	ld a, AI_NUDGE
	scf
	ret
.noChange
	xor a
	ret

; Double Edge / Take Down / Submission / Struggle cost the user
; damageDealt/4 (Struggle: /2 - RecoilEffect_ in move_effects/recoil.asm skips
; the second shift for it). Invisible to a pure damage ranking, so this needs
; its own handler.
;
; Must recompute the estimate itself: AI_SMART (bit 4) runs BEFORE AI_DAMAGE
; (bit 5) in the tier's layer order, so wAIDamageEstimate has not been filled in
; for the move currently being scored yet - same pattern as AILayerThreat's
; Quick Attack check in ai_threat.asm. Uses the RAW (pre-accuracy) estimate on
; purpose: recoil only happens when the hit actually connects, so scaling it by
; hit chance first would be answering a different question.
AISmart_RecoilEffect:
	farcall AIEstimateDamage ; -> wAIDamageEstimate. Clobbers af/bc/de/hl.
	ld a, [wAIDamageEstimate]
	ld d, a
	ld a, [wAIDamageEstimate + 1]
	ld e, a ; de = raw estimated damage
	srl d
	rr e ; de = damage / 2
	ld a, [wEnemyMoveNum]
	cp STRUGGLE
	jr z, .gotRecoil ; Struggle stops at /2
	srl d
	rr e ; de = damage / 4
.gotRecoil
	ld a, [wEnemyMonHP]
	ld b, a
	ld a, [wEnemyMonHP + 1]
	ld c, a ; bc = the user's own current HP
	ld a, e
	sub c
	ld a, d
	sbc b ; carry set iff recoil(de) < ownHP(bc), i.e. the user survives
	jr c, .recoilSurvivable
; The recoil would KO its own user. That is only a bad trade if the target
; survives too - AI_DAMAGE has already scored the kill on this move if it has
; one, so a mutual KO is left alone rather than fought with a discourage.
	call AIMoveWouldKO
	jr c, .noChange
	ld a, AI_HEAVY
	and a ; carry CLEAR = discourage
	ret
.recoilSurvivable
	ld a, AI_NUDGE
	and a
	ret
.noChange
	xor a
	ret
