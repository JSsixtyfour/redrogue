; Isolated lobby pose draft. NOT included by the game.
; Red Rogue adaptation of data/sprites/facings.asm and the existing split
; standing/walking sheets. No replacement art, game RAM or bank allocation.
SECTION "Lobby Pose Draft", ROMX

; d = lobby actor slot, e = logical image index. $ff means hidden.
; The caller must validate the finalized lobby roster before using this policy.
; Success: carry clear, d = first physical tile, e = source pose tile offset,
; b = 1 for a four-tile cache (else 0), c = X-flip attribute (else 0).
; Source offsets $80/$84/$88 denote the legacy walking half: in the source
; sheet these start at tile 12/16/20. Right uses the left source pose.
; The renderer must retain its ordinary coordinates, palette and grass bits.
; hl preserved; on rejection bc/de also preserved. No memory writes.
LobbyPoseResolve::
	ld a, e
	cp $ff
	jr z, .reject
	ld a, d
	cp 15
	jr z, .valid
	cp 12
	jr nc, .reject
.valid
	push hl
	ld l, a
	ld h, 0
	add hl, hl
	ld bc, .actors
	add hl, bc
	ld a, [hli]
	ld b, [hl] ; 0 full standing, 1 cached standing, 2 walker
	ld d, a
	ld l, e ; retain original direction/frame while resolving source pose
	ld a, e
	and $0c
	ld c, 0
	cp $0c
	jr nz, .direction
	ld c, $20
	ld a, 8
.direction
	ld e, a
	bit 1, b
	jr z, .physical
	bit 0, l
	jr z, .physical
	set 7, e
	ld a, l
	and 3
	cp 3
	jr nz, .physical
	ld a, e
	and $0c
	cp 8
	jr nc, .physical
	ld a, c
	xor $20 ; down/up alternate step uses the existing mirrored OAM
	ld c, a
.physical
	ld a, b
	cp 1
	jr z, .done
	ld b, 0
	ld a, d
	add e
	ld d, a
.done
	pop hl
	and a
	ret
.reject
	scf
	ret
.actors
	db $00, 2 ; player
	db $24, 0 ; nurse, including legacy image writes $18/$14
	db $30, 0 ; independent clerks share all standing poses
	db $30, 0
	db $3c, 0 ; gentleman
	db $48, 0 ; granny
	db $54, 0 ; president
	db $60, 0 ; youngster
	db $6c, 1 ; channeler
	db $18, 2 ; salesman
	db $70, 1 ; super nerd
	db $74, 1 ; Game Boy kid
	db 0, 0, 0, 0, 0, 0 ; rejected slots 12..14
	db $0c, 2 ; follower keeps physical slot 2

; Commit one staged four-tile pose and its complete four-entry OAM quad.
; hl = 64 stable staged bytes, de = 16 stable prepared OAM bytes (both WRAM).
; b = cache first tile ($6c/$70/$74), c = OAM BYTE offset ($00,$10,..,$90).
; bc/de/hl preserved. Carry clear only after every write, set if deferred/invalid.
;
; PRECONDITIONS: IME off, bank-0 VRAM selected, no DMA in flight; buffers do not
; overlap either output or stack. Caller owns this OAM quad for the transaction
; and prevents later rendering/DMA from publishing an older quad. Update any
; caller-owned cache key ONLY on success. This routine allocates no cache state.
; Do not call from the ordinary renderer or text loop without a scheduling seam.
;
; Accept LCD off, or ONLY the first VBlank line (LY=144). After the LY sample,
; the unrolled writes and return take <3000 single-speed clocks, below the
; >=4104 clocks left even at the end of line 144. No waits, calls, bank switch,
; or interrupt enable occurs inside this transaction. Double speed is faster.
; Both shadow and hardware OAM are written so the next scan cannot show new
; pose bytes with the old facing quad. The game dispatcher is NOT integrated.
LobbyPoseCommit::
	ld a, b
	cp $6c
	jr z, .baseOK
	cp $70
	jr z, .baseOK
	cp $74
	jp nz, .reject
.baseOK
	ld a, c
	and $0f
	jp nz, .reject
	ld a, c
	cp $a0
	jp nc, .reject
	ldh a, [rLCDC]
	bit 7, a
	jr z, .commit
	ldh a, [rLY]
	cp 144
	jp nz, .reject
.commit
	push bc
	push de
	push hl
	push de ; OAM source, used after the tile copy
	ld a, b
	and $0f
	swap a
	ld e, a
	ld a, b
	swap a
	and $0f
	or $80
	ld d, a
REPT 64
	ld a, [hli]
	ld [de], a
	inc de
ENDR
	pop hl
	push hl
	ASSERT LOW(wShadowOAM) == 0
	ld d, HIGH(wShadowOAM)
	ld e, c
REPT 16
	ld a, [hli]
	ld [de], a
	inc de
ENDR
	pop hl
	ld d, $fe
	ld e, c
REPT 16
	ld a, [hli]
	ld [de], a
	inc de
ENDR
	pop hl
	pop de
	pop bc
	and a
	ret
.reject
	scf
	ret
