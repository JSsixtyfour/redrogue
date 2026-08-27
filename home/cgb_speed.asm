; ShinRed 60 FPS helpers. Z is set when the saved option is disabled.
Check60FPS::
	ld a, [wOptions2]
	bit BIT_60_FPS, a
	ret

; Shin Red import: spinner speedup, 2026-08-26.
;
; Replaces a plain DelayFrame at OverworldLoopLessDelay. While the player is on
; a spinner tile (BIT_SPINNING) and LoadSpinnerArrowTiles' internal frame
; counter is about to expire this call, that routine is about to run its own
; VRAM transfer, which already consumes a frame - so skip this delay rather
; than stacking a second one on top. Every other case (not spinning, or
; spinning but not yet due for a tile update) behaves exactly like DelayFrame.
CheckForSpinAndDelay::
	ld a, [wMovementFlags]
	bit BIT_SPINNING, a
	jr z, .noSpinning
	ld a, [wSpinnerTileFrameCount]
	dec a
	ret z
.noSpinning
	call DelayFrame
	ret
