; Setup gate (2026-11-12, follow-on to FOLLOWUPS #61). INCLUDEd into "Battle
; Engine 7" (bank $0E) with the other layers: AI_DAMAGE and AI_PLAN plain-call it.
;
; THE QUESTION. Setting up spends a turn. What it costs is the extra hit the foe
; lands because we did not attack, so a boost is withheld only when BOTH hold:
;   (a) it costs a turn: it does not cut our best move's hits-to-KO on the
;       player's current HP by at least one (only Attack and Special boosts of
;       the best move's own category can do that: from the neutral stage +2
;       counts x2 and +1 x1.5; from any other stage, or a stat of 500+, the
;       boosted stat is projected and estimated, CP5: see AISetupTempo);
;   (b) that turn hurts: we would not live to act again. A faster mon sets up,
;       takes ONE hit and acts first next turn; a slower one takes this turn's
;       hit and next turn's before it acts, so TWO. The hit is the foe's best
;       believed one (AIPlayerWouldKO's fair-play scan, max roll). An Explosion
;       its species can learn (AIPlayerSpeciesCanExplode) counts once, since the
;       foe faints using it: it hurts only if it KOs outright.
; v2 (2026-11-12, measured on 250 autoplay seeds of setups that ran, T2+): a
; slower mon wasted 41-42% of its boosts, a faster one 11-16%; the first gate
; used the two-hit rule for both and cut the two alike, so its wasted rate did
; not move.
; Measured on a faster Pidgeot (157 HP, Take Down / Swords Dance) with reserves
; behind the foe: Swords Dance was picked into everything. Electabuzz takes 70%
; a hit, but Take Down needs 2 hits now and 1 after +2, so the boost costs no
; extra hit: allowed. A 30-HP Golem, Electrode or Cloyster dies to one Take Down
; anyway, and hits for 59-70%: withheld. A 30-HP Gengar hits for only 29% with
; what the AI believes it has, but its Explosion does 52-61%: withheld.
;
; EXEMPT: we have a Substitute up (the hit lands on it). v2 dropped the old
; "blunts the hit" exemption (Defense vs physical, Special vs special): those
; defensive boosts were the most wasted kind of all, 59% in the same data.
;
; WHO ASKS. AI_DAMAGE takes back AI_SETUP's turn-1 encourage (AISetupGate), and
; AI_PLAN skips each boost slot whose own effect is withheld (its apply loop,
; AIPlanSlotBoostWithheld, AI review CP6). T1 has no
; AI_DAMAGE, so its AI_SETUP encourage is not gated: the weakest tier keeps its
; blunt setup habit.

; From AILayerDamage.applyBest, after the #61 end-of-battle test. Fills the tempo
; bits for AI_PLAN, then takes back AI_SETUP's encourage on every slot that #61
; or the gate rejects. Clobbers af, bc, de, hl.
AISetupGate:
	call AISetupTempo
	ld a, [wBuffer + AI_BUF_SETUPMASK]
	and a
	ret z ; AI_SETUP encouraged nothing (it fires on a send-out's first turn only)
	ld c, a ; c = slots still to visit
	ld b, 0 ; b = slot
.slot
	srl c
	jr nc, .next
	push bc
	ld hl, wEnemyMonMoves
	ld e, b
	ld d, 0
	add hl, de
	ld a, [hl]
	call ReadMove ; preserves bc, de, hl
; AI_SETUP's vanilla effect ranges also take in a few damaging moves (Swift and
; Pay Day sit between the stat effects). Attacking spends no turn, and under #61
; such a move may be the very KO, so its encourage is never taken back.
	ld a, [wEnemyMovePower]
	and a
	jr nz, .keep
	ld a, [wAIReliableKOFound]
	bit AI_KO_ENDS_BATTLE_BIT, a
	jr nz, .withdrawn ; #61: one hit could win the battle
	ld a, [wEnemyMoveEffect]
	call AISetupWithheld
	jr nc, .keep
.withdrawn
	pop bc ; b = the slot again (AISetupWithheld clobbers bc)
	push bc
	ld hl, wBuffer
	ld e, b
	ld d, 0
	add hl, de
	ld a, AI_STRONG ; AI_SETUP's magnitude
	call AIDiscourage
.keep
	pop bc
.next
	inc b
	ld a, c
	and a
	jr nz, .slot
	ret

; Sets the AI_SG_*_FREE bits from AI_DAMAGE's best move (AI_BUF_BESTSLOT), and
; clears the rest of the byte, which until now held AI_SETUP's AI_BUF_PHYSICAL. A boost of the best
; move's category is free when n(boosted) + 1 <= n(now), n = hits-to-KO on the
; player's current HP. Clobbers af, bc, de, hl.
AISetupTempo:
	xor a
	ld [wBuffer + AI_BUF_SETUPGATE], a
	ld a, [wBuffer + AI_BUF_BESTSLOT]
	cp NUM_MOVES
	ret nc ; no damaging move
	ld e, a
	ld d, 0
	ld hl, wEnemyMonMoves
	add hl, de
	ld a, [hl]
	call ReadMove
	ld a, [wEnemyMovePower]
	cp 2
	ret c ; fixed damage (power 0-1) ignores Attack and Special
	ld a, [wEnemyMoveType]
	cp SPECIAL ; Gen 1: the type alone decides physical or special
	ld c, (1 << AI_SG_ATK2_FREE_BIT) | (1 << AI_SG_ATK1_FREE_BIT) ; ld keeps the flags
	jr c, .gotCategory
	ld c, (1 << AI_SG_SPC2_FREE_BIT) | (1 << AI_SG_SPC1_FREE_BIT)
.gotCategory
; D is one hit's damage as the hit lands: NOT AI_BUF_BESTDMG, which is capped at
; the player's HP and then scaled by accuracy. Measured: Take Down KOs a 30-HP
; foe in one hit, but 30 x 85% = 25 read as a 2HKO, and Swords Dance as free.
; Accuracy is whether a hit lands, not how many it takes. The estimate is cached
; for the decision, so this is a cache read.
	push bc
	call AIEstimateEnemyDamage
	call AIAdjustEnemyDamageForExpectedDelivery ; multi-hit moves count their hits
	pop bc
	ld a, [wAIDamageEstimate]
	ld d, a
	ld a, [wAIDamageEstimate + 1]
	ld e, a ; de = D
	call AIHitsToKO
	ld b, a ; b = n(D)
; Stage-aware (AI review CP5, 2026-11-13): x2 and x1.5 hold only from the neutral
; stage, below the cap. From +2 another +2 is x1.5 (2x -> 3x), at +6 nothing,
; from -1 x2.25, and a stat of 500+ doubles into the 999 cap. Off those, the
; boosted stat is projected as the stat-up effect computes it and estimated
; uncached (~12k cycles per boost). The neutral case keeps the free multiply.
	push de
	call AISetupStatPointers
	ld a, [hl]
	cp BASE_STAT_LEVEL
	jr nz, .exact
	ld a, [de]
	ld h, a
	inc de
	ld a, [de]
	sub LOW(MAX_STAT_VALUE / 2 + 1)
	ld a, h
	sbc HIGH(MAX_STAT_VALUE / 2 + 1)
	jr nc, .exact ; 500 or more: x2 passes the cap
	pop de
	push de
	sla e
	rl d ; 2D: D is capped near the player's HP, so no overflow
	call AIHitsToKO
	pop de
	inc a
	cp b
	jr z, .twoFree
	ret nc ; x2 costs a turn, so x1.5 does too
.twoFree
	ld h, d
	ld l, e
	srl d
	rr e
	add hl, de
	ld d, h
	ld e, l ; de = 1.5D
	call AIHitsToKO
	jr .judgeOne
.exact
	pop de
	ld a, 2
	call AISetupHitsAtBoost
	inc a
	cp b
	jr z, .exactTwoFree
	ret nc
.exactTwoFree
	ld a, 1
	call AISetupHitsAtBoost
.judgeOne
	inc a
	cp b
	ld a, (1 << AI_SG_ATK2_FREE_BIT) | (1 << AI_SG_SPC2_FREE_BIT) ; ld keeps the flags
	jr z, .oneFree
	jr nc, .store
.oneFree
	ld a, AI_SG_FREE_MASK
.store
	and c
	ld [wBuffer + AI_BUF_SETUPGATE], a
	ret

; INPUT c = AISetupTempo's category bits. OUTPUT hl = our stage byte and de = our
; unmodified stat for that category (Attack if the ATK bits, else Special).
AISetupStatPointers:
	ld hl, wEnemyMonAttackMod
	ld de, wEnemyMonUnmodifiedAttack
	bit AI_SG_ATK2_FREE_BIT, c
	ret nz
	ld hl, wEnemyMonSpecialMod
	ld de, wEnemyMonUnmodifiedSpecial
	ret

; INPUT a = a boost (1 or 2), c = AISetupTempo's category bits, the best move
; loaded (ReadMove). OUTPUT a = hits to KO the player (AIHitsToKO) with our stat
; at the boosted stage; AI_SG_MAX_HITS + 1 when the stage is already +6. The stat
; is the one effects.asm's stat-up computes (unmodified x stage ratio, capped at
; 999, minimum 1), halved again for a burned Attack as ApplySelfTargetStatPenalty
; re-applies it. It is staged in wEnemyMonAttack / Special for one UNCACHED
; estimate (the slot cache holds the real stat's answer) and put back.
; Preserves bc. Clobbers af, de, hl.
AISetupHitsAtBoost:
	push bc
	call AISetupStatPointers
	add [hl]
	cp MAX_STAT_LEVEL + 1
	jr c, .inRange
	ld a, MAX_STAT_LEVEL
.inRange
	cp [hl]
	jr z, .noGain ; already +6
	ld h, d
	ld l, e
	ld b, 0 ; none of the Speed-only adjustments
	call AIPredictSpeedAtStage ; de = the boosted stat
	pop bc
	push bc
	ld hl, wEnemyMonAttack
	bit AI_SG_ATK2_FREE_BIT, c
	jr z, .special
	ld a, [wEnemyMonStatus]
	bit BRN, a
	jr z, .stage
	srl d
	rr e
	ld a, d
	or e
	jr nz, .stage
	inc e
	jr .stage
.special
	ld hl, wEnemyMonSpecial
.stage
	ld a, [hl]
	ld b, a
	ld [hl], d
	inc hl
	ld a, [hl]
	ld c, a ; bc = the real stat
	ld [hl], e
	push hl
	push bc
	farcall AIEstimateDamage
	call AIAdjustEnemyDamageForExpectedDelivery
	pop bc
	pop hl
	ld [hl], c
	dec hl
	ld [hl], b
	ld a, [wAIDamageEstimate]
	ld d, a
	ld a, [wAIDamageEstimate + 1]
	ld e, a
	call AIHitsToKO
	pop bc
	ret
.noGain
	pop bc
	ld a, AI_SG_MAX_HITS + 1
	ret

; INPUT de = damage per hit. OUTPUT a = the smallest n (1 to AI_SG_MAX_HITS) with
; n * de >= the player's current HP, else AI_SG_MAX_HITS + 1 (also for de = 0).
; Preserves bc, de. Clobbers hl.
AIHitsToKO:
	ld a, [wBattleMonHP]
	ld h, a
	ld a, [wBattleMonHP + 1]
	ld l, a
	ld a, d
	or e
	ld a, AI_SG_MAX_HITS + 1
	ret z
	push bc
	ld b, 0
.hit
	inc b
	ld a, l
	sub e
	ld l, a
	ld a, h
	sbc d
	ld h, a
	jr c, .reached
	or l
	jr z, .reached
	ld a, b
	cp AI_SG_MAX_HITS
	jr c, .hit
	inc b
.reached
	ld a, b
	pop bc
	ret

; INPUT a = a setup move's effect. Carry SET = withhold its push: it costs a
; turn (see the header) and the foe's extra hit hurts. Uses the AI_SG_* bits
; AISetupTempo left, so it is valid from AI_DAMAGE's .applyBest on.
; Clobbers af, bc, de, hl.
AISetupWithheld:
	ld b, a ; b = effect
; Only stat raises and drops are setup in this sense. AI_SETUP's vanilla ranges
; also take in Recover/Rest, Reflect, Light Screen, Haze, Transform and
; Conversion: healing when the foe hits hard is the point of healing, and a
; screen is the answer to it (found by the AI scenarios, 2026-11-12: a 1/3-HP
; Chansey's Recover lost its encourage). Those are left to their own layers.
	cp ATTACK_UP1_EFFECT
	jr c, .allow
	cp EVASION_UP1_EFFECT + 1
	jr c, .statMove
	cp ATTACK_DOWN1_EFFECT
	jr c, .allow
	cp EVASION_DOWN1_EFFECT + 1
	jr c, .statMove
	cp ATTACK_UP2_EFFECT
	jr c, .allow
	cp EVASION_UP2_EFFECT + 1
	jr c, .statMove
	cp ATTACK_DOWN2_EFFECT
	jr c, .allow
	cp EVASION_DOWN2_EFFECT + 1
	jr nc, .allow
.statMove
	ld a, [wEnemyBattleStatus2]
	bit HAS_SUBSTITUTE_UP, a
	jr nz, .allow ; the extra hit lands on our Substitute
	ld a, [wBuffer + AI_BUF_SETUPGATE]
	ld c, a
	ld hl, .freeBits
.find
	ld a, [hli]
	and a
	jr z, .costsATurn ; table end: this boost never shortens a KO
	cp b
	ld a, [hli] ; ld keeps the flags
	jr nz, .find
	and c
	jr nz, .allow ; it cuts a hit off our KO
.costsATurn
	jp AISetupExtraHitHurts ; carry = we would not live to act again: withhold
.allow
	and a
	ret

.freeBits ; effect, the AI_SG bit that says it shortens our KO
	db ATTACK_UP2_EFFECT,  1 << AI_SG_ATK2_FREE_BIT
	db SPECIAL_UP2_EFFECT, 1 << AI_SG_SPC2_FREE_BIT
	db ATTACK_UP1_EFFECT,  1 << AI_SG_ATK1_FREE_BIT
	db SPECIAL_UP1_EFFECT, 1 << AI_SG_SPC1_FREE_BIT
	db 0 ; NO_ADDITIONAL_EFFECT is never a setup effect

; Carry SET if we would not live to act again after setting up (see the header):
; the foe's best believed hit (AIPlayerWouldKO's scan, max roll) KOs us, or, when
; we are slower, two of them do; or the Explosion its species can learn KOs us. Cached in AI_BUF_SETUPGATE for the decision, so AI_DAMAGE
; and AI_PLAN pay once. Clobbers af, bc, de, hl.
AISetupExtraHitHurts:
	ld hl, wBuffer + AI_BUF_SETUPGATE
	bit AI_SG_HURTS_KNOWN_BIT, [hl]
	jr nz, .answer
	set AI_SG_HURTS_KNOWN_BIT, [hl]
	call AIPlayerWouldKO ; cached for the decision
	jr c, .hurts
	ld a, [wAIPlayerKOMaxDamage]
	and LOW(~((1 << AI_KO_MAX_VALID_BIT) | (1 << AI_KO_MAX_PARTIAL_BIT)))
	ld d, a
	ld a, [wAIPlayerKOMaxDamage + 1]
	ld e, a ; de = the largest believed delivery (a full scan: no KO was found)
	push de
	call AIEnemyIsFaster ; carry = we act first; clobbers af, bc, de
	pop de
	jr c, .explosion ; faster: one hit before we act, and it does not KO
	call AIDamageTakesHalf ; slower: two hits
	jr c, .hurts
.explosion
; When the AI knows the whole moveset, the scan above already weighed every real
; move, Explosion included if it is one: the species guess would only add a move
; the player has been seen not to carry.
	call AIPlayerMovesetKnown
	jr c, .answer
	farcall AIPlayerSpeciesCanExplode ; flags survive the farcall return
	jr nc, .answer
	call AIEstimatePlayerExplosion
	call AIDamageKillsUs ; once: the foe faints using it
	jr nc, .answer
	ld hl, wBuffer + AI_BUF_SETUPGATE
	set AI_SG_BOOM_BIT, [hl]
.hurts
	ld hl, wBuffer + AI_BUF_SETUPGATE
	set AI_SG_HURTS_BIT, [hl]
.answer
	ld a, [wBuffer + AI_BUF_SETUPGATE]
	and 1 << AI_SG_HURTS_BIT
	ret z ; and clears the carry
	scf
	ret

; Carry SET if the AI knows the player's whole active moveset: an omniscient
; class (AIPlayerMovesAreKnown), or this party member has used every move it
; holds (wAISeenPlayerMoveMask, laid out as in AIGetPlayerMoveN).
; Clobbers af, bc, de, hl.
AIPlayerMovesetKnown:
	call AIPlayerMovesAreKnown
	ret c
	ld a, [wPlayerMonNumber]
	ld e, a
	srl a ; a = mask byte
	ld hl, wAISeenPlayerMoveMask
	add l
	ld l, a
	jr nc, .gotByte
	inc h
.gotByte
	ld a, [hl]
	bit 0, e
	jr z, .gotNibble
	swap a ; odd party slot: its bits are the high nibble
.gotNibble
	and $0f
	ld c, a ; c = this mon's seen slots
	ld hl, wBattleMonMoves
	ld b, 1 ; b = this slot's bit
.slot
	ld a, [hli]
	and a
	jr z, .next ; no move in this slot
	ld a, c
	and b
	ret z ; a move not yet seen (and `and` cleared the carry)
.next
	sla b
	bit 4, b
	jr z, .slot
	scf
	ret

; Carry SET if 2 * de >= our (the enemy mon's) current HP. de is a damage value
; of at most $1383, so 2de fits. Clobbers af, de, hl.
AIDamageTakesHalf:
	sla e
	rl d
; Carry SET if de >= our current HP. Clobbers af, hl.
AIDamageKillsUs:
	ld hl, wEnemyMonHP + 1
	ld a, e
	sub [hl]
	dec hl
	ld a, d
	sbc [hl] ; carry iff 2de < HP
	ccf
	ret

; OUTPUT de = the possible delivery of the player's Explosion into us (the
; engine formula, so the halved Defense is included). Borrows the wPlayerMove*
; block as _AIScanPlayerMovesForKO does and puts it back. Clobbers af, bc, hl.
AIEstimatePlayerExplosion:
	ld hl, wPlayerMoveNum
	ld de, wBuffer + AI_BUF_MOVESAVE
	ld bc, MOVE_LENGTH
	call CopyData
	ld a, EXPLOSION
	call AIReadMoveIntoPlayerBlock
	farcall AIEstimatePlayerMoveDamage
	call AIAdjustPlayerDamageForPossibleDelivery
	ld a, [wAIDamageEstimate]
	ld d, a
	ld a, [wAIDamageEstimate + 1]
	ld e, a
	push de
	call _AIScanPlayerMovesForKO.restorePlayerMove
	pop de
	ret
