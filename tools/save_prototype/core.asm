; ISOLATED EXPERIMENT ONLY. Not included by the production main.asm.
; Public entries return wPSResult=0 on success, 1 on refusal. No UI/boot hooks.
; Uses model_save_handoff's sum8/descriptor physical map, stable active box only.
SECTION "Protected Main Prototype", ROMX, BANK[$2A]

PSOpen:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ret
PSClose:
	ld a, 0
	ld [rRAMG], a
	ld [rBMODE], a
	ret
PSRefuse:
	ld a, 1
	ld [wPSResult], a
	jp PSClose

; Test-build SaveGameData dispatch only. Legacy format takes its original path.
PSIsExperimentalFormat::
	call PSOpen
	call PSFormatCheck
	jp PSClose

; CRC32/ISO-HDLC, little-endian, same polynomial/initial/final XOR as zlib.
PSCRCInit:
	ld hl, wPSCRC
	ld a, $ff
	ld b, 4
.loop
	ld [hli], a
	dec b
	jr nz, .loop
	ret
PSCRCByte:
	push bc
	push hl
	ld hl, wPSCRC
	xor [hl]
	ld [hl], a
	ld b, 8
.bit
	ld hl, wPSCRC + 3
	srl [hl]
	dec hl
	rr [hl]
	dec hl
	rr [hl]
	dec hl
	rr [hl]
	jr nc, .next
	ld a, [hl]
	xor $20
	ld [hli], a
	ld a, [hl]
	xor $83
	ld [hli], a
	ld a, [hl]
	xor $b8
	ld [hli], a
	ld a, [hl]
	xor $ed
	ld [hl], a
.next
	dec b
	jr nz, .bit
	pop hl
	pop bc
	ret

; HL -> 18-byte record in WRAM. Carry set only when CRC and context are valid.
PSMetadataValid:
	push hl
	ld de, 17
	add hl, de
	ld a, [hl]
	cp $a5
	pop hl
	jr nz, .bad
	push hl
	call PSCRCInit
	pop hl
	ld b, 13
.crc
	ld a, [hli]
	call PSCRCByte
	dec b
	jr nz, .crc
	ld de, wPSCRC
	ld b, 4
.compare
	ld a, [de]
	cpl
	cp [hl]
	jr nz, .bad
	inc de
	inc hl
	dec b
	jr nz, .compare
	scf
	ret
.bad
	and a
	ret

PSSelect::
	ld a, 1
	ld [wPSResult], a
	call PSOpen
	call PSFormatCheck
	jp nz, PSRefuse
	xor a
	ld [rRAMB], a
	ld hl, PS_SELECTOR
	ld de, wPSRecords
	ld bc, 36
	call CopyData
	ld hl, wPSRecords
	call PSMetadataValid
	ld a, 0
	rla
	ld [wPSValid], a
	ld hl, wPSRecords + 18
	call PSMetadataValid
	ld a, [wPSValid]
	rla
	ld [wPSValid], a
	and a
	jp z, PSRefuse
	cp 3
	jr z, .both
	; bit 0 represents slot 1; bit 1 represents slot 0.
	and 1
	jr .selected
.both
	; Unsigned modular (seq1 - seq0). Zero and half-range are ambiguous.
	ld hl, wPSRecords
	ld de, wPSRecords + 18
	ld bc, wPSDelta
	and a
	REPT 4
	ld a, [de]
	sbc [hl]
	ld [bc], a
	inc hl
	inc de
	inc bc
	ENDR
	ld hl, wPSDelta
	ld a, [hli]
	or [hl]
	inc hl
	or [hl]
	ld b, a
	inc hl
	or [hl]
	jp z, PSRefuse
	ld a, [hl]
	cp $80
	jr nz, .notHalf
	ld a, b
	and a
	jp z, PSRefuse
.notHalf
	ld a, [hl]
	rlca
	and 1
	xor 1
.selected
	ld [wPSWhich], a
	ld hl, wPSRecords
	and a
	jr z, .copy
	ld hl, wPSRecords + 18
