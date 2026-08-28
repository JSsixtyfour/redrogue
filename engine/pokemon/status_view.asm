; Yume-style START cycling, without changing Red Rogue's mon/page ownership.
; View state lives on the stack while waiting, not in save-backed menu RAM.
; The unused English-font slots $c0-$cd do not overlap either mon picture.
DEF STATUS_EXP_TILE EQU $c0
DEF STATUS_START_TILE EQU STATUS_EXP_TILE + 11

StatusScreenInitView:
	ld de, StatusViewGraphics
	ld hl, vChars1 tile (STATUS_EXP_TILE - $80)
	lb bc, BANK(StatusViewGraphics), 14
	call CopyVideoData
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
	lb de, STATUS_SCREEN_STATS_BOX, STATS_BOX_NORMAL
	farcall PrintStatsBox
	; Restore the actual HP fraction when returning from either alternate view.
	hlcoord 12, 4
	ld de, wLoadedMonHP
	lb bc, 2, 3
	call PrintNumber
	ld a, '/'
	ld [hli], a
	ld de, wLoadedMonMaxHP
	lb bc, 2, 3
	call PrintNumber
	pop de
	push de
	ld a, e
	and a
	jr z, .rendered
	push af
	call StatusViewClearNumbers
	pop af
	cp STATS_BOX_DVS
	jr nz, .bars
	call StatusViewDVs
	jr .rendered
.bars
	call StatusViewStatExp
.rendered
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
	ld a, STATUS_START_TILE
	ld [hli], a
	inc a
	ld [hli], a
	inc a
	ld [hl], a
	ret
.Stats
	db "STATS@"
.DVs
	db "DVs@"
.StatExp
	db "STAT.EXP@"

; Yume's direct DV presentation and HP-derived DV. Keep Red Rogue's full
; stat labels and print directly, avoiding the PrintNumber/HRAM alias trap.
StatusViewDVs:
	hlcoord 7, 10
	ld a, [wLoadedMonDVs]
	swap a
	call StatusViewPrintDV
	ld a, [wLoadedMonDVs]
	call StatusViewPrintDV
	ld a, [wLoadedMonDVs + 1]
	swap a
	call StatusViewPrintDV
	ld a, [wLoadedMonDVs + 1]
	call StatusViewPrintDV
	ld hl, wLoadedMonDVs
	ld e, 0
	ld a, [hl]
	swap a
	rrca
	rl e
	ld a, [hli]
	rrca
	rl e
	ld a, [hl]
	swap a
	rrca
	rl e
	ld a, [hl]
	rrca
	rl e
	ld a, e
	hlcoord 17, 4
	; fallthrough
StatusViewPrintDV:
	and $f
	ld b, ' '
	cp 10
	jr c, .ones
	sub 10
	ld b, '1'
.ones
	add '0'
	ld [hl], b
	inc hl
	ld [hl], a
	ld de, SCREEN_WIDTH * 2 - 1
	add hl, de
	ret

StatusViewClearNumbers:
	hlcoord 12, 4
	lb bc, 1, 7
	call ClearScreenArea
	hlcoord 3, 10
	ld b, 4
.row
	push bc
	push hl
	lb bc, 1, 6
	call ClearScreenArea
	pop hl
	ld de, SCREEN_WIDTH * 2
	add hl, de
	pop bc
	dec b
	jr nz, .row
	ret

StatusViewStatExp:
	hlcoord 12, 4
	ld de, wLoadedMonHPExp + 1
	call StatusViewPrintBar
	hlcoord 3, 10
	ld de, wLoadedMonAttackExp + 1
	call StatusViewPrintBar
	ld de, wLoadedMonDefenseExp + 1
	call StatusViewPrintBar
	ld de, wLoadedMonSpeedExp + 1
	call StatusViewPrintBar
	ld de, wLoadedMonSpecialExp + 1
	; fallthrough

; Pinned Yume 35d3bf9 PrintStatBar, remapped from $31-$3b to $c0-$ca.
; Raw stat experience is shown on a 32-pixel scale. Only $ffff is full.
; de = low byte of big-endian stat experience; hl = six-tile destination.
StatusViewPrintBar:
	ld c, 0
	ld a, [de]
	inc a
	dec de
	ld a, [de]
	jr nz, .notFull
	cp $ff
	jr nz, .notFull
	inc c
.notFull
	srl a
	srl a
	srl a
	add c
	ld b, 4
	ld c, a
	ld a, STATUS_EXP_TILE
	ld [hli], a
.fullTile
	ld a, c
	sub 8
	jr c, .partial
	ld c, a
	ld a, STATUS_EXP_TILE + 9
	ld [hli], a
	dec b
	jr nz, .fullTile
	jr .finish
.partial
	add 8 + STATUS_EXP_TILE + 1
	ld [hli], a
	dec b
	jr z, .finish
	ld a, STATUS_EXP_TILE + 1
.empty
	ld [hli], a
	dec b
	jr nz, .empty
.finish
	ld a, STATUS_EXP_TILE + 10
	ld [hl], a
	ld de, SCREEN_WIDTH * 2 - 5
	add hl, de
	ret

