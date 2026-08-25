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
; never clobbered and needs no save/restore - it is exactly what the caller
; needs back afterward. Clobbers af, bc.
AISmartCrossCutting::
; Anti-spam: two consecutive zero-power turns is how a Gen 1 AI stalls out.
; Exempt HEAL_EFFECT and SUBSTITUTE_EFFECT - repeating those is often correct.
	ld a, [wEnemyMovePower]
	and a
	jr nz, .fatigueCheck ; this move has power; anti-spam does not apply
	ld a, [wAILastMoveNum]
	and a
	jr z, .fatigueCheck ; no move tracked yet (turn 1, or the first decision
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
	jr nz, .fatigueCheck ; last move had power; no back-to-back zero yet
	ld a, [wEnemyMoveEffect]
	cp HEAL_EFFECT
	jr z, .fatigueCheck
	cp SUBSTITUTE_EFFECT
	jr z, .fatigueCheck
	ld a, AI_STRONG
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
	dbw SPECIAL_DAMAGE_EFFECT, AISmart_SpecialDamage
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

; Super Fang is much better when the target is already low, since halving a
; small HP pool can finish it. Source: pokecrystal AI_Smart_SuperFang.
AISmart_SuperFang:
	call AIPlayerHPBelowQuarter
	jr nc, .noChange
	ld a, AI_STRONG
	scf
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
AISmart_Paralyze:
	call AIPlayerHPBelowQuarter
	jr nc, .noChange
	ld a, AI_NUDGE
	and a
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
	jr z, .noChange ; bit tests a bit WITHOUT clearing a's value - a still
	                ; holds the raw status byte here, not 0
	ld a, AI_NUDGE
	and a
	ret
.noChange
	xor a
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
AISmart_Confusion:
	call AIPlayerHPBelowHalf
	jr nc, .noChange
	ld a, AI_NUDGE
	and a
	ret
.noChange
	xor a
	ret

; Fixed-damage moves (Seismic Toss etc.) are a reliable answer to a healthy
; target regardless of type walls (see AI_OVERHAUL_PLAN.md follow-up F1: this
; engine's fixed-damage moves ignore type immunity, unlike upstream). Source:
; Yume, adapted for the immunity divergence.
AISmart_SpecialDamage:
	call AIPlayerHPBelowHalf
	jr c, .noChange
	ld a, AI_NUDGE
	scf
	ret
.noChange
	xor a
	ret
