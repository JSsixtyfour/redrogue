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

; Isolated request/cache manager. NOT connected to gameplay.
; The caller supplies a 27-byte state block at hl. The future game allocation,
; lifetime and clearing boundary are deliberately not selected here.
;
; Layout: requested descriptors (3 * picture/poseflags/OAM offset), committed
; descriptors (same), dirty bits, valid bits, healing-ownership flag.
DEF LOBBY_POSE_REQUESTS EQU 0
DEF LOBBY_POSE_COMMITTED EQU 9
DEF LOBBY_POSE_DIRTY EQU 18
DEF LOBBY_POSE_VALID EQU 19
DEF LOBBY_POSE_HEALING EQU 20
DEF LOBBY_POSE_CACHE_STATE_SIZE EQU 21

; hl = state. Clears requests/committed descriptors to $ff and all flags.
; Preserves bc/de/hl. No external call or game RAM assumption.
LobbyPoseCacheReset::
	push bc
	push de
	push hl
	ld b, 18
	ld a, $ff
.clearDescriptors
	ld [hli], a
	dec b
	jr nz, .clearDescriptors
	xor a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	pop hl
	pop de
	pop bc
	ret

; Request the latest complete descriptor for cache a (0..2).
; d = picture ID (nonzero/non-$ff), e = source pose plus optional OAM_XFLIP,
; c = aligned OAM byte offset $00..$90, hl = state. Only standing sources
; 0/4/8 are accepted. Success coalesces an identical committed request or marks
; it dirty. Replacements overwrite only the request, never committed state.
; Preserves hl. Carry set rejects without writes; af/bc/de may be clobbered.
LobbyPoseCacheRequest::
	cp 3
	jp nc, .reject
	ld b, a
	ld a, d
	and a
	jp z, .reject
	cp $ff
	jp z, .reject
	ld a, e
	and $df
	cp 0
	jr z, .poseOK
	cp 4
	jr z, .poseOK
	cp 8
	jp nz, .reject
.poseOK
	bit 5, e
	jr z, .flipOK
	ld a, e
	and $df
	cp 8
	jp nz, .reject
.flipOK
	ld a, c
	and $0f
	jp nz, .reject
	ld a, c
	cp $a0
	jp nc, .reject
	push hl
	ld a, b
	call .DescriptorAddress
	ld [hl], d
	inc hl
	ld [hl], e
	inc hl
	ld [hl], c
	pop hl
	push hl
	ld a, b
	call .DescriptorAddress
	ld a, l
	add LOBBY_POSE_COMMITTED
	ld l, a
	jr nc, .committedAddress
	inc h
.committedAddress
	ld a, [hli]
	cp d
	jr nz, .dirty
	ld a, [hli]
	cp e
	jr nz, .dirty
	ld a, [hl]
	cp c
	jr nz, .dirty
	pop hl
	push hl
	ld a, l
	add LOBBY_POSE_VALID
	ld l, a
	jr nc, .validAddress
	inc h
.validAddress
	ld a, [hl]
	call .IndexMask
	and d
	jr z, .dirtyFromState
	pop hl
	push hl
	ld a, l
	add LOBBY_POSE_DIRTY
	ld l, a
	jr nc, .clearDirty
	inc h
.clearDirty
	ld a, [hl]
	call .IndexMask
	ld e, a
	ld a, d
	cpl
	and e
	ld [hl], a
	pop hl
	and a
	ret
.dirty
	pop hl
.dirtyFromState
	push hl
	ld a, l
	add LOBBY_POSE_DIRTY
	ld l, a
	jr nc, .setDirty
	inc h
.setDirty
	ld a, [hl]
	call .IndexMask
	or d
	ld [hl], a
	pop hl
	and a
	ret
.reject
	scf
	ret

; a = cache index, hl = state. Returns hl at its three-byte descriptor.
.DescriptorAddress
	push bc
	ld c, a
	add a
	add c
	add l
	ld l, a
	jr nc, .done
	inc h
.done
	pop bc
	ret

; b = cache index, a = flags. Returns d = mask and a restored flags.
.IndexMask
	ld d, 1
	push af
	ld a, b
	and a
	jr z, .maskDone
.maskLoop
	sla d
	dec a
	jr nz, .maskLoop
.maskDone
	pop af
	ret

; a = 0 releases healing ownership, nonzero claims it. hl = state.
; Preserves bc/de/hl. Pending overlapping requests remain dirty.
LobbyPoseCacheSetHealing::
	push bc
	push hl
	ld b, a
	ld a, l
	add LOBBY_POSE_HEALING
	ld l, a
	jr nc, .address
	inc h
.address
	ld a, b
	and a
	jr z, .store
	ld a, 1
.store
	ld [hl], a
	pop hl
	pop bc
	ret

