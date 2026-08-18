; This function is used to wait a short period after printing a letter to the
; screen unless the player presses the A/B button or the delay is turned off
; through the [wStatusFlags5] or [wLetterPrintingDelayFlags] flags.
PrintLetterDelay::
	ld a, [wStatusFlags5]
	bit BIT_NO_TEXT_DELAY, a
	ret nz
	ld a, [wLetterPrintingDelayFlags]
	bit BIT_TEXT_DELAY, a
	ret z
	push hl
	push de
	push bc
	ld a, [wLetterPrintingDelayFlags]
	bit BIT_FAST_TEXT_DELAY, a
	jr z, .waitOneFrame
	ld a, [wOptions]
	and $f
	ldh [hFrameCounter], a
	and a
	jr nz, .checkButtons
; instant text (zero delay): if the SFX channel is currently playing (same
; channel WaitForSoundToFinish/CollisionCheckOnLand already poll), flag it so
; PlaySound (home/audio.asm) can let it finish before starting a new one
; instead of it being cut off before the player even sees the letter that
; triggered it.
	ld a, [wChannelSoundIDs + CHAN5]
	and a
	jr z, .checkButtons
	ldh a, [hSFXPlayingDuringText]
	set 2, a
	ldh [hSFXPlayingDuringText], a
	jr .checkButtons
.waitOneFrame
	ld a, 1
	ldh [hFrameCounter], a
.checkButtons
	call Joypad
	ldh a, [hJoyHeld]
; check A button
	bit B_PAD_A, a
	jr z, .checkBButton
	jr .endWait
.checkBButton
	bit B_PAD_B, a
	jr z, .buttonsNotPressed
.endWait
	call DelayFrame
	jr .done
.buttonsNotPressed ; if neither A nor B is pressed
	ldh a, [hFrameCounter]
	and a
	jr nz, .checkButtons
.done
	pop bc
	pop de
	pop hl
	ret
