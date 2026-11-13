; Crit-certain moves (AI review CP2, 2026-11-12; AI_REVIEW_PLAN_2026-11-12.md).
; Its own floating SECTION "AI Crit" (main.asm): nothing here needs bank $0E,
; which is full, so every caller there reaches it by farcall. Entry points take
; no register inputs and answer in e, WRAM and the carry flag, the parts of a
; return that survive a farcall (a and bc do not).
;
; THE PROBLEM. Every KO and threat check estimated the ordinary, non-crit max
; roll. For most moves a crit is luck (base Speed / 512, ~11% measured), but the
; four high-crit moves multiply that by 8, which caps at 255/256 for any attacker
; with base Speed 48 or more: measured, 21 of 23 high-crit hits critted. For
; those the non-crit number is simply the wrong number, and a crit also ignores
; stat stages and screens, so a Defense boost or a Reflect against Slash bought
; nothing while the AI believed it halved the hit.
;
; THE RULE. A damaging move (power >= 2; fixed damage never crits) whose
; CalcCritRate threshold is at least AI_CRIT_CERTAIN is estimated as a crit,
; through the engine's own crit path (AIEstimate*DamageCrit, core.asm). Who uses
; it: every estimate of a PLAYER move (AIEstimatePlayerMoveDamage), and AI_DAMAGE's
; possible-KO test for our own moves (AIEstimateEnemyCritIfCertain). Ranking keeps
; AIScaleDamageForCrit's expected value, and the reliable-KO predicates stay
; non-crit: a 75-99% crit is not "reliable".

; OUTPUT: e = the loaded ENEMY move's crit threshold out of 256 ($ff for a
; guaranteed crit as well as a capped one), 0 for a move with no power. For
; AIScaleDamageForCrit. Clobbers af, bc, d, hl.
AIGetEnemyCritThreshold::
	ld a, 1
	call AIGetCritThreshold
	ld e, b
	ret

; INPUT: a = 0 for the player's loaded move (wPlayerMove*), 1 for the enemy's.
; OUTPUT: b = that move's crit threshold, as above.
; CalcCritRate loads the attacker's header (PublishFormContext + GetMonHeader):
; wCurSpecies (which is also wCurItem, see project_wcuritem_species_alias), the
; form context and hWhoseTurn are put back; the header itself stays clobbered, as
; CriticalHitTest leaves it moments later in the real move. CalcCritRate returns
; in e plus the Z and C flags, which survive its farcall return.
; Clobbers af, c, de, hl.
AIGetCritThreshold:
	ld b, a
	ld a, [wCurSpecies]
	push af
	ld hl, wFormContextSpecies
	ASSERT wFormContextForm == wFormContextSpecies + 1
	ld a, [hli]
	ld h, [hl]
	ld l, a
	push hl ; l = context species, h = context form
	ldh a, [hWhoseTurn]
	push af
	ld a, b
	ldh [hWhoseTurn], a ; CalcCritRate picks the attacker off this
	farcall CalcCritRate ; -> e = threshold, Z = no power, C = form always crits
; Capture the answer BEFORE the pops below: `pop af` restores flags.
	ld b, e
	jr z, .noPower
	jr nc, .gotRate
	ld b, $ff ; SF_ALWAYS_CRIT: worth the same as a capped threshold here
	jr .gotRate
.noPower
	ld b, 0
.gotRate
	pop af
	ldh [hWhoseTurn], a
	pop hl
	ld a, l
	ld [wFormContextSpecies], a
	ld a, h
	ld [wFormContextForm], a
	pop af
	ld [wCurSpecies], a
	ret

