HazeEffect_:
	ld a, $7
; store 7 on every stat mod
	ld hl, wPlayerMonAttackMod
	call ResetStatMods
	ld hl, wEnemyMonAttackMod
	call ResetStatMods
; copy unmodified stats to battle stats
	ld hl, wPlayerMonUnmodifiedAttack
	ld de, wBattleMonAttack
	call ResetStats
	ld hl, wEnemyMonUnmodifiedAttack
	ld de, wEnemyMonAttack
	call ResetStats
; Shin Red import Phase 13.6: cure non-volatile status on BOTH sides, as Shin
; does (vanilla cured only the target, leaving the user's burn/paralysis on with
; its stat penalty already wiped by ResetStats above).
	ld hl, wBattleMonStatus
	ld de, wPlayerSelectedMove
	ld bc, wPlayerBattleStatus1
	call .cureStatus
	ld hl, wEnemyMonStatus
	ld de, wEnemySelectedMove
	ld bc, wEnemyBattleStatus1
	call .cureStatus
	jr .cureVolatileStatuses

.cureStatus
; A side that was asleep or frozen skipped move selection this round, so its
; selected move is stale (0 at battle start); CANNOT_MOVE stops it acting.
; Shin drops this write outright, but Shin lets sleepers select a move and
; Red Rogue does not. A side locked into a move keeps its move instead: the
; vanilla write there was the Bide/Thrash/Rage/Hyper Beam never-acts glitch.
	ld a, [hl]
	ld [hl], 0
	and (1 << FRZ) | SLP_MASK
	ret z
	ld a, [bc]
	and (1 << STORING_ENERGY) | (1 << THRASHING_ABOUT) | (1 << CHARGING_UP) | (1 << USING_TRAPPING_MOVE)
	ret nz
	inc bc ; BATTSTATUS2
	ld a, [bc]
	and (1 << NEEDS_TO_RECHARGE) | (1 << USING_RAGE)
	ret nz
	ld a, CANNOT_MOVE
	ld [de], a
	ret

.cureVolatileStatuses
	xor a
	; Shin Red import Phase 13.6: CureVolatileStatuses clears BADLY_POISONED on
	; both sides; zero the matching counters with it.
	ld [wPlayerToxicCounter], a
	ld [wEnemyToxicCounter], a
	ld [wPlayerDisabledMove], a
	ld [wEnemyDisabledMove], a
	ld hl, wPlayerDisabledMoveNumber
	ld [hli], a
	ld [hl], a
	ld hl, wPlayerBattleStatus1
	call CureVolatileStatuses
	ld hl, wEnemyBattleStatus1
	call CureVolatileStatuses
	ld hl, PlayCurrentMoveAnimation
	call CallBankF
	ld hl, StatusChangesEliminatedText
	jp PrintText

CureVolatileStatuses:
	res CONFUSED, [hl]
	inc hl ; BATTSTATUS2
	ld a, [hl]
	; clear USING_X_ACCURACY, PROTECTED_BY_MIST, GETTING_PUMPED, and SEEDED statuses
	and ~((1 << USING_X_ACCURACY) | (1 << PROTECTED_BY_MIST) | (1 << GETTING_PUMPED) | (1 << SEEDED))
	ld [hli], a ; BATTSTATUS3
	ld a, [hl]
	and %11110000 | (1 << TRANSFORMED) ; clear Bad Poison, Reflect and Light Screen statuses
	ld [hl], a
	ret

ResetStatMods:
	ld b, NUM_STAT_MODS
.loop
	ld [hli], a
	dec b
	jr nz, .loop
	ret

ResetStats:
	ld b, (NUM_STATS - 1) * 2 ; doesn't reset STAT_HEALTH
.loop
	ld a, [hli]
	ld [de], a
	inc de
	dec b
	jr nz, .loop
	ret

StatusChangesEliminatedText:
	text_far _StatusChangesEliminatedText
	text_end
