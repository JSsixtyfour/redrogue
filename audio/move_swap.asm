; Play the move-replacement SFX. OneTwoAndText owns the text cursor and preserves BC
; around this farcall. Under the Crystal audio engine SFX IDs are global, so the old
; pause-music/switch-bank dance is gone: music keeps playing under the SFX as usual.
SECTION "Move Swap Sound", ROMX, BANK[$2C]

PlayMoveSwapSound::
	ld a, SFX_SWAP
	call PlaySound
.waitSfx
	; WaitForSoundToFinish returns at once while the low-HP alarm is on; this SFX
	; should still finish before the text moves on, so poll channels 5-8 directly.
	ld a, [wChannel5Flags1]
	ld hl, wChannel6Flags1
	or [hl]
	ld hl, wChannel7Flags1
	or [hl]
	ld hl, wChannel8Flags1
	or [hl]
	bit 0, a
	jr nz, .waitSfx
.done
	ret
