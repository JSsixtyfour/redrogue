GmoltresFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of MOLTRES's (MoltresEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
    db 6,  GUST
	db 12, FURY_ATTACK
	db 15, WING_ATTACK
	db 20, RAGE
	db 23, SHARPEN
	db 25, NIGHTSHADE
	db 30, SLAM
	db 35, AGILITY
	db 40, DRILL_PECK
	db 50, TRI_ATTACK
	db 55, SKY_ATTACK
	db 0
