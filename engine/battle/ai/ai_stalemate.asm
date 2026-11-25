; B17's first term, a stalemate breaker (AI_T4_REGRET_PLAN, 2026-11-17). Carry SET
; if the active mon has NOTHING it is willing to do that deals damage this turn:
; no move with PP, not disabled, whose estimate in wAIEnemyEstimateCache (filled
; by AI_DAMAGE this decision, T2+) is above zero, except Self-Destruct/Explosion
; that the AI did not choose (the Explosion veto refused the trade). Measured:
; seed 288's Weezing (Amnesia / Self-Destruct / Haze / Explosion) against a 27-HP
; Ekans looped Amnesia and Haze ~30 turns, each costing +0.22 of party HP, while a
; switch won; a plain "every estimate is 0" test misses it, Explosion's is 999.
; Out of bank $10 since 2026-11-24 (debug had 3 B free): WRAM reads and FarCopyData
; only, reached by farcall, so any bank with room would do.
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
; damage, so a status user keeps using it, IF it can still land (2026-11-24, seed
; 9008: a mon out of Psywave PP spent ~70 turns on Poison Gas into a paralyzed
; target, with a healthy reserve).
; Boosts, Haze and screens are not on the list: against a foe we cannot damage
; they buy nothing, which is exactly seed 288's Amnesia/Haze loop.
	ld a, [wEnemySelectedMove]
	and a
	jr z, .scan
	cp NUM_ATTACKS + 1 ; $ff means the enemy could not select a move
	jr nc, .scan
	ld b, a
	ld e, MOVE_EFFECT
	call .moveByte
	ld hl, .progressEffects
.progressLoop
	cp [hl]
	jr z, .chosenStatus
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
	ld a, b
	cp DREAM_EATER ; needs a sleeper, which neither the estimate nor its power shows
	jr nz, .usable
	ld a, [wBattleMonStatus]
	and SLP_MASK
	jr z, .next
.usable
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
; a = the chosen status move's effect. Can it still land? A major status needs a
; target without one; Leech Seed's target is not seeded here (checked above).
.chosenStatus
	cp LEECH_SEED_EFFECT
	jr z, .canAct
	cp CONFUSION_EFFECT
	jr z, .confusion
	cp DISABLE_EFFECT
	jr z, .disable
	ld a, [wBattleMonStatus]
	and a
	jr .statusVerdict
.confusion
	ld a, [wPlayerBattleStatus1]
	and 1 << CONFUSED
	jr .statusVerdict
.disable
	ld a, [wPlayerDisabledMove]
	and a
.statusVerdict
	jr z, .canAct
	jp .scan
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
