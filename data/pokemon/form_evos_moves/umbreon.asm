UmbreonFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of JOLTEON's (JolteonEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 8, SAND_ATTACK
	db 23, QUICK_ATTACK
	db 26, THUNDERSHOCK
	db 30, DOUBLE_KICK
	db 36, THUNDERBOLT
	db 39, PIN_MISSILE
	db 41, AGILITY
	db 47, THUNDER_WAVE
	db 52, THUNDER
	db 0
