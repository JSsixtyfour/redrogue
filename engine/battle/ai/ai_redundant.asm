; AI_REDUNDANT layer (AI_OVERHAUL_PLAN.md Phase 2a): "would this move do literally
; nothing right now." Table-driven per-effect dispatch, PureRGB's dbw-effect-handler
; shape, adapted from Gen 2's redundant.asm concept.
;
; INCLUDEd into "Battle Engine 7" (bank $0E) rather than given its own SECTION,
; because the dispatch in AIEnemyTrainerChooseMoves uses a same-bank `jp hl` to
; reach every scoring layer (see the header comment in ai_core.asm) - every
; layer routine has to live wherever that dispatcher lives. See ROM_BIBLE.md
; before changing that; bank $0E currently has room (measured 2026-08-25).
;
; ENGINE-TRUTH DEPENDENCIES, verified against source immediately before writing
; this (AI_OVERHAUL_PLAN.md's binding rule: cite the call site, don't trust the
; prior summary):
;   - Recover/Softboiled's old -255/-511 HP-delta bug is FIXED
;     (move_effects/heal.asm:14-26). Only "already at max HP" is checked here;
;     re-adding the delta check would be dead weight.
;   - Fixed-damage moves (Seismic Toss etc.) still ignore type immunity
;     (deliberately not imported, core.asm ~:3726). NOT handled here - adding
;     it would suppress a move that actually works. See AI_OVERHAUL_PLAN.md
;     follow-up F1.
;   - The Substitute-blocked-status set was re-verified from source ONE
;     EFFECT AT A TIME for this pass (not copied from the 2026-08-20 summary,
;     which turned out to be incomplete): PARALYZE_EFFECT (Thunder Wave) had
;     no CheckTargetSubstitute call in its dedicated handler at all, unlike
;     every other status effect. Fixed as a companion change in
;     move_effects/paralyze.asm before this file was written, so the table
;     below can treat every status effect uniformly. DISABLE_EFFECT was
;     checked too and confirmed to have no Substitute gate in this engine -
;     it is correctly left OUT of the Substitute table below.
;
; SCORE MAGNITUDES: two tiers, both via the saturating AIDiscourage (Phase 1).
;   AI_REDUNDANT_HEAVY: this move's entire effect is a no-op - push the score
;     to the saturation ceiling in one shot (79), so it is picked only if
;     every other move is equally hopeless.
;   AI_REDUNDANT_LIGHT: this move still does something (usually damage), only
;     its secondary chance is impossible against this specific target - a
;     small nudge, not an elimination, since eliminating a perfectly good
;     attack over a lost status chance would be a worse mistake than the one
;     being fixed.
; Phase 2b: was a hardcoded 69 ("from base 10, saturates to 79"), which stayed
; correct across the 10 -> 20 baseline widening only by luck. Now derived, so a
; future rescale cannot silently turn "always saturate" into "sometimes doesn't".
DEF AI_REDUNDANT_HEAVY EQU AI_SATURATE
DEF AI_REDUNDANT_LIGHT EQU AI_VERY_STRONG

; DISPATCH DISCIPLINE (learned the hard way during Phase 2a bring-up - see
; ai_score_helpers.asm for why AIEncourage/AIDiscourage live in this bank and
; take hl, not de): a handler is allowed to clobber ANY register except a on
; its way to returning a=0/magnitude, and several already do
; (AIRedundant_Heal, AIRedundant_BurnFreezeParaSide, AIRedundant_Substitute,
; AIRedundant_OHKO, AIRedundant_Haze all use b/c/d/e as scratch with no
; attempt to preserve them). So this loop's own state - the move-list
; pointer, the score-array pointer, and the b loop counter - is pushed once
; per move and not touched again until popped back in the same order,
; strictly after the handler has returned. None of `pop bc` / `pop de` /
; `pop hl` touch a, so the handler's result survives all three pops
; untouched, and AIDiscourage (same-bank call, no farcall involved) is safe
; to invoke with the just-restored hl and the never-disturbed a.
AILayerRedundant:
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
	call ReadMove ; sets wEnemyMoveEffect/Power/Type/Accuracy
	ld a, [wEnemyMoveEffect]
	ld c, a
	ld hl, AIRedundantEffectTable
	ld de, 3 ; effect id (1) + handler pointer (2)
	call IsInArray
	jr nc, .notFound
	inc hl
	ld a, [hli]
	ld h, [hl]
	ld l, a ; hl = handler address
	call .callHandler ; a = 0 (no-op) or a discourage magnitude; every other
	                   ; register is fair game for the handler to clobber
	pop bc ; restore loopCounter - does not touch a
	pop de ; restore movelistPtr - does not touch a
	pop hl ; restore scorePtr - does not touch a; also exactly AIDiscourage's
	       ; INPUT pointer, so no further juggling is needed
	and a  ; only now inspect the handler's result
	jr z, .nextMove
	call AIDiscourage ; hl=scorePtr, a=magnitude, both already in place
	jr .nextMove
