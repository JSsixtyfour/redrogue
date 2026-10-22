; TURN PLANNING (2026-10-22). The enemy decides its whole turn before the
; player's battle menu, from the state the player can also see: its move, a T2+
; voluntary switch, and the replacement any switch would send in. It used to
; choose after the menu, so it scored its moves (and picked its switch target)
; against a mon the player had just switched in.
;
; Commit (core.asm .selectEnemyMove) then runs TrainerAI, so a trainer's switch
; goes before every move, Gen 2 style. TrainerAI reads the plan rather than the
; live board. Forced turns (the player recharging, thrashing, charging or
; raging: no menu, so no choice to read) and AIPsychicClasses decide at commit
; instead, which for a psychic class means after seeing the player's choice.
;
; PINNED to bank $3C: $2C, home of the switching engine, had 96 B free. Every
; call out of here is a farcall; carry survives each return (Bankswitch's
; return path leaves flags alone), which every predicate below relies on.

SECTION "Trainer AI Turn Plan", ROMX, BANK[$3C]

; core.asm MainInBattleLoop, right before the battle menu (not again when a
; cancelled move menu returns to it).
AIPlanEnemyTurn::
	xor a
	ld [wAITurnPlan], a
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret z ; the link exchange carries the other player's choice, at commit
; The player's active mon is on screen at the menu: the AI has now seen it.
	ld a, [wPlayerMonNumber]
	call AISlotBit
	ld hl, wAISeenPlayerMons
	or [hl]
	ld [hl], a
	call AIOpponentIsPsychic
	ret c ; decides at commit, after the player's choice
; Set before deciding, so move choice knows it is the pre-menu plan (switch
; prediction runs only here).
	ld a, 1 << AI_TURN_PLANNED_BIT
	ld [wAITurnPlan], a
	ldh a, [hWhoseTurn] ; the move menu must see the side it had (FOLLOWUPS #44)
	push af
	call AIDecideEnemyTurn
	pop af
	ldh [hWhoseTurn], a
	ret

; core.asm .selectEnemyMove, once per turn: the enemy's turn as planned (or
; decided now), then TrainerAI's switch, which goes before every move.
; OUTPUT: carry SET if TrainerAI spent the enemy's turn.
AICommitEnemyTurn::
	ld hl, wAITurnPlan
	bit AI_TURN_PLANNED_BIT, [hl]
	jr z, .decideNow ; a forced turn, a psychic class or a link battle
	bit AI_TURN_MOVE_CHOSEN_BIT, [hl]
	jr nz, .trainerAI
; Locked when the plan was made, and the menu may have freed it: the Poke
; Flute wakes it, a player switch ends its Wrap, a player item can end the
; player's. The switch and replacement stay as planned; only the move is
; chosen now, as it was before turn planning (the plan's move was stale).
	res AI_TURN_PLANNED_BIT, [hl] ; after the menu: no switch prediction
	farcall SelectEnemyMove
	jr .trainerAI
.decideNow
	xor a
	ld [wAITurnPlan], a
	call AIDecideEnemyTurn
.trainerAI
	ld hl, wAITurnPlan ; this turn's move is settled: a forced turn next must
	ld a, [hl]         ; not read these as its own
	and ~((1 << AI_TURN_PLANNED_BIT) | (1 << AI_TURN_MOVE_CHOSEN_BIT))
	ld [hl], a
	ld a, 1
	ldh [hWhoseTurn], a
	farcall TrainerAI ; carry survives the farcall return
.done ; carry = TrainerAI spent the turn. Zero-byte seam: hook_trainer_ai_calls
	ret

; The move, then for a trainer everything TrainerAI would read off the player's
; side. The caller zeroes wAITurnPlan (the plan sets AI_TURN_PLANNED_BIT first).
; Clobbers af, bc, de, hl.
AIDecideEnemyTurn:
; SelectEnemyMove leaves the move alone when the enemy is locked (asleep,
; frozen, recharging, charging, thrashing, raging, wrapping, Bide), so a
; sentinel tells a choice from a lock. The old move goes back at once: the
; switch decision below reads the selected move, and a continuing move needs it.
	ld a, [wEnemySelectedMove]
	push af
	xor a ; NO_MOVE: never a choice (ChooseEnemyMove falls back to Struggle)
	ld [wEnemySelectedMove], a
	farcall SelectEnemyMove
	pop bc ; b = the move before
	ld a, [wEnemySelectedMove]
	and a
	jr z, .locked
	ASSERT CANNOT_MOVE == $ff
	inc a ; held by the player's trapping move, which the menu can end
	jr z, .noChoice
	ld hl, wAITurnPlan
	set AI_TURN_MOVE_CHOSEN_BIT, [hl]
	jr .moveSettled
.locked
	ld a, b
	ld [wEnemySelectedMove], a
.noChoice
; No move choice ran, so nothing opened a new decision: the caches still hold
; the last one's answers, and the switch check below would trust them (a short
; sleep reaches AIPlayerWouldKO; Codex review 2026-10-22, measured). Clear
; them, so each reader rescans the board the player sees.
	farcall AIClearDecisionCaches
