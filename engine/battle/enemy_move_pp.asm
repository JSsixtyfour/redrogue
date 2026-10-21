; Enemy Pokemon spend PP (2026-10-20), after the pret wiki tutorial "Enemy
; Pokemon Use PP". In vanilla Gen 1 an enemy's PP is never decremented or
; checked, so a faster Wrap user could lock the player out until the whole
; party fell (measured: Giovanni's Tentacruel held a Wrap for ~17,000 frames).
;
; Battle Core (bank $0F) is full, so the tutorial's core.asm edits live here
; and Battle Core reaches them by farcall:
;   EnemyCanExecuteMove  -> EnemyMoveExecuted   (was AITrackExecutedEnemyMove)
;   LoadEnemyMonData     -> LoadEnemyMonPP      (was predef LoadMovePPs)
;   SelectEnemyMove      -> ChooseEnemyMove     (its non-link body)
; DecrementPP (decrement_pp.asm) now serves both sides by hWhoseTurn. The AI's
; legality filter (trainer_ai.asm) and Disable (effects.asm) skip moves with
; no PP left.

; EnemyCanExecuteMove, after "<ENEMY> used <MOVE>!" (hWhoseTurn = 1): record
; the move for the AI's history, then spend its PP.
EnemyMoveExecuted::
	farcall AITrackExecutedEnemyMove
	ld de, wEnemySelectedMove
	jp DecrementPP

; LoadEnemyMonData: the battle mon's PP. A trainer's mon keeps the PP its party
; struct holds, so PP it spent survives switching out; a wild mon gets full PP.
; The party structs hold each move's max PP (measured over 2,316 move slots).
LoadEnemyMonPP::
	ldh a, [hIsInBattle]
	cp 2 ; trainer battle?
	jr nz, .fullPP
	ld hl, wEnemyMon1PP
	ldh a, [hWhichPokemon]
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld de, wEnemyMonPP
	ld bc, NUM_MOVES
	jp CopyData
.fullPP
	ld hl, wEnemyMonMoves
	ld de, wEnemyMonPP - 1
	predef_jump LoadMovePPs

; SelectEnemyMove, once the enemy is free to choose in a non-link battle.
; Struggle when no move has PP left (a disabled move's PP not counted), else
; the trainer AI's candidates (or every move, for a wild mon) drawn at random
; until one is present, not disabled and has PP. Writes wEnemySelectedMove and
; wEnemyMoveListIndex. The draw always ends: EnemyHasMoveWithPP found a slot
; that passes all three, and the AI's legality filter keeps one too.
ChooseEnemyMove::
	call EnemyHasMoveWithPP
	jr nz, .choose
	ld a, STRUGGLE
	ld [wEnemySelectedMove], a
	ret
.choose
	ld hl, wEnemyMonMoves
	ldh a, [hIsInBattle]
	dec a
	jr z, .chooseRandomMove ; wild encounter
	farcall AIEnemyTrainerChooseMoves ; hl = the candidates (wBuffer)
.chooseRandomMove
	push hl
	call Random ; BattleRandom outside a link battle
	ld b, 1 ; 25% chance to select move 1
	cp 25 percent
	jr c, .moveChosen
	inc hl
	inc b ; 25% chance to select move 2
	cp 50 percent
	jr c, .moveChosen
	inc hl
	inc b ; 25% chance to select move 3
	cp 75 percent - 1
	jr c, .moveChosen
	inc hl
	inc b ; 25% chance to select move 4
.moveChosen
	ld a, b
	dec a
	ld [wEnemyMoveListIndex], a
	call EnemySlotHasPP
	jr z, .redraw ; no PP left in this slot
	ld a, [wEnemyDisabledMove]
	swap a
	and $f
	cp b
	ld a, [hl]
	pop hl
	jr z, .chooseRandomMove ; move disabled, try again
	and a
	jr z, .chooseRandomMove ; move non-existent, try again
	ld [wEnemySelectedMove], a
	ret
.redraw
	pop hl
	jr .chooseRandomMove

; nz if the enemy has a move it can use: present, not disabled, PP left -
; exactly the draw's three tests, so the draw cannot loop forever. (A slot
; with PP but no move never comes from party generation, but the moveless
; guard this replaced existed for a freeze, so the move is checked too.)
EnemyHasMoveWithPP:
	ld a, [wEnemyDisabledMove]
	swap a
	and $f
	ld c, a ; disabled slot 1-4, or 0
	ld b, 1
.loop
	ld a, b
	cp c
	jr z, .next ; a disabled move's PP does not count
	ld hl, wEnemyMonMoves - 1
	ld e, b
	ld d, 0
	add hl, de
	ld a, [hl]
	and a
	jr z, .next ; no move in this slot
	call EnemySlotHasPP
	ret nz
.next
	inc b
	ld a, b
	cp NUM_MOVES + 1
	jr nz, .loop
	xor a ; z: Struggle
	ret

; nz if enemy move slot b (1-4) has PP left. Preserves bc, de, hl.
EnemySlotHasPP:
	push hl
	push bc
	ld hl, wEnemyMonPP - 1
	ld c, b
	ld b, 0
	add hl, bc
	ld a, [hl]
	and PP_MASK
	pop bc
	pop hl
	ret
