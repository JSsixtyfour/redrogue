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
    db 6,  AURORA_BEAM
	db 35, AGILITY
	db 45, ICE_BEAM
	db 51, BLIZZARD
	db 55, SKY_ATTACK
	db 60, MIST
	db 0
