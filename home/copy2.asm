FarCopyData2::
; Identical to FarCopyData, but uses hROMBankTemp
; as temp space instead of wBuffer.
	ldh [hROMBankTemp], a
	ldh a, [hLoadedROMBank]
	push af
	ldh a, [hROMBankTemp]
	call SetCurBank      ; was inline ldh[hLoadedROMBank]/ld[rROMB]; -2 bytes (HOME space)
	call CopyData
	pop af
	jp SetCurBank        ; tail call = restore bank + ret; -3 bytes (HOME space)

FarCopyData3::
; Copy bc bytes from a:de to hl.
	ldh [hROMBankTemp], a
	ldh a, [hLoadedROMBank]
	push af
	ldh a, [hROMBankTemp]
	call SetCurBank      ; -2 bytes (HOME space)
	push hl
	push de
	push de
	ld d, h
	ld e, l
	pop hl
	call CopyData
	pop de
	pop hl
	pop af
	jp SetCurBank        ; tail call = restore bank + ret; -3 bytes (HOME space)

FarCopyDataDouble::
; Expand bc bytes of 1bpp image data
; from a:hl to 2bpp data at de.
	ldh [hROMBankTemp], a
	ldh a, [hLoadedROMBank]
	push af
	ldh a, [hROMBankTemp]
	call SetCurBank      ; -2 bytes (HOME space)
.loop
	ld a, [hli]
	ld [de], a
	inc de
	ld [de], a
	inc de
	dec bc
	ld a, c
	or b
	jr nz, .loop
	pop af
	jp SetCurBank        ; tail call = restore bank + ret; -3 bytes (HOME space)

CopyVideoDataPaced::
; Wait for the next VBlank, then copy c 2bpp
; tiles from b:de to hl, 8 tiles at a time.
; This takes c/8 frames. Kept for the callers whose timing is part of an
; animation, as pureRGB did: emotion bubbles and credits. Everything else,
; including battle animation tilesets, uses CopyVideoData.

	ldh a, [hAutoBGTransferEnabled]
	push af
	xor a ; disable auto-transfer while copying
	ldh [hAutoBGTransferEnabled], a

	ldh a, [hLoadedROMBank]
	ldh [hROMBankTemp], a

	ld a, b
	call SetCurBank      ; was inline ldh[hLoadedROMBank]/ld[rROMB]; -2 bytes (HOME space)

	ld a, e
	ldh [hVBlankCopySource], a
	ld a, d
	ldh [hVBlankCopySource + 1], a

	ld a, l
	ldh [hVBlankCopyDest], a
	ld a, h
	ldh [hVBlankCopyDest + 1], a

.loop
	ld a, c
	cp 8
	jr nc, .keepgoing

.done
	ldh [hVBlankCopySize], a
	call DelayFrame
	ldh a, [hROMBankTemp]
	call SetCurBank      ; was inline ldh[hLoadedROMBank]/ld[rROMB]; -2 bytes (HOME space)
	pop af
	ldh [hAutoBGTransferEnabled], a
	ret

.keepgoing
	ld a, 8
	ldh [hVBlankCopySize], a
	call DelayFrame
	ld a, c
	sub 8
	ld c, a
	jr .loop

; pureRGB 2.7.5 CopyVideoDataHBlank / CopyVideoDataHBlankDouble. Writes with the
; LCD on whenever VRAM is unlocked (STAT mode 0 or 1), interrupts off for the
; whole copy; ~18 2bpp / ~36 1bpp tiles per frame at single speed, double that
; at CGB double speed (the old VBlank-paced copy did 8 per frame at either
; speed). Unlike pureRGB's, these keep the old copy's contract: bc, de and hl
; are preserved, so no caller had to change. Do not copy VRAM to VRAM.
; Measured (PURERGB_HBLANK_COPY_SPEC.md): start menu 25 -> 9 frames, no music
; steps lost or delayed beyond master.

