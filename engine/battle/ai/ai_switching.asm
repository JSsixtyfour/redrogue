; AI switching engine (AI_OVERHAUL_PLAN.md Phase 4).
;
; PINNED to bank $2C, deliberately, and NOT floated like ai_core.asm's section:
; ROM_BIBLE.md section 5 rule 6 ("pin any new floating section once its intended
; budget matters") applies here because Red, Blue and Debug first-fit
; independently, and Debug is consistently the tightest of the three - a floated
; section of this size could land in a different, tight bank in one variant
; only. $2C is the established relocation bank (10 KB free, already holds a
; pinned section) and section 5 rule 3 names it first for general relocated
; leaves.
;
; WHY THIS CAN LIVE OUTSIDE BANK $0E AT ALL, unlike every AILayer* routine:
; switching is decided ONCE PER TURN, from TrainerAI, not once per move from
; AIEnemyTrainerChooseMoves' same-bank `jp hl` dispatch. The Phase 2a rule that
; forces scoring-loop code into bank $0E simply does not reach this file. See
; ai_score_helpers.asm's header for that rule and why it exists.
;
; FARCALL RETURN CONVENTION, verified from home/bankswitch.asm rather than
; assumed, because it is what lets the predicates here live out-of-bank at all:
; Bankswitch's return path is `pop bc / ld a, b / ldh [hLoadedROMBank], a /
; ld [rROMB], a / ret`. NONE of those instructions touch flags, and `pop bc`
; only touches bc. So across a farcall RETURN:
;   - CARRY survives      -> a predicate may return a boolean in carry
;   - de and hl survive   -> a routine may return a value in either
;   - a and bc are DESTROYED (a is reused, bc receives the saved bank)
; This is the mirror of the better-known inbound rule (an argument cannot travel
; in a, because Bankswitch's FIRST instruction is `ldh a, [hLoadedROMBank]`).

SECTION "Trainer AI Switching", ROMX, BANK[$2C]

; OUTPUT: a = 1 << (input a). INPUT: a = a party slot index (0-5).
; Shared by the anti-ping-pong marking in AISelectSendOut and the grace-period
; check in AIShouldSwitch, so the bit<->slot mapping can only be defined once.
; Clobbers b.
AIPartySlotBit:
	ld b, a
	ld a, 1
	inc b ; so a slot of 0 correctly does zero shifts (same idiom as
	      ; AIHPShiftCompare's shift-count loop in ai_predicates.asm)
.loop
	dec b
	ret z
	sla a
	jr .loop

; Chooses which party mon the enemy sends out, replacing the first-healthy-mon
; scan that EnemySendOut used to run inline (engine/battle/core.asm). Writes the
; chosen slot to hWhichPokemon and returns; the caller falls straight through to
; its .next3 label, which reads hWhichPokemon and loads that mon.
;
; CONTRACT INHERITED FROM THE SCAN THIS REPLACES, and not optional: on return
; hWhichPokemon must name a LIVING party slot that is not the one currently out.
; The vanilla scan had no bounds check and looped until it found one, relying
; entirely on the caller never reaching here unless such a mon exists. This
; version bounds itself by wEnemyPartyCount instead, which is strictly safer,
; but the .noCandidate path is still load-bearing rather than defensive padding:
; if it were ever reached, EnemySendOut would load a fainted mon and the battle
; would break.
;
; SELECTION RULE: pick the candidate with the lowest COMBINED score (see
; AIScoreSendOutMon): (a) how hard the player's WORST believed damaging move type
; hits it (PreviewTypeMatchup, in twentieths; the believed moveset is fair play
; since 2026-09-29 - revealed or type-guessed, see AIBuildPlayerThreatTypes),
; (b) an HP penalty (+15 below a quarter HP, +5 below half), and (c) a major
; status penalty (freeze +40, sleep/paralysis/burn +25, poison +10). Every
; penalty is relative: if all living reserves are in bad shape, the
; lowest-scoring one still wins (the inherited best-of-a-bad-set contract).
;
; Clobbers af, bc, de, hl.
AISelectSendOut::
; Phase 5: a mon coming in gets a fresh strategy plan. Cleared here rather than
; in EnemySendOut because this routine already runs on EVERY enemy send-out -
; the first one as well as every later switch - so it is the one place that
; cannot be reached without a new mon arriving, and it costs Battle Core (53
; bytes free) nothing. AILayerPlan re-selects on the next decision because
; AI_PLAN_NONE is what "not selected yet" means, which is also what the
; battle-start zeroing of wMiscBattleData produces.
	xor a
	ld [wAIPlan], a
	ld [wAIPlanStep], a
; ...and a fresh move history (AITrackLastMove's send-out lifecycle, L1).
	ld a, AI_LAST_MOVE_FRESH_MON
	ld [wAILastMoveNum], a

; ===========================================================================
; OPENING LEAD: no scoring. User decision, 2026-09-01.
;
; Scoring the opening lead is CHEATING and it did not even work. It reads
; wBattleMonType1 (below), but on the battle's first send-out the player's mon
; has not been loaded yet: EnemySendOutFirstMon runs at core.asm:190 and
; LoadBattleMonFromParty not until core.asm:284, and InitBattleVariables zeroes
; wBattleMonSpecies without touching the wBattleMon struct. So the lead was
; being chosen against the PREVIOUS battle's player mon type - real information
; the AI has no right to, and stale on top of that.
;
; A trainer picks their lead before seeing your team, exactly like the player.
; So the opening send-out now takes the first living mon, which is what the
; vanilla inline scan this routine replaced always did.
;
; wEnemyMonPartyPos is $ff at this point and only at this point:
; InitBattleCommon writes it (core.asm:7966) before the first send-out, and
; every later send-out leaves a real slot index behind. No new WRAM needed.
;
; >>> FUTURE BOSS HOOK <<<
; A boss designed around "studies your team before choosing a lead" would branch
; to .scoredLead from here instead of falling through, gated on whatever
; identifies it (a trainer class, or a wRogueFlagsBitfield bit). That boss does
; not exist yet, so there is deliberately no test here to go stale. Everything
; needed is already below: .scoredLead is the full scored path, unchanged.
	ld a, [wEnemyMonPartyPos]
	inc a ; $ff -> 0, and no real slot index can wrap to 0
	jr nz, .scoredLead

	ld hl, wEnemyMon1
	ld c, 0
.findFirstLiving
	ld a, [wEnemyPartyCount]
	cp c
	jr z, .scoredLead ; no living mon found: fall through to the scored path
	                  ; rather than returning a garbage slot. Unreachable in
	                  ; practice (the caller only sends out when one exists),
	                  ; but the contract this routine inherited is "hWhichPokemon
	                  ; must name a LIVING slot", so it must not be broken here.
	push hl
	inc hl
	ld a, [hli]
	ld b, a
	or [hl]
	pop hl
	jr nz, .gotFirstLiving
	ld de, PARTYMON_STRUCT_LENGTH
	add hl, de
	inc c
	jr .findFirstLiving
.gotFirstLiving
	ld a, c
	ldh [hWhichPokemon], a
	ret

.scoredLead
	call AIRankSendOutCandidates

	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	cp $ff
	jp z, .noCandidate

; Anti-ping-pong: mark the slot we are about to send in so AIShouldSwitch can
; give it one full decision cycle before considering switching it away again -
; see that routine's grace-period comment for why this matters specifically
; when the whole party has a bad type matchup against the player.
	push af
	call AIPartySlotBit
	ld b, a
	ld a, [wAISwitchedFlags]
	or b
	ld [wAISwitchedFlags], a
	pop af

	ldh [hWhichPokemon], a
	ret

.noCandidate
; Unreachable by the contract documented above - EnemySendOut only calls here
; when a living replacement exists. Kept because the alternative on a broken
; assumption is loading a fainted mon: slot 0 at least keeps the battle
; structurally valid while making the fault obvious in a scenario's telemetry,
; rather than corrupting state silently.
	xor a
	ldh [hWhichPokemon], a
	ret

; ---------------------------------------------------------------------------
; Ranks every living reserve (never the active mon) with AIScoreSendOutMon.
; AIRankSendOutCandidates builds the believed attacker types first and accepts
; any candidate; AIRankSendOutCandidatesBelow reuses the types already built and
; accepts only a candidate scoring strictly below the bound in a.
; OUTPUT: wBuffer + AI_BUF_BESTPARTYSLOT = best slot ($ff = none beat the
; bound), AI_BUF_BESTPARTYSCORE = its score. The three bytes PreviewTypeMatchup
; is fed through are restored. Clobbers af, bc, de, hl.
AIRankSendOutCandidates:
	farcall AIBuildPlayerThreatTypes ; bank $0E; no register contract
	ld a, $ff ; worse than any real combined score
AIRankSendOutCandidatesBelow:
	ld [wBuffer + AI_BUF_BESTPARTYSCORE], a
; PreviewTypeMatchup reads its defender types from wEnemyMonType and its
; attacking type from wPlayerMoveType, so those are borrowed rather than
; passed - the same forge-and-restore shape AIEstimateDamage uses, and for the
; same reason: the routine being reused is engine-exact.
	ld a, [wEnemyMonType1]
	push af
	ld a, [wEnemyMonType2]
	push af
	ld a, [wPlayerMoveType]
	push af
	ld a, $ff
	ld [wBuffer + AI_BUF_BESTPARTYSLOT], a ; $ff = nothing chosen yet
	xor a
	ld [wBuffer + AI_BUF_SCANSLOT], a
.nextSlot
	ld a, [wBuffer + AI_BUF_SCANSLOT]
	ld b, a
	ld a, [wEnemyPartyCount]
	cp b
	jr z, .done ; scanned every slot
	ld a, [wEnemyMonPartyPos]
	cp b
	jr z, .skip ; never pick the mon that is already out
	ld hl, wEnemyMon1
	ld a, b
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
; Fainted candidates are skipped. HP is a big-endian word at struct offset +1.
	push hl
	inc hl
	ld a, [hli]
	or [hl]
	pop hl
	jr z, .skip
	ld c, wEnemyMon1MaxHP - wEnemyMon1
	call AIScoreSendOutMon
	ld a, [wBuffer + AI_BUF_BESTPARTYSCORE]
	cp e
	jr c, .skip ; current best is already lower (better) - keep it
	jr z, .skip ; a tie keeps the EARLIER slot, so selection stays deterministic
	ld a, e
	ld [wBuffer + AI_BUF_BESTPARTYSCORE], a
	ld a, [wBuffer + AI_BUF_SCANSLOT]
	ld [wBuffer + AI_BUF_BESTPARTYSLOT], a
.skip
	ld hl, wBuffer + AI_BUF_SCANSLOT
	inc [hl]
	jr .nextSlot
.done
	pop af
	ld [wPlayerMoveType], a
	pop af
	ld [wEnemyMonType2], a
	pop af
	ld [wEnemyMonType1], a
	ret

; Scores one enemy mon as a send-out target. LOWER is better.
; INPUT:  hl = the mon's struct base, c = offset of its MaxHP. Works on both a
;         party_struct and the live wEnemyMon battle_struct: HP +1, status +4,
;         and types +5/+6 are the same in both; only MaxHP moves (+34 / +15).
;         wBuffer + AI_BUF_THREATTYPES holds the attacker types, and
;         AI_BUF_BESTPARTYSCORE the bound to beat ($ff = none).
; OUTPUT: e = worst believed player attack on it (twentieths: 0-80)
;         + HP penalty (+15 below a quarter, +5 below half)
;         + major-status penalty (freeze +40, sleep/par/burn +25, poison +10);
;         maximum 135. PRUNED: once the running total reaches the bound the
;         routine returns early with e >= bound, which every caller already
;         treats as "not better". The penalties go first because they are cheap
;         and each type-chart walk is ~8k cycles (measured 2026-09-29).
; Writes wEnemyMonType1/2 and wPlayerMoveType (the caller saves them).
; Clobbers af, bc, d, hl.
AIScoreSendOutMon:
	push hl
	inc hl
	ld a, [hli]
	ld d, a
	ld e, [hl] ; de = current HP
	pop hl
	push hl
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld b, a
	ld c, [hl] ; bc = max HP
	pop hl
	sla e
	rl d
	sla e
	rl d ; de = current HP * 4
	ld a, e
	sub c
	ld a, d
	sbc b ; carry iff below a quarter HP
	ld a, 15 ; ld keeps the carry
	jr c, .gotHPPenalty
	srl d
	rr e ; de = current HP * 2
	ld a, e
	sub c
	ld a, d
	sbc b ; carry iff below half HP
	ld a, 5
	jr c, .gotHPPenalty
	xor a
.gotHPPenalty
	ld d, a ; d = HP penalty
	ld bc, 4
	add hl, bc
	ld a, [hl] ; status
	ld e, 40
	bit FRZ, a
	jr nz, .gotStatusPenalty
	ld e, 25
	and SLP_MASK | (1 << PAR) | (1 << BRN)
	jr nz, .gotStatusPenalty
	ld a, [hl]
	ld e, 10
	bit PSN, a
	jr nz, .gotStatusPenalty
	ld e, 0
.gotStatusPenalty
	ld a, e
	add d
	ld d, a ; d = both penalties
	ld e, a ; e = running score, no attack counted yet
	ld a, [wBuffer + AI_BUF_BESTPARTYSCORE]
	cp e
	ret c
	ret z ; the penalties alone already fail to beat the bound
	inc hl ; status -> Type1
	ld a, [hli]
	ld [wEnemyMonType1], a
	ld a, [hl]
	ld [wEnemyMonType2], a
	ld hl, wBuffer + AI_BUF_THREATTYPES
	ld b, NUM_MOVES
.nextThreat
	ld a, [hli]
	cp $ff
	jr z, .skipThreat
	ld [wPlayerMoveType], a
	push hl
	push bc
	push de
	farcall PreviewTypeMatchup ; -> e = multiplier in twentieths; e survives
	ld a, e
	pop de ; d = penalties, e = running score
	pop bc
	pop hl
	add d
	cp e
	jr c, .skipThreat
	jr z, .skipThreat
	ld e, a ; a worse attack: raise the running score
	ld a, [wBuffer + AI_BUF_BESTPARTYSCORE]
	cp e
	ret c
	ret z ; can no longer beat the bound
.skipThreat
	dec b
	jr nz, .nextThreat
	ret

; Carry SET if some living reserve scores strictly better than the active mon
; under the same AIScoreSendOutMon metric, the active mon being scored on its
; LIVE HP and status (wEnemyMon). This is what stops an emergency switch into a
; reserve that is no better off, which only hands the player a free hit
; (2026-09-29 review F5: an outclassed party switched every turn). The active
; score is the ranking's bound, so pruning stops at the first proof either way.
; Clobbers af, bc, de, hl.
AIReplacementIsBetter:
	farcall AIBuildPlayerThreatTypes
	ld a, $ff
	ld [wBuffer + AI_BUF_BESTPARTYSCORE], a ; no bound for the active mon
	ld a, [wEnemyMonType1]
	push af
	ld a, [wEnemyMonType2]
	push af
	ld a, [wPlayerMoveType]
	push af
	ld hl, wEnemyMon
	ld c, wEnemyMonMaxHP - wEnemyMon
	call AIScoreSendOutMon
	pop af
	ld [wPlayerMoveType], a
	pop af
	ld [wEnemyMonType2], a
	pop af
	ld [wEnemyMonType1], a
	ld a, e
	call AIRankSendOutCandidatesBelow
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	cp $ff ; carry iff a slot beat the active score (any slot < $ff)
	ret

; AIReplacementIsBetter, and the chosen reserve also SURVIVES the believed
; threat at its current HP (AI_BACKLOG B4, 2026-09-29): when the alternative to
; switching is attacking, switching into a mon the player KOs anyway only hands
; over the turn. Not used by the frozen/long-sleep trigger, whose alternative is
; doing nothing at all. Clobbers af, bc, de, hl.
AIReplacementIsBetterAndSurvives:
	call AIReplacementIsBetter
	ret nc
	farcall AIBestReserveSurvivesThreat ; e = 1 survives, 0 = would be KO'd
	ld a, e
	and a
	ret z ; carry clear
	scf
	ret

; ---------------------------------------------------------------------------
; Carry SET if the enemy should switch its active mon out this turn.
;
; Called from AISwitchIfEnoughMons (bank $0E) AFTER that routine has confirmed
; at least two living mons exist, so this does not re-check that.
;
; WHY BOOLEAN PREDICATES IN PRIORITY ORDER RATHER THAN A WEIGHTED SUM (the plan
; revised Phase 4 to this shape after the pokeemerald-expansion review): each
; check is independently tier-gateable and independently testable, most turns
; exit on the first or second one, and - the real reason - switching is a rare,
; highly visible action that should be EXPLICABLE. "It switched because it was
; about to be KO'd" is a debuggable claim; "the weighted sum came out to 61" is
; not. WHO to switch to stays scalar (AISelectSendOut above), because ranking
; candidates is exactly what a score is for. The two halves of the question get
; the shape that suits each.
;
; TIER GATE: T0/T1 keep vanilla behaviour outright (switch whenever the trainer
; class's own random roll asked to), T2 gets the emergency triggers and vetoes,
; T3 additionally gets the generic bad-matchup case.
;
; Reads the tier through wAITier rather than AIGetTier's return value: that
; routine returns the tier in `a`, which cannot survive a farcall return
; (Bankswitch's return path does `ld a, b`). Farcalling it is still required,
; because that call is what RESOLVES wAITier on first use; the value is then
; read back from WRAM, where it is stored as tier+1.
; Clobbers af, bc, de, hl.
AIShouldSwitch::
	farcall AIGetTier ; resolve wAITier - its `a` return cannot survive the trip
	ld a, [wAITier]
	and a
	jp z, .vanilla ; still unresolved: behave exactly as before
	dec a ; a = resolved tier
	cp AI_TIER_SKILLED
	jp c, .vanilla ; T0/T1 are not supposed to switch intelligently

; --- Anti-ping-pong grace period, FIRST ---
; wAISwitchedFlags is set by AISelectSendOut when it commits to a slot. If the
; CURRENTLY ACTIVE mon's bit is set, it arrived on the immediately preceding
; decision and has not acted yet - clear its bit (so the NEXT decision
; evaluates it normally) and stay. Checked before every trigger, emergencies
; included (2026-09-29 review F5): with the emergency trigger ahead of it, an
; outclassed party switched A -> B -> A every single turn, each switch a free
; hit for the player. A mon that has just come in never leaves before acting.
	ld a, [wEnemyMonPartyPos]
	call AIPartySlotBit
	ld c, a
	ld a, [wAISwitchedFlags]
	and c
	jp z, .noGrace
	ld a, c
	cpl
	ld c, a
	ld a, [wAISwitchedFlags]
	and c
	ld [wAISwitchedFlags], a
	jp .stay
.noGrace

; --- Emergency triggers and winning-action veto, short-circuiting ---
; No probability roll on any of these (contrast the generic case at the bottom,
; which does roll): "sometimes forgets to flee certain death" reads as broken
; AI to a player, not as personality. Texture belongs on the SOFT preference,
; not the hard ones. Triggers 1 and 3 only fire when AIReplacementIsBetter says
; the best reserve is strictly better off than the active mon, scored the same
; way AISelectSendOut ranks send-outs; switching into an equally bad reserve
; only spends the turn.
;
; 1. Badly statused: frozen is a total lockout, and a long sleep is close to
;    one. A short sleep is left alone - waking up next turn is better than
;    spending the switch and giving the player a free hit anyway.
	ld a, [wEnemyMonStatus]
	bit FRZ, a
	jr nz, .badlyStatused
	and SLP_MASK
	cp 2
	jr c, .notBadlyStatused
.badlyStatused
	call AIReplacementIsBetter
	jp c, .switch
.notBadlyStatused

; 2. The damage simulator says the player's believed moveset kills us.
; 3. Caught in the player's trapping move AND slower, so we cannot break out by
;    KOing first. A faster trapped mon is left in: it still gets to act.
; Both are VETOED by a reliable KO with the selected move: at this call point
; that move lands before the player's next action at ANY speed (see the
; predicate's header), so a slower finisher that survived the hit stays in.
; The veto costs an estimate (20-33k cycles, measured), so it runs only once a
; trigger would actually fire, not every turn.
	farcall AIPlayerWouldKO
	jr nc, .noKOThreat
	farcall AIEnemyHasReliableFirstKO
	jp c, .stay
	call AIReplacementIsBetterAndSurvives
	jr nc, .noSafeReserve
; B5: a safe reserve exists, but sacrificing the active mon may still be the
; better trade (a replacement after a faint enters free) - see the predicate.
	farcall AISacrificeBeatsSwitch ; carry = sacrifice; survives the return
	jp c, .stay
	jp .switch
.noSafeReserve
; Under a KO threat with no better reserve, nothing below may switch: the
; generic case is a weaker reason than the one just rejected, and the vetoes
; only ever say stay. Only the trap still can (a trapped, slower mon cannot act
; at all). The veto above already came back false, so it is not re-run.
	call .trappedAndSlower
	jp c, .switch
	jp .stay
.noKOThreat
	call .trappedAndSlower
	jr nc, .noTrap
	farcall AIEnemyHasReliableFirstKO
	jp c, .stay
	jp .switch
.noTrap

; --- Vetoes: reasons to stay put even though nothing above forced a switch ---
; A super-effective move is worth more than a better matchup we would have to
; spend a turn (and a free hit) to reach.
	farcall AIHasSuperEffectiveMove
	jp c, .stay

; Never abandon our own setup. Any raised stat means a previous turn was already
; invested here.
	ld hl, wEnemyMonAttackMod
	ld b, 6 ; the six real stat mods; NUM_STAT_MODS is 8 but the last two are
	        ; const_skip padding that carries no game state (same subset
	        ; AISmart_Haze walks - see ai_smart.asm)
.statLoop
	ld a, [hli]
	cp BASE_STAT_LEVEL + 1
	jp nc, .stay ; strictly above neutral: we have a boost worth keeping
	dec b
	jp nz, .statLoop

; --- Generic case: T3 only, and the ONE place this layer rolls a probability ---
; "Urgency x personality", scaled down to what this codebase actually has: Red
; Rogue does not carry Gen 2's per-trainer-class switch-probability profiles
; (AIRunPersonality is effectively just "is this the Gambler"), so the second
; axis here is the AI's own skill TIER rather than a trainer personality table.
; The generic bad-matchup case is the lowest-urgency trigger in this routine -
; nothing forces it, it is a soft preference - so it is the one place adding
; texture is safe: sometimes a T3 trainer sticks around anyway, which keeps
; switch outcomes from being fully solved by the player without ever looking
; like the AI failed to notice a threat it should have.
	ld a, [wAITier]
	dec a
	cp AI_TIER_EXPERT
	jp c, .stay

; Bad matchup = the player's primary type hits us for more than neutral. Same
; forge-and-restore of PreviewTypeMatchup's inputs as AISelectSendOut above;
; see that routine's header for why the engine's own dual-type walk is reused
; rather than reimplemented.
	ld a, [wPlayerMoveType]
	push af
	ld a, [wBattleMonType1]
	ld [wPlayerMoveType], a
	farcall PreviewTypeMatchup ; -> e = multiplier in twentieths, so NEUTRAL IS
	                           ; 20, not 10 (it starts at EFFECTIVE * 2). Reads
	                           ; the LIVE wEnemyMonType, which is already the
	                           ; active mon here - only the attacking type needs
	                           ; forging, unlike the send-out scan.
	ld a, e
	pop bc
	ld a, b
	ld [wPlayerMoveType], a ; restore before branching, so every exit path below
	                        ; is already clean
	ld a, e
	cp EFFECTIVE * 2 + 1
	jp c, .stay ; not strictly worse than neutral for us

; The roll. 75% is a design choice, not an engine fact - worth retuning if a
; full run feels too random or too predictable here.
	call Random
	cp 75 percent + 1
	jp nc, .stay
; ...and only into a reserve that is actually better off, or the bad matchup
; just moves to the next mon and the free hit is wasted (review F5).
	call AIReplacementIsBetterAndSurvives
	jp c, .switch

.stay
	and a ; clear carry
	ret
.vanilla
.switch
	scf
	ret

; Carry SET if the player holds us in a trapping move and we are slower.
.trappedAndSlower
	ld a, [wPlayerBattleStatus1]
	and 1 << USING_TRAPPING_MOVE ; `and` clears carry, so not trapped -> no carry
	ret z
	farcall AIEnemyIsFaster ; carry = faster; flags survive the farcall return
	ccf ; faster -> no carry; slower -> carry
	ret
