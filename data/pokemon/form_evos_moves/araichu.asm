AraichuFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of RAICHU's (RaichuEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 6, QUICK_ATTACK
	db 8, THUNDER_WAVE
	db 11, TAIL_WHIP
	db 15, DOUBLE_TEAM
	db 20, THUNDERPUNCH
	db 24, HEADBUTT
	db 30, THUNDERBOLT
	db 36, AGILITY
	db 41, THUNDER
	db 50, LIGHT_SCREEN
	db 0
