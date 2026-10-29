; Direct blackout only. No ordinary manual-save or archival-ending protection.
; All external edges are farcalls; local pointers/table reads stay in bank 2A.
DEF LOSS_RECOVERY_FORMAT EQU 1
; Body = name + Main Data up to wGameProgressFlags + the tail after it + gyms + credits,
; packed densely across the three SRAM spans; the slack sits at the end of span 3.
; Label differences are link-time values, so the split is literal and the ASSERTs pin it.
DEF LOSS_MAIN_HEAD EQU 596 ; 696 before the Crystal audio port took 100 B of follower pad
DEF LOSS_MAIN_TAIL EQU 790
DEF LOSS_RECOVERY_BODY EQU NAME_LENGTH + LOSS_MAIN_HEAD + LOSS_MAIN_TAIL + 2 + 1
DEF LOSS_SPAN1_MAIN EQU 512 - 27 ; span 1: 16 B header + name + this much Main Data
DEF LOSS_SPAN2_MAIN EQU LOSS_MAIN_HEAD - LOSS_SPAN1_MAIN
DEF LOSS_SPAN2_TAIL EQU 497 - LOSS_SPAN2_MAIN
DEF LOSS_SPAN3_TAIL EQU LOSS_MAIN_TAIL - LOSS_SPAN2_TAIL
DEF LOSS_SPAN3_USED EQU LOSS_SPAN3_TAIL + 2 + 1
ASSERT LOSS_SPAN2_MAIN > 0 && LOSS_SPAN3_TAIL > 0
ASSERT LOSS_SPAN3_USED <= 507, "loss-recovery record no longer fits its SRAM spans"
ASSERT NAME_LENGTH == 11
ASSERT wGameProgressFlags - wMainDataStart == LOSS_MAIN_HEAD
ASSERT wMainDataEnd - wGameProgressFlagsEnd == LOSS_MAIN_TAIL

DEF LOSS_RECOVERY_VALID EQU $a5
DEF LOSS_RECOVERY_DEBUG EQU (1 << BIT_DEBUG_MODE) | (1 << BIT_DEBUG2_MODE)

MACRO loss_copy
	ld a, \1
	ld [rRAMB], a
	ld hl, \2
	ld de, \3
	ld bc, \4
	call CopyData
ENDM

LossRecoveryOpen:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, 3
	ld [rRAMB], a
	ret
LossRecoveryClose:
	xor a
	ld [rRAMG], a
	ld [rBMODE], a
	ret

; New Game's consent gate calls this before invalidating its main header.
LossRecoveryDiscard::
	call LossRecoveryOpen
	xor a
	ld [sLossRecoveryValid], a
	ld [wLossRecoveryPending], a
	jp LossRecoveryClose

; Capture BEFORE any covered reset. Rental terminal paths already reclaimed
; storage, so ALL nonzero rental states are deliberately excluded here.
LossRecoveryCapture::
	xor a
	ld [wLossRecoveryPending], a
	ld a, [wStatusFlags6]
	and LOSS_RECOVERY_DEBUG
	ret nz
	ld a, [wRentalState]
	and a
	ret nz
	call LossRecoveryOpen
	ld a, [sLossRecoveryValid]
	cp LOSS_RECOVERY_VALID
	jr nz, .prepare
	; Never overwrite an active record, even if main memory was loaded oddly.
	call LossRecoveryClose
	jp Init
.prepare
	; Do not write the invalid marker again: publication is the final write.
	call LossRecoveryClose
	ld de, LossRecoverySavingText
	call LossRecoveryNotice
LossRecoveryPrepare::
	; Synchronize exactly the saved gamma event, without changing detection.
	ldh a, [hGBC]
	and a
	jr z, .gammaReady
	cp 2
	jr z, .gammaOn
	ResetEvent EVENT_GAMMA_SHADER
	jr .gammaReady
.gammaOn
	SetEvent EVENT_GAMMA_SHADER
