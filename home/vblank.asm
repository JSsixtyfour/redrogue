VBlank::

	push af
	push bc
	push de
	push hl

	ldh a, [hLoadedROMBank]
	ld [wVBlankSavedROMBank], a

	ldh a, [hSCX]
	ldh [rSCX], a
	ldh a, [hSCY]
	ldh [rSCY], a

	ld a, [wDisableVBlankWYUpdate]
	and a
	jr nz, .ok
	ldh a, [hWY]
	ldh [rWY], a
.ok

	call AutoBgMapTransfer
	call VBlankCopyBgMap
	call RedrawRowOrColumn
	call VBlankCopy
	call VBlankCopyDouble
	call UpdateMovingBgTiles
	call hDMARoutine
	ld a, BANK(PrepareOAMData)
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	call PrepareOAMData

	; VBlank-sensitive operations end.

	call Random

	ldh a, [hVBlankOccurred]
	and a
	jr z, .skipZeroing
	xor a
	ldh [hVBlankOccurred], a

.skipZeroing
	ldh a, [hFrameCounter]
	and a
	jr z, .skipDec
	dec a
	ldh [hFrameCounter], a

.skipDec
	call FadeOutAudio

; There is a single music engine now (AUDIO_1), so this no longer dispatches
; on [wAudioROMBank] to pick which AudioN_UpdateMusic to call - it's always
; Audio1_UpdateMusic (see engine_1.asm / home/audio.asm's UpdateMusic6Times).
; Music_DoLowHealthAlarm used to run only on this branch's old ".audio2" path
; (i.e. only while AUDIO_2 happened to be the active UpdateMusic bank), which
; the single engine has no equivalent of; it must run unconditionally every
; VBlank now, same as pokeyellow's VBlank, or the alarm tone would never play.
	ld a, BANK(Music_DoLowHealthAlarm)
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	call Music_DoLowHealthAlarm

	ld a, BANK(Audio1_UpdateMusic)
	ldh [hLoadedROMBank], a
	ld [rROMB], a
	call Audio1_UpdateMusic

	farcall TrackPlayTime ; keep track of time played

	ldh a, [hDisableJoypadPolling]
	and a
	call z, ReadJoypad

	; Keep CGB palette attributes synchronized with tile rows and columns drawn
	; earlier in this VBlank. RedrawRowOrColumn saved its mode in bits 0-1.
	ldh a, [hVblankBackup]
	and %11
	jr z, .skipGBCEnhancedRedraw
	farcall GBCEnhancedRedrawRowOrColumn
.skipGBCEnhancedRedraw

	ld a, [wVBlankSavedROMBank]
	ldh [hLoadedROMBank], a
	ld [rROMB], a

	pop hl
	pop de
	pop bc
	pop af
	reti


DelayFrame::
; Wait for the next vblank interrupt.
; As a bonus, this saves battery.

DEF NOT_VBLANKED EQU 1

	ld a, NOT_VBLANKED
	ldh [hVBlankOccurred], a
.halt
	halt
	ldh a, [hVBlankOccurred]
	and a
	jr nz, .halt
	ret
