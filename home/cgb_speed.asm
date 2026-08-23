; ShinRed 60 FPS helpers. Z is set when the saved option is disabled.
Check60FPS::
	ld a, [wOptions2]
	bit BIT_60_FPS, a
	ret
