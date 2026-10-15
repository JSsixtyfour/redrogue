GarticunoFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of ARTICUNO's (ArticunoEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
    db 8,  GUST
	db 16, CONFUSION
	db 21, HYPNOSIS
	db 26, REFLECT
	db 30, PSYBEAM
	db 35, AGILITY
	db 45, PSYCHIC_M
	db 50, RECOVER
	db 55, SKY_ATTACK
	db 0