.gammaReady
	call LossRecoveryOpen
	loss_copy 1, sStolenRecord, wStolenSaveSnapshot, sStolenRecordEnd - sStolenRecord
	ld hl, LossRecoveryHeaderTemplate
	ld de, wLossRecoveryHeader
	ld bc, 16
	call CopyData
	ld a, [wPlayerID]
	ld [wLossRecoveryHeader + 10], a
	ld a, [wPlayerID + 1]
	ld [wLossRecoveryHeader + 11], a
	ldh a, [hCurMap]
	ld [wLossRecoveryHeader + 12], a
	ldh a, [hTileAnimations]
	ld [wLossRecoveryHeader + 13], a
	CheckEvent EVENT_GAMMA_SHADER
	ld a, 0
	jr z, .gammaCaptured
	inc a
.gammaCaptured
	ld [wLossRecoveryHeader + 14], a
	ld a, [wStatusFlags6]
	ld [wLossRecoveryHeader + 15], a
	loss_copy 1, wLossRecoveryHeader, sLossRecovery1, 16
	loss_copy 1, wPlayerName, sLossRecovery1 + 16, 11
	loss_copy 1, wMainDataStart, sLossRecovery1 + 27, LOSS_SPAN1_MAIN
	loss_copy 3, wMainDataStart + LOSS_SPAN1_MAIN, sLossRecovery2, LOSS_SPAN2_MAIN
	loss_copy 3, wGameProgressFlagsEnd, sLossRecovery2 + LOSS_SPAN2_MAIN, LOSS_SPAN2_TAIL
	loss_copy 3, wGameProgressFlagsEnd + LOSS_SPAN2_TAIL, sLossRecovery3, LOSS_SPAN3_TAIL
	loss_copy 3, wGymsUsedMask, sLossRecovery3 + LOSS_SPAN3_TAIL, 2
	ld a, [wCreditsEarnedThisRun]
	ld [sLossRecovery3 + LOSS_SPAN3_TAIL + 2], a
	; zero the unused tail of span 3 so the CRC never covers stale bytes
	ld hl, sLossRecovery3 + LOSS_SPAN3_USED
	ld bc, 507 - LOSS_SPAN3_USED
	xor a
	call FillMemory
	call LossRecoveryChecksum
	loss_copy 3, wLossRecoveryCRC, sLossRecoveryCRC, 4
.publish
	ld a, LOSS_RECOVERY_VALID
	ld [sLossRecoveryValid], a
	ld a, 1
	ld [wLossRecoveryPending], a
	jp LossRecoveryClose

LossRecoveryHeaderTemplate:
	db $52, $52, $4c, $52, LOSS_RECOVERY_FORMAT
	dw SAVE_SCHEMA_ID, LOSS_RECOVERY_BODY
	db 1 ; typed intent: direct loss, NEVER infer an ending from source map
	ds 6, 0

; Carry iff the immutable record is valid for this executable's exact schema.
; The validity marker alone is never sufficient. Does not touch main SRAM.
LossRecoveryValidate::
	call LossRecoveryOpen
	ld a, [sLossRecoveryValid]
	cp LOSS_RECOVERY_VALID
	jr nz, .invalid
	loss_copy 1, sLossRecovery1, wLossRecoveryHeader, 16
	ld hl, LossRecoveryHeaderTemplate
	ld de, wLossRecoveryHeader
	ld b, 10
.header
	ld a, [de]
	cp [hl]
	jr nz, .invalid
	inc hl
	inc de
	dec b
	jr nz, .header
	ld a, [wLossRecoveryHeader + 15]
	and LOSS_RECOVERY_DEBUG
	jr nz, .invalid
	ld a, [wLossRecoveryHeader + 14]
	cp 2
	jr nc, .invalid
	call LossRecoveryChecksum
	ld hl, sLossRecoveryCRC
	ld de, wLossRecoveryCRC
	ld b, 4
.crc
	ld a, [de]
	cp [hl]
	jr nz, .invalid
	inc hl
	inc de
	dec b
	jr nz, .crc
	call LossRecoveryClose
	scf
	ret
.invalid
	call LossRecoveryClose
	and a
	ret

; MainMenu enters here BEFORE examining the main header/checksum. Return to
; HOME before SpecialEnterMap, never jump across banks from ROMX.
LossRecoveryBoot::
	xor a
	ld [wLossRecoveryPending], a
	call LossRecoveryValidate
	jr c, .recover
	call LossRecoveryOpen
	ld a, [sLossRecoveryValid]
	cp LOSS_RECOVERY_VALID
	push af
	call LossRecoveryClose
	pop af
	jr z, .damaged
	xor a ; Z, carry clear: no active recovery
	ret
