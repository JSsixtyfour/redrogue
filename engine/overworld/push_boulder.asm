; Legacy entrypoints clear stale saved flags without moving any object.
TryPushingBoulder::
DoBoulderDustAnimation::
; [code sweep 2026-09-27] unreferenced vanilla code, commented out to reclaim ROM
;ResetBoulderPushFlags:
	ld hl, wMiscFlags
	res BIT_BOULDER_DUST, [hl]
	res BIT_TRIED_PUSH_BOULDER, [hl]
	ret
