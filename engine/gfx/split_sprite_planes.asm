; Second half of UncompressSpriteData (home/uncompress.asm). Decompress has left
; a pic's interleaved, column-major 2bpp (lo, hi, lo, hi, ...) in sSpriteBuffer0
; onward; this splits it into the two planes the rest of the pic pipeline
; expects - low plane in sSpriteBuffer1, high plane in sSpriteBuffer2 - zeroes
; the rest of both buffers, and mirrors the bytes when wSpriteFlipped is set.
; See home/uncompress.asm for the full output contract.

; Every byte with both nybbles bit-reversed: the old decoder's flipped output.
; Page-aligned so a lookup is `ld e, byte / ld a, [de]` with d fixed: it must
; stay FIRST in its section, which main.asm declares ALIGN[8].
SpriteNybbleReverseTable:
FOR n, 256
	DEF hi_nybble = n >> 4
	DEF lo_nybble = n & $f
	db (((hi_nybble & 1) << 3) | ((hi_nybble & 2) << 1) | ((hi_nybble & 4) >> 1) | ((hi_nybble & 8) >> 3)) << 4 \
		| ((lo_nybble & 1) << 3) | ((lo_nybble & 2) << 1) | ((lo_nybble & 4) >> 1) | ((lo_nybble & 8) >> 3)
ENDR
	PURGE hi_nybble, lo_nybble

; In: de = end of Decompress's output (sSpriteBuffer0 + 2n, n <= SPRITEBUFFERSIZE).
; Assumes SRAM enabled, bank 0. Clobbers everything.
;
; Both copies run BACKWARDS, which is what makes splitting in place safe without
; a third buffer. The input spans [buf0, buf0 + 2n), at most buffers 0 and 1.
; The high plane goes to sSpriteBuffer2, entirely past the input. The low plane
; byte k goes to sSpriteBuffer1 + k = buf0 + SPRITEBUFFERSIZE + k, and copying
; from the end, the only input still unread at step k lies below buf0 + 2k -
; which never exceeds buf0 + SPRITEBUFFERSIZE + k, since k < SPRITEBUFFERSIZE.
SplitSpritePlanes::
	ld a, e
	sub LOW(sSpriteBuffer0)
	ld c, a
	ld a, d
	sbc HIGH(sSpriteBuffer0)
	ld b, a
	srl b
	rr c ; bc = n, bytes per plane
	push bc
	push de
	dec de ; last high-plane byte
	ld hl, sSpriteBuffer2 - 1
	call .copyPlane
	pop de
	pop bc
	push bc
	dec de
	dec de ; last low-plane byte
	ld hl, sSpriteBuffer1 - 1
	call .copyPlane
	pop bc

	; Zero both planes past n. FillMemory treats a count of 0 as 65536, so a
	; full 7x7 pic (n = SPRITEBUFFERSIZE) must skip this.
	ld a, LOW(SPRITEBUFFERSIZE)
	sub c
	ld c, a
	ld a, HIGH(SPRITEBUFFERSIZE)
	sbc b
	ld b, a ; bc = SPRITEBUFFERSIZE - n
	or c
	jr z, .tailsDone
	ld hl, sSpriteBuffer2 ; = end of sSpriteBuffer1
	call .fillTail
	ld hl, sSpriteBuffer2 + SPRITEBUFFERSIZE
	call .fillTail
.tailsDone

	ld a, [wSpriteFlipped]
	and a
	ret z
	; Nybble-reverse every byte of both planes (zero maps to zero, so the
	; tails need no special case).
	ld hl, sSpriteBuffer1
	ld bc, 2 * SPRITEBUFFERSIZE
	ld d, HIGH(SpriteNybbleReverseTable)
.flipLoop
	ld e, [hl]
	ld a, [de]
	ld [hli], a
	dec bc
	ld a, b
	or c
	jr nz, .flipLoop
	ret

; hl = destination plane - 1, de = last source byte of that plane, bc = n.
; Copies every other byte, walking both pointers down: dest[k] = src[2k].
.copyPlane
	add hl, bc ; hl = destination plane + n - 1
.copyLoop
	ld a, [de]
	dec de
	dec de
	ld [hld], a
	dec bc
	ld a, b
	or c
	jr nz, .copyLoop
	ret

; hl = end of a plane, bc = tail length (preserved). Zeroes [hl - bc, hl).
.fillTail
	ld a, l
	sub c
	ld l, a
	ld a, h
	sbc b
	ld h, a
	push bc
	xor a
	call FillMemory
	pop bc
	ret