StatusViewGraphics:
	INCBIN "gfx/status_screen/stat_exp_bar.2bpp"
	; Yume status tiles $6e-$78: the final three are its START badge.
	INCBIN "gfx/status_screen/status_screen.2bpp", 8 * TILE_SIZE, 3 * TILE_SIZE
StatusViewGraphicsEnd:
	ASSERT StatusViewGraphicsEnd - StatusViewGraphics == 14 * TILE_SIZE

; ============================================================================
; Status Screen page 2 sub-views (Learndex, LEARNDEX_DESIGN.md D-1).
;
; Same START-cycling idiom as StatusScreenWaitView/StatusScreenDrawView
; above, reused rather than a second navigation concept. Two differences from
; page 1's version, both deliberate:
;   - A and B are NOT tested together. B always exits; A exits only on
;     MOVES_BOX_CURRENT and otherwise calls StatusScreen2SelectHook, a bare
;     ret stub until D-5 (a possible per-move detail page) is approved. This
;     keeps a future D-5 a pure addition - replace the one stub - instead of
;     a rewrite of this loop.
;   - UP/DOWN is wired to StatusScreen2MoveCursor, also a bare ret stub until
;     D-2 gives the list views something to scroll.
; View index and cursor position live in de across the wait, not in WRAM -
; same rule status_view.asm's own header comment states for page 1.
; ============================================================================

; Input: a = PAD_UP|PAD_DOWN (which direction was pressed), de = (d=cursor,
; e=view). Output: d = updated cursor. Stub until D-2; no view has a cursor
; yet, so this does nothing.
StatusScreen2MoveCursor:
	ret

; Input: de = (d=cursor, e=view). Stub until D-5; A currently does nothing on
; any non-CURRENT view.
StatusScreen2SelectHook:
	ret

StatusScreen2WaitView:
	ld d, 0
	ld e, MOVES_BOX_CURRENT
.wait
	push de
	call DelayFrame
	call Joypad
	pop de
	ldh a, [hJoyPressed]
	bit B_PAD_B, a
	ret nz ; B always exits, from every view
	bit B_PAD_A, a
	jr z, .checkStart
	ld a, e
	cp MOVES_BOX_CURRENT
	ret z ; A exits only on the default view, until D-5 changes this
	push de
	call StatusScreen2SelectHook
	pop de
	jr .wait
.checkStart
	ldh a, [hJoyPressed]
	bit B_PAD_START, a
	jr z, .checkUpDown
	ld a, e
	inc a
	cp NUM_MOVES_BOX_VIEWS
	jr nz, .gotNextView
	xor a
.gotNextView
	ld e, a
	push de
	call StatusScreen2DrawView
	pop de
	jr .wait
.checkUpDown
	ldh a, [hJoyPressed]
	and PAD_UP | PAD_DOWN
	jr z, .wait
	call StatusScreen2MoveCursor ; a = direction, de = (cursor,view); updates d
	push de
	call StatusScreen2DrawView
	pop de
	jr .wait

; Draws Status Screen page 2's moves box for the given sub-view: the border
; (which also blanks the interior, discarding the previous view's content -
; same pattern as PrintStatsBox uses for page 1), the view's content, and the
; view label + START badge on row 8 (drawn over the border's own top-row
; characters, same as StatusScreenDrawView above).
; Input: e = MOVES_BOX_*. Clobbers everything - callers that need their own
; de preserved must push/pop it themselves, exactly as StatusScreen2WaitView
; does above.
StatusScreen2DrawView:
	push de
	hlcoord 0, 8
	ld b, 8
	ld c, 18
	call TextBoxBorder
	pop de

	push de
	ld a, e
	add a
	ld c, a
	ld b, 0
	ld hl, .ContentPointers
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld bc, .contentDone
	push bc
	jp hl
.contentDone
	pop de

	ld a, e
	add a
	ld c, a
	ld b, 0
	ld hl, .LabelPointers
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld d, h
	ld e, l
	hlcoord 2, 8
	call PlaceString
	hlcoord 15, 8
	ld a, STATUS_START_TILE
	ld [hli], a
	inc a
	ld [hli], a
	inc a
	ld [hl], a
	ret

.ContentPointers
	dw .DrawCurrent
	dw .DrawLevelUp
	dw .DrawTMHM
	dw .DrawTutor
.DrawCurrent
	farcall StatusScreen2DrawMovesBoxCurrent
	ret
.DrawLevelUp
	ret ; MOVES_BOX_LEVELUP content - D-2
.DrawTMHM
	ret ; MOVES_BOX_TMHM content - D-3
.DrawTutor
	ret ; MOVES_BOX_TUTOR content - D-4

.LabelPointers
	dw .CurrentLabel
	dw .LevelUpLabel
	dw .TMHMLabel
	dw .TutorLabel
.CurrentLabel
	db "MOVES@"
.LevelUpLabel
	db "LEVEL UP@"
.TMHMLabel
	db "TM/HM@"
.TutorLabel
	db "TUTOR@"
