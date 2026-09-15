AsandshrewFormEvosMoves:
; Evolutions - never read through this record. Evolution stays
; species-keyed (the form's own bits ride along in the block-copied
; party struct), so it already evolves correctly through the
; species-keyed EvosMovesPointerTable. This terminator exists only
; because every consumer skips this block before reading the learnset.
	db 0
; Learnset - verbatim copy of SANDSHREW's (SandshrewEvosMoves)
; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;
; this file is never regenerated.
; Learnset
	db 5,  POISON_STING
	db 8,  FURY_SWIPES
	db 10, SAND_ATTACK
	db 14, DIG
	db 18, SWIFT
	db 22, SLASH
	db 33, EARTHQUAKE
	db 0
