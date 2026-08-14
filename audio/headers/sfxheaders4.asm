; AUDIO_4 (bank $33) is scaffolding for future content - see engine_4.asm's
; header comment. No sound effects live here yet, only the padding entry
; every SFX_Headers_N array needs at index 0 (see sfxheaders1/2/3.asm).
SFX_Headers_4::
	db $ff, $ff, $ff ; padding
