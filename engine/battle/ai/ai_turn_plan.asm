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
	call AIOpponentIsPsychic
	ret c ; decides at commit, after the player's choice
	ldh a, [hWhoseTurn] ; the move menu must see the side it had (FOLLOWUPS #44)
	push af
	call AIDecideEnemyTurn
	pop af
	ldh [hWhoseTurn], a
	ld hl, wAITurnPlan
	set AI_TURN_PLANNED_BIT, [hl]
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
	farcall SelectEnemyMove
	jr .trainerAI
.decideNow
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
; side. Clobbers af, bc, de, hl.
AIDecideEnemyTurn:
	xor a
	ld [wAITurnPlan], a
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
