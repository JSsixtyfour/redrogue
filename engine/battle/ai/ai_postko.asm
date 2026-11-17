; T2/T3 free replacements: prefer a usable reply over a type-chart tie.
; Separate from voluntary switching, which must pay an entry hit. No new RAM.
; $2C and $2E have only 135 and 305 bytes in the baseline; pin this independent
; farcalled leaf in $10 (2889 bytes free in all three baseline maps).
SECTION "AI Post KO", ROMX, BANK[$10]

; Private wBuffer aliases, live only during this post-KO pass. The called threat
; scan owns +4..13 and +20, the legacy ranker +0..3/+10/+17..19. No move-scoring
; layer or turn planner runs here. Do not overlap those owners.
DEF PK_BEST_TYPE EQU 14
DEF PK_SURVIVES EQU 21
DEF PK_QUALITY EQU 22
DEF PK_DAMAGE EQU 23 ; word, big endian
DEF PK_MOVE EQU 25
DEF PK_BEST_QUALITY EQU 26
DEF PK_BEST_DAMAGE EQU 27 ; word
DEF PK_BEST_SLOT EQU 29
DEF PK_MON_LENGTH EQU 29
ASSERT wEnemyMonPP + NUM_MOVES - wEnemyMon == PK_MON_LENGTH

; Candidates compare by quality tier, then the old type/health/status score,
; then expected attack damage, then party order (the enumeration already breaks
; exact ties). Damage beneath the legacy score: more damage short of a KO is no
; reason to send in a mon that matches up worse. A KO is its own tier (FINISH).
; If ALL reserves are threatened, their potential retaliation still breaks ties:
; the defensive scan uses maximum rolls/hit counts, not a certain prediction.
DEF PK_FINISH EQU 5 ; reliable immediate KO, with time to deliver it
DEF PK_SURVIVE_COMFORT EQU 4 ; survives and keeps the B5 margin (AI_RESERVE_HALF_KEEPS)
DEF PK_SURVIVE_REPLY EQU 3 ; survives, but the hit takes that margin
DEF PK_FIRST_REPLY EQU 2 ; fragile, but gets an attack before being KO'd
DEF PK_DOOMED EQU 1 ; damaging move, but no safe opportunity to deliver it
ASSERT PK_SURVIVE_COMFORT == PK_SURVIVE_REPLY + 1
ASSERT PK_FINISH > PK_SURVIVE_COMFORT

AIRankPostKOSendOut::
	farcall AIRankSendOutCandidates
	ld a, [wEnemyMonPartyPos]
	inc a
	ret z ; opening lead's defensive fallback, never a scored lead
	ld a, [wEnemyMonHP]
	ld hl, wEnemyMonHP + 1
	or [hl]
	ret nz ; unplanned voluntary switch: retain the original ranking
	ld a, [wBattleMonHP]
	ld hl, wBattleMonHP + 1
	or [hl]
	ret z ; double KO: there is no live opponent to evaluate yet
	farcall AIGetTier
	ld a, [wAITier] ; stored as tier + 1, not Bankswitch's destroyed a
	cp AI_TIER_SKILLED + 1
	ret c
; One living reserve is no choice: keep the legacy answer and skip ~265k
; cycles. FaintEnemyPokemon has already zeroed the fainted mon's party HP, so
; every living struct is a reserve (if that ever failed, this would only run
; the pass needlessly, never skip a real choice).
	ld hl, wEnemyMon1HP
	ld de, PARTYMON_STRUCT_LENGTH
	ld a, [wEnemyPartyCount]
	ld b, a
	ld c, 0
.countLiving
	ld a, [hli]
	or [hl]
	dec hl
	jr z, .notLiving
	inc c
.notLiving
	add hl, de
	dec b
	jr nz, .countLiving
	ld a, c
	cp 2
	ret c
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	cp $ff
	ret z
	ld [wBuffer + PK_BEST_SLOT], a
	ld a, [wBuffer + AI_BUF_BESTPARTYSCORE]
	ld [wBuffer + PK_BEST_TYPE], a
	xor a
	ld [wBuffer + PK_BEST_QUALITY], a
	ld [wBuffer + PK_BEST_DAMAGE], a
	ld [wBuffer + PK_BEST_DAMAGE + 1], a
; C0 cut 1 (2026-11-17): the scan below is pure computation, run at double speed
; on CGB with the 60 FPS option, exactly as AIShouldSwitchAtSelectedSpeed wraps
; the switch predicate. DMG, option-off and already-double callers are untouched.
; Placed after the early exits so a pass that does no work pays no speed switch.
	ldh a, [hGBC]
	and a
	jr z, .rankLoop
	ld a, [wOptions2]
	bit BIT_60_FPS, a
	jr z, .rankLoop
	ldh a, [rKEY1]
	bit 7, a
	jr nz, .rankLoop
	predef SetCPUSpeed
	call .rankLoop
	predef SingleCPUSpeed
	ret