; Invalidate cache a, or all three for $ff. The latest valid request becomes
; dirty, so a full graphics overwrite can be recovered without inventing a new
; request. hl = state. Preserves hl; carry set rejects other indices.
LobbyPoseCacheInvalidate::
	cp $ff
	jr z, .all
	cp 3
	jr nc, .reject
	ld b, a
	call .invalidateOne
	and a
	ret
.all
	ld b, 0
	call .invalidateOne
	inc b
	call .invalidateOne
	inc b
	call .invalidateOne
	and a
	ret
.reject
	scf
	ret
.invalidateOne
	push hl
	ld a, l
	add LOBBY_POSE_VALID
	ld l, a
	jr nc, .validAddress
	inc h
.validAddress
	ld a, [hl]
	call LobbyPoseCacheRequest.IndexMask
	ld e, a
	ld a, d
	cpl
	and e
	ld [hl], a
	pop hl
	push hl
	ld a, b
	call LobbyPoseCacheRequest.DescriptorAddress
	ld a, [hl]
	cp $ff
	pop hl
	ret z
	push hl
	ld a, l
	add LOBBY_POSE_DIRTY
	ld l, a
	jr nc, .dirtyAddress
	inc h
.dirtyAddress
	ld a, [hl]
	call LobbyPoseCacheRequest.IndexMask
	or d
	ld [hl], a
.done
	pop hl
	ret

; Return the first publishable dirty request. Healing ownership skips OAM
; quads beginning at $80/$90 because they overlap healing entries 33..39.
; hl = state. Success: a=index, b=physical cache base, c=OAM byte offset,
; d=picture, e=poseflags. Carry set means no publishable request. Preserves hl.
LobbyPoseCacheSelect::
	push hl
	ld b, 0
.loop
	ld a, l
	add LOBBY_POSE_DIRTY
	ld l, a
	jr nc, .dirtyAddress
	inc h
.dirtyAddress
	ld a, [hl]
	call LobbyPoseCacheRequest.IndexMask
	and d
	jr z, .next
	pop hl
	push hl
	ld a, b
	call LobbyPoseCacheRequest.DescriptorAddress
	ld d, [hl]
	inc hl
	ld e, [hl]
	inc hl
	ld c, [hl]
	pop hl
	push hl
	ld a, l
	add LOBBY_POSE_HEALING
	ld l, a
	jr nc, .healingAddress
	inc h
.healingAddress
	ld a, [hl]
	and a
	jr z, .selected
	ld a, c
	cp $80
	jr nc, .next
.selected
	ld a, b
	add a
	add a
	add $6c
	ld b, a
	pop hl
	ld a, b
	sub $6c
	srl a
	srl a
	and a
	ret
.next
	pop hl
	push hl
	inc b
	ld a, b
	cp 3
	jr c, .loop
	pop hl
	scf
	ret

; Publish a descriptor previously selected and staged by the caller.
; a=index, d=picture, e=poseflags, c=OAM byte offset, hl=state. The caller
; prepares wLobbyPoseStagingTiles (64 bytes) and wLobbyPoseStagingOAM (16).
; The descriptor is rechecked, so a replacement request cannot publish stale
; staging. A deferred/invalid commit remains dirty. Success copies the exact
; descriptor into committed state, sets valid and clears dirty. Preserves hl.
LobbyPoseCachePublish::
	cp 3
	jr nc, .reject
	ld b, a
	push hl
	ld a, b
	call LobbyPoseCacheRequest.DescriptorAddress
	ld a, [hli]
	cp d
	jr nz, .mismatch
	ld a, [hli]
	cp e
	jr nz, .mismatch
	ld a, [hl]
	cp c
	jr nz, .mismatch
	pop hl
	push hl
	ld a, l
	add LOBBY_POSE_DIRTY
	ld l, a
	jr nc, .dirtyAddress
	inc h
.dirtyAddress
	ld a, [hl]
	push de
	call LobbyPoseCacheRequest.IndexMask
	and d
	jr z, .notDirty
	pop de
	pop hl
	push hl
	ld a, l
	add LOBBY_POSE_HEALING
	ld l, a
	jr nc, .healingAddress
	inc h
.healingAddress
	ld a, [hl]
	and a
	jr z, .commit
	ld a, c
	cp $80
	jr nc, .mismatch
.commit
	pop hl
	push hl
	push bc
	push de
	ld a, b
	add a
	add a
	add $6c
	ld b, a
	ld hl, wLobbyPoseStagingTiles
	ld de, wLobbyPoseStagingOAM
	call LobbyPoseCommit
	pop de
	pop bc
	pop hl
	ret c
	push hl
	ld a, b
	call LobbyPoseCacheRequest.DescriptorAddress
	push hl
	ld a, l
	add LOBBY_POSE_COMMITTED
	ld l, a
	jr nc, .committedAddress
	inc h
