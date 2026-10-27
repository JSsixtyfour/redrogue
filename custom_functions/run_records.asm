; Farcalled leaves and their local menu/data helpers. No SRAM mapping changes.
; Saved padding holds all state; the ordinary main-save checksum covers it.
SECTION "Run Records", ROMX, BANK[$12]

RunRecordsInit::
	ld hl, wRunRecordCount
	ld bc, 10
	xor a
	call FillMemory
	ld hl, wRunRecordsLast
	ld bc, 6
	xor a
	call FillMemory
RunTimerReset::
	xor a
	ld [wRunTimerState], a
	ret

; Called only after a starter has been accepted, before the rival walks.
RunTimerStart::
	ld hl, wRunTimerState
	ld bc, 5
	xor a
	call FillMemory
	ld a, 1
	ld [wRunTimerState], a
	ret

; VBlank leaf: no shared scratch, UI, SRAM or nested farcalls.
RunTimerTick::
	ld a, [wRunTimerState]
	cp 1
	ret nz
	ld hl, wRunTimerFrames
	inc [hl]
	ld a, [hl]
	cp 60
	ret c
	xor a
	ld [hld], a
	inc [hl] ; seconds
	ld a, [hl]
	cp 60
	ret c
	xor a
	ld [hld], a
	inc [hl] ; minutes
	ld a, [hl]
	cp 60
	ret c
	xor a
	ld [hld], a
	inc [hl] ; hours
	ret nz
	; Saturate rather than wrapping a 256-hour run into a fast record.
	ld a, $ff
	ld [hli], a
	ld a, 59
	ld [hli], a
	ld [hli], a
	ld [hl], a
	ld a, 2
	ld [wRunTimerState], a
	ret

; Stop before Champion congratulations. An imported/inactive run stays idle.
RunTimerFinish::
	ld a, [wRunTimerState]
	cp 1
	ret nz
	ld a, 2
	ld [wRunTimerState], a
	ret

; Publish only on the normal Hall of Fame path, before its run-reset save.
; A reset/load before that save restores BOTH the timer and previous table.
RunRecordsCommit::
	ld a, [wRunTimerState]
	cp 2
	ret nz
	call RunTimerReset
	call RunRecordsRead
	ld hl, wBuffer + 1
	ld b, 5
.find
	ld a, [hli] ; all-zero entries are unused (a clear takes >0 seconds)
	ld c, a
	ld a, [hli]
	or c
	or [hl]
	dec hl
	dec hl
	jr z, .insert
	push hl
	ld de, wRunTimerHours
	ld c, 3
.compare
	ld a, [de]
	cp [hl]
	jr nz, .compared
	inc de
	inc hl
	dec c
	jr nz, .compare
.compared
	pop hl
	jr c, .insert
	inc hl
	inc hl
	inc hl
	dec b
	jr nz, .find
	ret
.insert
	; Move the remaining entries backwards, discarding the sixth.
	push hl
	ld d, h
	ld e, l
	ld hl, wBuffer + 12
.shift
	ld a, h
	cp d
	jr c, .shifted
	jr nz, .copy
	ld a, l
	cp e
	jr c, .shifted
.copy
	ld a, [hl]
	inc hl
	inc hl
	inc hl
	ld [hld], a
	dec hl
	dec hl
	dec hl
	jr .shift
.shifted
	pop de
	ld hl, wRunTimerHours
	ld bc, 3
	call CopyData
	ld a, [wBuffer]
	cp 5
	jr nc, .store
	inc a
	ld [wBuffer], a
.store
	ld hl, wBuffer
	ld de, wRunRecordCount
	ld bc, 10
	call CopyData
	ld hl, wBuffer + 10
	ld de, wRunRecordsLast
	ld bc, 6
	jp CopyData

RunRecordsRead:
	ld hl, wRunRecordCount
	ld de, wBuffer
	ld bc, 10
	call CopyData
	ld hl, wRunRecordsLast
	ld de, wBuffer + 10
	ld bc, 6
	jp CopyData

RoomRecordsMenu::
.menu
	call LoadScreenTilesFromBuffer2
	hlcoord 0, 0
	lb bc, 8, 14
	call TextBoxBorder
	hlcoord 2, 2
	ld de, .Times
	call PlaceString
	hlcoord 2, 4
	ld de, .Hall
	call PlaceString
	hlcoord 2, 6
	ld de, .Back
	call PlaceString
	xor a
	ldh [hCurrentMenuItem], a
	ld [wMenuWatchMovingOutOfBounds], a
	ld hl, wTopMenuItemY
	ld a, 2
	ld [hli], a
	dec a
	ld [hl], a
	ld a, 2
	ld [wMaxMenuItem], a
	ld a, PAD_A | PAD_B
	ld [wMenuWatchedKeys], a
	call HandleMenuInput
	bit B_PAD_B, a
	ret nz
	ldh a, [hCurrentMenuItem]
	cp 2
	ret z
	and a
	jr nz, .hof
	call RunRecordsShow
	jr .menu
.hof
	farcall PKMNLeaguePC
	call ReloadMapData ; restore Dorm tiles overwritten by the Pokemon pictures
	jr .menu
.Times
	db "RUN TIMES@"
.Hall
	db "HALL OF FAME@"
.Back
	db "BACK@"

RunRecordsShow::
	call ClearScreen
	hlcoord 0, 0
	lb bc, 16, 18
	call TextBoxBorder
	hlcoord 2, 1
	ld de, .Title
	call PlaceString
	call RunRecordsRead
	ld a, [wBuffer]
	and a
	jr z, .empty
	cp 6
	jr nc, .empty
	ld c, a
	ld de, wBuffer + 1
	hlcoord 2, 4
	ld a, CHARVAL("1")
.row
	ld [hli], a
	ld [hl], CHARVAL(".")
	inc hl
	inc hl
	push af
	push bc
	push hl
	lb bc, LEADING_ZEROES | 1, 3
	push de
	call PrintNumber
	pop de
	ld [hl], CHARVAL(":")
	inc hl
	inc de
	lb bc, LEADING_ZEROES | 1, 2
	push de
	call PrintNumber
	pop de
	ld [hl], CHARVAL(":")
	inc hl
	inc de
	lb bc, LEADING_ZEROES | 1, 2
	push de
	call PrintNumber
	pop de
	inc de
	pop hl
	ld bc, 2 * SCREEN_WIDTH - 3
	add hl, bc
	pop bc
	pop af
	inc a
	dec c
	jr nz, .row
	jr .wait
.empty
	hlcoord 2, 5
	ld de, .Empty
	call PlaceString
.wait
	hlcoord 2, 15
	ld de, .Back
	call PlaceString
	call UpdateSprites
	jp WaitForTextScrollButtonPress
.Title
	db "FASTEST CLEARS@"
.Empty
	db "NO TIMES YET.@"
.Back
	db "A/B: BACK@"
