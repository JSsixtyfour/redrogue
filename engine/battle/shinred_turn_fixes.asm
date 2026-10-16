; Shin Red import Phase 13 (2026-10-16): per-round battle fixups. Both are
; predefs so their Battle Core / bank $38 call sites cost 3 B each.

; Once per round, from the top of BattleTurnCommitted (MainInBattleLoop's
; .selectEnemyMove seam, reached exactly once per turn before either side acts).
;  1. Phase 13.3: Rage and Thrash/Petal Dance repeat without GetCurrentMove, so
;     the side's move accuracy is never reloaded, while CalcHitChance writes its
;     accuracy/evasion-modified result back into it. Under an accuracy drop the
;     hit chance compounded every turn. Restore the base accuracy ($FF = 100%,
;     which Rage, Thrash and Petal Dance all are), as shinpokered does.
;  2. Phase 13.7: clear both sides' MOVING_SECOND flag for the new round.
; Clobbers af, hl, de.
BattleRoundStartFixups:
	ld hl, wPlayerBattleStatus1
	ld de, wPlayerMoveAccuracy
	call .side
	ld hl, wEnemyBattleStatus1
	ld de, wEnemyMoveAccuracy
.side
	ld a, [hli] ; BATTSTATUS1
	bit THRASHING_ABOUT, a
	jr nz, .resetAccuracy
	bit USING_RAGE, [hl] ; BATTSTATUS2
	jr z, .clearOrder
.resetAccuracy
	ld a, $ff
	ld [de], a
.clearOrder
	res MOVING_SECOND, [hl]
	ret

; Phase 13.7, ported from shinpokered PlayerDisableHandler/EnemyDisableHandler
; (custom_functions/func_battle.asm), merged into one routine keyed on
; hWhoseTurn. Called just before a Disable counter ticks, with hl = that side's
; w{Player,Enemy}DisabledMove; returns with hl, de and bc as the caller had them.
;
; The tick happens when the disabled mon acts. If Disable landed earlier in the
; same round, a slower target ticks immediately, so a roll of 1 expired before it
; ever blocked a menu and the real range was 0-7 turns. DisableEffect therefore
; stores a fresh roll n (1-8) as n + 8 wrapped into the nibble (9-F, 0). On the
; first tick this recovers n; if the side is moving second it then turns a 1 into
; 9, which ticks to 8. Moving second, rolls 2-8 give 1-7 blocked turns and a 1
; gives 8, so the range is 1-8 either way.
DisableCounterFixup:
	call GetPredefRegisters
	push bc
	ld a, [wPlayerBattleStatus2]
	ld c, a
	ldh a, [hWhoseTurn]
	and a
	jr z, .gotSide
	ld a, [wEnemyBattleStatus2]
	ld c, a
.gotSide
	ld a, [hl]
	and $f
	cp 9
	jr nc, .fresh
	and a
	jr nz, .done ; a live 1-8 count from an earlier tick
.fresh
	sub 8
	jr nc, .gotCount
	ld a, 8 ; nibble 0 encodes a fresh 8
.gotCount
	bit MOVING_SECOND, c
	jr z, .store
	cp 1
	jr nz, .store
	ld a, 9 ; ticks to 8 in the caller
.store
	ld b, a
	ld a, [hl]
	and $f0
	or b
	ld [hl], a
.done
	pop bc
	ret