; C0 cut 2 (2026-11-17): score every slot ONCE into PARTY_LENGTH stack bytes
; (score, or $ff = not a candidate), then take each next candidate from that
; array. Before, each step re-ran the legacy ranker (the since-removed
; AIRankRemainingSendOutCandidates): a threat-type rebuild plus a full re-score of
; every reserve (5 x 16.6k cycles measured on five
; reserves). Same order: lowest score first, a tie keeps the earlier slot, a
; skipped or ineligible slot never wins. wBuffer is full (30 of 30), hence the
; stack; the array sits at sp + 0 whenever the loop is at its own level.
.rankLoop
	add sp, -PARTY_LENGTH
	ld a, [wEnemyMonType1]
	push af
	ld a, [wEnemyMonType2]
	push af
	ld a, [wPlayerMoveType]
	push af
	ld e, 0 ; e = slot
.scoreSlot
	ld a, [wEnemyPartyCount]
	cp e
	jr z, .scored
	ld d, $ff ; not a candidate unless proven below
	ld a, [wEnemyMonPartyPos]
	cp e
	jr z, .storeScore ; never the mon that is out
	push de
	ld hl, wEnemyMon1HP
	ld a, e
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld a, [hli]
	or [hl]
	pop de
	jr z, .storeScore ; fainted
	push de
	farcall AIScoreSendOutSlot ; e in, e = score out (de survives the trip)
	ld a, e
	pop de
	ld d, a
.storeScore
	ld hl, sp + 6 ; past the three saved bytes
	ld a, l
	add e
	ld l, a
	adc h
	sub l
	ld h, a
	ld [hl], d
	inc e
	jr .scoreSlot
.scored
	pop af
	ld [wPlayerMoveType], a
	pop af
	ld [wEnemyMonType2], a
	pop af
	ld [wEnemyMonType1], a
; AIScoreSendOutSlot cleared the bound; the first candidate's own score is the
; legacy score the loop compares against.
	ld a, [wBuffer + PK_BEST_TYPE]
	ld [wBuffer + AI_BUF_BESTPARTYSCORE], a
.candidate
	call AIPostKOReply
	ld a, [wBuffer + PK_QUALITY]
	ld hl, wBuffer + PK_BEST_QUALITY
	cp [hl]
	jr c, .next
	jr nz, .better
; Same tier: the legacy score (lower is better) before damage. Enumeration is
; in nondecreasing score order, so this is normally a tie or a loss; the lower
; branch keeps the rule exact if that ever stops holding.
	ld a, [wBuffer + AI_BUF_BESTPARTYSCORE]
	ld hl, wBuffer + PK_BEST_TYPE
	cp [hl]
	jr c, .better
	jr nz, .next
	ld a, [wBuffer + PK_DAMAGE + 1]
	ld hl, wBuffer + PK_BEST_DAMAGE + 1
	sub [hl]
	ld a, [wBuffer + PK_DAMAGE]
	dec hl
	sbc [hl]
	jr c, .next
	jr nz, .better
	ld a, [wBuffer + PK_DAMAGE + 1]
	inc hl
	cp [hl]
	jr z, .next ; exact tie keeps the earlier legacy-ranked candidate
.better
	ld a, [wBuffer + PK_QUALITY]
	ld [wBuffer + PK_BEST_QUALITY], a
	ld a, [wBuffer + PK_DAMAGE]
	ld [wBuffer + PK_BEST_DAMAGE], a
	ld a, [wBuffer + PK_DAMAGE + 1]
	ld [wBuffer + PK_BEST_DAMAGE + 1], a
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	ld [wBuffer + PK_BEST_SLOT], a
	ld a, [wBuffer + AI_BUF_BESTPARTYSCORE]
	ld [wBuffer + PK_BEST_TYPE], a
.next
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	ld b, a
	ld a, 1
	inc b
.bit
	dec b
	jr z, .mark
	add a
	jr .bit
.mark
	ld hl, wBuffer + AI_BUF_SENDOUT_SKIP
	or [hl]
	ld [hl], a
; Next candidate from the cached scores (see .rankLoop).
	ld c, a ; c = skip mask, bit N = slot N, shifted out one slot at a time
	ld a, $ff
	ld [wBuffer + AI_BUF_BESTPARTYSLOT], a
	ld [wBuffer + AI_BUF_BESTPARTYSCORE], a
	ld hl, sp + 0
	ld e, 0