.moveSettled
	ldh a, [hIsInBattle]
	cp 2
	ret nz ; wild: TrainerAI does nothing
	ld a, [wLinkState]
	cp LINK_STATE_BATTLING
	ret z
	ld a, [wEnemyBattleStatus1]
	and AI_LOCKED_STATUS1
	ret nz ; TrainerAI will not switch
	ld a, [wEnemyBattleStatus2]
	and AI_LOCKED_STATUS2
	ret nz
	farcall AIActiveMonIsAce
	ret c ; the ace has no one to switch to (and trainers use no items)
; Two or more living mons. T2+ decides whether to switch (TrainerAI's
; AITrySmartSwitch); T0/T1 class rolls decide at commit. Any replacement a
; switch could send in is ranked here, against the board the player saw.
	farcall AIGetTier ; resolve wAITier - its `a` return cannot survive the trip
	ld a, [wAITier]
	cp AI_TIER_SKILLED + 1 ; wAITier holds tier + 1, 0 = unresolved
	jr nc, .smartSwitch
; T0/T1: only a class whose TrainerAI handler can roll a switch needs a
; replacement ranked now (the roll itself is at commit). Others never switch
; voluntarily, and a faint replacement ranks live.
	ld a, [wAICount]
	and a
	ret z ; no AI uses left: the handler is never called
	ld hl, AILowTierSwitchClasses
	call AIClassIsListed
	ret nc
	jr .rank
.smartSwitch
	ld a, $ff
	ld [wBuffer + AI_BUF_BESTPARTYSLOT], a ; nothing ranked yet
	farcall AIShouldSwitchAtSelectedSpeed
.switchDecisionReady ; carry = switch. Zero-byte test seam: this replaces the
                      ; old AISwitchIfEnoughMons.switchDecisionReady as the
                      ; point where the live decision (and the CGB speed
                      ; wrapper around it) actually happens; TrainerAI's own
                      ; .switchDecisionReady now just plays back wAITurnPlan.
	ret nc ; staying: nothing sends a replacement in, so skip ranking one
	       ; (~16.7k cycles a turn; AISelectSendOut ranks live on slot 0)
	ld hl, wAITurnPlan
	set AI_TURN_SWITCH_BIT, [hl]
; Most switches were decided by AIReplacementIsBetter(AndSurvives), which has
; just ranked the reserves on the same metric. Its bound only filters: a slot
; it found is also the unbounded best (ties keep the earlier slot either way),
; so reuse it. The trapped-and-slower switch can come without a ranking.
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	inc a ; slot + 1, and $ff (none) -> 0
	jr nz, .storeSlot
.rank
	farcall AIRankSendOutCandidates
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	inc a ; slot + 1, and $ff (none) -> 0
.storeSlot
	ld hl, wAITurnPlan
	or [hl]
	ld [hl], a
	ret

