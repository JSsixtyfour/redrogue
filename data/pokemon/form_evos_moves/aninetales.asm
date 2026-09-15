AninetalesFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of NINETALES's (NinetalesEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 7, QUICK_ATTACK
	db 16, CONFUSE_RAY
	db 25, REFLECT
	db 32, FLAMETHROWER
	db 37, NIGHT_SHADE
	db 42, FIRE_SPIN
	db 0
