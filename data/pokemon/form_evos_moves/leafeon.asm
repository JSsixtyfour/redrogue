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
	db 6, SCRATCH
	db 8, SAND_ATTACK
	db 10, LEER
	db 16, ABSORB
	db 20, LEECH_SEED
	db 23, QUICK_ATTACK
	db 25, VINE_WHIP
	db 30, RAZOR_LEAF
	db 33, MEGA_DRAIN
	db 36, SLASH
	db 39, DOUBLE_EDGE
	db 41, SWORDS_DANCE
	db 47, RECOVER
	db 50, PETAL_DANCE
	db 52, GUILLOTINE
	db 0
