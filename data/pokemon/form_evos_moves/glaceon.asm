GlaceonFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of VAPOREON's (VaporeonEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 8, SAND_ATTACK
	db 16, TAKE_DOWN
	db 23, QUICK_ATTACK
	db 26, AURORA_BEAM
	db 30, BITE
	db 36, ICE_BEAM
	db 39, MIST
	db 39, HAZE
	db 41, BARRIER
	db 47, REST
	db 52, BLIZZARD
	db 0
