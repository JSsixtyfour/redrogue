; replaces a tile block with the one specified in [wNewTileBlockID]
; and redraws the map view if necessary
; b = Y
; c = X
ReplaceTileBlock:
	call GetPredefRegisters
	ld hl, wOverworldMap
	ld a, [wCurMapWidth]
	add $6
	ld e, a
	ld d, $0
	add hl, de
	add hl, de
	add hl, de
	ld e, $3
	add hl, de
	ld e, a
	ld a, b
	and a
	jr z, .addX
; add width * Y
.addWidthYTimesLoop
	add hl, de
	dec b
	jr nz, .addWidthYTimesLoop
.addX
	add hl, bc ; add X
	ld a, [wNewTileBlockID]

; shinpokered/pureRGB import: nothing to redraw if the block is already what we
; are about to write. RedrawMapView costs a 9-frame wall-clock floor no matter
; how little changed, and the lobby's exit-door replacement
; (scripts/IndigoPlateauLobby.asm) runs on every map entry and is frequently a
; no-op, because wOverworldMap is refilled from the .blk each load.
	cp [hl]
	ret z

	ld [hl], a
	call IsBCInHLTileBlockMapView
	ret c ; return if the replaced tile block is off-screen

; Exported so custom_functions/room_pc.asm can farcall it: LoadCurrentMapView
; alone only refills wTileMap (which feeds the WINDOW at vBGMap1), while the
;gbcnote - it is useful to have a version of RedrawMapView that does not mess with hAutoBGTransferEnabled
;used particularly for clean enhanced GBC colors during in-game trades
RedrawMapView_NoChangeAutoBGTransfer:
	ldh a, [hIsInBattle]
	inc a
	ret z
	ldh a, [hAutoBGTransferEnabled]
	push af
	ldh a, [hTileAnimations]
	push af
	xor a
	jp RedrawMapView.done_AutoBGTransfer

; overworld the player actually sees is vBGMap0, written here and by
; RedrawRowOrColumn during walking.
RedrawMapView::
	ldh a, [hIsInBattle]
	inc a
	ret z
	ldh a, [hAutoBGTransferEnabled]
	push af
	ldh a, [hTileAnimations]
	push af
	xor a
	ldh [hAutoBGTransferEnabled], a
.done_AutoBGTransfer
	ldh [hTileAnimations], a
	call LoadCurrentMapView
	call RunDefaultPaletteCommand
    ;GBCnote - 	for enhanced GBC colors, TransferGBCEnhancedBGMapAttributes already ran during RunDefaultPaletteCommand
	ld hl, wMapViewVRAMPointer
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld de, -2 * TILEMAP_WIDTH
	add hl, de
	ld a, h
	and $3
	or $98
	ld a, l
	ld [wBuffer], a
	ld a, h
	ld [wBuffer + 1], a ; this copy of the address is not used
	ld a, 2
	ldh [hRedrawMapViewRowOffset], a
	ld c, SCREEN_HEIGHT / 2 ; number of rows of 2x2 tiles (this covers the whole screen)
.redrawRowLoop
	push bc
	push hl
	push hl
	ld hl, wTileMap - 2 * SCREEN_WIDTH
	ld de, SCREEN_WIDTH
	ldh a, [hRedrawMapViewRowOffset]
.calcWRAMAddrLoop
	add hl, de
	dec a
	jr nz, .calcWRAMAddrLoop
	call CopyToRedrawRowOrColumnSrcTiles
	pop hl
	ld de, TILEMAP_WIDTH
	ldh a, [hRedrawMapViewRowOffset]
	ld c, a
.calcVRAMAddrLoop
	add hl, de
	ld a, h
	and $3
	or $98
	dec c
	jr nz, .calcVRAMAddrLoop
	ldh [hRedrawRowOrColumnDest + 1], a
	ld a, l
	ldh [hRedrawRowOrColumnDest], a
	ld a, REDRAW_ROW
	ldh [hRedrawRowOrColumnMode], a
	call DelayFrame
	ld hl, hRedrawMapViewRowOffset
	inc [hl]
	inc [hl]
	pop hl
	pop bc
	dec c
	jr nz, .redrawRowLoop
	pop af
	ldh [hTileAnimations], a
	pop af
	ldh [hAutoBGTransferEnabled], a
	ret

; pureRGB/shinpokered import, replacing vanilla's linear address-range test.
; Vanilla compared the replaced block's address against the single span running
; from the view's top-left to its bottom-right. wOverworldMap is row-major with
; stride (wCurMapWidth + 6), so a block far to the left or right of the visible
; window still lands inside that span whenever it sits on an intermediate row,
; and the redraw fired for blocks the player cannot see. This walks the view's
; rows individually instead. (Vanilla's `ld e, $6` was also wrong: the view's
; lower-right corner is 4 columns over, not 6, which widened the span further.)
;
; Input:  hl = address of the replaced block within wOverworldMap
;         e  = row stride, wCurMapWidth + 6, still live from ReplaceTileBlock
; Output: carry set = block is off-screen, so the caller should skip the redraw
; Clobbers a, b, c, d, h, l. Preserves e.
;
; Deliberately biased conservative: .CheckRow's first comparison reports
; "on-screen" when the block's high byte is above the row's, which can cost an
; unnecessary redraw but can never skip a needed one. A false "off-screen" would
; be a silent rendering bug; a false "on-screen" is merely today's behavior.
IsBCInHLTileBlockMapView:
	push hl
	pop bc ; bc = the replaced tile block
	ld a, [wCurrentTileBlockMapViewPointer]
	ld l, a
	ld a, [wCurrentTileBlockMapViewPointer + 1]
	ld h, a ; hl = upper-left tile block of the map view
	ld d, 5 ; rows of tile blocks in the view
.loop
	call .CheckRow
	ret nc ; found it in this row
	dec d
	ret z ; out of rows, so it is off-screen (carry still set)
	push de
	ld d, 0
	add hl, de ; advance hl to the next row of the view
	pop de
	jr .loop

.CheckRow
	ld a, b
	sub h
	ret nz
	ld a, c
	sub l
	ret c ; before this row's left edge
	push hl
	push bc
	ld bc, 4
	add hl, bc ; hl = this row's right edge
	pop bc
	ld a, h
	sub b
	jr nz, .next
	ld a, l
	sub c
.next
	pop hl
	ret