.damaged
	call LoadFontTilePatterns
	call LoadTextBoxTilePatterns
	ld hl, .damagedText
	call PrintText
	ld a, 1
	ld [wSaveFileStatus], a
	and a ; NZ, carry clear: never load even a superficially valid old main
	ret
.damagedText
	text "Recovery damaged."
	line "Start NEW GAME."
	prompt
.recover
	call LossRecoveryRestore
	; The real hardware was detected by Init. Restore only its gamma preference.
	ldh a, [hGBC]
	and a
	jr z, .hardwareReady
	ld a, [wLossRecoveryHeader + 14]
	inc a
	ldh [hGBC], a
.hardwareReady
	call LoadFontTilePatterns
	call LoadTextBoxTilePatterns
	ld de, LossRecoverySavingText
	call LossRecoveryNotice
	rfarcall ResetStatusAndHalveMoneyOnBlackout
	rfarcall PrepareForSpecialWarp
	ld a, 1
	ld [wLossRecoveryPending], a
	scf
	ret

; Restore the envelope and seed every omitted saved region explicitly, even
; when a prior failed load left arbitrary RAM. No New Game initializer.
LossRecoveryRestore::
	call LossRecoveryOpen
	loss_copy 1, sLossRecovery1 + 16, wPlayerName, 11
	loss_copy 1, sLossRecovery1 + 27, wMainDataStart, LOSS_SPAN1_MAIN
	loss_copy 3, sLossRecovery2, wMainDataStart + LOSS_SPAN1_MAIN, LOSS_SPAN2_MAIN
	loss_copy 3, sLossRecovery2 + LOSS_SPAN2_MAIN, wGameProgressFlagsEnd, LOSS_SPAN2_TAIL
	loss_copy 3, sLossRecovery3, wGameProgressFlagsEnd + LOSS_SPAN2_TAIL, LOSS_SPAN3_TAIL
	ld hl, wGameProgressFlags
	ld bc, wGameProgressFlagsEnd - wGameProgressFlags
	xor a
	call FillMemory
	loss_copy 3, sLossRecovery3 + LOSS_SPAN3_TAIL, wGymsUsedMask, 2
	ld a, [sLossRecovery3 + LOSS_SPAN3_TAIL + 2]
	ld [wCreditsEarnedThisRun], a
	loss_copy 1, wStolenSaveSnapshot, sStolenRecord, sStolenRecordEnd - sStolenRecord
	call LossRecoveryClose
	ld hl, wSpriteDataStart
	ld bc, wSpriteDataEnd - wSpriteDataStart
	xor a
	call FillMemory
	ld hl, wPartyDataStart
	ld bc, wPartyDataEnd - wPartyDataStart
	xor a
	call FillMemory
	ld hl, wBoxDataStart
	ld bc, wBoxDataEnd - wBoxDataStart
	xor a
	call FillMemory
	; These are transient map/battle/warp owners, not permanent progression.
	xor a
	ld [wStatusFlags3], a
	ld [wStatusFlags4], a
	ld [wStatusFlags5], a
	ld [wStatusFlags6], a
	ld [wCableClubDestinationMap], a
	ld [wEnteringCableClub], a
	ld a, [wLossRecoveryHeader + 12]
	ldh [hCurMap], a
	ld a, [wLossRecoveryHeader + 13]
	ldh [hTileAnimations], a
	ret

; Only the settled Dorm consumes this unsaved request. The recovery record
; remains authoritative through the full writer, then is retired LAST.
LossRecoveryFinish::
	ld a, [wLossRecoveryPending]
	and a
	ret z
	xor a
	ld [wLossRecoveryPending], a
	ld a, [wStatusFlags6]
	and LOSS_RECOVERY_DEBUG
	ret nz
	ldh a, [hCurMap]
	cp SILPH_CO_DORM
	ret nz
	rfarcall SaveGameData
.retire
	call LossRecoveryDiscard
	ld de, LossRecoverySavedText
	jp LossRecoveryNotice