; ---------------------------------------------------------------------------
; SWITCH PREDICTION (2026-10-22, AI_SWITCH_PREDICTION_PROPOSAL_2026-10-22.md).
; Farcalled by AIEnemyTrainerChooseMoves once every layer, the Explosion veto
; and the reliable-KO pass have scored, just before the minimum is found. On a
; turn the player would likely switch out - their mon is outclassed: we hold a
; super effective move, nothing they are believed to have KOs us, and they have
; another mon - a T2+ trainer sometimes (AIPredictChance) hedges. A move scoring
; within AI_PREDICT_MARGIN of the best becomes the unique minimum:
;   1. coverage, when a mon the AI has SEEN this battle (wAISeenPlayerMons)
;      shrugs off the best move's type: a damaging move at least neutral on
;      that mon and on the active one;
;   2. else setup or status (AIHedgeEffects), which the switch-in takes.
; Only in the pre-menu plan (AI_TURN_PLANNED_BIT), and never with a possible
; KO on the board: the KO is taken (user decision). The scores already rule
; out a redundant, wasted or vetoed move, since it scores out of the margin.
; Clobbers af, bc, de, hl.
AIPredictPlayerSwitch::
	ld a, [wAITurnPlan]
	bit AI_TURN_PLANNED_BIT, a
	ret z ; a forced turn, FINAL_AI, or a re-choice after the menu
	ld a, [wAITier]
	sub AI_TIER_SKILLED + 1
	ret c ; T0/T1 (or unresolved)
	ld a, [wAIReliableKOFound]
	ld hl, wBuffer + AI_BUF_POSSKO
	or [hl]
	ret nz ; a KO is on the board: take it
	call AIPlayerHasReserve
	ret nc ; nowhere to switch to
	farcall AIPlayerWouldKO
	ret c ; their mon can win the exchange: no reason to leave
	farcall AIHasSuperEffectiveMove
	ret nc ; no big advantage to run from
	ld a, [wAITier]
	sub AI_TIER_SKILLED + 1
	ld c, a
	ld b, 0
	ld hl, AIPredictChance
	add hl, bc
	ld a, [hl]
	push af
	call Random
.rolled ; zero-byte test seam: a = the roll
	pop bc ; b = the chance
	cp b
	ret nc
.predicts ; zero-byte seam: the telemetry counts predictions here
	call AIFindHedge ; carry: c = the hedge slot, d = the best score
	ret nc
	ld b, 0
	ld hl, wBuffer
	add hl, bc
	ld a, d
	dec a
	ld [hl], a ; the unique minimum
	ld hl, wAITurnPlan
	set AI_TURN_PREDICT_BIT, [hl]
.hedged ; zero-byte seam: c = the hedge slot
	ret

; TUNING KNOB: the chance a T2 / T3 trainer acts on a predicted switch.
AIPredictChance:
	db 25 percent ; T2 Skilled
	db 50 percent ; T3 Expert

; Setup and status a switch-in takes as well as the mon that left.
AIHedgeEffects:
	db ATTACK_UP1_EFFECT, SPECIAL_UP1_EFFECT, SPEED_UP1_EFFECT
	db ATTACK_UP2_EFFECT, SPECIAL_UP2_EFFECT, SPEED_UP2_EFFECT, DEFENSE_UP2_EFFECT
	db SLEEP_EFFECT, POISON_EFFECT, PARALYZE_EFFECT, LEECH_SEED_EFFECT
	db $ff

; Carry SET if the player has a living mon besides the active one (the party
; balls are on screen: fair to know). Clobbers af, bc, de, hl.
AIPlayerHasReserve:
	ld hl, wPartyMon1HP
	ld de, PARTYMON_STRUCT_LENGTH
	ld b, 0
.loop
	ld a, [wPartyCount]
	cp b
	jr z, .no
	ld a, [wPlayerMonNumber]
	cp b
	jr z, .next
	ld a, [hli]
	or [hl]
	dec hl
	jr nz, .yes
.next
	add hl, de
	inc b
	jr .loop
.yes
	scf
	ret
.no
	and a
	ret