.notFound
	pop bc
	pop de
	pop hl
	jr .nextMove
.callHandler
	jp hl

; Effect -> handler table, IsInArray's dbw shape (1-byte key + 2-byte target).
; Every handler: INPUT none beyond wEnemyMove*/wBattleMon*/wEnemyMon* already
; being live from ReadMove and the ongoing battle; OUTPUT a = 0 (leave the
; score alone) or a magnitude for AIDiscourage. Clobbers whatever it needs;
; the dispatcher above only guarantees de (the score pointer) survives.
AIRedundantEffectTable:
	dbw EFFECT_01, AIRedundant_AlreadyStatused
	dbw SLEEP_EFFECT, AIRedundant_AlreadyStatused
	dbw POISON_EFFECT, AIRedundant_Poison
	dbw PARALYZE_EFFECT, AIRedundant_Paralyze
	dbw POISON_SIDE_EFFECT1, AIRedundant_PoisonSide
	dbw POISON_SIDE_EFFECT2, AIRedundant_PoisonSide
	dbw BURN_SIDE_EFFECT1, AIRedundant_BurnFreezeParaSide
	dbw BURN_SIDE_EFFECT2, AIRedundant_BurnFreezeParaSide
	dbw FREEZE_SIDE_EFFECT1, AIRedundant_BurnFreezeParaSide
	dbw FREEZE_SIDE_EFFECT2, AIRedundant_BurnFreezeParaSide
	dbw PARALYZE_SIDE_EFFECT1, AIRedundant_BurnFreezeParaSide
	dbw PARALYZE_SIDE_EFFECT2, AIRedundant_BurnFreezeParaSide
	dbw FLINCH_SIDE_EFFECT1, AIRedundant_SubOnly
	dbw FLINCH_SIDE_EFFECT2, AIRedundant_SubOnly
	dbw CONFUSION_EFFECT, AIRedundant_ConfusionEffect
	dbw CONFUSION_SIDE_EFFECT, AIRedundant_SubOnly
	dbw DRAIN_HP_EFFECT, AIRedundant_SubOnly
	dbw DREAM_EATER_EFFECT, AIRedundant_DreamEater
	dbw LEECH_SEED_EFFECT, AIRedundant_LeechSeed
	dbw ATTACK_DOWN1_EFFECT, AIRedundant_SubOnly
	dbw DEFENSE_DOWN1_EFFECT, AIRedundant_SubOnly
	dbw SPEED_DOWN1_EFFECT, AIRedundant_SubOnly
	dbw SPECIAL_DOWN1_EFFECT, AIRedundant_SubOnly
	dbw ACCURACY_DOWN1_EFFECT, AIRedundant_SubOnly
	dbw EVASION_DOWN1_EFFECT, AIRedundant_SubOnly
	dbw ATTACK_DOWN2_EFFECT, AIRedundant_SubOnly
	dbw DEFENSE_DOWN2_EFFECT, AIRedundant_SubOnly
	dbw SPEED_DOWN2_EFFECT, AIRedundant_SubOnly
	dbw SPECIAL_DOWN2_EFFECT, AIRedundant_SubOnly
	dbw ACCURACY_DOWN2_EFFECT, AIRedundant_SubOnly
	dbw EVASION_DOWN2_EFFECT, AIRedundant_SubOnly
	dbw ATTACK_DOWN_SIDE_EFFECT, AIRedundant_SubOnly
	dbw DEFENSE_DOWN_SIDE_EFFECT, AIRedundant_SubOnly
	dbw SPEED_DOWN_SIDE_EFFECT, AIRedundant_SubOnly
	dbw SPECIAL_DOWN_SIDE_EFFECT, AIRedundant_SubOnly
	dbw LIGHT_SCREEN_EFFECT, AIRedundant_LightScreen
	dbw REFLECT_EFFECT, AIRedundant_Reflect
	dbw MIST_EFFECT, AIRedundant_Mist
	dbw FOCUS_ENERGY_EFFECT, AIRedundant_FocusEnergy
	dbw SUBSTITUTE_EFFECT, AIRedundant_Substitute
	dbw DISABLE_EFFECT, AIRedundant_Disable
	dbw HEAL_EFFECT, AIRedundant_Heal
	dbw OHKO_EFFECT, AIRedundant_OHKO
	dbw HAZE_EFFECT, AIRedundant_Haze
	db -1 ; IsInArray terminator - NOT 0, matches home/array2.asm's convention

