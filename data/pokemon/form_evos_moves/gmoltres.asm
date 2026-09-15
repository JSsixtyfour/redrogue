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
    db 6,  EMBER
	db 35, AGILITY
	db 45, FLAMETHROWER
	db 51, FIRE_BLAST
	db 55, SKY_ATTACK
	db 60, FIRE_SPIN
	db 0
