; TryKODefiance (core.asm) has decided to revive the active mon: half of max HP (at
; least 1), major status cleared, stat stages reset as LoadBattleMonFromParty does for
; a fresh send-out. Out of Battle Core because that bank is full; farcall only, plain
; WRAM reads and writes, so any bank with room would do. Clobbers af, bc, hl.
KODefianceRevive::
	ld hl, wBattleMonMaxHP
	ld a, [hli]
	ld b, a
	ld c, [hl]
	srl b
	rr c
	ld a, b
	or c
	jr nz, .haveRevivalHP
	ld c, 1
.haveRevivalHP
	ld hl, wBattleMonHP
	ld a, b
	ld [hli], a
	ld [hl], c
; A sleeping mon skipped move selection this round, so its selected move is stale (the
; fainted mon's, or 0 at battle start). If the enemy moved first, the revived mon's own
; action is still to come and, awake now, would use it: CANNOT_MOVE stops that, as in
; HazeEffect_. A mon locked into a move keeps it. A frozen mon chose a real move.
	ld a, [wBattleMonStatus]
	and SLP_MASK
	jr z, .moveSettled
	ld a, [wPlayerBattleStatus1]
	and (1 << STORING_ENERGY) | (1 << THRASHING_ABOUT) | (1 << CHARGING_UP) | (1 << USING_TRAPPING_MOVE)
	jr nz, .moveSettled
	ld a, [wPlayerBattleStatus2]
	and (1 << NEEDS_TO_RECHARGE) | (1 << USING_RAGE)
	jr nz, .moveSettled
	ld a, CANNOT_MOVE
	ld [wPlayerSelectedMove], a
.moveSettled
	xor a
	ld [wBattleMonStatus], a
	ld a, $7 ; default stat modifier
	ld b, NUM_STAT_MODS
	ld hl, wPlayerMonStatMods
.statModResetLoop
	ld [hli], a
	dec b
	jr nz, .statModResetLoop
.revived
	ret
