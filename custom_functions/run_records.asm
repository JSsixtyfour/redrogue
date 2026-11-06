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
	ld hl, wFurthestRunsFirst
	ld bc, 8
	xor a
	call FillMemory
	ld hl, wFurthestRunsLast
	ld bc, 2
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

; ---------------------------------------------------------------------------
; Furthest runs: five (depth, count) pairs in saved padding, best first. Unlike
; the fastest clears, every ended run can rank, so the commit is separate from
; RunRecordsCommit: that one runs before the Endless offer, when nobody yet knows
; whether the run is over.
; ---------------------------------------------------------------------------

; Publish the run that just ended. Callers run it once, before anything wipes
; run state: LossRecoveryCapture (blackout and END RUN, before the record is
; taken, because the record does not hold wBattleCount) and the Hall of Fame's
; normal-clear branch (Endless declined or not offered). Debug runs do not rank.
FurthestRunsCommit::
	ld a, [wStatusFlags6]
	and (1 << BIT_DEBUG_MODE) | (1 << BIT_DEBUG2_MODE)
	ret nz
	call FurthestRunRanks
	ret nc
	call FurthestRunsRead
	ld hl, wBuffer
	ld b, 5
.find
	ld a, [wEndlessDepth]
	cp [hl]
	jr c, .next
	jr nz, .insert
	inc hl
	ld a, [wBattleCount]
	cp [hl]
	dec hl                       ; leaves the flags: 16-bit
	jr c, .next
	jr nz, .insert               ; a tie keeps the older run first
.next
	inc hl
	inc hl
	dec b
	jr nz, .find
	ret                          ; below all five
.insert
	; Move the entries from here down one slot, discarding the fifth.
	push hl
	ld a, b
	dec a
	add a
	ld c, a                      ; bytes to move
	ld de, wBuffer + 9
	ld hl, wBuffer + 7
.shift
	ld a, c
	and a
	jr z, .shifted
	ld a, [hld]
	ld [de], a
	dec de
	dec c
	jr .shift
.shifted
	pop hl
	ld a, [wEndlessDepth]
	ld [hli], a
	ld a, [wBattleCount]
	ld [hl], a
	ld hl, wBuffer
	ld de, wFurthestRunsFirst
	ld bc, 8
	call CopyData
	ld hl, wBuffer + 8
	ld de, wFurthestRunsLast
	ld bc, 2
	jp CopyData

FurthestRunsRead:
	ld hl, wFurthestRunsFirst
	ld de, wBuffer
	ld bc, 8
	call CopyData
	ld hl, wFurthestRunsLast
	ld de, wBuffer + 8
	ld bc, 2
	jp CopyData

; Carry set if the current run has won anything: Oak's Lab leaves wBattleCount
; at 1, and a continuation sets it back to 1 with the depth raised.
FurthestRunRanks:
	ld a, [wEndlessDepth]
	and a
	jr nz, .yes
	ld a, [wBattleCount]
	cp 2
	ccf
	ret
.yes
	scf
	ret

; One row of numbers. IN: b = depth, c = wBattleCount, hl = column 5 of the row.
; Scratch: wBuffer + 10/11, past the table; PrintNumber reads big-endian.
FurthestRunsPrintRow:
	; circuit = depth + 1, which reaches 256
	ld a, b
	add 1
	ld [wBuffer + 11], a
	ld a, 0
	adc a
	ld [wBuffer + 10], a
	push bc
	call .number4
	inc hl
	pop bc
	push bc
	; Round in this circuit, 1-based. The Elite Four's counts run past the last
	; round's row, so hold at Victory Road / Elite Four.
	ld a, c
	ASSERT ROUND_BATTLES == 8
	srl a
	srl a
	srl a
	cp LAST_ROUND
	jr c, .roundReady
	ld a, LAST_ROUND
.roundReady
	inc a
	ld [wBuffer + 11], a
	xor a
	ld [wBuffer + 10], a
	push hl
	ld de, wBuffer + 10
	lb bc, 2, 3
	call PrintNumber
	pop hl
	ld de, 4
	add hl, de
	pop bc
	; Wins: wBattleCount + depth * ENDLESS_CIRCUIT_SPAN - 1, 16-bit. Not
	; GetRunProgress, which saturates at 255.
	push hl
	ld h, 0
	ld l, c
	ld de, ENDLESS_CIRCUIT_SPAN
	ld a, b
	and a
	jr z, .totalled
