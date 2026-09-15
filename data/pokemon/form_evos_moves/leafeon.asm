LeafeonFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of FLAREON's (FlareonEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 8, SAND_ATTACK
	db 10, LEER
	db 23, QUICK_ATTACK
	db 26, EMBER
	db 30, DOUBLE_KICK
	db 36, FLAMETHROWER
	db 39, DOUBLE_EDGE
	db 41, GROWTH
	db 47, FIRE_SPIN
	db 52, FIRE_BLAST
	db 0