.pick
	ld a, [wEnemyPartyCount]
	cp e
	jr z, .picked
	ld a, [hli]
	srl c
	jr c, .pickNext ; already a candidate
	ld d, a
	ld a, [wBuffer + AI_BUF_BESTPARTYSCORE]
	cp d
	jr c, .pickNext ; the current best is lower
	jr z, .pickNext ; a tie keeps the earlier slot; $ff never beats the $ff start
	ld a, d
	ld [wBuffer + AI_BUF_BESTPARTYSCORE], a
	ld a, e
	ld [wBuffer + AI_BUF_BESTPARTYSLOT], a
.pickNext
	inc e
	jr .pick
.picked
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	cp $ff
	jp nz, .candidate
	add sp, PARTY_LENGTH
	ld a, [wBuffer + PK_BEST_SLOT]
	ld [wBuffer + AI_BUF_BESTPARTYSLOT], a
	ld a, [wBuffer + PK_BEST_TYPE]
	ld [wBuffer + AI_BUF_BESTPARTYSCORE], a
	xor a
	ld [wBuffer + AI_BUF_SENDOUT_SKIP], a
	ret

; Save byte blocks as stack words, including an odd trailing byte in AF. Used
; only inline: the snapshot remains below all helper return addresses.
MACRO pk_push
	FOR offset, 0, (\2 / 2) * 2, 2
		ld hl, \1 + offset
		ld a, [hli]
		ld h, [hl]
		ld l, a
		push hl
	ENDR
	IF \2 % 2
		ld a, [\1 + \2 - 1]
		push af
	ENDC
ENDM
MACRO pk_pop
	IF \2 % 2
		pop af
		ld [\1 + \2 - 1], a
	ENDC
	FOR index, 0, \2 / 2
		pop hl
		ld a, l
		ld [\1 + (\2 / 2 - 1 - index) * 2], a
		ld a, h
		ld [\1 + (\2 / 2 - 1 - index) * 2 + 1], a
	ENDR
ENDM

AIPostKOReply:
	xor a
	ld [wBuffer + PK_QUALITY], a
	ld [wBuffer + PK_DAMAGE], a
	ld [wBuffer + PK_DAMAGE + 1], a
	ld a, [wBuffer + AI_BUF_BESTPARTYSCORE]
	cp AI_SEND_OUT_SPENT
	ret z
; Ask the established uncached fair-play defensive scan before staging the
; attacker's full block. It preserves the live mon and active KO caches.
	farcall AIBestReserveSurvivesThreat
; PK_SURVIVES: 0 = KO'd, 1 = survives, 2 = survives with the B5 margin. The same
; scan leaves its answer in AI_BUF_RESERVEHALF at no extra cost: KEEPS means more
; than half its HP is left (a faster reserve) or 3x the hit is below its HP (a
; slower one, which takes a second hit before acting again). UNKNOWN (a Super
; Fang was scanned) is not a margin. KEEPS is only ever written with e = 1.
	ld a, [wBuffer + AI_BUF_RESERVEHALF]
	cp AI_RESERVE_HALF_KEEPS
	ld a, e
	jr nz, .storeSurvives
	inc a
.storeSurvives
	ld [wBuffer + PK_SURVIVES], a
	pk_push wEnemyMon, PK_MON_LENGTH
	pk_push wEnemyMoveNum, MOVE_LENGTH
	pk_push wEnemyBattleStatus1, 3
	pk_push wEnemyMonAccuracyMod, 1

; Match LoadEnemyMonFromParty's struct copies without its header, nickname,
; sprite, stage, or party-position side effects. Borrowed bytes are restored.
; CalcCritRate and GetEnemyMonStat publish identity/form from this staged struct
; themselves; their AI wrappers restore the previous global form context.
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	ld hl, wEnemyMon1
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld de, wEnemyMon
	ld bc, wEnemyMonDVs - wEnemyMon
	call CopyData
	ld bc, MON_DVS - MON_OTID
	add hl, bc
	ld de, wEnemyMonDVs
	ld bc, 2
	call CopyData
	ld de, wEnemyMonPP
	ld bc, NUM_MOVES
	call CopyData
	ld de, wEnemyMonLevel
	ld bc, 1 + NUM_STATS * 2
	call CopyData
	ld hl, wEnemyMonCatchRate
	bit BIT_GHOST_VARIANT, [hl]
	jr z, .typesReady
	ld a, GHOST
	ld [wEnemyMonType2], a
.typesReady
	xor a
	ld [wEnemyBattleStatus1], a
	ld [wEnemyBattleStatus2], a
	ld [wEnemyBattleStatus3], a
	ld [wBuffer + PK_MOVE], a
	ld a, 7
	ld [wEnemyMonAccuracyMod], a
	ldh a, [hWhoseTurn]
	push af
	farcall ApplyBurnAndParalysisPenaltiesToEnemy
	pop af
	ldh [hWhoseTurn], a
	ld a, [wEnemyMonStatus]
	and SLP_MASK | (1 << FRZ)
	jp nz, .restore ; not an immediate reply while asleep or frozen
