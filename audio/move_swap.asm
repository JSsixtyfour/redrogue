; Play the move-replacement SFX without reading live music from the SFX bank.
; OneTwoAndText owns the text cursor and preserves BC around this farcall.
; Only HOME calls are used; changing wAudioROMBank does not bank out this code.
SECTION "Move Swap Sound", ROMX, BANK[$2C]

PlayMoveSwapSound::
	ld a, [wLowHealthAlarm]
	push af
	bit BIT_LOW_HEALTH_ALARM, a
	jr z, .alarmQuiet
	ld a, DISABLE_LOW_HEALTH_ALARM
	ld [wLowHealthAlarm], a
	call DelayFrame ; the alarm handler clears its CHAN5 reservation
.alarmQuiet
	call .waitSfx
	di
	ld a, [wMuteAudioAndPauseMusic]
	push af
	ld a, [wAudioFadeOutControl]
	push af
	ldh a, [rAUDVOL]
	push af
	ld a, [wAudioROMBank]
	push af
	xor a
	ld [wAudioFadeOutControl], a ; a fade must not switch banks during the SFX
	inc a
	ld [wMuteAudioAndPauseMusic], a
	ei
	call DelayFrame ; pause music and mute its hardware output before the SFX
	ld a, BANK(SFX_Swap_1)
	ld [wAudioROMBank], a
	ld a, SFX_SWAP
	call PlaySound
	call .waitSfx
	di
	pop af
	ld [wAudioROMBank], a ; restore the bank before allowing music to advance
	pop af
	ldh [rAUDVOL], a
	pop af
	ld [wAudioFadeOutControl], a
	pop af
	ld [wMuteAudioAndPauseMusic], a
	pop af
	ld [wLowHealthAlarm], a
	ei
	ret

.waitSfx
	; WaitForSoundToFinish skips CHAN7 and can bypass its wait for the alarm.
	ld hl, wChannelSoundIDs + CHAN5
	xor a
	or [hl]
	inc hl
	or [hl]
	inc hl
	or [hl]
	inc hl
	or [hl]
	jr nz, .waitSfx
	ret

