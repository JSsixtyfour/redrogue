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
	set AI_TURN_MOVE_CHOSEN_BIT, [hl]
	ret

; core.asm .selectEnemyMove, once per turn: the enemy's turn as planned (or
; decided now), then TrainerAI's switch, which goes before every move.
; OUTPUT: carry SET if TrainerAI spent the enemy's turn.
AICommitEnemyTurn::
	ld hl, wAITurnPlan
	bit AI_TURN_MOVE_CHOSEN_BIT, [hl]
	res AI_TURN_MOVE_CHOSEN_BIT, [hl] ; res keeps the flags
	call z, AIDecideEnemyTurn ; a forced turn, a psychic class or a link battle
	ld a, 1
	ldh [hWhoseTurn], a
	farcall TrainerAI ; carry survives the farcall return
	ret

; The move, then for a trainer everything TrainerAI would read off the player's
; side. Clobbers af, bc, de, hl.
AIDecideEnemyTurn:
	xor a
	ld [wAITurnPlan], a
	farcall SelectEnemyMove
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
; AITrySmartSwitch); T0/T1 class rolls decide at commit, but either way the
; replacement is ranked here, against the board the player saw.
	farcall AIGetTier ; resolve wAITier - its `a` return cannot survive the trip
	ld a, [wAITier]
	cp AI_TIER_SKILLED + 1 ; wAITier holds tier + 1, 0 = unresolved
	jr c, .rank
	farcall AIShouldSwitchAtSelectedSpeed
.switchDecisionReady ; carry = switch. Zero-byte test seam: this replaces the
                      ; old AISwitchIfEnoughMons.switchDecisionReady as the
                      ; point where the live decision (and the CGB speed
                      ; wrapper around it) actually happens; TrainerAI's own
                      ; .switchDecisionReady now just plays back wAITurnPlan.
	jr nc, .rank
	ld hl, wAITurnPlan
	set AI_TURN_SWITCH_BIT, [hl]
.rank
	farcall AIRankSendOutCandidates
	ld a, [wBuffer + AI_BUF_BESTPARTYSLOT]
	inc a ; slot + 1, and $ff (none) -> 0
	ld hl, wAITurnPlan
	or [hl]
	ld [hl], a
	ret

; Carry SET if this trainer class decides its turn after the player's choice.
; Clobbers af, b, hl.
AIOpponentIsPsychic:
	ldh a, [hIsInBattle]
	cp 2
	jr nz, .no ; a wild mon's random move has nothing to gain
	ld a, [wTrainerClass]
	ld b, a
	ld hl, AIPsychicClasses
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
