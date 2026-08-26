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
; SELECTION RULE (Phase 4 Opus portion): pick the candidate the player's PRIMARY
; type hurts least. That is the single highest-value half of "who to switch to" -
; not walking a fresh mon into a type it dies to - and it is deliberately the
; whole rule for now. AIScoreParty's fuller weight table (offensive matchup,
; HP, revealed player moves) is the Sonnet half of this phase and slots in at
; the marked call site below without changing this routine's shape.
;
; Clobbers af, bc, de, hl.
AISelectSendOut::
; Save the three bytes forged below. PreviewTypeMatchup reads its defender types
; from wEnemyMonType and its attacking type from wPlayerMoveType, so those are
; borrowed rather than passed - the same forge-and-restore shape AIEstimateDamage
; uses on the damage path, and for the same reason: the routine being reused is
; engine-exact, and reimplementing dual-type stacking a fourth time would be
; strictly worse than briefly borrowing three bytes.
	ld a, [wEnemyMonType1]
	push af
	ld a, [wEnemyMonType2]
	push af
	ld a, [wPlayerMoveType]
	push af

; The player's primary type is the attacker for every comparison in the loop, so
; it is set once here rather than per candidate.
	ld a, [wBattleMonType1]
	ld [wPlayerMoveType], a

	ld a, $ff
	ld [wBuffer + AI_BUF_BESTPARTYSCORE], a ; worse than any real multiplier (max 80)
	ld [wBuffer + AI_BUF_BESTPARTYSLOT], a  ; $ff = nothing chosen yet
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

; hl = &wEnemyMon1 + slot * PARTYMON_STRUCT_LENGTH
	ld hl, wEnemyMon1
	ld a, b
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes

; Fainted candidates are skipped. HP is a big-endian word at struct offset +1.
	push hl
	inc hl
	ld a, [hli]
	ld c, a
	ld a, [hl]
	or c
	pop hl
	jr z, .skip

; Forge this candidate as the "defender" PreviewTypeMatchup will read. Type1 and
; Type2 sit at struct offsets +5 and +6 (box_struct: Species, HP.w, BoxLevel,
; Status, Type1, Type2 - see macros/ram.asm).
	ld bc, 5
	add hl, bc
	ld a, [hli]
	ld [wEnemyMonType1], a
	ld a, [hl]
	ld [wEnemyMonType2], a

	farcall PreviewTypeMatchup ; -> e = multiplier in twentieths
	                           ; (0, 5, 10, 20, 40, 80). LOWER is better for us:
	                           ; it is how hard the PLAYER hits this candidate.
	                           ; e survives the farcall return - see the header.

	ld a, [wBuffer + AI_BUF_BESTPARTYSCORE]
	cp e
	jr c, .skip ; current best is already lower (better) - keep it
	jr z, .skip ; a tie keeps the EARLIER slot, so selection stays deterministic
	            ; and the scenarios built on it cannot go flaky
	ld a, e
	ld [wBuffer + AI_BUF_BESTPARTYSCORE], a
	ld a, [wBuffer + AI_BUF_SCANSLOT]
	ld [wBuffer + AI_BUF_BESTPARTYSLOT], a

.skip
	ld hl, wBuffer + AI_BUF_SCANSLOT
	inc [hl]
	jr .nextSlot

.done
; Restore in exactly reverse push order.
	pop af
	ld [wPlayerMoveType], a
	pop af
	ld [wEnemyMonType2], a
	pop af
	ld [wEnemyMonType1], a

	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	cp $ff
	jr z, .noCandidate
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
	jr z, .vanilla ; still unresolved: behave exactly as before
	dec a ; a = resolved tier
	cp AI_TIER_SKILLED
	jr c, .vanilla ; T0/T1 are not supposed to switch intelligently

; --- Emergency triggers, highest priority, short-circuiting ---
; 1. The damage simulator says the player kills us next turn.
	farcall AIPlayerWouldKO
	jr c, .switch

; 2. Badly statused: frozen is a total lockout, and a long sleep is close to
;    one. A short sleep is left alone - waking up next turn is better than
;    spending the switch and giving the player a free hit anyway.
	ld a, [wEnemyMonStatus]
	bit FRZ, a
	jr nz, .switch
	ld a, [wEnemyMonStatus]
	and SLP_MASK
	cp 2
	jr nc, .switch

; 3. Caught in the player's trapping move AND slower, so we cannot break out by
;    KOing first. A faster trapped mon is left in: it still gets to act.
	ld a, [wPlayerBattleStatus1]
	bit USING_TRAPPING_MOVE, a
	jr z, .noTrap
	farcall AIEnemyIsFaster
	jr nc, .switch
.noTrap

; --- Vetoes: reasons to stay put even though nothing above forced a switch ---
; A super-effective move is worth more than a better matchup we would have to
; spend a turn (and a free hit) to reach.
	farcall AIHasSuperEffectiveMove
	jr c, .stay

; Never abandon our own setup. Any raised stat means a previous turn was already
; invested here.
	ld hl, wEnemyMonAttackMod
	ld b, 6 ; the six real stat mods; NUM_STAT_MODS is 8 but the last two are
	        ; const_skip padding that carries no game state (same subset
	        ; AISmart_Haze walks - see ai_smart.asm)
.statLoop
	ld a, [hli]
	cp BASE_STAT_LEVEL + 1
	jr nc, .stay ; strictly above neutral: we have a boost worth keeping
	dec b
	jr nz, .statLoop

; --- Generic case: T3 only ---
	ld a, [wAITier]
	dec a
	cp AI_TIER_EXPERT
	jr c, .stay

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
	jr nc, .switch ; strictly worse than neutral for us

.stay
	and a ; clear carry
	ret
.vanilla
.switch
	scf
	ret