.move
	ld a, [wBuffer + PK_MOVE]
	ld e, a
	ld d, 0
	ld hl, wEnemyMonPP
	add hl, de
	ld a, [hl]
	and PP_MASK
	jp z, .nextMove
	ld hl, wEnemyMonMoves
	add hl, de
	ld a, [hl]
	and a
	jp z, .nextMove
; ReadMove takes a and is bank-local. Copy the ROM row through FarCopyData
; instead of passing a across Bankswitch. It may clobber wBuffer[0], which the
; next legacy ranking explicitly rebuilds.
	dec a
	ld hl, Moves
	ld bc, MOVE_LENGTH
	call AddNTimes
	ld de, wEnemyMoveNum
	ld bc, MOVE_LENGTH
	ld a, BANK(Moves)
	call FarCopyData
	ld a, [wEnemyMoveNum]
	cp COUNTER
	jp z, .nextMove
	ld a, [wEnemyMoveEffect]
	cp CHARGE_EFFECT
	jp z, .nextMove
	cp FLY_EFFECT
	jp z, .nextMove
	cp DREAM_EATER_EFFECT
	jr nz, .estimate
	ld a, [wBattleMonStatus]
	and SLP_MASK
	jp z, .nextMove
.estimate
	farcall AIEstimateDamage
; One estimate per move: the reliable path scales wAIDamageEstimate in place,
; so keep the raw word and restore it for the expected path. Nothing downstream
; reads any other output of the estimate (re-estimating cost ~20k cycles a move).
	ld hl, wAIDamageEstimate
	ld a, [hli]
	ld l, [hl]
	ld h, a
	push hl
	farcall AIAdjustEnemyDamageForReliableDelivery
	farcall AIMoveIsReliableKO
	pop hl ; flags survive
	push af ; reliable KO flag
	ld a, h
	ld [wAIDamageEstimate], a
	ld a, l
	ld [wAIDamageEstimate + 1], a
	farcall AIScaleDamageForCrit
	farcall AIAdjustEnemyDamageForExpectedDelivery
	farcall AIScaleDamageByAccuracy
	pop bc ; carry from the reliable KO test is bit 4 of c
	ld a, [wAIDamageEstimate]
	ld hl, wAIDamageEstimate + 1
	or [hl]
	jp z, .nextMove
	push bc
	farcall AIEnemyActsFirstWith
	pop bc
	ld a, PK_FIRST_REPLY
	jr c, .canReply
	ld a, [wBuffer + PK_SURVIVES]
	and a
	ld a, PK_DOOMED
	jr z, .qualityReady
.canReply
	ld a, [wBuffer + PK_SURVIVES]
	and a
	ld a, PK_FIRST_REPLY
	jr z, .checkFinish
	ld a, [wBuffer + PK_SURVIVES]
	add PK_SURVIVE_REPLY - 1 ; 1 -> SURVIVE_REPLY, 2 -> SURVIVE_COMFORT
.checkFinish
	ld b, a
	ld a, [wEnemyMoveEffect]
	cp EXPLODE_EFFECT
	ld a, PK_FIRST_REPLY ; a trade never outranks a surviving reply or finish
	jr z, .qualityReady
	ld a, b
	bit 4, c
	jr z, .qualityReady
	ld a, PK_FINISH
.qualityReady
	ld hl, wBuffer + PK_QUALITY
	cp [hl]
	jr c, .nextMove
	jr nz, .bestMove
	ld a, [wAIDamageEstimate + 1]
	ld hl, wBuffer + PK_DAMAGE + 1
	sub [hl]
	ld a, [wAIDamageEstimate]
	dec hl
	sbc [hl]
	jr c, .nextMove
	ld a, [wBuffer + PK_QUALITY]
.bestMove
	ld [wBuffer + PK_QUALITY], a
	ld a, [wAIDamageEstimate]
	ld [wBuffer + PK_DAMAGE], a
	ld a, [wAIDamageEstimate + 1]
	ld [wBuffer + PK_DAMAGE + 1], a
.nextMove
	ld hl, wBuffer + PK_MOVE
	inc [hl]
	ld a, [hl]
	cp NUM_MOVES
	jp c, .move
.restore
	pk_pop wEnemyMonAccuracyMod, 1
	pk_pop wEnemyBattleStatus1, 3
	pk_pop wEnemyMoveNum, MOVE_LENGTH
	pk_pop wEnemyMon, PK_MON_LENGTH
	ret

PURGE pk_push, pk_pop
