; Legacy entrypoints clear stale saved flags without moving any object.
TryPushingBoulder::
DoBoulderDustAnimation::
ResetBoulderPushFlags:
	ld hl, wMiscFlags
	res BIT_BOULDER_DUST, [hl]
	res BIT_TRIED_PUSH_BOULDER, [hl]
	ret