CopyVideoData::
; Copy c 2bpp tiles from b:de to hl.
	ld a, c
	and a
	ret z
	push bc
	push de
	push hl
	ldh a, [hLoadedROMBank]
	push af
	ld a, b
	call SetCurBank
	ld a, c ; tile count (kept in a while bc is used to swap dest/source)
	di
	ld [hSPTemp], sp
	ld b, h
	ld c, l ; bc = dest
	ld h, d
	ld l, e
	ld sp, hl ; SP = source
	ld h, b
	ld l, c ; hl = dest
	ld b, a
.tileLoop
	ld c, TILE_SIZE / 2 ; 8 word writes per tile
.pairLoop
	pop de ; fetch next 2 bytes (safe in any PPU mode)
.waitVRAM
	ldh a, [rSTAT]
	and %10 ; wait while Mode 2 or 3 (VRAM locked in Mode 3)
	jr nz, .waitVRAM
	ld a, e
	ld [hli], a
	ld a, d
	ld [hli], a
	dec c
	jr nz, .pairLoop
	dec b
	jr nz, .tileLoop
	jr CopyVideoDataFinish

CopyVideoDataDouble::
; Copy c 1bpp tiles from b:de to hl, expanding to 2bpp.
	ld a, c
	and a
	ret z
	push bc
	push de
	push hl
	ldh a, [hLoadedROMBank]
	push af
	ld a, b
	call SetCurBank
	ld a, c ; tile count (kept in a while bc is used to swap dest/source)
	di
	ld [hSPTemp], sp
	ld b, h
	ld c, l ; bc = dest
	ld h, d
	ld l, e
	ld sp, hl ; SP = source
	ld h, b
	ld l, c ; hl = dest
	ld b, a
.tileLoop
	ld c, TILE_SIZE / 4 ; 4 word pops per 1bpp tile (8 source bytes -> 16 dest bytes)
.pairLoop
	pop de ; fetch next 2 source bytes (safe in any PPU mode)
.waitVRAM
	ldh a, [rSTAT]
	and %10 ; wait while Mode 2 or 3 (VRAM locked in Mode 3)
	jr nz, .waitVRAM
	ld a, e
	ld [hli], a
	ld [hli], a
	ld a, d
	ld [hli], a
	ld [hli], a
	dec c
	jr nz, .pairLoop
	dec b
	jr nz, .tileLoop
	; fallthrough

CopyVideoDataFinish:
	ld sp, hSPTemp
	pop hl
	ld sp, hl
	ei
	pop af
	call SetCurBank
	pop hl
	pop de
	pop bc
	ret

ClearScreenArea::
; Clear tilemap area cxb at hl.
	ld a, ' '
	ld de, SCREEN_WIDTH
.loopRows
	push hl
	push bc
.loopTiles
	ld [hli], a
	dec c
	jr nz, .loopTiles
	pop bc
	pop hl
	add hl, de
	dec b
	jr nz, .loopRows
	ret

CopyScreenTileBufferToVRAM::
; Copy wTileMap to the BG Map starting at b * $100.
; This is done in thirds of 6 rows, so it takes 3 frames.

	ld c, SCREEN_HEIGHT / 3

	lb hl, 0, 0
	decoord 0, 6 * 0
	call .setup
	call DelayFrame

	lb hl, SCREEN_HEIGHT / 3, 0
	decoord 0, 6 * 1
	call .setup
	call DelayFrame

	lb hl, 2 * SCREEN_HEIGHT / 3, 0
	decoord 0, 6 * 2
	call .setup
	jp DelayFrame

.setup
	ld a, d
	ldh [hVBlankCopyBGSource+1], a
	call GetRowColAddressBgMap
	ld a, l
	ldh [hVBlankCopyBGDest], a
	ld a, h
	ldh [hVBlankCopyBGDest+1], a
	ld a, c
	ldh [hVBlankCopyBGNumRows], a
	ld a, e
	ldh [hVBlankCopyBGSource], a
	ret

ClearScreen::
; Clear wTileMap, then wait
; for the bg map to update.
	ld bc, SCREEN_AREA
	inc b
	hlcoord 0, 0
	ld a, ' '
.loop
	ld [hli], a
	dec c
	jr nz, .loop
	dec b
	jr nz, .loop
	jp Delay3
