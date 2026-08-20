; AI Overhaul Phase 0: badge-boost re-application fix.
;
; THE BUG (vanilla, still present before this change):
; Stat-modifying moves recalculate ONE stat from its unmodified base plus the
; new stat stage, which discards that stat's badge boost. Vanilla then called
; ApplyBadgeStatBoosts (engine/battle/core.asm), which re-boosts ALL FOUR
; badge stats by 1.125x. The three stats that were never touched keep their
; original boost AND receive another one, compounding every time any stat
; changes. A player spamming a stat move inflates Attack/Defense/Speed/Special
; toward 999 regardless of which stat the move actually affected.
;
; THE FIX (ShinRed's approach: selectively boost only the correct stat):
; re-apply the badge boost to ONLY the stat that was just recalculated. The
; other three never lost theirs, so they must not receive another.
;
; Declares its own floating SECTION - "Battle Core" (engine/battle/core.asm +
; engine/battle/effects.asm) has ~51 bytes free and cannot host this. Same
; pattern as custom_functions/apply_self_stat_penalty.asm.
;
; Called unconditionally from BOTH stat-mod sites in engine/battle/effects.asm
; (StatModifierUpEffect and UpdateLoweredStatDone). The whose-turn test that
; used to gate those calls now lives here, which keeps the change byte-neutral
; in the tight Battle Core bank.
;
; Badges only ever boost the PLAYER's stats, so this returns without doing
; anything unless the mon whose stat just changed is the player's:
;   stat UP   -> affects the USER   (self-targeted in Gen 1)
;   stat DOWN -> affects the TARGET (the opponent of whoever's turn it is)
;
; Clobbers af, bc, de, hl.

SECTION "Single Badge Stat Boost", ROMX

ApplySingleBadgeStatBoost::
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret z ; no badge boosts in link battles, matching ApplyBadgeStatBoosts

	ld hl, wPlayerMoveEffect
	ldh a, [hWhoseTurn]
	and a
	jr z, .gotEffectPtr
	ld hl, wEnemyMoveEffect
.gotEffectPtr
	ld d, 0 ; d = 0 -> stat UP, d = 1 -> stat DOWN
	ld a, [hl]

; Normalize whichever stat-mod effect range this is down to the +1 range
; (ATTACK_UP1_EFFECT..EVASION_UP1_EFFECT = 0..5) and record the direction.
	cp ATTACK_DOWN_SIDE_EFFECT
	jr c, .checkDown2
	cp SPECIAL_DOWN_SIDE_EFFECT + 1
	ret nc ; above the stat-mod effects entirely
	sub ATTACK_DOWN_SIDE_EFFECT - ATTACK_UP1_EFFECT
	inc d
	jr .haveStatIndex
.checkDown2
	cp ATTACK_DOWN2_EFFECT
	jr c, .checkUp2
	sub ATTACK_DOWN2_EFFECT - ATTACK_UP1_EFFECT
	inc d
	jr .haveStatIndex
.checkUp2
	cp ATTACK_UP2_EFFECT
	jr c, .checkDown1
	sub ATTACK_UP2_EFFECT - ATTACK_UP1_EFFECT
	jr .haveStatIndex
.checkDown1
	cp ATTACK_DOWN1_EFFECT
	jr c, .checkUp1
	sub ATTACK_DOWN1_EFFECT - ATTACK_UP1_EFFECT
	inc d
	jr .haveStatIndex
.checkUp1
	cp ATTACK_UP1_EFFECT
	ret c ; below the stat-mod effects entirely
	sub ATTACK_UP1_EFFECT
.haveStatIndex
	cp 4
	ret nc ; accuracy/evasion have no stored stat to re-boost
	ld c, a ; c = stat index: 0 Attack, 1 Defense, 2 Speed, 3 Special

; Is the affected mon the player's? UP affects the user, DOWN affects the
; target, so xor'ing the direction against hWhoseTurn yields 0 for "player".
	ldh a, [hWhoseTurn]
	xor d
	and a
	ret nz ; the enemy's stat changed - badges never apply to it

; Badge bit for this stat is index * 2:
; Boulder (0) Attack, Thunder (2) Defense, Soul (4) Speed, Volcano (6) Special.
	ld a, [wObtainedBadges]
	ld b, c
	inc b
.shiftToBadgeBit
	dec b
	jr z, .testBadgeBit
	rrca
	rrca
	jr .shiftToBadgeBit
.testBadgeBit
	bit 0, a
	ret z ; badge not obtained, so this stat never had a boost to lose

	ld hl, wBattleMonAttack
	sla c ; each stat is 2 bytes
	ld b, 0
	add hl, bc

; Multiply the stat at hl by 1.125, capped at MAX_STAT_VALUE.
; Mirrors ApplyBadgeStatBoosts.applyBoostToStat in engine/battle/core.asm.
; Duplicated rather than shared because farcall overwrites hl, so the original
; cannot be handed a pointer across a bank boundary. If the boost formula there
; ever changes, change it here too.
	ld a, [hli]
	ld d, a
	ld e, [hl]
	srl d
	rr e
	srl d
	rr e
	srl d
	rr e
	ld a, [hl]
	add e
	ld [hld], a
	ld a, [hl]
	adc d
	ld [hli], a
	ld a, [hld]
	sub LOW(MAX_STAT_VALUE)
	ld a, [hl]
	sbc HIGH(MAX_STAT_VALUE)
	ret c
	ld a, HIGH(MAX_STAT_VALUE)
	ld [hli], a
	ld a, LOW(MAX_STAT_VALUE)
	ld [hld], a
	ret