.copy
	ld de, wPSSelected
	ld bc, 18
	call CopyData
	ld a, [wPSSelected + 4]
	cp 2 ; DONE
	jp nz, PSRefuse
	ld a, [wPSSelected + 10]
	ld b, a
	ld a, [wPSSelected + 11]
	or b
	ld b, a
	ld a, [wPSSelected + 12]
	or b
	jp nz, PSRefuse
	ld a, [wPSSelected + 9]
	cp 24
	jp nc, PSRefuse
	ld b, a
	and 1
	ld [wPSSlot], a
	ld a, b
	srl a
	ld [wPSActive], a
	call PSSetStream
	; The record's generation must match the CRC-protected selector.
	ld de, wPSSelected + 5
	ld b, 4
.generation
	call PSReadByte
	ld c, a
	ld a, [de]
	cp c
	jp nz, PSRefuse
	inc de
	dec b
	jr nz, .generation
	ld bc, PS_PAYLOAD
	xor a
	ld [wPSSum], a
.sum
	call PSReadByte
	ld hl, wPSSum
	add [hl]
	ld [hl], a
	dec bc
	ld a, b
	or c
	jr nz, .sum
	call PSReadByte
	ld b, a
	ld a, [wPSSum]
	cpl
	cp b
	jp nz, PSRefuse
	call PSReadByte
	cp $a5
	jp nz, PSRefuse
	; Independently check that payload active-box identity agrees with metadata.
	call PSSetStream
	ld bc, 4 + PS_CURRENT_OFFSET
.skip
	call PSReadByte
	dec bc
	ld a, b
	or c
	jr nz, .skip
	call PSReadByte
	and BOX_NUM_MASK
	ld b, a
	ld a, [wPSActive]
	cp b
	jp nz, PSRefuse
	xor a
	ld [wPSResult], a
	jp PSClose

; Stream table pointer for the selected slot and active box; each row is
; bank/address/length, followed by bank $ff. PSReadByte preserves BC and DE.
PSSetStream:
	ld hl, PSFixedMap
	ld a, [wPSSlot]
	and a
	jr z, .store
	ld a, [wPSActive]
	add a
	ld e, a
	ld d, 0
	ld hl, PSShadowMaps
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
.store
	ld a, l
	ld [wPSStream], a
	ld a, h
	ld [wPSStream + 1], a
	xor a
	ld [wPSRemaining], a
	ld [wPSRemaining + 1], a
	ret
PSReadByte:
	push bc
	push de
	push hl
	ld a, [wPSRemaining]
	ld b, a
	ld a, [wPSRemaining + 1]
	or b
	jr nz, .read
	ld a, [wPSStream]
	ld l, a
	ld a, [wPSStream + 1]
	ld h, a
	ld a, [hli]
	ld [wPSBank], a
	ld a, [hli]
	ld [wPSAddress], a
	ld a, [hli]
	ld [wPSAddress + 1], a
	ld a, [hli]
	ld [wPSRemaining], a
	ld a, [hli]
	ld [wPSRemaining + 1], a
	ld a, l
	ld [wPSStream], a
	ld a, h
	ld [wPSStream + 1], a
.read
	ld a, [wPSBank]
	ld [rRAMB], a
	ld a, [wPSAddress]
	ld l, a
	ld a, [wPSAddress + 1]
	ld h, a
	ld a, [hli]
	ld c, a
	ld a, l
	ld [wPSAddress], a
	ld a, h
	ld [wPSAddress + 1], a
	ld a, [wPSRemaining]
	ld l, a
	ld a, [wPSRemaining + 1]
	ld h, a
	dec hl
	ld a, l
	ld [wPSRemaining], a
	ld a, h
	ld [wPSRemaining + 1], a
	ld a, c
	pop hl
	pop de
	pop bc
	ret

; No writes to the destination until PSSelect validates the entire record.
PSLoad::
	call PSSelect
	ld a, [wPSResult]
	and a
	ret nz
	call PSOpen
	call PSSetStream
	REPT 4
	call PSReadByte
	ENDR
	ld hl, PSWRAMRegions
.region
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a
	ld a, [hli]
	ld c, a
	ld a, [hli]
	ld b, a
	or c
	jr z, .done
.copy
	call PSReadByte
	ld [de], a
	inc de
	dec bc
	ld a, b
	or c
	jr nz, .copy
	jr .region
.done
	jp PSClose