; Noninteractive overlay, using the same saved bank/text lifecycle as credits.
; Half a second of served frames, independent of the battle-speed option.
LossRecoveryNotice:
	push de
	hlcoord 1, 1
	lb bc, 18, 3
	predef SaveScreenTileAreaToBuffer3
	hlcoord 1, 1
	lb bc, 1, 16
	call TextBoxBorder
	pop de
	hlcoord 2, 2
	call PlaceString
	ldh a, [hLoadedROMBank]
	push af
	ld hl, wAutoTextBoxDrawingControl
	ld a, [hl]
	push af
	set BIT_NO_AUTO_TEXT_BOX, [hl]
	rfarcall DisplayTextIDInit
	pop af
	ld [wAutoTextBoxDrawingControl], a
	; EndOfBattle leaves the palettes white. Reveal only AFTER the notice's
	; tiles/font/window are ready, including the CGB overworld palette set.
	ld b, SET_PAL_OVERWORLD
	call RunPaletteCommand
	xor a
	ld [wMapPalOffset], a
	call LoadGBPal
	ld c, 30
.hold
	call DelayFrame
	dec c
	jr nz, .hold
	hlcoord 1, 1
	lb bc, 18, 3
	predef LoadScreenTileAreaFromBuffer3
	jp CloseTextDisplay
LossRecoverySavingText: db "SAVING...@"
LossRecoverySavedText: db "RUN SAVED@"

; IEEE CRC32, initial/final complement. Four 256-byte table planes avoid a
; bit-at-a-time hot path. SRAM stays open; each span selects its own bank.
LossRecoveryChecksum:
	ld hl, wLossRecoveryCRC
	ld bc, 4
	ld a, $ff
	call FillMemory
	ld a, 1
	ld [rRAMB], a
	ld hl, sLossRecovery1
	ld bc, 512
	call .span
	ld a, 3
	ld [rRAMB], a
	ld hl, sLossRecovery2
	ld bc, 497
	call .span
	ld hl, sLossRecovery3
	ld bc, 507
	call .span
	ld hl, wLossRecoveryCRC
	ld b, 4
.complement
	ld a, [hl]
	cpl
	ld [hli], a
	dec b
	jr nz, .complement
	ret
.span
	ld a, [hli]
	push hl
	push bc
	call LossRecoveryCRCByte
	pop bc
	pop hl
	dec bc
	ld a, b
	or c
	jr nz, .span
	ret
LossRecoveryCRCByte:
	ld hl, wLossRecoveryCRC
	xor [hl]
	ld l, a
	ld h, HIGH(LossRecoveryCRCTable)
	ld a, [wLossRecoveryCRC + 1]
	xor [hl]
	ld [wLossRecoveryCRC], a
	inc h
	ld a, [wLossRecoveryCRC + 2]
	xor [hl]
	ld [wLossRecoveryCRC + 1], a
	inc h
	ld a, [wLossRecoveryCRC + 3]
	xor [hl]
	ld [wLossRecoveryCRC + 2], a
	inc h
	ld a, [hl]
	ld [wLossRecoveryCRC + 3], a
	ret

