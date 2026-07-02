; custom_functions/func_fusion_sprite.asm — diagonal sprite fusion
;
; See oak_speech.asm for the 6-step call sequence.
; Species_a = top-right (col > row). Species_b = bottom-left (col <= row).
;
; 2bpp column-major layout in sSpriteBuffer1+2:
;   Tile(c,r) index = c*7+r, byte offset = (c*7+r)*16.
;   Diagonal tile c (c==r): index c*8, byte offset c*128.

FusionDiagonalMaskTable::
    db $7F,$3F,$1F,$0F,$07,$03,$01,$00

; ============================================================
; _SrcA: hl = sFusionDiagBuf + a*16  (a = tile 0-6)
; ============================================================
_SrcA:
    sla a
    sla a
    sla a
    sla a            ; a = tile*16
    ld l, a
    ld h, 0
    ld a, LOW(sFusionDiagBuf)
    add a, l
    ld l, a
    ld a, HIGH(sFusionDiagBuf)
    adc a, h
    ld h, a
    ret

; ============================================================
; _SrcB: hl = sSpriteBuffer1 + a*128  (a = tile 0-6)
; a*128: H = a>>1, L = (a&1)*128
; ============================================================
_SrcB:
    ld h, a
    srl h            ; H = a/2
    and 1
    ld l, 0
    jr z, .even
    ld l, $80
.even
    ld a, l
    add a, LOW(sSpriteBuffer1)
    ld l, a
    ld a, h
    adc a, HIGH(sSpriteBuffer1)
    ld h, a
    ret

; ============================================================
; FusionSaveDiagTiles
; Copy the 7 diagonal tiles from sSpriteBuffer1+2 to sFusionDiagBuf.
; HRAM used: hSpriteDataOffset = tile index (0-6)
; ============================================================
FusionSaveDiagTiles::
    xor a
    ld [rRAMB], a
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    xor a
    ldh [hSpriteDataOffset], a   ; tile = 0
.saveTile
    ldh a, [hSpriteDataOffset]
    cp 7
    jr z, .saveDone
    ; src: sSpriteBuffer1 + tile*128  (a = tile index, cp preserves a)
    call _SrcB
    ld d, h
    ld e, l           ; de = source (sSpriteBuffer1 + tile*128)
    ; dst: sFusionDiagBuf + tile*16
    ldh a, [hSpriteDataOffset]
    call _SrcA        ; hl = sFusionDiagBuf + tile*16
    ; Copy 16 bytes: de (source) → hl (dest)
    ld b, 16
.saveByte
    ld a, [de]
    ld [hli], a
    inc de
    dec b
    jr nz, .saveByte
    ldh a, [hSpriteDataOffset]
    inc a
    ldh [hSpriteDataOffset], a
    jr .saveTile
.saveDone
    xor a
    ld [rRAMG], a
    ret

; ============================================================
; FusionBlendDiagTiles
; Blend saved spec_a diagonal tiles (sFusionDiagBuf) into sSpriteBuffer1+2.
; HRAM: hSpriteDataOffset = tile index, hSpriteIndex = pixel row.
; ============================================================
FusionBlendDiagTiles::
    xor a
    ld [rRAMB], a
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    xor a
    ldh [hSpriteDataOffset], a
.blendTile
    ldh a, [hSpriteDataOffset]
    cp 7
    jr z, .blendDone
    ; de = sFusionDiagBuf + tile*16   (spec_a source, a = tile index)
    call _SrcA
    ld d, h
    ld e, l
    ; hl = sSpriteBuffer1 + tile*128  (spec_b/output)
    ldh a, [hSpriteDataOffset]
    call _SrcB
    ; de=spec_a ptr, hl=spec_b/out ptr. Blend 8 pixel rows.
    xor a
    ldh [hSpriteIndex], a        ; pixel row = 0
.blendRow
    ldh a, [hSpriteIndex]
    cp 8
    jr z, .blendTileDone
    ; Get mask for this row into c
    push hl
    push de
    ld hl, FusionDiagonalMaskTable
    ld b, 0
    ld c, a
    add hl, bc
    ld c, [hl]        ; c = A_mask
    pop de
    pop hl
    ; Blend byte 0: out = (spec_a[0] & c) | (spec_b[0] & ~c)
    ld a, [de]        ; a = spec_a byte0
    inc de
    and c             ; a &= mask
    ld b, a           ; b = spec_a contribution
    ld a, [hl]        ; a = spec_b byte0
    push bc
    ld b, a
    ld a, c
    cpl               ; a = ~mask
    and b             ; a = spec_b & ~mask
    pop bc
    or b              ; a = blended
    ld [hli], a       ; write, advance hl
    ; Blend byte 1 (identical logic)
    ld a, [de]
    inc de
    and c
    ld b, a
    ld a, [hl]
    push bc
    ld b, a
    ld a, c
    cpl
    and b
    pop bc
    or b
    ld [hli], a
    ldh a, [hSpriteIndex]
    inc a
    ldh [hSpriteIndex], a
    jr .blendRow
.blendTileDone
    ldh a, [hSpriteDataOffset]
    inc a
    ldh [hSpriteDataOffset], a
    jr .blendTile
.blendDone
    xor a
    ld [rRAMG], a
    ret
