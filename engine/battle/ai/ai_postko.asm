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

; The ranking pass serves two callers (AI_T4_REGRET_PLAN E2, 2026-11-17):
; FAINT, a free replacement after a faint (AIRankPostKOSendOut), and VOLUNTARY, a
; T3 switch target that first takes the player's hit on entry
; (AIRankVoluntaryTarget). Mode and score bound ride in the loop's stack frame.
DEF PK_MODE_FAINT EQU 0
DEF PK_MODE_VOLUNTARY EQU 1
DEF PK_FRAME_MODE EQU PARTY_LENGTH
DEF PK_FRAME_BOUND EQU PARTY_LENGTH + 1
DEF PK_FRAME_SIZE EQU PARTY_LENGTH + 2

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
	ld de, PK_MODE_FAINT << 8 | $ff ; d = mode, e = score bound ($ff: none)
; INPUT d = PK_MODE_*, e = the legacy score a candidate must stay strictly below
; (AIRankVoluntaryTarget's "beats the active mon" gate). Both survive the predefs.
.rankWithSpeed
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
; Stack frame at the loop's own level: sp + 0 the score array, sp + PK_FRAME_MODE
; the mode, sp + PK_FRAME_BOUND the bound (AIPostKOReply reads the mode 2 higher).
	add sp, -PK_FRAME_SIZE
	ld hl, sp + PK_FRAME_MODE
	ld [hl], d
	inc hl
	ld [hl], e
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
; legacy score the loop compares against. Read it from the array: in VOLUNTARY
; mode PK_BEST_TYPE holds the fallback's 0 floor, not this score.
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	ld hl, sp + 0
	add l
	ld l, a
	adc h
	sub l
	ld h, a
	ld a, [hl]
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
	jr z, .rankDone
; The bound (voluntary mode): scores come in nondecreasing order, so the first
; one at or above the bound ends the enumeration. A faint replacement's bound is
; $ff, which no score reaches.
	ld hl, sp + PK_FRAME_BOUND
	ld a, [wBuffer + AI_BUF_BESTPARTYSCORE]
	cp [hl]
	jr nc, .rankDone
; C0 cut 4 (2026-11-17), exact: candidates come in nondecreasing legacy score and
; compare by tier, then LOWER legacy score, then damage, and FINISH is the top
; tier. Once a FINISH leads, a candidate scoring strictly above its legacy score
; cannot win, and every later one scores at least as much: stop. A tie on the
; score is still scanned, since it can win on damage.
	ld a, [wBuffer + PK_BEST_QUALITY]
	cp PK_FINISH
	jp nz, .candidate
	ld a, [wBuffer + PK_BEST_TYPE]
	ld hl, wBuffer + AI_BUF_BESTPARTYSCORE
	cp [hl]
	jp nc, .candidate ; the next score is not above the leader's: it can still tie
.rankDone
	add sp, PK_FRAME_SIZE
	ld a, [wBuffer + PK_BEST_SLOT]
	ld [wBuffer + AI_BUF_BESTPARTYSLOT], a
	ld a, [wBuffer + PK_BEST_TYPE]
	ld [wBuffer + AI_BUF_BESTPARTYSCORE], a
	xor a
	ld [wBuffer + AI_BUF_SENDOUT_SKIP], a
	ret

; T3 voluntary switch target (AI_T4_REGRET_PLAN E2, 2026-11-17). Farcalled from
; AIShouldSwitch ($2C) once a switch trigger has found a better reserve that
; survives (AIReplacementIsBetterAndSurvives): wBuffer + AI_BUF_BESTPARTYSLOT is
; that reserve, kept as the fallback. Re-ranks every reserve that beats the
; active mon's legacy score (the same gate) with the post-KO tiers in VOLUNTARY
; mode, then re-runs B4 on the slot chosen so B5 (AISacrificeBeatsSwitch) judges
; it. T2 keeps the old pick. No register inputs; clobbers af, bc, de, hl.
AIRankVoluntaryTarget::
	farcall AIGetTier
	ld a, [wAITier] ; tier + 1
	cp AI_TIER_EXPERT + 1
	ret c
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	ld [wBuffer + PK_BEST_SLOT], a
; The bound: the active mon's own legacy score, on its live battle struct.
	farcall AIBuildPlayerThreatTypes
	ld a, [wEnemyMonType1]
	push af
	ld a, [wEnemyMonType2]
	push af
	ld a, [wPlayerMoveType]
	push af
	farcall AIScoreActiveMon ; e = score (de survives the trip)
	pop af
	ld [wPlayerMoveType], a
	pop af
	ld [wEnemyMonType2], a
	pop af
	ld [wEnemyMonType1], a
	push de
	farcall AIRankSendOutCandidates ; the first candidate, in legacy order
	pop de
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	cp $ff
	jr z, .keep
	ld a, [wBuffer + AI_BUF_BESTPARTYSCORE]
	cp e
	jr nc, .keep ; nothing beats the active mon (the caller proved otherwise)
; The fallback sits at quality 0 with score 0, so only a candidate with a real
; tier displaces it: one KO'd on entry also scores quality 0 and loses the tie.
	xor a
	ld [wBuffer + PK_BEST_TYPE], a
	ld [wBuffer + PK_BEST_QUALITY], a
	ld [wBuffer + PK_BEST_DAMAGE], a
	ld [wBuffer + PK_BEST_DAMAGE + 1], a
	ld d, PK_MODE_VOLUNTARY
	call AIRankPostKOSendOut.rankWithSpeed
	jr .rescan
.keep
	ld a, [wBuffer + PK_BEST_SLOT]
	ld [wBuffer + AI_BUF_BESTPARTYSLOT], a
	xor a
	ld [wBuffer + AI_BUF_SENDOUT_SKIP], a
.rescan
	farcall AIBestReserveSurvivesThreat ; B4 for the chosen slot, read by B5
	ret

; B17's first term, a stalemate breaker (AI_T4_REGRET_PLAN, 2026-11-17). Carry SET
; if the active mon has NOTHING it is willing to do that deals damage this turn:
; no move with PP, not disabled, whose estimate in wAIEnemyEstimateCache (filled
; by AI_DAMAGE this decision, T2+) is above zero, except Self-Destruct/Explosion
; that the AI did not choose (the Explosion veto refused the trade). Measured:
; seed 288's Weezing (Amnesia / Self-Destruct / Haze / Explosion) against a 27-HP
; Ekans looped Amnesia and Haze ~30 turns, each costing +0.22 of party HP, while a
; switch won; a plain "every estimate is 0" test misses it, Explosion's is 999.
; No register inputs; clobbers af, bc, de, hl.
AIActiveCanDoNothing::
; While the player takes residual damage every turn (poisoned, badly poisoned,
; burned, or Leech Seeded), stalling IS progress: the poison or seed is doing the
; damage, so any staller (Toxic then Double Team / Rest / Reflect, or any other
; moveset) stays in while it ticks.
	ld a, [wBattleMonStatus]
	and (1 << PSN) | (1 << BRN)
	jp nz, .canAct
	ld a, [wPlayerBattleStatus2]
	bit SEEDED, a
	jp nz, .canAct
; A status move the AI CHOSE is progress, not a stalemate: sleep, paralysis,
; poison or confusion on the player changes the board even though it deals no
; damage, so a status user keeps using it.
; Boosts, Haze and screens are not on the list: against a foe we cannot damage
; they buy nothing, which is exactly seed 288's Amnesia/Haze loop.
	ld a, [wEnemySelectedMove]
	and a
	jr z, .scan
	ld b, a
	ld e, MOVE_EFFECT
	call .moveByte
	ld hl, .progressEffects
.progressLoop
	cp [hl]
	jr z, .canAct
	inc hl
	ld c, a
	ld a, [hl]
	inc a ; $ff ends the table
	ld a, c
	jr nz, .progressLoop
.scan
	ld c, 0 ; c = slot
.slot
	ld hl, wEnemyMonMoves
	call .index
	ld a, [hl]
	and a
	jr z, .next
	ld b, a ; b = move id
	ld hl, wEnemyMonPP
	call .index
	ld a, [hl]
	and PP_MASK
	jr z, .next
	ld a, [wEnemyDisabledMoveNumber]
	cp b
	jr z, .next
	ld hl, wAIEnemyEstimateCache
	call .index
	call .index ; two bytes per slot
	ld a, [hli]
	bit AI_ESTIMATE_VALID_BIT, a
	jr z, .unestimated
	and ~(1 << AI_ESTIMATE_VALID_BIT)
	or [hl]
	jr z, .next ; estimated at zero (an immunity)
	ld a, b
	cp SELFDESTRUCT
	jr z, .selfKO
	cp EXPLOSION
	jr nz, .canAct
.selfKO
	ld a, [wEnemyMoveListIndex]
	cp c
	jr z, .canAct ; it chose the trade: let it go through
.next
	inc c
	ld a, c
	cp NUM_MOVES
	jr c, .slot
	scf
	ret
.canAct
	and a
	ret
; No estimate this decision. AI_DAMAGE (T2+) estimates every damaging move it
; can use, so in play this is a status move; but do not depend on that: read the
; move's power from ROM, and count a damaging move with no estimate as usable
; (never call a stalemate on missing data).
.unestimated
	ld e, MOVE_POWER
	call .moveByte
	and a
	jr z, .next ; a status move: not a way to deal damage
	jr .canAct
; a = one byte of move b's ROM row: field offset e (MOVE_EFFECT, MOVE_POWER...).
; Preserves bc; clobbers de, hl.
.moveByte
	push bc
	ld a, b
	dec a
	ld hl, Moves
	ld d, 0
	add hl, de
	ld bc, MOVE_LENGTH
	call AddNTimes ; hl = that byte, in BANK(Moves)
	push af ; two bytes of stack scratch: the copy lands where a pops from
	ld d, h
	ld e, l
	ld hl, sp + 1
	ld b, h
	ld c, l
	ld h, d
	ld l, e
	ld d, b
	ld e, c
	ld bc, 1
	ld a, BANK(Moves)
	call FarCopyData
	pop af
	pop bc
	ret
.progressEffects
	db SLEEP_EFFECT, POISON_EFFECT, PARALYZE_EFFECT, CONFUSION_EFFECT
	db LEECH_SEED_EFFECT, DISABLE_EFFECT, $ff
.index ; hl += c
	ld a, l
	add c
	ld l, a
	ret nc
	inc h
	ret

; Target for that stalemate switch. Carry SET with wBuffer + AI_BUF_BESTPARTYSLOT =
; a reserve that, ranked in VOLUNTARY mode (after the entry hit), survives and
; replies: PK_SURVIVE_REPLY or better. Unlike AIRankVoluntaryTarget there is no
; "beats the active mon's legacy score" gate: a mon that can do nothing is not
; worth keeping in for its typing. Carry clear = no such reserve, stay.
; No register inputs; clobbers af, bc, de, hl.
AIRankStalemateTarget::
	farcall AIRankSendOutCandidates
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	cp $ff
	jr z, .none
	ld [wBuffer + PK_BEST_SLOT], a
; The floor sits just under SURVIVE_REPLY with score 0 and maximal damage, so a
; candidate only displaces it with a higher tier.
	xor a
	ld [wBuffer + PK_BEST_TYPE], a
	ld a, PK_SURVIVE_REPLY - 1
	ld [wBuffer + PK_BEST_QUALITY], a
	ld a, $ff
	ld [wBuffer + PK_BEST_DAMAGE], a
	ld [wBuffer + PK_BEST_DAMAGE + 1], a
	ld de, PK_MODE_VOLUNTARY << 8 | $ff
	call AIRankPostKOSendOut.rankWithSpeed
	ld a, [wBuffer + PK_BEST_QUALITY]
	cp PK_SURVIVE_REPLY ; carry iff still the floor
	ccf
	ret
.none
	and a
	ret

; E6.2 heal race (Pokemon Stadium 2's "heal worth double", fragment79_3BC290.c).
; Carry SET if the loaded heal move (Recover / Softboiled; never Rest, whose two
; sleep turns are a different trade) out-paces the player: we act first and half
; our max HP (the heal, an engine fact) exceeds the player's best POSSIBLE hit
; (AIPlayerWouldKO's believed-moveset scan, max roll). Measured 2026-11-18 (AI
; backlog B21.2, 200 forced states, Recover in slot 0): faster + out-paces beat
; the best other move by +0.075 / +0.045 / +0.072 at 30 / 45 / 60% HP, all
; significant; faster without out-pacing and slower were ~0 or negative.
; Farcalled from AISmart_Heal ($0E, which has no room for it).
; No register inputs; clobbers af, bc, de, hl.
AIHealOutpaces::
	ld a, [wEnemyMoveNum]
	cp REST
	jr z, .no
	farcall AIEnemyIsFaster ; carry = faster; survives the return
	jr nc, .no
	farcall AIPlayerWouldKO ; carry = KOs us this turn; fills wAIPlayerKOMaxDamage
	jr c, .no
	ld hl, wAIPlayerKOMaxDamage
	ld a, [hli]
	bit 7, a ; valid
	jr z, .no
	and %00111111 ; drop the valid / lower-bound flags
	ld d, a
	ld e, [hl] ; de = the player's best possible hit
	ld hl, wEnemyMonMaxHP
	ld a, [hli]
	ld b, a
	ld c, [hl]
	srl b
	rr c ; bc = the heal
	ld a, e
	sub c
	ld a, d
	sbc b ; carry iff the hit < the heal
	ret
.no
	and a
	ret

; AISmart_Haze's verdict (moved from $0E, which has no room for the KO test).
; INPUT d = what Haze gains us, e = what it costs (that handler's tallies).
; OUTPUT e = the magnitude and carry = encourage, the AI_SMART handler contract
; carried in e because a farcall returns nothing in a. Net +2 or more encourages
; strongly, +1 mildly, 0 not at all, negative discourages strongly.
; A net gain is DECISIVE when Haze takes a boosted KO away: the player holds an
; Attack or Special stage of +AI_HAZE_KO_STAGES or more, we act first (Haze
; lands before the hit), and its best believed hit KOs us (AIPlayerWouldKO, max
; roll). Measured 2026-11-18 (AI backlog B21, 400 forced states, Haze in slot 0,
; the player boosted in the stat its best move uses): faster with the boost
; turning a 2-3 hit KO into a 1-hit KO, Haze beat the best other move by +0.119
; at +4 (significant; mean decision regret is +0.022) and +0.038 at +2, while
; the old scoring picked it 16-19% of the time. Faster without that threat it
; lost by 0.02-0.03. A KO of our own still outranks it (AI_KILL, AI_DAMAGE).
; Level-matched re-measure (2026-11-20, AI backlog "Level-matched Haze VALUE"):
; - faster, when one of OUR moves could KO, Haze lost at +2 (-0.091) and +4
;   (-0.058), and a possible KO (AI_KILL_POSSIBLE) only tied this verdict. So the
;   faster verdict flags AI_HAZE_DECISIVE_BIT, and AIHazeYieldsToKO (AI_DAMAGE,
;   which knows our KOs) takes the whole AI_VERY_STRONG back, leaving Haze neutral.
; - slower, at +AI_HAZE_SLOW_STAGES Haze won (+0.072) with or without the
;   player's KO, so that is decisive too, with no KO test and no take-back (our
;   own KO did not make it lose there: +0.046, n.s.).
; Clobbers af, bc, d, hl.
AIHazeVerdict::
	ld a, d
	sub e
	ld e, 0
	ret z ; nothing net: carry clear, magnitude 0
	ld e, AI_STRONG
	jr c, .harmful
	ld d, a ; d = the net gain
	ld a, [wPlayerMonAttackMod]
	cp BASE_STAT_LEVEL + AI_HAZE_KO_STAGES
	jr nc, .boosted
	ld a, [wPlayerMonSpecialMod]
	cp BASE_STAT_LEVEL + AI_HAZE_KO_STAGES
	jr c, .ordinary
.boosted
	push de
	farcall AIEnemyIsFaster ; carry = we act first; survives the return
	jr nc, .slower
	farcall AIPlayerWouldKO ; carry = its boosted hit KOs us this turn
	jr nc, .popOrdinary
	ld hl, wBuffer + AI_BUF_SETUPMASK
	set AI_HAZE_DECISIVE_BIT, [hl] ; ld and set keep the carry
	jr .popOrdinary
.slower
	ld a, [wPlayerMonAttackMod]
	cp BASE_STAT_LEVEL + AI_HAZE_SLOW_STAGES
	ccf
	jr c, .popOrdinary ; carry = at or above
	ld a, [wPlayerMonSpecialMod]
	cp BASE_STAT_LEVEL + AI_HAZE_SLOW_STAGES
	ccf
.popOrdinary
	pop de ; flags survive
	ld e, AI_VERY_STRONG
	jr c, .encourage
.ordinary
	ld a, d
	cp 2
	ld e, AI_STRONG ; ld keeps the cp flags
	jr nc, .encourage
	ld e, AI_NUDGE
.encourage
	scf
	ret
.harmful
	and a ; carry clear = discourage
	ret

; The faster Haze verdict yields to our own KO (2026-11-20, see AIHazeVerdict).
; Farcalled from AI_DAMAGE's .applyBest after AIPossibleKOEndsBattle, which left
; AI_BUF_POSSKO = the live slots that could KO this turn, vetoed Explosions out.
; AI_SMART scored Haze before AI_DAMAGE knew our KOs, hence the flag. Always
; clears AI_HAZE_DECISIVE_BIT, since AISetupGate, next, walks the same byte as a
; slot mask. If it was set and a slot could KO, every Haze slot gives back its
; AI_VERY_STRONG (the verdict's whole encourage, not just the decisive part).
; No register inputs; clobbers af, bc, hl.
AIHazeYieldsToKO::
	ld hl, wBuffer + AI_BUF_SETUPMASK
	bit AI_HAZE_DECISIVE_BIT, [hl]
	ret z
	res AI_HAZE_DECISIVE_BIT, [hl]
	ld a, [wBuffer + AI_BUF_POSSKO]
	and a
	ret z ; nothing of ours could KO: the decisive Haze stands
	ld hl, wEnemyMonMoves
	ld bc, wBuffer ; bc = this slot's score
.slot
	ld a, [hli]
	cp HAZE ; the only HAZE_EFFECT move
	jr nz, .next
	ld a, [bc]
	cp AI_SCORE_DISABLED
	jr z, .next ; legality is not a preference
	add AI_VERY_STRONG
	cp AI_SCORE_MAX + 1
	jr c, .store
	ld a, AI_SCORE_MAX
.store
	ld [bc], a
.next
	inc c ; wBuffer + 0-3 never crosses a page (ASSERT below)
	ld a, l
	cp LOW(wEnemyMonMoves + NUM_MOVES)
	jr nz, .slot
	ret
	ASSERT HIGH(wBuffer) == HIGH(wBuffer + NUM_MOVES - 1)

IF DEF(STADIUM_SWITCH)
; E2b TEST BUILD ONLY (AI_T4_REGRET_PLAN E2b, 2026-11-18): Pokemon Stadium 1's
; voluntary switch decision, ported term for term from team-hippodrome/pokestadium
; battle_engine_com_decision_logic.c (BattleAI_ScoreAttackOption 4632-4678,
; BattleAI_ScoreAttackVsSwitch 4720-4865, SelectBestAttackTargetIndex 4488-4581),
; to compare against our trigger chain. The gate worktree defines STADIUM_SWITCH;
; normal ROMs never assemble this. Our TARGET choice is kept (the post-KO ranking
; in VOLUNTARY mode), so the comparison isolates the decision rule.
; Ratios are Stadium's: damage x 255 / HP, capped at 255. Stadium's per-difficulty
; constants live in a ROM blob, not the source: STADIUM_BASELINE (unk_05),
; STADIUM_MARGIN (unk_07) and STADIUM_LOWHP (unk_08) are the swept knobs.
; Carry SET = switch, wBuffer + AI_BUF_BESTPARTYSLOT = the target. Clobbers all.
; Scratch: wBuffer +4/+5 (the B4 scan's largest hit, flag build), +6 Dealt,
; +7 Taken, +8 target D, +9 target T, +10 we are faster; nothing else runs here.
IF !DEF(STADIUM_BASELINE)
DEF STADIUM_BASELINE EQU 64
ENDC
IF !DEF(STADIUM_MARGIN)
DEF STADIUM_MARGIN EQU 0
ENDC
IF !DEF(STADIUM_LOWHP)
DEF STADIUM_LOWHP EQU 64 ; a quarter of 255
ENDC
DEF SS_DEALT EQU 6
DEF SS_TAKEN EQU 7
DEF SS_TD EQU 8
DEF SS_TT EQU 9
DEF SS_FASTER EQU 10

MACRO ss_add ; bc += signed constant \1
	ld hl, (\1) & $ffff
	add hl, bc
	ld b, h
	ld c, l
ENDM

AIStadiumSwitch::
; --- the target: our ranking, then its B4 scan (which leaves its largest hit at +4)
	farcall AIRankSendOutCandidates
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	cp $ff
	jp z, .stay ; one usable mon: Stadium scores 0
	ld [wBuffer + PK_BEST_SLOT], a
	xor a
	ld [wBuffer + PK_BEST_TYPE], a
	ld [wBuffer + PK_BEST_QUALITY], a
	ld [wBuffer + PK_BEST_DAMAGE], a
	ld [wBuffer + PK_BEST_DAMAGE + 1], a
	ld de, PK_MODE_VOLUNTARY << 8 | $ff
	call AIRankPostKOSendOut.rankWithSpeed
	farcall AIBestReserveSurvivesThreat
; --- target D: its best expected hit vs the player's current HP; 0 if it sleeps
	ld a, [wBuffer + PK_BEST_DAMAGE]
	ld d, a
	ld a, [wBuffer + PK_BEST_DAMAGE + 1]
	ld e, a
	ld hl, wBattleMonHP
	call .ratioOfHL
	ld [wBuffer + SS_TD], a
	call .targetStruct
	ld bc, wEnemyMon1Status - wEnemyMon1
	add hl, bc
	ld a, [hl]
	and SLP_MASK
	jr z, .targetAwake
	xor a
	ld [wBuffer + SS_TD], a
.targetAwake
; --- target T: Stadium counts the entry hit and one more, except that a SLOWER
; reserve whose reply KOs takes only the entry hit (4532-4547)
	ld a, [wBuffer + AI_BUF_MOVESAVE]
	ld d, a
	ld a, [wBuffer + AI_BUF_MOVESAVE + 1]
	ld e, a ; de = one hit
	call .targetFaster
	jr c, .twoHits
	ld a, [wBuffer + SS_TD]
	inc a
	jr z, .gotT ; slower, and its reply KOs: one hit
.twoHits
	sla e
	rl d
.gotT
	call .targetStruct
	inc hl ; HP
	call .ratioOfHL
	ld [wBuffer + SS_TT], a
	inc a
	jr nz, .tDone
	ld [wBuffer + SS_TD], a ; T = 255 (it dies in the exchange): D = 0 (a is 0 here)
.tDone
; --- active: Dealt = our best one-hit estimate (AI_DAMAGE's cache) vs their HP,
; Taken = their best possible hit vs our MAX HP
	farcall AIPlayerWouldKO
	ld hl, wAIPlayerKOMaxDamage
	ld a, [hli]
	ld e, [hl]
	bit AI_KO_MAX_VALID_BIT, a
	jr nz, .takenValid
	xor a
	ld e, a
.takenValid
	and %00111111
	ld d, a
	ld hl, wEnemyMonMaxHP
	call .ratioOfHL
	ld [wBuffer + SS_TAKEN], a
	ld de, 0
	ld hl, wAIEnemyEstimateCache
	ld b, NUM_MOVES
.cache
	ld a, [hli]
	bit AI_ESTIMATE_VALID_BIT, a
	jr z, .cacheSkip
	and $7f
	cp d
	jr c, .cacheSkip
	jr nz, .cacheBest
	ld a, [hl]
	cp e
	jr c, .cacheSkip
.cacheBest
	dec hl
	ld a, [hli]
	and $7f
	ld d, a
	ld e, [hl]
.cacheSkip
	inc hl
	dec b
	jr nz, .cache
	ld hl, wBattleMonHP
	call .ratioOfHL
	ld [wBuffer + SS_DEALT], a
	farcall AIEnemyIsFaster ; carry = faster
	ld a, 0
	rla
	ld [wBuffer + SS_FASTER], a
	and a
	jr z, .slower
	ld a, [wBuffer + SS_DEALT]
	inc a
	jr nz, .speedDone
	ld [wBuffer + SS_TAKEN], a ; we KO first: nothing taken (a = 0)
	jr .speedDone
.slower
	ld a, [wBuffer + SS_TAKEN]
	inc a
	jr nz, .speedDone
	ld [wBuffer + SS_DEALT], a ; they KO first: nothing dealt
.speedDone
; --- the sum (bc, signed 16-bit), BattleAI_ScoreAttackOption first
	ld bc, 0
	ld a, [wBuffer + SS_TAKEN] ; free entry with an answer: +52
	and a
	jr z, .noFreeEntry
	ld a, [wBuffer + SS_TT]
	and a
	jr nz, .noFreeEntry
	ld a, [wBuffer + SS_TD]
	and a
	jr z, .noFreeEntry
	ss_add 52
.noFreeEntry
	ld a, [wBuffer + SS_DEALT] ; we deal nothing, the reserve would: +128
	and a
	jr nz, .weDeal
	ld a, [wBuffer + SS_TD]
	and a
	jr z, .weDeal
	ld a, [wBattleMonStatus]
	and SLP_MASK | (1 << FRZ)
	jr nz, .weDeal
	ss_add 128
.weDeal
; (Dealt - Taken) < (D - T) - margin: +153
	ld a, [wBuffer + SS_DEALT]
	ld l, a
	ld h, 0
	ld a, [wBuffer + SS_TAKEN]
	ld e, a
	ld d, 0
	ld a, l
	sub e
	ld l, a
	ld a, h
	sbc d
	ld h, a ; hl = ours
	push hl
	ld a, [wBuffer + SS_TD]
	ld l, a
	ld h, 0
	ld a, [wBuffer + SS_TT]
	ld e, a
	ld a, l
	sub e
	ld l, a
	ld a, h
	sbc 0
	ld h, a
	ld de, (-STADIUM_MARGIN) & $ffff
	add hl, de ; hl = theirs - margin
	pop de ; de = ours
	ld a, e
	sub l
	ld a, d
	sbc h ; ours - theirs: negative (signed) iff ours < theirs
	bit 7, a
	jr z, .noMarginTerm
	ss_add 153
.noMarginTerm
; --- BattleAI_ScoreAttackVsSwitch's terms
; low HP while the target is healthier: +100
	ld a, [wEnemyMonHP]
	ld d, a
	ld a, [wEnemyMonHP + 1]
	ld e, a
	push bc
	ld hl, wEnemyMonMaxHP
	call .ratioOfHL
	pop bc
	cp STADIUM_LOWHP
	jr nc, .notLow
	push bc
	call .targetStruct
	inc hl
	ld d, [hl]
	inc hl
	ld e, [hl]
	call .targetStruct
	ld bc, wEnemyMon1MaxHP - wEnemyMon1
	add hl, bc
	call .ratioOfHL
	pop bc
	cp STADIUM_LOWHP + 1
	jr c, .notLow
	ss_add 100
.notLow
; trapped by the player and slower: +128; otherwise our KO -255 and sleep
	ld a, [wPlayerBattleStatus1]
	bit USING_TRAPPING_MOVE, a
	jr z, .notTrapped
	ld a, [wBuffer + SS_FASTER]
	and a
	jr nz, .notTrapped
	ss_add 128
	jr .trapDone
.notTrapped
	ld a, [wBuffer + SS_DEALT]
	cp $fa
	jr c, .noOwnKO
	ss_add -255
.noOwnKO
	ld a, [wEnemyMonStatus]
	and SLP_MASK ; turns left
	jr z, .trapDone
	ld e, a
	ld a, 4
	sub e ; 4 - turns (signed)
	sra a ; / 2, toward minus infinity: C truncates toward zero, so fix odd negatives
	jr nc, .halfDone
	bit 7, a
	jr z, .halfDone
	inc a
.halfDone
	ss_add -77
	and a
	jr z, .trapDone
.sleepLoop ; subtract 77 per unit of (4 - turns) / 2 (adds when it is negative)
	bit 7, a
	jr nz, .sleepNeg
	ss_add -77
	dec a
	jr nz, .sleepLoop
	jr .trapDone
.sleepNeg
	ss_add 77
	inc a
	jr nz, .sleepLoop
.trapDone
; Toxic counter x77, the running score x2 if also seeded
	ld a, [wEnemyBattleStatus3]
	bit BADLY_POISONED, a
	jr z, .noToxic
	ld a, [wEnemyToxicCounter]
	and a
	jr z, .seedCheck
.toxicLoop
	push af
	ss_add 77
	pop af
	dec a
	jr nz, .toxicLoop
.seedCheck
	ld a, [wEnemyBattleStatus2]
	bit SEEDED, a
	jr z, .noToxic
	sla c
	rl b
.noToxic
; stat stages: 4 per Atk/Def/Spd/Spc stage, 26 per accuracy/evasion stage,
; positive below neutral (push out), negative above (keep the boost)
	ld hl, wEnemyMonAttackMod
	ld e, 0
.stage
	ld a, [hli]
	push hl
	push de
	ld d, a ; d = stage (1-13, 7 neutral)
	ld a, e
	cp 4
	ld e, 4
	jr c, .gotWeight
	ld e, 26
.gotWeight
.stageLoop
	ld a, d
	cp 7
	jr z, .stageDone
	jr nc, .above
	ld a, e
	ld l, a
	ld h, 0
	add hl, bc
	ld b, h
	ld c, l
	inc d
	jr .stageLoop
.above
	ld a, c
	sub e
	ld c, a
	ld a, b
	sbc 0
	ld b, a
	dec d
	jr .stageLoop
.stageDone
	pop de
	pop hl
	inc e
	ld a, e
	cp 6
	jr c, .stage
; screens and a Substitute are worth keeping
	ld a, [wEnemyBattleStatus3]
	bit HAS_REFLECT_UP, a
	jr z, .noReflect
	ss_add -52
.noReflect
	ld a, [wEnemyBattleStatus3]
	bit HAS_LIGHT_SCREEN_UP, a
	jr z, .noScreen
	ss_add -52
.noScreen
	ld a, [wEnemyBattleStatus2]
	bit HAS_SUBSTITUTE_UP, a
	jr z, .noSub
	ss_add -77
.noSub
; the threat-move urgency (4833): if we would take less than the target would,
; and we are faster while their best hit twice reaches our HP, -153
	ld a, [wBuffer + SS_TAKEN]
	ld e, a
	ld a, [wBuffer + SS_TT]
	cp e
	jr c, .noUrgency
	jr z, .noUrgency
	ld a, [wBuffer + SS_FASTER]
	and a
	jr z, .noUrgency
	ld a, [wBuffer + SS_TAKEN]
	cp 128
	jr c, .noUrgency
	ss_add -153
.noUrgency
; the difficulty constant and Stadium's baseline, then clamp to 0..255
	ss_add STADIUM_BASELINE - 127
	bit 7, b
	jr nz, .stay
	ld a, b
	and a
	ld a, $ff
	jr nz, .roll
	ld a, c
.roll
	ld c, a
	push bc
	call Random ; a = 0..255 (keep the score out of its way)
	pop bc
	cp $ff
	jr z, .stay ; Random(0..254), as BattleAI_RandomBelowInclusive(0xFE)
	cp c ; carry iff the roll is below the score: switch
	ret
.stay
	and a
	ret
; hl -> the target's party struct (wBuffer + AI_BUF_BESTPARTYSLOT). Clobbers af, bc.
.targetStruct
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	ld hl, wEnemyMon1
	ld bc, PARTYMON_STRUCT_LENGTH
	jp AddNTimes
; Carry SET if the target outspeeds the player (party Speed, quartered if
; paralysed, against wBattleMonSpeed). Preserves de.
.targetFaster
	push de
	call .targetStruct
	push hl
	ld bc, wEnemyMon1Status - wEnemyMon1
	add hl, bc
	ld a, [hl]
	pop hl
	ld bc, wEnemyMon1Speed - wEnemyMon1
	add hl, bc
	ld d, [hl]
	inc hl
	ld e, [hl]
	and 1 << PAR
	jr z, .speedReady
	srl d
	rr e
	srl d
	rr e
.speedReady
	ld hl, wBattleMonSpeed
	ld a, [hli]
	ld b, a
	ld c, [hl]
	ld a, c
	sub e
	ld a, b
	sbc d ; carry iff player < target
	pop de
	ret
; a = min(255, de x 255 / [hl]) where hl -> a big-endian HP word. Normalizes both
; until the HP fits a byte (as the Gen 1 HP bar does), then divides de x 256 by it.
; Clobbers af, b, de, hl.
.ratioOfHL
	ld a, [hli]
	ld l, [hl]
	ld h, a
.norm
	ld a, h
	and a
	jr z, .normDone
	srl h
	rr l
	srl d
	rr e
	jr .norm
.normDone
	ld a, l
	and a
	jr z, .full
	ld a, d
	and a
	jr nz, .full
	ld a, e
	cp l
	jr nc, .full
	ldh [hDividend], a
	xor a
	ldh [hDividend + 1], a
	ld a, l
	ldh [hDivisor], a
	ld b, 2
	call Divide
	ldh a, [hQuotient + 3]
	ret
.full
	ld a, $ff
	ret
ENDC

; AIShouldSwitch's generic T3 case (moved here from "Trainer AI Switching", $2C,
; on 2026-11-18 to free that bank; behaviour and the Random call order unchanged).
; Carry SET if the player's primary type hits the active mon for more than neutral
; AND the 75% roll passes. Same forge-and-restore of PreviewTypeMatchup's inputs as
; AISelectSendOut; see that routine's header for why the engine's own dual-type
; walk is reused rather than reimplemented. No register inputs; clobbers af, bc, de, hl.
AIBadMatchupRoll::
	ld a, [wPlayerMoveType]
	push af
	ld a, [wBattleMonType1]
	ld [wPlayerMoveType], a
	farcall PreviewTypeMatchup ; -> e = multiplier in twentieths, so NEUTRAL IS
	                           ; 20, not 10 (it starts at EFFECTIVE * 2). Reads
	                           ; the LIVE wEnemyMonType, which is already the
	                           ; active mon here - only the attacking type needs
	                           ; forging, unlike the send-out scan.
	pop bc
	ld a, b
	ld [wPlayerMoveType], a ; restored before branching, so every exit is clean
	ld a, e
	cp EFFECTIVE * 2 + 1
	ccf
	ret nc ; not strictly worse than neutral for us
; The roll. 75% is a design choice, not an engine fact - worth retuning if a
; full run feels too random or too predictable here.
	call Random
	cp 75 percent + 1 ; carry iff the roll passes
	ret

; B17 Toxic pressure, copied from Pokemon Stadium 1's switch score
; (team-hippodrome/pokestadium, battle_engine_com_decision_logic.c lines 4801-4806):
; it adds toxicCounter * 77 against a -127 baseline and doubles the running score
; when the mon is also Leech Seeded, whose drain runs off the same counter. Read
; literally, counter >= 2 crosses the baseline alone, and counter >= 1 while
; seeded. Switching out turns Toxic back into regular poison and resets the
; counter, so the ramp stops. Carry SET if the active mon is badly poisoned past
; that threshold and has no reliable first KO to land instead (Stadium's own
; -255 for "our move KOs"). The caller still needs a better reserve that survives.
; Measured 2026-11-18 (200 forced states, rule off, over an unpoisoned control):
; switching out beat sitting in Toxic by +0.038 to +0.055 of party HP per
; counter level, +0.088 when also seeded.
;
; Second term, also Stadium's: a LOWERED ACCURACY stage (26 points per stage
; there, against 4 for Attack/Defense/Speed/Special). Switching resets it.
; Measured the same way: accuracy -1 +0.052, -2 +0.095; Defense -2 +0.024 and
; Attack -2 +0.017, neither significant, so only accuracy is a term here.
; No register inputs; clobbers af, bc, de, hl.
AIPushOutTerms::
	ld a, [wEnemyMonAccuracyMod]
	cp BASE_STAT_LEVEL
	jr c, .pushed ; any stage below neutral
	ld a, [wEnemyBattleStatus3]
	bit BADLY_POISONED, a
	jr z, .no
	ld a, [wEnemyMonStatus]
	bit PSN, a
	jr z, .no ; the flag outlived the poison (cured): nothing ticks
	ld a, [wEnemyToxicCounter]
	ld c, a
	ld a, [wEnemyBattleStatus2]
	bit SEEDED, a
	ld a, c
	jr z, .notSeeded
	add a ; Stadium doubles the score when seeded: the same as halving the bar
.notSeeded
	cp 2
	jr c, .no
.pushed
	farcall AIEnemyHasReliableFirstKO ; carry = we finish first; survives the return
	ccf
	ret
.no
	and a
	ret

; B17 free switch-in (AI_T4_REGRET_PLAN, measured 2026-11-17: in 67 states where a
; reserve was immune to every damaging player move, the best switch beat the best
; stay by +0.071 of party HP [+0.030, +0.111], 600 seeds). Carry SET with
; wBuffer + AI_BUF_BESTPARTYSLOT = a living reserve that
;   1. takes x0 from every believed player threat type (AIBuildPlayerThreatTypes)
;      while the active mon does not, and
;   2. keeps more than half its HP through every believed move by the real B4
;      scan. Stage 1 cannot see fixed-damage moves (AIBuildPlayerThreatTypes drops
;      them, and in this engine Seismic Toss / Night Shade ignore immunity, see
;      AIEstimateDamage's .specialDamage), so stage 2 prices them exactly.
; Stage 1 is the cheap filter: a reserve fails at its first non-immune threat
; (one chart walk), so an ordinary turn costs about one walk per reserve, and
; the ~40k-cycle B4 scan runs only on a reserve that passed it.
; No register inputs; clobbers af, bc, de, hl.
AIFreeSwitchInTarget::
	farcall AIBuildPlayerThreatTypes
	ld a, [wEnemyMonType1]
	push af
	ld a, [wEnemyMonType2]
	push af
	ld a, [wPlayerMoveType]
	push af
	call .immuneToEveryThreat ; the active mon on its live types
	jr c, .noneRestore ; already immune: nothing to gain by switching
	ld c, 0 ; c = party slot
.slot
	ld a, [wEnemyPartyCount]
	cp c
	jr z, .noneRestore
	jr c, .noneRestore
	ld a, [wEnemyMonPartyPos]
	cp c
	jr z, .next
	ld a, c
	ld hl, wEnemyMon1HP
	push bc
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	pop bc
	ld a, [hli]
	or [hl]
	jr z, .next ; fainted
	inc hl ; HP low -> BoxLevel
	inc hl ; Status
	inc hl ; Type1
	ASSERT wEnemyMon1Type1 == wEnemyMon1HP + 4
	ld a, [hli]
	ld [wEnemyMonType1], a
	ld a, [hl]
	ld [wEnemyMonType2], a
	push bc
	call .immuneToEveryThreat
	pop bc
	jr nc, .next
; Stage 2 on this candidate. The B4 scan reads the live wEnemyMonType1/2 as the
; ACTIVE mon's and restores them itself, so put the real ones back first.
	ld hl, sp + 5 ; the saved wEnemyMonType1: A of the af pushed first (push af
	              ; puts A in the higher byte), above Type2's and MoveType's
	ld a, [hl]
	ld [wEnemyMonType1], a
	ld hl, sp + 3
	ld a, [hl]
	ld [wEnemyMonType2], a
	ld a, c
	ld [wBuffer + AI_BUF_BESTPARTYSLOT], a
	push bc
	farcall AIBestReserveSurvivesThreat ; e = 1 survives; AI_BUF_RESERVEHALF set
	pop bc
	ld a, [wBuffer + AI_BUF_RESERVEHALF]
	cp AI_RESERVE_HALF_KEEPS
	jr z, .found
.next
	inc c
	jr .slot
.found
	pop af
	ld [wPlayerMoveType], a
	pop af
	ld [wEnemyMonType2], a
	pop af
	ld [wEnemyMonType1], a
	scf
	ret
.noneRestore
	pop af
	ld [wPlayerMoveType], a
	pop af
	ld [wEnemyMonType2], a
	pop af
	ld [wEnemyMonType1], a
	and a
	ret
; Carry SET if every believed threat type does x0 to the types staged in
; wEnemyMonType1/2. Writes wPlayerMoveType. Clobbers af, bc, de, hl.
.immuneToEveryThreat
	ld hl, wBuffer + AI_BUF_THREATTYPES
	ld b, NUM_MOVES
.threat
	ld a, [hli]
	cp $ff
	jr z, .nextThreat
	ld [wPlayerMoveType], a
	push hl
	push bc
	farcall PreviewTypeMatchup ; e = multiplier in twentieths; e survives
	pop bc
	pop hl
	ld a, e
	and a ; clears carry
	ret nz ; this threat lands
.nextThreat
	dec b
	jr nz, .threat
	scf
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
	ld hl, sp + 2 + PK_FRAME_MODE ; above our return address
	ld a, [hl]
	cp PK_MODE_VOLUNTARY
	jr nz, .faintSurvives
; VOLUNTARY: the reserve takes the player's hit on entry before anything else.
; KO'd on entry: never a target (quality stays 0). Otherwise B4's KEEPS already
; prices the entry hit: faster, more than half left after it (it acts, then
; survives the next hit); slower, 3x the hit below its HP (entry hit, next hit
; before it acts, and one more). So PK_SURVIVES = KEEPS ? 1 : 0, and the tiers
; below then read: faster without the margin FIRST_REPLY, slower without it
; DOOMED, either with it SURVIVE_REPLY, and a reliable KO on either reply path
; FINISH. UNKNOWN (a Super Fang was scanned) is not a margin.
	ld a, e
	and a
	ret z
	ld a, [wBuffer + AI_BUF_RESERVEHALF]
	cp AI_RESERVE_HALF_KEEPS
	ld a, 0
	jr nz, .storeSurvives
	inc a
	jr .storeSurvives
.faintSurvives
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
