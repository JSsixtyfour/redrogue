AmarowakFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of MAROWAK's (MarowakEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 5, LEER
	db 10, BONE_CLUB
	db 13, TAIL_WHIP
	db 18, HEADBUTT
	db 25, FOCUS_ENERGY
	db 31, BONEMERANG
	db 38, THRASH
	db 46, EARTHQUAKE
	db 0
