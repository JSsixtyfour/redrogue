Rogue_Pokemon_Display_1::
	ld a, [wRoguePokemon1]
	ld [wCurPartySpecies], a
	call DisplayDiagonalTest        ; TEMP: test diagonal Charizard display
	call EnableAutoTextBoxDrawing
	ret
    
; ============================================================
; DisplayFusionTest — TEMP: left half Charizard + right half Blastoise.
; AnimateSendingOutMon writes tile IDs column-major to wTileMap.
; Sprite lands at screen cols 2-8, rows 0-5 (row above screen is cropped).
; Blastoise at vChars1 tile $00 (IDs $80-$B0), Charizard at tile $31 ($B1-$E1).
; After animating Charizard, overwrite screen cols 6-8 with Blastoise col 4-6 IDs.
; ============================================================
DisplayDiagonalTest::
    ld a, 1
    ldh [hAutoBGTransferEnabled], a
    call Delay3
    xor a
    ldh [hWY], a
    call SaveScreenTilesToBuffer1
    call UpdateSprites
    ; Load Blastoise tiles at vChars1 tile $00 (tile IDs $80-$B0)
    ld a, BLASTOISE
    ld [wCurPartySpecies], a
    ld [wCurSpecies], a
    call GetMonHeader
    ld de, vChars1 tile $00
    call LoadMonFrontSprite
    ; Load Charizard tiles at vChars1 tile $31 (tile IDs $B1-$E1)
    ld a, CHARIZARD
    ld [wCurPartySpecies], a
    ld [wCurSpecies], a
    call GetMonHeader
    ld de, vChars1 tile $31
    call LoadMonFrontSprite
    ; Animate Charizard — writes column-major IDs $B1+ to wTileMap
    ld a, $80
    ldh [hStartTileID], a
    hlcoord 5, 5
    predef AnimateSendingOutMon
    ; Diagonal overwrite: Blastoise fills the lower-right triangle (col+row >= 7),
    ; Charizard stays in the upper-left triangle. Anti-diagonal from top-right to
    ; bottom-left. wTileMap offset = (r-1)*20 + (c+2); tile ID = $80 + c*7 + r.
    ; For each sprite col c (1-6), write the bottom (7-c) visible rows of Blastoise.
    ; Sprite row 0 is above screen, so visible rows start at r=max(1, 7-c).
    ; Col 0: entirely Charizard (no Blastoise tiles needed)
    ; Col 1: r=6 only → 1 tile at wTileMap+103, ID $8D
    ; Col 2: r=5,6   → 2 tiles at wTileMap+84,  IDs $93-$94
    ; Col 3: r=4,5,6 → 3 tiles at wTileMap+65,  IDs $99-$9B
    ; Col 4: r=3..6  → 4 tiles at wTileMap+46,  IDs $9F-$A2
    ; Col 5: r=2..6  → 5 tiles at wTileMap+27,  IDs $A5-$A9
    ; Col 6: r=1..6  → 6 tiles at wTileMap+8,   IDs $AB-$B0
    ld de, SCREEN_WIDTH
    ld hl, wTileMap + 103
    ld a, $8D
    ld [hl], a
    ld hl, wTileMap + 84
    ld a, $93
    ld b, 2
.dc2
    ld [hl], a
    add hl, de
    inc a
    dec b
    jr nz, .dc2
    ld hl, wTileMap + 65
    ld a, $99
    ld b, 3
.dc3
    ld [hl], a
    add hl, de
    inc a
    dec b
    jr nz, .dc3
    ld hl, wTileMap + 46
    ld a, $9F
    ld b, 4
.dc4
    ld [hl], a
    add hl, de
    inc a
    dec b
    jr nz, .dc4
    ld hl, wTileMap + 27
    ld a, $A5
    ld b, 5
.dc5
    ld [hl], a
    add hl, de
    inc a
    dec b
    jr nz, .dc5
    ld hl, wTileMap + 8
    ld a, $AB
    ld b, 6
.dc6
    ld [hl], a
    add hl, de
    inc a
    dec b
    jr nz, .dc6
    ret
; --- LEFT/RIGHT SPLIT (commented out — swap with diagonal block above to use) ---
; Blastoise col 4 (screen col 6): IDs $9D-$A2
;    ld de, SCREEN_WIDTH
;    ld hl, wTileMap + 6
;    ld a, $9D
;    ld b, 6
;.lrCol4
;    ld [hl], a
;    add hl, de
;    inc a
;    dec b
;    jr nz, .lrCol4
; Blastoise col 5 (screen col 7): IDs $A4-$A9
;    ld hl, wTileMap + 7
;    ld a, $A4
;    ld b, 6
;.lrCol5
;    ld [hl], a
;    add hl, de
;    inc a
;    dec b
;    jr nz, .lrCol5
; Blastoise col 6 (screen col 8): IDs $AB-$B0
;    ld hl, wTileMap + 8
;    ld a, $AB
;    ld b, 6
;.lrCol6
;    ld [hl], a
;    add hl, de
;    inc a
;    dec b
;    jr nz, .lrCol6
;    ret
; --- END LEFT/RIGHT SPLIT ---

DisplayRogueMonFrontSpriteInBox:
; Displays a pokemon's front sprite in a pop-up window.
	ld a, 1
	ldh [hAutoBGTransferEnabled], a
	call Delay3
	xor a
	ldh [hWY], a
	call SaveScreenTilesToBuffer1
	ld a, MON_SPRITE_POPUP
	;ld [wTextBoxID], a
	;call DisplayTextBoxID
	call UpdateSprites
	ld a, [wCurPartySpecies]
	ld [wCurSpecies], a
	call GetMonHeader
	ld de, vChars1 tile $31
	call LoadMonFrontSprite
	ld a, $80
	ldh [hStartTileID], a
	hlcoord 5, 5
	predef AnimateSendingOutMon
	;call WaitForTextScrollButtonPress
	;call LoadScreenTilesFromBuffer1
	;call Delay3
	;ld a, $90
	;ldh [hWY], a
	ret
