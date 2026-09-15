WugtrioFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of DUGTRIO's (DugtrioEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 15, GROWL
	db 19, DIG
	db 24, SAND_ATTACK
	db 31, SLASH
	db 35, SCREECH
	db 40, EARTHQUAKE
	db 55, FISSURE
	db 0
