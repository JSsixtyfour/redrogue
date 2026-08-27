; Yume-style START cycling, without changing Red Rogue's mon/page ownership.
; View state lives on the stack while waiting, not in save-backed menu RAM.
StatusScreenInitView:
	ld e, STATS_BOX_NORMAL
	jp StatusScreenDrawView

StatusScreenWaitView:
	ld e, STATS_BOX_NORMAL
.wait
	push de
	call DelayFrame
	call Joypad
	pop de
	ldh a, [hJoyPressed]
	and PAD_A | PAD_B
	ret nz ; retain the caller's existing move-page behavior
	ldh a, [hJoyPressed]
	bit B_PAD_START, a
	jr z, .wait
	; Existing enum is NORMAL=0, STAT_EXP=1, DVS=2.
	dec e
	ld a, e
	cp $ff
	jr nz, .draw
	ld e, STATS_BOX_DVS
.draw
	push de
	call StatusScreenDrawView
	pop de
	jr .wait

StatusScreenDrawView:
	push de
	ld d, STATUS_SCREEN_STATS_BOX
	farcall PrintStatsBox
	pop de
	ld a, e
	ld de, .Stats
	and a
	jr z, .label
	ld de, .StatExp
	dec a
	jr z, .label
	ld de, .DVs
.label
	hlcoord 1, 8
	call PlaceString
	hlcoord 13, 8
	ld de, .Start
	jp PlaceString
.Stats
	db "STATS@"
.DVs
	db "DVs@"
.StatExp
	db "STAT.EXP@"
.Start
	db "START@"