; --- Shared primitive: does the TARGET (opponent of whoever's turn it is,
; always the player from this AI's perspective) have a Substitute up? ---
; OUTPUT: z set if no Substitute, nz if one is up. Preserves everything.
; A local copy of CheckTargetSubstitute's exact logic (engine/battle/effects.asm)
; rather than a call to it, because handlers here need it composed with other
; tests without paying a bank-crossing farcall each time, and the source of
; truth (HAS_SUBSTITUTE_UP on wPlayerBattleStatus2 when it's the enemy's turn)
; is a two-instruction check.
AIRedundantTargetHasSubstitute:
	push hl
	ld hl, wPlayerBattleStatus2 ; the AI only ever runs on the enemy's turn
	bit HAS_SUBSTITUTE_UP, [hl]
	pop hl
	ret

; --- Handlers -------------------------------------------------------------
; Each returns a = 0 (do nothing) or a discourage magnitude in a.

; A pure status effect (Sleep, and the dead EFFECT_01 slot) against a target
; that already has ANY non-volatile status. AI_BASIC (bit 1) also discourages
; this, mildly; this fires first and eliminates it outright, matching the
; plan's explicit "status vs an already-statused target" item.
AIRedundant_AlreadyStatused:
	call AIRedundantTargetHasSubstitute
	jr nz, .heavy ; Sleep is blocked by Substitute (effects.asm SleepEffect)
	ld a, [wBattleMonStatus]
	and a
	jr nz, .heavy
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

; Toxic (POISON_EFFECT): redundant if the target already has a status, is
; Poison-type (PoisonEffect's own immunity check, effects.asm), or is behind
; a Substitute.
AIRedundant_Poison:
	call AIRedundantTargetHasSubstitute
	jr nz, .heavy
	ld a, [wBattleMonStatus]
	and a
	jr nz, .heavy
	ld a, [wBattleMonType1]
	cp POISON
	jr z, .heavy
	ld a, [wBattleMonType2]
	cp POISON
	jr z, .heavy
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

; Thunder Wave (PARALYZE_EFFECT): redundant if the target already has a
; status, is Ground-type (ParalyzeEffect_'s own immunity check), or is behind
; a Substitute (move_effects/paralyze.asm, fixed alongside this phase).
AIRedundant_Paralyze:
	call AIRedundantTargetHasSubstitute
	jr nz, .heavy
	ld a, [wBattleMonStatus]
	and a
	jr nz, .heavy
	ld a, [wBattleMonType1]
	cp GROUND
	jr z, .heavy
	ld a, [wBattleMonType2]
	cp GROUND
	jr z, .heavy
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

; A damaging move whose poison SIDE effect (Twineedle etc.) is blocked
; entirely when the target has a Substitute up (Substitute blocks the WHOLE
; move here, not just the poison chance - PoisonEffect in effects.asm), so
; that case stays a heavy discourage.
;
; Phase 3 Step 3: when only the RIDER is blocked (target already statused, or
; is Poison-type so poison cannot apply) this handler no longer discourages at
; all - the move's damage still lands normally, and AI_SMART's side-effect
; BONUS handlers (ai_smart.asm) already skip the bonus in exactly this case.
; Keeping a LIGHT penalty here on top of that was double-counting in the wrong
; direction: a move that deals full damage but loses only its status rider was
; being penalized MORE than its damage ranking alone justified. See
; PHASE_3_STEP3_SPEC.md's "magnitude imbalance" finding for the case that
; surfaced this (Seismic Toss beating a higher-damage Body Slam solely because
; Body Slam's paralysis could not land on a same-typed target).
AIRedundant_PoisonSide:
	call AIRedundantTargetHasSubstitute
	jr nz, .heavy
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

; Body Slam / Ice Beam / Thunder-family side effects: a Substitute blocks the
; WHOLE move, so that stays a heavy discourage.
;
; Phase 3 Step 3: when only the RIDER is blocked (move's type matches one of
; the target's types - the engine's own same-type-immunity rule in
; FreezeBurnParalyzeEffect - or the target is already statused) this handler no
; longer discourages at all. See AIRedundant_PoisonSide just above for the full
; reasoning; it is identical here.
AIRedundant_BurnFreezeParaSide:
	call AIRedundantTargetHasSubstitute
	jr nz, .heavy
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

; Confuse Ray (CONFUSION_EFFECT): redundant if the target is already
; confused, or is behind a Substitute.
AIRedundant_ConfusionEffect:
	call AIRedundantTargetHasSubstitute
	jr nz, .heavy
	ld a, [wPlayerBattleStatus1]
	bit CONFUSED, a
	jr nz, .heavy
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

; Effects whose ENTIRE mechanism is "does nothing at all if the target has a
; Substitute up" and has no other redundancy condition worth checking here:
; flinch/confusion side effects, drain HP, and every stat-down move (own or
; side-effect). Stat-down moves already-at-minimum are left alone - the
; engine's own CantLowerAnymore path (effects.asm) handles that gracefully
; and it is not worth duplicating the six-stat "already at -6" scan here for
; a case that merely prints a different message rather than truly wasting
; the turn on top of a Substitute block.
AIRedundant_SubOnly:
	call AIRedundantTargetHasSubstitute
	jr nz, .heavy
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

; Dream Eater: redundant if the target is not asleep (0 damage, matches
; DREAM_EATER_EFFECT's dedicated check in MoveHitTest, core.asm) or is
; behind a Substitute (same MoveHitTest arm).
AIRedundant_DreamEater:
	call AIRedundantTargetHasSubstitute
	jr nz, .heavy
	ld a, [wBattleMonStatus]
	and SLP_MASK
	jr z, .heavy
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

; Leech Seed: redundant if the target is Grass-type (LeechSeedEffect_'s own
; hardcoded check, move_effects/leech_seed.asm - not a type-chart lookup),
; already seeded, or behind a Substitute (core.asm MoveHitTest).
AIRedundant_LeechSeed:
	call AIRedundantTargetHasSubstitute
	jr nz, .heavy
	ld a, [wBattleMonType1]
	cp GRASS
	jr z, .heavy
	ld a, [wBattleMonType2]
	cp GRASS
	jr z, .heavy
	ld a, [wPlayerBattleStatus2]
	bit SEEDED, a
	jr nz, .heavy
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

; Light Screen / Reflect / Mist / Focus Energy: redundant if the ENEMY (the
; caster) already has that effect up on its own side. Not Substitute-gated -
; these are self-targeted and effects.asm's ReflectLightScreenEffect etc.
; never call CheckTargetSubstitute for them.
AIRedundant_LightScreen:
	ld a, [wEnemyBattleStatus3]
	bit HAS_LIGHT_SCREEN_UP, a
	jr nz, .heavy
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

AIRedundant_Reflect:
	ld a, [wEnemyBattleStatus3]
	bit HAS_REFLECT_UP, a
	jr nz, .heavy
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

AIRedundant_Mist:
	ld a, [wEnemyBattleStatus2]
	bit PROTECTED_BY_MIST, a
	jr nz, .heavy
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

AIRedundant_FocusEnergy:
	ld a, [wEnemyBattleStatus2]
	bit GETTING_PUMPED, a
	jr nz, .heavy
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

; Substitute: redundant if the enemy already has one up, OR its own HP is at
; or below a quarter of max (the exact SubstituteEffect_ fail threshold,
; move_effects/substitute.asm: currentHP <= maxHP/4, floor division). The
; 4*hp<=maxHP form below is the same boundary without replicating the
; engine's shift-and-subtract: k <= floor(n/4) iff 4k <= n for all integers.
AIRedundant_Substitute:
	ld a, [wEnemyBattleStatus2]
	bit HAS_SUBSTITUTE_UP, a
	jr nz, .heavy
	ld hl, wEnemyMonHP
	ld a, [hli]
	ld d, a
	ld e, [hl] ; de = current HP
	sla e
	rl d
	sla e
	rl d ; de = current HP * 4
	ld hl, wEnemyMonMaxHP
	ld a, [hl]
	cp d
	jr c, .ok ; maxHP high byte < hp*4 high byte -> hp*4 > maxHP, legal
	jr nz, .heavy ; maxHP high byte > hp*4 high byte -> hp*4 <= maxHP, redundant
	inc hl
	ld a, [hl]
	cp e
	; Phase 2b bugfix: this was `jr c, .heavy`, exactly backwards. High bytes
	; are already confirmed equal at this point (the two branches above ruled
	; out < and >), so the 16-bit comparison reduces entirely to the low
	; bytes: maxHP < hp*4 (i.e. legal) iff maxHP_lo < hp4_lo, i.e. iff THIS
	; `cp e` sets carry - so carry means legal, not redundant. The old code
	; blocked Substitute as illegal across a real band of legal HP values
	; (any HP where hp*4's high byte happened to equal maxHP's high byte),
	; caught by a Phase 2b scenario that landed in that exact band.
	jr c, .ok ; maxHP low < hp*4 low -> maxHP < hp*4 -> legal
	jr .heavy ; else maxHP low >= hp*4 low -> maxHP >= hp*4 -> at or past the
	          ; 25% boundary -> redundant
.ok
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

; Disable: redundant if the player already has a move disabled. Confirmed
; NOT Substitute-gated in this engine (DisableEffect, effects.asm, has no
; CheckTargetSubstitute call) - deliberately not included here.
AIRedundant_Disable:
	ld a, [wPlayerDisabledMove]
	and a
	jr nz, .heavy
	xor a
	ret
.heavy
	ld a, AI_REDUNDANT_HEAVY
	ret

; Recover / Softboiled: redundant only when the enemy is already at max HP.
; The old -255/-511 delta bug is fixed (see the header comment), so that is
; deliberately the ONLY condition checked.
AIRedundant_Heal:
	ld hl, wEnemyMonHP
	ld a, [hli]
	ld b, a
	ld c, [hl]
	ld hl, wEnemyMonMaxHP
	ld a, [hli]
	cp b
	jr nz, .notFull
	ld a, [hl]
	cp c
	jr nz, .notFull
	ld a, AI_REDUNDANT_HEAVY
	ret
.notFull
	xor a
	ret

; OHKO moves (Horn Drill etc.) auto-miss unless the user is strictly faster
; than the target. Mirrors the exact 16-bit compare already established in
; AIMoveChoiceModification5 (trainer_ai.asm), but this needs the OPPOSITE
; outcome and a strict (not >=) threshold: OHKO needs enemySpeed > playerSpeed
; to have any chance at all.
AIRedundant_OHKO:
	ld a, [wEnemyMonSpeed]
	ld b, a
	ld a, [wBattleMonSpeed]
	cp b
	jr z, .notFaster ; high bytes equal -> check low bytes
	jr c, .faster     ; player_hi < enemy_hi -> enemy is faster
	jr .notFaster      ; player_hi > enemy_hi -> enemy is not faster
.notFaster
	ld a, [wEnemyMonSpeed + 1]
	ld b, a
	ld a, [wBattleMonSpeed + 1]
	cp b
	jr c, .faster ; player_lo < enemy_lo -> enemy is faster
	; equal or player faster: OHKO auto-fails either way
	ld a, AI_REDUNDANT_HEAVY
	ret
.faster
	xor a
	ret

; Haze: deliberately conservative. Only asserts "nothing to clear" when
; every stat modifier on both sides is neutral AND the player has no
; non-volatile status - this catches the common case without walking every
; volatile status flag Haze also clears (confusion, disable, etc; see
; HazeEffect_, move_effects/haze.asm). A false "not redundant" here just
; costs a wasted turn sometimes; a false "redundant" would suppress a Haze
; that was actually clearing something this check doesn't look at, so the
; check only fires when it is certain.
AIRedundant_Haze:
	ld a, [wBattleMonStatus]
	and a
	jr nz, .notRedundant
	ld hl, wPlayerMonAttackMod
	ld b, 5
	call .allNeutral
	ret nc
	ld hl, wEnemyMonAttackMod
	ld b, 5
	call .allNeutral
	ret nc
	ld a, AI_REDUNDANT_HEAVY
	ret
.notRedundant
	xor a
	ret
; INPUT: hl = first of b consecutive stat-mod bytes. OUTPUT: carry set if
; every one equals BASE_STAT_LEVEL (neutral).
.allNeutral
	ld a, [hli]
	cp BASE_STAT_LEVEL
	ret nz
	dec b
	jr nz, .allNeutral
	scf
	ret