; Carry SET with c = the hedge slot and d = the best live score, else no carry.
; Scratch: wBuffer + AI_BUF_HEDGE_* (AI_DAMAGE's, done by now). Every farcall
; here clobbers all registers, so loop state lives there.
AIFindHedge:
	ld a, $ff
	ld [wBuffer + AI_BUF_HEDGE_BEST], a
	ld [wBuffer + AI_BUF_HEDGE_COUNTER], a
	ld c, 0
.bestLoop
	ld a, c
	call AIHedgeSlotIsLive
	jr z, .bestNext
	ld b, 0
	ld hl, wBuffer
	add hl, bc
	ld a, [wBuffer + AI_BUF_HEDGE_BEST]
	cp [hl]
	jr c, .bestNext
	jr z, .bestNext ; a tie keeps the earlier slot
	ld a, [hl]
	ld [wBuffer + AI_BUF_HEDGE_BEST], a
	ld a, c
	ld [wBuffer + AI_BUF_HEDGE_PICK], a
.bestNext
	inc c
	ld a, c
	cp NUM_MOVES
	jr c, .bestLoop
; A seen benched mon the best move's type does not hit (resisted or immune).
	ld a, [wBuffer + AI_BUF_HEDGE_PICK]
	call AIHedgeReadSlotMove
	ld a, [wEnemyMovePower]
	and a
	jr z, .statusPass ; the best move is not an attack: nothing to cover
	xor a
	ld [wBuffer + AI_BUF_HEDGE_SLOT], a
.counterLoop
	ld a, [wBuffer + AI_BUF_HEDGE_SLOT]
	ld c, a
	ld a, [wPartyCount]
	cp c
	jr z, .counterDone
	call AIHedgeSeenBenched
	jr z, .counterNext
	ld a, [wBuffer + AI_BUF_HEDGE_SLOT]
	call AIHedgeEffectivenessOn
	cp EFFECTIVE
	jr nc, .counterNext
	ld a, [wBuffer + AI_BUF_HEDGE_SLOT]
	ld [wBuffer + AI_BUF_HEDGE_COUNTER], a
	jr .counterDone
.counterNext
	ld hl, wBuffer + AI_BUF_HEDGE_SLOT
	inc [hl]
	jr .counterLoop
.counterDone
	ld a, [wBuffer + AI_BUF_HEDGE_COUNTER]
	inc a
	jr z, .statusPass
; 1. Coverage: at least neutral on the active mon and on the counter.
	xor a
	ld [wBuffer + AI_BUF_HEDGE_SLOT], a
.coverageLoop
	call AIHedgeCandidate
	jr z, .coverageNext
	ld a, [wEnemyMovePower]
	and a
	jr z, .coverageNext
	farcall AIGetTypeEffectiveness ; on the active mon
	ld a, [wTypeEffectiveness]
	cp EFFECTIVE
	jr c, .coverageNext
	ld a, [wBuffer + AI_BUF_HEDGE_COUNTER]
	call AIHedgeEffectivenessOn
	cp EFFECTIVE
	jr nc, .found
.coverageNext
	call AIHedgeNextSlot
	jr nz, .coverageLoop
; 2. Setup or status.
.statusPass
	xor a
	ld [wBuffer + AI_BUF_HEDGE_SLOT], a
.statusLoop
	call AIHedgeCandidate
	jr z, .statusNext
	ld a, [wEnemyMovePower]
	and a
	jr nz, .statusNext
	ld a, [wEnemyMoveEffect]
	ld hl, AIHedgeEffects
	ld de, 1
	call IsInArray
	jr c, .found
.statusNext
	call AIHedgeNextSlot
	jr nz, .statusLoop
	and a
	ret
.found
	ld a, [wBuffer + AI_BUF_HEDGE_SLOT]
	ld c, a
	ld a, [wBuffer + AI_BUF_HEDGE_BEST]
	ld d, a
	scf
	ret

; nz while AI_BUF_HEDGE_SLOT has slots left after stepping it. Clobbers af, hl.
AIHedgeNextSlot:
	ld hl, wBuffer + AI_BUF_HEDGE_SLOT
	inc [hl]
	ld a, [hl]
	cp NUM_MOVES
	ret

; nz if AI_BUF_HEDGE_SLOT is a hedge candidate: not the best slot, live, and
; scoring within AI_PREDICT_MARGIN of the best. Its move is then loaded
; (wEnemyMove*). Clobbers af, bc, de, hl.
AIHedgeCandidate:
	ld a, [wBuffer + AI_BUF_HEDGE_SLOT]
	ld c, a
	ld a, [wBuffer + AI_BUF_HEDGE_PICK]
	cp c
	jr z, .no
	ld a, c
	call AIHedgeSlotIsLive
	ret z
	ld b, 0
	ld hl, wBuffer
	add hl, bc
	ld a, [wBuffer + AI_BUF_HEDGE_BEST]
	add AI_PREDICT_MARGIN
	cp [hl] ; carry iff best + margin < this score
	jr c, .no
	ld a, c
	call AIHedgeReadSlotMove
	or 1
	ret
.no
	xor a
	ret

; nz if enemy move slot a (0-3) holds a move that is not disabled and has PP.
; Preserves bc, de, hl.
AIHedgeSlotIsLive:
	push hl
	push bc
	ld c, a
	ld b, 0
	ld hl, wEnemyMonMoves
	add hl, bc
	ld a, [hl]
	and a
	jr z, .done
	ld a, [wEnemyDisabledMove]
	swap a
	and $f
	dec a ; the disabled slot 0-3, or $ff for none
	cp c
	jr z, .dead
	ld hl, wEnemyMonPP
	add hl, bc
	ld a, [hl]
	and PP_MASK
	jr .done
.dead
	xor a
.done
	pop bc
	pop hl
	ret

; Loads enemy move slot a (0-3) into wEnemyMove*. Clobbers af, bc, de, hl.
AIHedgeReadSlotMove:
	ld c, a
	ld b, 0
	ld hl, wEnemyMonMoves
	add hl, bc
	ld e, [hl]
	farcall AIReadMoveFromE
	ret

; nz if player party slot c was seen at a menu, is alive and is not the active
; mon. Preserves c.
AIHedgeSeenBenched:
	ld a, [wPlayerMonNumber]
	cp c
	jr z, .no
	ld a, c
	call AISlotBit
	ld hl, wAISeenPlayerMons
	and [hl]
	ret z
	ld hl, wPartyMon1HP
	push bc
	ld a, c
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	pop bc
	ld a, [hli]
	or [hl]
	ret
.no
	xor a
	ret

; wTypeEffectiveness of the loaded enemy move on player party slot a, returned
; in a: the party mon's types stand in for the active mon's for the lookup.
; Clobbers af, bc, de, hl.
AIHedgeEffectivenessOn:
	ld hl, wPartyMon1Type1
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld a, [wBattleMonType1]
	ld d, a
	ld a, [wBattleMonType2]
	ld e, a
	push de
	ld a, [hli]
	ld [wBattleMonType1], a
	ld a, [hl]
	ld [wBattleMonType2], a
	farcall AIGetTypeEffectiveness
	pop de
	ld a, d
	ld [wBattleMonType1], a
	ld a, e
	ld [wBattleMonType2], a
	ld a, [wTypeEffectiveness]
	ret

; a = 1 << a (a = 0-7). Clobbers b.
AISlotBit:
	inc a
	ld b, a
	ld a, 1 << 7
.loop
	rlca
	dec b
	jr nz, .loop
	ret

; Carry SET if this trainer class decides its turn after the player's choice.
; Clobbers af, b, hl.
AIOpponentIsPsychic:
	ldh a, [hIsInBattle]
	cp 2
	jr nz, AIClassIsListed.no ; a wild mon's random move has nothing to gain
	ld hl, AIPsychicClasses
; Carry SET if wTrainerClass is in the $ff-terminated list at hl.
; Clobbers af, b, hl.
AIClassIsListed:
	ld a, [wTrainerClass]
	ld b, a
.next
	ld a, [hli]
	cp $ff
	jr z, .no
	cp b
	jr nz, .next
	scf
	ret
.no
	and a
	ret

; TUNING KNOB: trainer classes that decide their turn AFTER the player's choice,
; so their move, switch and replacement are chosen against the mon the player
; just switched in. One line per class; $ff terminates. Independent of
; AIOmniscientClasses (moveset knowledge).
AIPsychicClasses:
	db FINAL_AI ; the final boss reads your choice (user decision 2026-10-22)
	db $ff

; The classes whose TrainerAI handler (data/trainers/ai_pointers.asm) can switch
; at T0/T1: JugglerAI, CooltrainerFAI and AgathaAI. Keep in step with that
; table; test_ai_turn_plan checks it.
AILowTierSwitchClasses:
	db JUGGLER
	db COOLTRAINER_F
	db AGATHA
	db MORTY
	db KAREN
	db $ff