; INPUT: a = side, as AIGetCritThreshold. Carry SET if that side's loaded move
; is estimated as a crit. Clobbers af, bc, de, hl.
; PREFILTER (AI review CP9, 2026-11-13): CalcCritRate costs ~5.7k cycles
; (PublishFormContext + GetMonHeader) and ran for every damaging move in every
; scan. An ordinary move's threshold is at most 127 (base Speed / 2 x2 then /2;
; Focus Energy's x8 caps at 255 before the same /2), so only these reach
; AI_CRIT_CERTAIN: a HighCriticalMoves move; the player's Bridge bonuses
; (Witch x1.25 tops out at 158, the Captain pick adds 64 on top); or a special
; form, whose SF_ALWAYS_CRIT forces 255. Anything else answers "no" without
; the lookup; those three still take the exact one.
; INPUT a = side, d = the cutoff (every caller passes AI_CRIT_CERTAIN since CP8's
; lower AI_CRIT_RISK was cut, FU4; below AI_CRIT_CERTAIN the prefilter's 127 bound
; proves nothing, so a lower cutoff looks every move up). Carry SET if the
; threshold is at least the cutoff.
AIMoveCritCertain:
	ld c, a
	push de
	ld hl, wPlayerMovePower
	and a
	jr z, .gotBlock
	ld hl, wEnemyMovePower
.gotBlock
	ld a, [hld]
	cp 2
	jr c, .no ; status (0) or fixed damage (1): the crit path never applies
	ld a, d
	cp AI_CRIT_CERTAIN
	jr c, .lookup ; a lower cutoff: every damaging move is looked up
	dec hl
	ld b, [hl] ; the move id (the block is num, effect, power)
	ld hl, AIHighCritMoves
.scan
	ld a, [hli]
	cp b
	jr z, .lookup
	inc a
	jr nz, .scan ; $ff ends the list
	ld a, c
	and a
	ld a, [wEnemyMon + MON_CATCH_RATE] ; ld keeps the flags
	jr nz, .formByte
	push bc
	ld e, BRIDGE_SELECTED_EFFECT_CRITICAL_RATE
	farcall BridgeActiveMonHasSelectedEffect ; carry = the Captain pick; flags survive
	pop bc
	jr c, .lookup
	ld a, [wBattleMon + MON_CATCH_RATE]
.formByte
	bit BIT_SPECIAL_FORM, a
	jr z, .no
.lookup
	ld a, c
	call AIGetCritThreshold
	pop de
	ld a, b
	cp d
	ccf ; carry iff threshold >= the cutoff
	ret
.no
	pop de
	and a
	ret

; A copy of HighCriticalMoves (data/battle/critical_hit_moves.asm, bank $0F):
; this floating section must not read across banks. tools/gen_ai_crit_species.py
; --check (make audit) fails if the two lists ever differ.
AIHighCritMoves:
	db KARATE_CHOP
	db RAZOR_LEAF
	db CRABHAMMER
	db SLASH
	db -1 ; end

; INPUT: a = side. That side's loaded move as a CRITICAL hit, max roll, into
; wAIDamageEstimate. The engine's crit path rebuilds the enemy's stat from
; species, level and DVs (GetEnemyMonStat), writing wCurSpecies, wCurEnemyLevel,
; the form context, wLoadedMonSpeedExp and the mon header; the first three are
; put back. wLoadedMonSpeedExp is read only by the status screen, which loads the
; mon first, and a real crit writes it too. Clobbers af, bc, de, hl.
AIEstimateCritDamage:
	ld d, a
	ld a, [wCurSpecies]
	push af
	ld a, [wCurEnemyLevel]
	push af
	ld hl, wFormContextSpecies
	ld a, [hli]
	ld h, [hl]
	ld l, a
	push hl
	ld a, d
	and a
	jr nz, .enemyAttacks
	farcall AIEstimatePlayerDamageCrit
	jr .restore
.enemyAttacks
	farcall AIEstimateDamageCrit
.restore
	pop hl
	ld a, l
	ld [wFormContextSpecies], a
	ld a, h
	ld [wFormContextForm], a
	pop af
	ld [wCurEnemyLevel], a
	pop af
	ld [wCurSpecies], a
	ret