SECTION "Loss Recovery CRC", ROMX, BANK[$2A], ALIGN[8]
LossRecoveryCRCTable:
	db $00, $96, $2c, $ba, $19, $8f, $35, $a3, $32, $a4, $1e, $88, $2b, $bd, $07, $91
	db $64, $f2, $48, $de, $7d, $eb, $51, $c7, $56, $c0, $7a, $ec, $4f, $d9, $63, $f5
	db $c8, $5e, $e4, $72, $d1, $47, $fd, $6b, $fa, $6c, $d6, $40, $e3, $75, $cf, $59
	db $ac, $3a, $80, $16, $b5, $23, $99, $0f, $9e, $08, $b2, $24, $87, $11, $ab, $3d
	db $90, $06, $bc, $2a, $89, $1f, $a5, $33, $a2, $34, $8e, $18, $bb, $2d, $97, $01
	db $f4, $62, $d8, $4e, $ed, $7b, $c1, $57, $c6, $50, $ea, $7c, $df, $49, $f3, $65
	db $58, $ce, $74, $e2, $41, $d7, $6d, $fb, $6a, $fc, $46, $d0, $73, $e5, $5f, $c9
	db $3c, $aa, $10, $86, $25, $b3, $09, $9f, $0e, $98, $22, $b4, $17, $81, $3b, $ad
	db $20, $b6, $0c, $9a, $39, $af, $15, $83, $12, $84, $3e, $a8, $0b, $9d, $27, $b1
	db $44, $d2, $68, $fe, $5d, $cb, $71, $e7, $76, $e0, $5a, $cc, $6f, $f9, $43, $d5
	db $e8, $7e, $c4, $52, $f1, $67, $dd, $4b, $da, $4c, $f6, $60, $c3, $55, $ef, $79
	db $8c, $1a, $a0, $36, $95, $03, $b9, $2f, $be, $28, $92, $04, $a7, $31, $8b, $1d
	db $b0, $26, $9c, $0a, $a9, $3f, $85, $13, $82, $14, $ae, $38, $9b, $0d, $b7, $21
	db $d4, $42, $f8, $6e, $cd, $5b, $e1, $77, $e6, $70, $ca, $5c, $ff, $69, $d3, $45
	db $78, $ee, $54, $c2, $61, $f7, $4d, $db, $4a, $dc, $66, $f0, $53, $c5, $7f, $e9
	db $1c, $8a, $30, $a6, $05, $93, $29, $bf, $2e, $b8, $02, $94, $37, $a1, $1b, $8d
	db $00, $30, $61, $51, $c4, $f4, $a5, $95, $88, $b8, $e9, $d9, $4c, $7c, $2d, $1d
	db $10, $20, $71, $41, $d4, $e4, $b5, $85, $98, $a8, $f9, $c9, $5c, $6c, $3d, $0d
	db $20, $10, $41, $71, $e4, $d4, $85, $b5, $a8, $98, $c9, $f9, $6c, $5c, $0d, $3d
	db $30, $00, $51, $61, $f4, $c4, $95, $a5, $b8, $88, $d9, $e9, $7c, $4c, $1d, $2d
	db $41, $71, $20, $10, $85, $b5, $e4, $d4, $c9, $f9, $a8, $98, $0d, $3d, $6c, $5c
	db $51, $61, $30, $00, $95, $a5, $f4, $c4, $d9, $e9, $b8, $88, $1d, $2d, $7c, $4c
	db $61, $51, $00, $30, $a5, $95, $c4, $f4, $e9, $d9, $88, $b8, $2d, $1d, $4c, $7c
	db $71, $41, $10, $20, $b5, $85, $d4, $e4, $f9, $c9, $98, $a8, $3d, $0d, $5c, $6c
	db $83, $b3, $e2, $d2, $47, $77, $26, $16, $0b, $3b, $6a, $5a, $cf, $ff, $ae, $9e
	db $93, $a3, $f2, $c2, $57, $67, $36, $06, $1b, $2b, $7a, $4a, $df, $ef, $be, $8e
	db $a3, $93, $c2, $f2, $67, $57, $06, $36, $2b, $1b, $4a, $7a, $ef, $df, $8e, $be
	db $b3, $83, $d2, $e2, $77, $47, $16, $26, $3b, $0b, $5a, $6a, $ff, $cf, $9e, $ae
	db $c2, $f2, $a3, $93, $06, $36, $67, $57, $4a, $7a, $2b, $1b, $8e, $be, $ef, $df
	db $d2, $e2, $b3, $83, $16, $26, $77, $47, $5a, $6a, $3b, $0b, $9e, $ae, $ff, $cf
	db $e2, $d2, $83, $b3, $26, $16, $47, $77, $6a, $5a, $0b, $3b, $ae, $9e, $cf, $ff
	db $f2, $c2, $93, $a3, $36, $06, $57, $67, $7a, $4a, $1b, $2b, $be, $8e, $df, $ef
	db $00, $07, $0e, $09, $6d, $6a, $63, $64, $db, $dc, $d5, $d2, $b6, $b1, $b8, $bf
	db $b7, $b0, $b9, $be, $da, $dd, $d4, $d3, $6c, $6b, $62, $65, $01, $06, $0f, $08
	db $6e, $69, $60, $67, $03, $04, $0d, $0a, $b5, $b2, $bb, $bc, $d8, $df, $d6, $d1
	db $d9, $de, $d7, $d0, $b4, $b3, $ba, $bd, $02, $05, $0c, $0b, $6f, $68, $61, $66
	db $dc, $db, $d2, $d5, $b1, $b6, $bf, $b8, $07, $00, $09, $0e, $6a, $6d, $64, $63
	db $6b, $6c, $65, $62, $06, $01, $08, $0f, $b0, $b7, $be, $b9, $dd, $da, $d3, $d4
	db $b2, $b5, $bc, $bb, $df, $d8, $d1, $d6, $69, $6e, $67, $60, $04, $03, $0a, $0d
	db $05, $02, $0b, $0c, $68, $6f, $66, $61, $de, $d9, $d0, $d7, $b3, $b4, $bd, $ba
	db $b8, $bf, $b6, $b1, $d5, $d2, $db, $dc, $63, $64, $6d, $6a, $0e, $09, $00, $07
	db $0f, $08, $01, $06, $62, $65, $6c, $6b, $d4, $d3, $da, $dd, $b9, $be, $b7, $b0
	db $d6, $d1, $d8, $df, $bb, $bc, $b5, $b2, $0d, $0a, $03, $04, $60, $67, $6e, $69
	db $61, $66, $6f, $68, $0c, $0b, $02, $05, $ba, $bd, $b4, $b3, $d7, $d0, $d9, $de
	db $64, $63, $6a, $6d, $09, $0e, $07, $00, $bf, $b8, $b1, $b6, $d2, $d5, $dc, $db
	db $d3, $d4, $dd, $da, $be, $b9, $b0, $b7, $08, $0f, $06, $01, $65, $62, $6b, $6c
	db $0a, $0d, $04, $03, $67, $60, $69, $6e, $d1, $d6, $df, $d8, $bc, $bb, $b2, $b5
	db $bd, $ba, $b3, $b4, $d0, $d7, $de, $d9, $66, $61, $68, $6f, $0b, $0c, $05, $02
	db $00, $77, $ee, $99, $07, $70, $e9, $9e, $0e, $79, $e0, $97, $09, $7e, $e7, $90
	db $1d, $6a, $f3, $84, $1a, $6d, $f4, $83, $13, $64, $fd, $8a, $14, $63, $fa, $8d
	db $3b, $4c, $d5, $a2, $3c, $4b, $d2, $a5, $35, $42, $db, $ac, $32, $45, $dc, $ab
	db $26, $51, $c8, $bf, $21, $56, $cf, $b8, $28, $5f, $c6, $b1, $2f, $58, $c1, $b6
	db $76, $01, $98, $ef, $71, $06, $9f, $e8, $78, $0f, $96, $e1, $7f, $08, $91, $e6
	db $6b, $1c, $85, $f2, $6c, $1b, $82, $f5, $65, $12, $8b, $fc, $62, $15, $8c, $fb
	db $4d, $3a, $a3, $d4, $4a, $3d, $a4, $d3, $43, $34, $ad, $da, $44, $33, $aa, $dd
	db $50, $27, $be, $c9, $57, $20, $b9, $ce, $5e, $29, $b0, $c7, $59, $2e, $b7, $c0
	db $ed, $9a, $03, $74, $ea, $9d, $04, $73, $e3, $94, $0d, $7a, $e4, $93, $0a, $7d
	db $f0, $87, $1e, $69, $f7, $80, $19, $6e, $fe, $89, $10, $67, $f9, $8e, $17, $60
	db $d6, $a1, $38, $4f, $d1, $a6, $3f, $48, $d8, $af, $36, $41, $df, $a8, $31, $46
	db $cb, $bc, $25, $52, $cc, $bb, $22, $55, $c5, $b2, $2b, $5c, $c2, $b5, $2c, $5b
	db $9b, $ec, $75, $02, $9c, $eb, $72, $05, $95, $e2, $7b, $0c, $92, $e5, $7c, $0b
	db $86, $f1, $68, $1f, $81, $f6, $6f, $18, $88, $ff, $66, $11, $8f, $f8, $61, $16
	db $a0, $d7, $4e, $39, $a7, $d0, $49, $3e, $ae, $d9, $40, $37, $a9, $de, $47, $30
	db $bd, $ca, $53, $24, $ba, $cd, $54, $23, $b3, $c4, $5d, $2a, $b4, $c3, $5a, $2d