.committedAddress
	ld a, d
	ld [hli], a
	ld a, e
	ld [hli], a
	ld [hl], c
	pop hl
	pop hl
	push hl
	ld a, l
	add LOBBY_POSE_DIRTY
	ld l, a
	jr nc, .flagsAddress
	inc h
.flagsAddress
	ld a, [hl]
	call LobbyPoseCacheRequest.IndexMask
	ld e, a
	ld a, d
	cpl
	and e
	ld [hli], a ; dirty
	ld a, [hl] ; valid immediately follows dirty
	or d
	ld [hl], a
	pop hl
	and a
	ret
.notDirty
	pop de
	jr .mismatch
.mismatch
	pop hl
.reject
	scf
	ret

; Stage one four-tile standing pose through the established bank-aware copy.
; DIRECT-CALL ABI: a = source ROM bank, de = start of a 12-tile standing sheet,
; b = available tile count, c = poseflags (source 0/4/8 plus optional X flip).
; The source pointer is advanced to the selected four tiles and copied into the
; shared 64-byte wLobbyPoseStagingTiles buffer. X flip changes OAM only and does
; not alter source bytes. Carry set rejects invalid size/pose before any write.
;
; This ABI is deliberately not advertised as farcall-safe: farcall destroys a,
; bc and hl on entry. A future bank-$05 table resolver must either direct-call
; this with the resolved bank/address, or publish those values through audited
; scratch before calling across banks. Do not direct-read SpriteSheetPointerTable
; from a differently placed integration section.
;
; Farcall-safe entry: the future bank-$05 resolver writes bank/address/count and
; selected pose into the five synthetic descriptor bytes named below, then
; farcalls with no register arguments. These symbols remain test-only pending
; WRAM ownership. The ordinary entry immediately following retains the direct
; ABI for same-bank composition and focused testing.
LobbyPoseStageTilesFromDescriptor::
	ld a, [wLobbyPoseStageSourceBank]
	ld de, wLobbyPoseStageSourceAddress
	push af
	ld a, [de]
	ld l, a
	inc de
	ld a, [de]
	ld d, a
	ld e, l
	ld a, [wLobbyPoseStageTileCount]
	ld b, a
	ld a, [wLobbyPoseStagePoseFlags]
	ld c, a
	pop af
	; fall through with the direct-call ABI reconstructed from scratch
LobbyPoseStageTiles::
	ld h, a
	ld a, b
	cp 12
	jr c, .reject
	ld a, c
	and $df
	cp 0
	jr z, .poseOK
	cp 4
	jr z, .poseOK
	cp 8
	jr nz, .reject
.poseOK
	bit 5, c
	jr z, .flipOK
	ld a, c
	and $df
	cp 8
	jr nz, .reject
.flipOK
	ld a, c
	and $0c
	swap a ; source tile offset * 16 bytes
	add e
	ld e, a
	jr nc, .sourceReady
	inc d
.sourceReady
	ld a, h
	ld hl, wLobbyPoseStagingTiles
	ld bc, 4 tiles
	call FarCopyData3
	and a
	ret
.reject
	scf
	ret

; Prepare one current four-entry renderer snapshot for atomic publication.
; hl = 16 stable WRAM bytes produced by the ordinary renderer, b = physical
; cache base ($6c/$70/$74). Copies the quad to wLobbyPoseStagingOAM, preserving
; Y/X coordinates and every attribute bit (including X flip, palette and grass),
; while replacing only tile IDs with base+0..3. Preserves bc/de/hl. Carry set
; rejects an invalid base without writes. Source/destination must not overlap.
; Farcall-safe entry reuses the transient source descriptor after tile staging:
; SourceBank holds the physical cache base and SourceAddress holds the current
; 16-byte renderer snapshot pointer. No additional scratch is required.
LobbyPosePrepareOAMFromDescriptor::
	ld a, [wLobbyPoseStageSourceBank]
	ld b, a
	ld hl, wLobbyPoseStageSourceAddress
	ld a, [hli]
	ld h, [hl]
	ld l, a
	; fall through with the direct-call ABI reconstructed from scratch
LobbyPosePrepareOAM::
	ld a, b
	cp $6c
	jr z, .valid
	cp $70
	jr z, .valid
	cp $74
	jr nz, .reject
.valid
	push bc
	push de
	push hl
	ld de, wLobbyPoseStagingOAM
	ld c, 4
.entry
	ld a, [hli] ; Y
	ld [de], a
	inc de
	ld a, [hli] ; X
	ld [de], a
	inc de
	inc hl ; discard the renderer's previous physical tile
	ld a, b
	ld [de], a
	inc b
	inc de
	ld a, [hli] ; attributes
	ld [de], a
	inc de
	dec c
	jr nz, .entry
	pop hl
	pop de
	pop bc
	and a
	ret
.reject
	scf
	ret