; Replaces `farcall AIEstimatePlayerDamage` (the wPlayerMove* block loaded): the
; one-hit max roll into wAIDamageEstimate, as a crit when the move's crit is near
; certain. Carry SET = estimated as a crit (it ignores screens and our stat
; stages). Every player-move estimate goes through here: the KO scan
; (AIPlayerWouldKO, B4/B5 reserves, heals), the best expected hit, the screen
; handler and the setup gate's Explosion. Clobbers af, bc, de, hl.
; FU1 part 2 (2026-11-13): every consumer asks how hard the move can hit, so a
; crit-certain move gives the LARGER of its normal hit and its crit (carry only
; when the crit is the larger, so the screen handler buckets the normal hit by
; category). A crit ignores stages, so the normal hit can be larger only when the
; player's Attack or Special stage is raised or ours of Defense or Special is
; lowered; only then is the normal hit estimated too. A staged reserve (B4/B5)
; reads the active mon's stage bytes, which can only add a needless estimate:
; its normal hit already uses its own unmodified stats.
AIEstimatePlayerMoveDamage::
	ld d, AI_CRIT_CERTAIN
	xor a
	call AIMoveCritCertain
	jr c, .crit
	farcall AIEstimatePlayerDamage
	and a
	ret
.crit
	ld a, [wPlayerMonAttackMod]
	cp BASE_STAT_LEVEL + 1
	jr nc, .both
	ld a, [wPlayerMonSpecialMod]
	cp BASE_STAT_LEVEL + 1
	jr nc, .both
	ld a, [wEnemyMonDefenseMod]
	cp BASE_STAT_LEVEL
	jr c, .both
	ld a, [wEnemyMonSpecialMod]
	cp BASE_STAT_LEVEL
	jr c, .both
	xor a
	call AIEstimateCritDamage
	scf
	ret
.both
	farcall AIEstimatePlayerDamage
	xor a
	jr AIKeepEstimateOrCrit

; AI_DAMAGE's possible-KO test, on the loaded enemy move: when its crit is near
; certain, wAIDamageEstimate (the cached one-hit max) becomes the LARGER of it
; and the crit estimate (uncached). Leaves it alone otherwise.
; FU1 (2026-11-13): a crit ignores stat stages, so from +6 Attack it does less
; than the normal hit. Measured: Persian's Slash at +6 was a possible KO only up
; to its crit (102 HP) while its normal hit reaches the 227-HP cap. Either outcome
; can happen, so a possible KO takes the larger. Clobbers af, bc, de, hl.
AIEstimateEnemyCritIfCertain::
	ld d, AI_CRIT_CERTAIN
	ld a, 1
	call AIMoveCritCertain
	ret nc
	ld a, 1
	; fallthrough

; INPUT a = side (as AIEstimateCritDamage), wAIDamageEstimate = that side's normal
; one-hit max. Leaves the larger of it and the crit estimate. Carry SET = the
; crit is the larger (or equal). Clobbers af, bc, de, hl.
AIKeepEstimateOrCrit:
	ld hl, wAIDamageEstimate
	ld d, [hl]
	inc hl
	ld e, [hl]
	push de ; the normal one-hit max
	call AIEstimateCritDamage
	pop de
	ld hl, wAIDamageEstimate + 1
	ld a, [hld]
	sub e
	ld a, [hl]
	sbc d
	ccf
	ret c ; the crit is at least the normal hit
	ld [hl], d
	inc hl
	ld [hl], e
	ret ; carry clear (ld keeps it)

; The reliable-KO contract's crit half (AIMoveIsReliableKO tail-calls this once
; the normal minimum roll KOs at 90%+ to hit). When the loaded enemy move's crit
; is near certain, the KO is reliable only if the crit's minimum delivery KOs
; too: a crit ignores stat stages, and it is the likely outcome. FU1, 2026-11-13.
; Carry SET = still reliable. Leaves wAIDamageEstimate as the crit's delivery
; when it ran (no caller reads it afterwards). Clobbers af, bc, de, hl.
AIEnemyCritAlsoKOs::
	ld d, AI_CRIT_CERTAIN
	ld a, 1
	call AIMoveCritCertain
	ccf
	ret c ; not crit-certain: the normal test stands
	ld a, 1
	call AIEstimateCritDamage
	farcall AIAdjustEnemyDamageForReliableDelivery
	farcall AIMoveWouldKO ; carry survives the farcall return
	ret