.total
	add hl, de
	dec a
	jr nz, .total
.totalled
	dec hl
	ld a, h
	ld [wBuffer + 10], a
	ld a, l
	ld [wBuffer + 11], a
	pop hl
	ld de, wBuffer + 10
	lb bc, 2, 5
	jp PrintNumber
.number4
	push hl
	ld de, wBuffer + 10
	lb bc, 2, 4
	call PrintNumber
	pop hl
	ld de, 4
	add hl, de
	ret

FurthestRunsShow::
	call ClearScreen
	hlcoord 0, 0
	lb bc, 16, 18
	call TextBoxBorder
	hlcoord 2, 1
	ld de, .Title
	call PlaceString
	hlcoord 2, 3
	ld de, .Header
	call PlaceString
	call FurthestRunsRead
	ld a, [wBuffer]
	ld b, a
	ld a, [wBuffer + 1]
	or b
	jr nz, .table
	hlcoord 2, 6
	ld de, .Empty
	call PlaceString
	jr .thisRun
.table
	ld de, wBuffer
	hlcoord 2, 4
	ld c, 5
	ld a, CHARVAL("1")
.row
	push af
	push bc
	push de
	push hl
	ld [hli], a
	ld [hl], CHARVAL(".")
	ld a, [de]
	ld b, a
	inc de
	ld a, [de]
	ld c, a
	or b
	jr z, .rowDone               ; an unused slot: its rank alone
	inc hl
	inc hl                       ; column 5
	call FurthestRunsPrintRow
.rowDone
	pop hl
	ld de, SCREEN_WIDTH
	add hl, de
	pop de
	inc de
	inc de
	pop bc
	pop af
	inc a
	dec c
	jr nz, .row
.thisRun
	call FurthestRunRanks
	jr nc, .wait
	hlcoord 2, 11
	ld de, .ThisRun
	call PlaceString
	ld a, [wEndlessDepth]
	ld b, a
	ld a, [wBattleCount]
	ld c, a
	hlcoord 5, 12
	call FurthestRunsPrintRow
.wait
	hlcoord 2, 15
	ld de, .Back
	call PlaceString
	call UpdateSprites
	jp WaitForTextScrollButtonPress
.Title
	db "FURTHEST RUNS@"
.Header
	db "   CIRC RND  WINS@"
.Empty
	db "NO RUNS YET.@"
.ThisRun
	db "THIS RUN@"
.Back
	db "A/B: BACK@"

RoomRecordsMenu::
.menu
	call LoadScreenTilesFromBuffer2
	hlcoord 0, 0
	lb bc, 8, 14
	ld a, [wNumHoFTeams]
	and a
	jr z, .drawBorder
	inc b
	inc b
.drawBorder
	ld a, b
	srl a
	dec a
	ld [wMaxMenuItem], a
	call TextBoxBorder
	hlcoord 2, 2
	ld de, .Times
	call PlaceString
	hlcoord 2, 4
	ld de, .Furthest
	call PlaceString
	hlcoord 2, 6
	ld a, [wNumHoFTeams]
	and a
	jr z, .drawSpecial
	ld de, .Hall
	call PlaceString
	hlcoord 2, 8
.drawSpecial
	ld de, .Special
	call PlaceString
	ld bc, 2 * SCREEN_WIDTH
	add hl, bc
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
	ld a, PAD_A | PAD_B
	ld [wMenuWatchedKeys], a
	call HandleMenuInput
	bit B_PAD_B, a
	ret nz
	ldh a, [hCurrentMenuItem]
	ld hl, wMaxMenuItem
	cp [hl]
	ret z
	cp 3
	jr z, .special
	cp 2
	jr z, .hallOrSpecial
	and a
	jr nz, .furthest
	call RunRecordsShow
	jp .menu
.furthest
	call FurthestRunsShow
	jp .menu
.hallOrSpecial
	ld a, [wNumHoFTeams]
	and a
	jr nz, .hof
.special
	farcall SpecialCollectionMenu
	jr .reload
.hof
	farcall PKMNLeaguePC
.reload
	call ReloadMapData ; restore Dorm tiles overwritten by the Pokemon pictures
	jp .menu
.Times
	db "RUN TIMES@"
.Furthest
	db "FURTHEST RUNS@"
.Hall
	db "HALL OF FAME@"
.Special
	db "SPECIAL FORMS@"
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