; Settled main-only write. Refuses active-box changes and unknown formats.
; Companion mutations, initial format creation and gameplay hooks are excluded.
PSSave::
	call PSSelect
	ld a, [wPSResult]
	and a
	ret nz
	ld a, [wCurrentBoxNum]
	and BOX_NUM_MASK
	ld b, a
	ld a, [wPSActive]
	cp b
	jp nz, PSRefuse
	call PSOpen
	ld a, [wPSSlot]
	xor 1
	ld [wPSSlot], a
	; Invalidate the target main record before any generation or payload byte.
	call PSMarkerAddress
	xor a
.invalidateMain
	ld [hl], a
	; New generation, modulo 2^32, and selector sequence.
	ld hl, wPSSelected + 5
	call PSIncrement
	ld hl, wPSSelected
	call PSIncrement
	ld a, [wPSActive]
	add a
	ld b, a
	ld a, [wPSSlot]
	or b
	ld [wPSSelected + 9], a
	call PSWriteGeneration
	; Generated split-copy table for the two physical payload mappings.
	call PSPayloadTable
	xor a
	ld [wPSSum], a
.region
	ld a, [hli]
	cp $ff
	jr z, .finishMain
	ld [rRAMB], a
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a
	ld a, [hli]
	ld [wPSLength], a
	ld a, [hli]
	ld [wPSLength + 1], a
	ld a, [hli]
	ld c, a
	ld a, [hli]
	ld b, a
	ld a, l
	ld [wPSTable], a
	ld a, h
	ld [wPSTable + 1], a
	ld h, b
	ld l, c
	ld a, [wPSLength]
	ld c, a
	ld a, [wPSLength + 1]
	ld b, a
	ld a, [wPSSum]
	call PSCopySum
	ld [wPSSum], a
	ld a, [wPSTable]
	ld l, a
	ld a, [wPSTable + 1]
	ld h, a
	jr .region
.finishMain
	call PSChecksumAddress
	ld a, [wPSSum]
	cpl
.checksum
	ld [hl], a
	call PSMarkerAddress
	ld a, $a5
.commitMain
	ld [hl], a
	; CRC-seal and publish the inactive selector, retaining the selected slot.
	call PSCRCInit
	ld hl, wPSSelected
	ld b, 13
.crc
	ld a, [hli]
	call PSCRCByte
	dec b
	jr nz, .crc
	ld de, wPSCRC
	ld b, 4
.seal
	ld a, [de]
	cpl
	ld [hli], a
	inc de
	dec b
	jr nz, .seal
	xor a
	ld [rRAMB], a
	ld hl, PS_SELECTOR + 18
	ld a, [wPSWhich]
	and a
	jr z, .selector
	ld hl, PS_SELECTOR
.selector
	push hl
	ld de, 17
	add hl, de
	xor a
.invalidateSelector
	ld [hl], a
	pop de
	ld hl, wPSSelected
	ld bc, 17
	call CopyData
	ld a, $a5
.commitSelector
	ld [de], a
	xor a
	ld [wPSResult], a
	jp PSClose

PSWriteGeneration:
	xor a
	ld [rRAMB], a
	ld de, PS_FIXED_GENERATION
	ld a, [wPSSlot]
	and a
	jr z, .copy
	ld de, PS_SHADOW_GENERATION
.copy
	ld hl, wPSSelected + 5
	ld bc, 4
	jp CopyData

PSMarkerAddress:
	ld a, [wPSSlot]
	and a
	jr nz, .shadow
	ld [rRAMB], a
	ld hl, PS_FIXED_MARKER
	ret
.shadow
	ld a, [wPSActive]
	ld e, a
	add a
	add e
	ld e, a
	ld d, 0
	ld hl, PSShadowMarkers
	add hl, de
	ld a, [hli]
	ld [rRAMB], a
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret
PSChecksumAddress:
	ld a, [wPSSlot]
	and a
	jr nz, .shadow
	ld a, BANK(sMainDataCheckSum)
	ld [rRAMB], a
	ld hl, sMainDataCheckSum
	ret
.shadow
	call PSMarkerAddress
	dec hl
	ret

PSIncrement:
	ld b, 4
.loop
	inc [hl]
	ret nz
	inc hl
	dec b
	jr nz, .loop
	ret

; Generated code and map constants follow in generated.asm.
