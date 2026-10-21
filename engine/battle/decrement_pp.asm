DecrementPP:
; after using a move, decrement pp in battle and (if not transformed?) in party
; Both sides since 2026-10-20 (enemy_move_pp.asm): hWhoseTurn picks the player's
; or the enemy's structs. A wild enemy's party struct is not its own, so only
; its battle copy is decremented.
	ld a, [de]
	cp STRUGGLE
	ret z                ; if the pokemon is using "struggle", there's nothing to do
	                     ; we don't decrement PP for "struggle"
	call .battleStatus1  ; this side's wPlayerBattleStatus1 / wEnemyBattleStatus1
	ld a, [hli]          ; load the BattleStatus1 pokemon status flags and increment hl to load the
	                     ; BattleStatus2 status flags later
	and (1 << STORING_ENERGY) | (1 << THRASHING_ABOUT) | (1 << ATTACKING_MULTIPLE_TIMES)
	ret nz               ; if any of these statuses are true, don't decrement PP
	bit USING_RAGE, [hl]
	ret nz               ; don't decrement PP either if Pokemon is using Rage
	ldh a, [hWhoseTurn]
	and a
	ld hl, wBattleMonPP  ; PP of first move (in battle)
	jr z, .gotBattlePP
	ld hl, wEnemyMonPP
.gotBattlePP

; decrement PP in the battle struct
	call .DecrementPP

; decrement PP in the party struct
	call .battleStatus1
	inc hl
	inc hl               ; this side's BattleStatus3 (the pret wiki tutorial
	                     ; read wPlayerBattleStatus3 on both branches here)
	bit TRANSFORMED, [hl]
	ret nz               ; Return if transformed. Pokemon Red stores the "current pokemon's" PP
	                     ; separately from the "Pokemon in your party's" PP.  This is
	                     ; duplication -- in all cases *other* than Pokemon with Transform.
	                     ; Normally, this means we have to go on and make the same
	                     ; modification to the "party's pokemon" PP that we made to the
	                     ; "current pokemon's" PP.  But, if we're dealing with a Transformed
	                     ; Pokemon, it has separate PP for the move set that it copied from
	                     ; its opponent, which is *not* the same as its real PP as part of your
	                     ; party.  So we return, and don't do that part.

	ldh a, [hWhoseTurn]
	and a
	ld hl, wPartyMon1PP  ; PP of first move (in party)
	ld a, [wPlayerMonNumber] ; which mon in party is active
	jr z, .gotPartyPP
	ldh a, [hIsInBattle]
	dec a
	ret z                ; wild: wEnemyMon1 is not this mon's party struct
	ld hl, wEnemyMon1PP
	ld a, [wEnemyMonPartyPos]
.gotPartyPP
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes       ; calculate address of the mon to modify
.DecrementPP:
	ldh a, [hWhoseTurn]
	and a
	ld a, [wPlayerMoveListIndex] ; which move (0, 1, 2, 3) did we use?
	jr z, .gotMoveIndex
	ld a, [wEnemyMoveListIndex]
.gotMoveIndex
	ld c, a
	ld b, 0
	add hl, bc           ; calculate the address in memory of the PP we need to decrement
	                     ; based on the move chosen.
	dec [hl]             ; Decrement PP

	; CHALLENGE_DOUBLE_PP: burn a second PP point per move use. This tail runs
	; TWICE per move - once for the battle struct via the explicit "call
	; .DecrementPP" above, once for the party struct via fallthrough - so this
	; check naturally applies to both, which is correct and intended. Player
	; only: the challenge is the player's handicap, not the enemy's.
	ldh a, [hWhoseTurn]
	and a
	ret nz
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z
	ld a, [wWitchChallenge]
	cp CHALLENGE_DOUBLE_PP
	ret nz
	ld a, [hl]
	and PP_MASK          ; PP only - ignore the PP Up count packed in bits 6-7
	ret z                ; already at 0 - never wrap into the PP Up bits
	dec [hl]
	ret

; hl = wPlayerBattleStatus1 on the player's turn, wEnemyBattleStatus1 on the enemy's.
.battleStatus1:
	ldh a, [hWhoseTurn]
	and a
	ld hl, wPlayerBattleStatus1
	ret z
	ld hl, wEnemyBattleStatus1
	ret
