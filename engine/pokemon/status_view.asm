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
